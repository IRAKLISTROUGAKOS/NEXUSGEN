import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../providers/alert_provider.dart';
import '../providers/settings_provider.dart';

// ── Page ──────────────────────────────────────────────────────────────────────

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final alert = context.watch<AlertProvider>();
    final type = alert.currentAlert;

    return Column(
      children: [
        Expanded(
          child: _GradientStage(
            type: type,
            confidence: alert.currentConfidence,
            lastAlertTime: alert.lastAlertTime,
            isConnected: alert.isConnected,
            isDemoMode: alert.isDemoMode,
          ),
        ),
        _TestPanel(),
      ],
    );
  }
}

// ── Gradient stage (full-screen animated area) ────────────────────────────────

class _GradientStage extends StatelessWidget {
  final AlertType type;
  final double confidence;
  final DateTime? lastAlertTime;
  final bool isConnected;
  final bool isDemoMode;

  const _GradientStage({
    required this.type,
    required this.confidence,
    required this.lastAlertTime,
    required this.isConnected,
    required this.isDemoMode,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Animated gradient background ──────────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 650),
          child: Container(
            key: ValueKey(type),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: type.gradientColors,
              ),
            ),
          ),
        ),

        // ── Subtle grid overlay ───────────────────────────────────────────
        Opacity(
          opacity: 0.04,
          child: CustomPaint(painter: _GridPainter()),
        ),

        // ── Content ───────────────────────────────────────────────────────
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopBar(isConnected: isConnected, isDemoMode: isDemoMode),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PulseRing(type: type),
                    const SizedBox(height: 28),
                    _AlertTitle(type: type),
                    const SizedBox(height: 10),
                    _AlertSubtitle(type: type),
                    const SizedBox(height: 32),
                    _BadgeRow(
                      type: type,
                      confidence: confidence,
                      lastAlertTime: lastAlertTime,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool isConnected;
  final bool isDemoMode;

  const _TopBar({required this.isConnected, required this.isDemoMode});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          const Icon(Icons.hearing_rounded, color: Colors.white, size: 26),
          const SizedBox(width: 8),
          const Text(
            'NexusGen',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          _ConnectionBadge(isConnected: isConnected, isDemoMode: isDemoMode),
        ],
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  final bool isConnected;
  final bool isDemoMode;

  const _ConnectionBadge(
      {required this.isConnected, required this.isDemoMode});

  @override
  Widget build(BuildContext context) {
    final dotColor = isConnected ? const Color(0xFF44FF88) : const Color(0xFFFF4444);
    final label = isConnected ? 'Connected' : 'Demo Mode';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(60),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(color: dotColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat(reverse: true);
  late final Animation<double> _opacity =
      Tween<double>(begin: 0.5, end: 1.0).animate(_ctrl);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(color: widget.color.withAlpha(120), blurRadius: 6),
          ],
        ),
      ),
    );
  }
}

// ── Pulsing ring animation ────────────────────────────────────────────────────

class _PulseRing extends StatefulWidget {
  final AlertType type;
  const _PulseRing({required this.type});

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing> with TickerProviderStateMixin {
  late AnimationController _ring1;
  late AnimationController _ring2;
  late AnimationController _icon;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _ring1 = AnimationController(vsync: this, duration: _ringDuration)
      ..repeat();
    _ring2 = AnimationController(vsync: this, duration: _ringDuration);
    _ring2.forward(from: 0.5).then((_) {
      if (!_disposed) _ring2.repeat();
    });
    _icon = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _ringDuration.inMilliseconds ~/ 2),
    )..repeat(reverse: true);
  }

  Duration get _ringDuration {
    switch (widget.type) {
      case AlertType.alarm:
        return const Duration(milliseconds: 750);
      case AlertType.name:
        return const Duration(milliseconds: 1300);
      case AlertType.noise:
        return const Duration(milliseconds: 2400);
    }
  }

  @override
  void didUpdateWidget(_PulseRing old) {
    super.didUpdateWidget(old);
    if (old.type == widget.type) return;
    final dur = _ringDuration;
    final halfMs = dur.inMilliseconds ~/ 2;
    _ring1.duration = dur;
    _ring2.duration = dur;
    _icon.duration = Duration(milliseconds: halfMs);
    _ring1.repeat();
    _ring2.forward(from: 0.5).then((_) {
      if (!_disposed) _ring2.repeat();
    });
    _icon.repeat(reverse: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _ring1.dispose();
    _ring2.dispose();
    _icon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.type.accentColor;
    return SizedBox(
      width: 210,
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring 1
          _RingLayer(animation: _ring1, accent: accent, maxRadius: 210),
          // Outer ring 2 (offset)
          _RingLayer(animation: _ring2, accent: accent, maxRadius: 210),
          // Icon circle
          AnimatedBuilder(
            animation: _icon,
            builder: (_, __) {
              final scale = 0.95 + 0.07 * _icon.value;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withAlpha(35),
                    border: Border.all(color: accent.withAlpha(140), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withAlpha(70),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.type.icon,
                    size: 66,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RingLayer extends StatelessWidget {
  final AnimationController animation;
  final Color accent;
  final double maxRadius;

  const _RingLayer(
      {required this.animation,
      required this.accent,
      required this.maxRadius});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final t = animation.value;
        final size = maxRadius * (0.65 + 0.45 * t);
        final opacity = (1.0 - t).clamp(0.0, 1.0);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: accent.withAlpha((opacity * 160).round()),
              width: 1.5,
            ),
          ),
        );
      },
    );
  }
}

