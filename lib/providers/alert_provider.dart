import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert.dart';
import '../services/arduino_service.dart';
import 'settings_provider.dart';

class AlertProvider extends ChangeNotifier {
  // ── State ────────────────────────────────────────────────────────────────
  AlertType _currentAlert = AlertType.noise;
  double _currentConfidence = 0.0;
  bool _isConnected = false;
  bool _isDemoMode = true;
  DateTime? _lastAlertTime;

  final List<AlertRecord> _history = [];

  // ── Arduino service ──────────────────────────────────────────────────────
  ArduinoService? _service;
  SettingsProvider? _settings;

  // ── Auto-reset timer (demo mode) ─────────────────────────────────────────
  Timer? _resetTimer;

  // ── Flutter-side alert cooldown ──────────────────────────────────────────
  // Prevents re-triggering the same non-noise alert immediately after Arduino
  // reverts to noise (e.g. background noise misclassified as "name").
  DateTime? _lastNonNoiseFiredAt;
  static const Duration _flutterAlertCooldown = Duration(seconds: 8);

  // Track which settings were used to start the service
  String? _svcIp;
  int? _svcPort;
  int? _svcInterval;

  // ── Getters ──────────────────────────────────────────────────────────────
  AlertType get currentAlert => _currentAlert;
  double get currentConfidence => _currentConfidence;
  bool get isConnected => _isConnected;
  bool get isDemoMode => _isDemoMode;
  DateTime? get lastAlertTime => _lastAlertTime;
  List<AlertRecord> get history =>
      List.unmodifiable(_history.reversed.toList());

  AlertProvider() {
    _loadHistory();
  }

  // ── Called by ProxyProvider whenever SettingsProvider notifies ───────────

  void applySettings(SettingsProvider settings) {
    _settings = settings;

    final connectionChanged = settings.arduinoIp != _svcIp ||
        settings.arduinoPort != _svcPort ||
        settings.pollingIntervalMs != _svcInterval;

    if (connectionChanged) {
      _svcIp = settings.arduinoIp;
      _svcPort = settings.arduinoPort;
      _svcInterval = settings.pollingIntervalMs;
      _restartService();
    }
  }

  void _restartService() {
    _service?.dispose();
    _service = ArduinoService(
      ip: _svcIp!,
      port: _svcPort!,
      intervalMs: _svcInterval!,
    )..start(_onArduinoAlert, _onConnectionChanged);
  }

  // ── Arduino callbacks ────────────────────────────────────────────────────

  void _onConnectionChanged(bool connected) {
    if (_isConnected == connected) return;
    _isConnected = connected;
    _isDemoMode = !connected;
    notifyListeners();
  }

  void _onArduinoAlert(String alertStr, double confidence) {
    final s = _settings;
    if (s == null) return;

    // If a manual demo alert is active (timer running), don't let Arduino
    // "noise" reports cancel it — let the 2-second timer handle the reset.
    if (_resetTimer != null && alertStr == 'noise') return;

    // Reject below threshold
    if (confidence < s.confidenceThreshold) return;

    // Map string → type, respect enabled toggles
    AlertType? type;
    switch (alertStr) {
      case 'alarm':
        if (!s.alarmEnabled) return;
        type = AlertType.alarm;
      case 'name':
        if (!s.ericaEnabled) return;
        type = AlertType.name;
      case 'noise':
        type = AlertType.noise;
      default:
        return;
    }

    // Suppress identical consecutive alerts — only apply on type change.
    // This prevents history spam when Arduino keeps reporting the same alert
    // during its 2-second cooldown window.
    if (type == _currentAlert) return;

    // Flutter-side cooldown: after a non-noise alert fires, ignore new
    // non-noise alerts for 8 seconds. This prevents "name" from immediately
    // re-triggering when Arduino reverts to noise then re-detects.
    if (type != AlertType.noise) {
      final now = DateTime.now();
      if (_lastNonNoiseFiredAt != null &&
          now.difference(_lastNonNoiseFiredAt!) < _flutterAlertCooldown) {
        return;
      }
      _lastNonNoiseFiredAt = now;
    }

    _applyAlert(type, confidence);
  }

  // ── Demo / manual trigger ────────────────────────────────────────────────

  Future<void> triggerAlert(AlertType type, {double confidence = 1.0}) async {
    // Cancel any pending auto-reset from a previous test trigger
    _resetTimer?.cancel();

    _applyAlert(type, confidence);
    await _triggerHaptic(type);
    _triggerSystemSound(type);

    // Auto-reset to monitoring after 2 s (mirrors Arduino COOLDOWN_MS = 2000).
    // This only matters in demo mode; when connected, Arduino drives the state.
    if (type != AlertType.noise) {
      _resetTimer = Timer(const Duration(seconds: 2), () {
        if (_currentAlert != AlertType.noise) {
          _applyAlert(AlertType.noise, 0.99);
        }
      });
    }
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  void _applyAlert(AlertType type, double confidence) {
    _currentAlert = type;
    _currentConfidence = confidence;
    _lastAlertTime = DateTime.now();

    // Only record real alerts in history — noise (monitoring state) is excluded
    // so the history log shows only meaningful events.
    if (type != AlertType.noise) {
      _history.add(AlertRecord(
        type: type,
        timestamp: _lastAlertTime!,
        confidence: confidence,
      ));

      // Cap history at 200 entries
      if (_history.length > 200) _history.removeAt(0);

      _saveHistory();
    }

    notifyListeners();
  }

  // ── History persistence ──────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('alertHistory');
      if (raw != null) {
        final list = (jsonDecode(raw) as List<dynamic>)
            .cast<Map<String, dynamic>>();
        _history
          ..clear()
          ..addAll(list.map(AlertRecord.fromJson));
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'alertHistory',
        jsonEncode(_history.map((r) => r.toJson()).toList()),
      );
    } catch (_) {}
  }

  void clearHistory() {
    _history.clear();
    _saveHistory();
    notifyListeners();
  }

  // ── Haptic & sound ───────────────────────────────────────────────────────

  Future<void> _triggerHaptic(AlertType type) async {
    switch (type) {
      case AlertType.alarm:
        for (int i = 0; i < 3; i++) {
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 160));
        }
      case AlertType.name:
        await HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 120));
        await HapticFeedback.mediumImpact();
      case AlertType.noise:
        await HapticFeedback.selectionClick();
    }
  }

  void _triggerSystemSound(AlertType type) {
    switch (type) {
      case AlertType.alarm:
      case AlertType.name:
        SystemSound.play(SystemSoundType.alert);
      case AlertType.noise:
        SystemSound.play(SystemSoundType.click);
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _service?.dispose();
    super.dispose();
  }
}
