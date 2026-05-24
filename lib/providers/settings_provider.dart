import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  // ── Arduino connection ───────────────────────────────────────────────────
  String _arduinoIp = '192.168.1.100';
  int _arduinoPort = 8080;
  int _pollingIntervalMs = 500;

  // ── Detection ────────────────────────────────────────────────────────────
  double _confidenceThreshold = 0.70;
  bool _alarmEnabled = true;
  bool _ericaEnabled = true;
  bool _phoneEnabled = true;

  // ── Appearance ───────────────────────────────────────────────────────────
  bool _isDarkTheme = true;

  // ── Getters ──────────────────────────────────────────────────────────────
  String get arduinoIp => _arduinoIp;
  int get arduinoPort => _arduinoPort;
  int get pollingIntervalMs => _pollingIntervalMs;
  double get confidenceThreshold => _confidenceThreshold;
  bool get alarmEnabled => _alarmEnabled;
  bool get ericaEnabled => _ericaEnabled;
  bool get phoneEnabled => _phoneEnabled;
  bool get isDarkTheme => _isDarkTheme;

  SettingsProvider() {
    _load();
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _arduinoIp = p.getString('arduinoIp') ?? '192.168.1.100';
    _arduinoPort = p.getInt('arduinoPort') ?? 8080;
    _pollingIntervalMs = p.getInt('pollingIntervalMs') ?? 500;
    _confidenceThreshold = p.getDouble('confidenceThreshold') ?? 0.70;
    _alarmEnabled = p.getBool('alarmEnabled') ?? true;
    _ericaEnabled = p.getBool('ericaEnabled') ?? true;
    _phoneEnabled = p.getBool('phoneEnabled') ?? true;
    _isDarkTheme = p.getBool('isDarkTheme') ?? true;
    notifyListeners();
  }

  // ── Setters ──────────────────────────────────────────────────────────────

  Future<void> setArduinoIp(String v) async {
    _arduinoIp = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString('arduinoIp', v);
  }

  Future<void> setArduinoPort(int v) async {
    _arduinoPort = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt('arduinoPort', v);
  }

  Future<void> setPollingIntervalMs(int v) async {
    _pollingIntervalMs = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt('pollingIntervalMs', v);
  }

  Future<void> setConfidenceThreshold(double v) async {
    _confidenceThreshold = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble('confidenceThreshold', v);
  }

  Future<void> setAlarmEnabled(bool v) async {
    _alarmEnabled = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('alarmEnabled', v);
  }

  Future<void> setEricaEnabled(bool v) async {
    _ericaEnabled = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('ericaEnabled', v);
  }

  Future<void> setPhoneEnabled(bool v) async {
    _phoneEnabled = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('phoneEnabled', v);
  }

  Future<void> setDarkTheme(bool v) async {
    _isDarkTheme = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('isDarkTheme', v);
  }
}