// ── Alert title & subtitle ────────────────────────────────────────────────────

class _AlertTitle extends StatelessWidget {
  final AlertType type;
  const _AlertTitle({required this.type});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Text(
          type.displayTitle,
          key: ValueKey(type),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.2,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _AlertSubtitle extends StatelessWidget {
  final AlertType type;
  const _AlertSubtitle({required this.type});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        type.subtitle,
        key: ValueKey(type),
        style: TextStyle(
          color: Colors.white.withAlpha(204),
          fontSize: 16,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

// ── Badge row ─────────────────────────────────────────────────────────────────

class _BadgeRow extends StatelessWidget {
  final AlertType type;
  final double confidence;
  final DateTime? lastAlertTime;

  const _BadgeRow(
      {required this.type,
      required this.confidence,
      required this.lastAlertTime});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (confidence > 0) ...[
          _ConfidenceBadge(confidence: confidence),
          const SizedBox(width: 10),
        ],
        if (lastAlertTime != null)
          _TimeBadge(time: lastAlertTime!),
      ],
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  final double confidence;
  const _ConfidenceBadge({required this.confidence});

  Color get _color {
    if (confidence >= 0.85) return const Color(0xFF44FF88);
    if (confidence >= 0.65) return const Color(0xFFFFCC44);
    return const Color(0xFFFF6644);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withAlpha(120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.speed_rounded, size: 13, color: _color),
          const SizedBox(width: 5),
          Text(
            '${(confidence * 100).round()}% confidence',
            style: TextStyle(
                color: _color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _TimeBadge extends StatelessWidget {
  final DateTime time;
  const _TimeBadge({required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time_rounded,
              size: 13, color: Colors.white.withAlpha(180)),
          const SizedBox(width: 5),
          Text(
            DateFormat('HH:mm:ss').format(time),
            style: TextStyle(
                color: Colors.white.withAlpha(204),
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── Test buttons panel ────────────────────────────────────────────────────────

class _TestPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final alertProvider = context.read<AlertProvider>();
    final settings = context.watch<SettingsProvider>();
    final isDemoMode = context.watch<AlertProvider>().isDemoMode;

    return Container(
      color: const Color(0xFF0A0A14),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  if (isDemoMode)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4444).withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFFF4444).withAlpha(80)),
                      ),
                      child: const Text('DEMO MODE',
                          style: TextStyle(
                              color: Color(0xFFFF4444),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2)),
                    ),
                  if (isDemoMode) const SizedBox(width: 8),
                  Text(
                    'SIMULATE ALERT',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                _TestButton(
                  label: 'Alarm',
                  icon: Icons.warning_amber_rounded,
                  color: const Color(0xFFFF4444),
                  enabled: settings.alarmEnabled,
                  onPressed: () => alertProvider.triggerAlert(
                      AlertType.alarm,
                      confidence: 0.93),
                ),
                const SizedBox(width: 8),
                _TestButton(
                  label: 'Name',
                  icon: Icons.record_voice_over_rounded,
                  color: const Color(0xFF4488FF),
                  enabled: settings.ericaEnabled,
                  onPressed: () => alertProvider.triggerAlert(
                      AlertType.name,
                      confidence: 0.87),
                ),
                const SizedBox(width: 8),
                _TestButton(
                  label: 'Noise',
                  icon: Icons.sensors_rounded,
                  color: const Color(0xFF44FF88),
                  enabled: true,
                  onPressed: () => alertProvider.triggerAlert(
                      AlertType.noise,
                      confidence: 0.98),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _TestButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;

  const _TestButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1.0 : 0.35,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withAlpha(30),
            foregroundColor: color,
            disabledBackgroundColor: color.withAlpha(15),
            disabledForegroundColor: color.withAlpha(60),
            side: BorderSide(color: color.withAlpha(80)),
            padding: const EdgeInsets.symmetric(vertical: 11),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Subtle grid painter ───────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 0.5;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
