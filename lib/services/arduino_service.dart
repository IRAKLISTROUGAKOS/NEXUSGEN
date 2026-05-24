import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

typedef AlertCallback = void Function(String alert, double confidence);
typedef ConnectionCallback = void Function(bool connected);

/// Polls the Arduino WiFi HTTP server at GET /status every [intervalMs] ms.
///
/// Design choices that keep the connection stable:
///  • Sequential polling — the next request only starts AFTER the previous one
///    finishes (or times out).  This prevents stacking concurrent requests
///    against the Arduino's single-client WiFiS3 HTTP server.
///  • 2 s timeout — tolerant of WiFi jitter without being too slow to detect
///    a genuine disconnect.
///  • 3-failure grace — a single dropped packet doesn't flip to Demo Mode;
///    three consecutive failures are required before reporting disconnected.
class ArduinoService {
  final String ip;
  final int port;
  final int intervalMs;

  Timer? _timer;
  bool _disposed = false;
  bool _lastConnected = false;
  int _failCount = 0;

  // How many consecutive failures before we declare disconnected.
  static const int _graceFails = 3;

  ArduinoService({
    required this.ip,
    required this.port,
    required this.intervalMs,
  });

  void start(AlertCallback onAlert, ConnectionCallback onConnection) {
    _timer?.cancel();
    _failCount = 0;
    _scheduleNext(onAlert, onConnection);
  }

  /// Schedules a single poll after [intervalMs], then re-schedules itself.
  /// Because it waits for _poll() to complete before scheduling the next
  /// timer, requests never overlap.
  void _scheduleNext(AlertCallback onAlert, ConnectionCallback onConnection) {
    _timer = Timer(Duration(milliseconds: intervalMs), () async {
      if (_disposed) return;
      await _poll(onAlert, onConnection);
      if (!_disposed) _scheduleNext(onAlert, onConnection);
    });
  }

  Future<void> _poll(
    AlertCallback onAlert,
    ConnectionCallback onConnection,
  ) async {
    try {
      final uri = Uri.parse('http://$ip:$port/status');
      final response = await http
          .get(uri)
          .timeout(const Duration(milliseconds: 2000));

      if (_disposed) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final alert = (data['alert'] as String? ?? 'noise').toLowerCase();
        final confidence = (data['confidence'] as num?)?.toDouble() ?? 0.0;

        // Reset failure counter on success
        _failCount = 0;

        if (!_lastConnected) {
          _lastConnected = true;
          onConnection(true);
        }
        onAlert(alert, confidence);
      } else {
        _handleFailure(onConnection);
      }
    } catch (_) {
      if (!_disposed) _handleFailure(onConnection);
    }
  }

  void _handleFailure(ConnectionCallback onConnection) {
    _failCount++;
    // Only report disconnected after _graceFails consecutive failures.
    // A single dropped packet or slow response won't trigger Demo Mode.
    if (_failCount >= _graceFails && _lastConnected) {
      _lastConnected = false;
      onConnection(false);
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    stop();
  }
}
