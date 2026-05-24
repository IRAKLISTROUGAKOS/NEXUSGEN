import 'package:flutter/material.dart';

enum AlertType { alarm, name, noise }

extension AlertTypeX on AlertType {
  // ── Labels & text ────────────────────────────────────────────────────────

  String get displayTitle {
    switch (this) {
      case AlertType.alarm:
        return '⚠️ ALARM DETECTED';
      case AlertType.name:
        return '📢 Someone calls you';
      case AlertType.noise:
        return '✅ System Active';
    }
  }

  String get subtitle {
    switch (this) {
      case AlertType.alarm:
        return 'Evacuate immediately!';
      case AlertType.name:
        return 'Your name was called!';
      case AlertType.noise:
        return 'Monitoring…';
    }
  }

  String get label {
    switch (this) {
      case AlertType.alarm:
        return 'Alarm';
      case AlertType.name:
        return 'Name';
      case AlertType.noise:
        return 'Noise';
    }
  }

  // ── Icons ────────────────────────────────────────────────────────────────

  IconData get icon {
    switch (this) {
      case AlertType.alarm:
        return Icons.warning_amber_rounded;
      case AlertType.name:
        return Icons.record_voice_over_rounded;
      case AlertType.noise:
        return Icons.sensors_rounded;
    }
  }

  // ── Colors ───────────────────────────────────────────────────────────────

  /// Vibrant accent used for glows, chips, and borders.
  Color get accentColor {
    switch (this) {
      case AlertType.alarm:
        return const Color(0xFFFF4444);
      case AlertType.name:
        return const Color(0xFF4488FF);
      case AlertType.noise:
        return const Color(0xFF44FF88);
    }
  }

  /// Gradient stop colors for the full-screen background.
  List<Color> get gradientColors {
    switch (this) {
      case AlertType.alarm:
        return const [Color(0xFF1C0505), Color(0xFF5C0808)];
      case AlertType.name:
        return const [Color(0xFF030318), Color(0xFF06066B)];
      case AlertType.noise:
        return const [Color(0xFF03120A), Color(0xFF063D18)];
    }
  }

  /// Foreground (text / icon) colour on top of the gradient background.
  Color get onGradientColor => Colors.white;
}

// ── AlertRecord ───────────────────────────────────────────────────────────────

class AlertRecord {
  final AlertType type;
  final DateTime timestamp;
  final double confidence;

  const AlertRecord({
    required this.type,
    required this.timestamp,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'confidence': confidence,
      };

  factory AlertRecord.fromJson(Map<String, dynamic> json) => AlertRecord(
        type: AlertType.values.firstWhere(
          (t) => t.name == (json['type'] as String? ?? 'noise'),
          orElse: () => AlertType.noise,
        ),
        timestamp: DateTime.parse(json['timestamp'] as String),
        confidence: (json['confidence'] as num).toDouble(),
      );
}
