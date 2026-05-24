import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _ipCtrl;
  late final TextEditingController _portCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _connectionDirty = false;
  bool _testingConnection = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _ipCtrl = TextEditingController(text: s.arduinoIp);
    _portCtrl = TextEditingController(text: s.arduinoPort.toString());
    _ipCtrl.addListener(_onConnectionFieldChanged);
    _portCtrl.addListener(_onConnectionFieldChanged);
  }

  void _onConnectionFieldChanged() {
    final s = context.read<SettingsProvider>();
    final dirty = _ipCtrl.text != s.arduinoIp ||
        _portCtrl.text != s.arduinoPort.toString();
    if (dirty != _connectionDirty) setState(() => _connectionDirty = dirty);
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyConnection(SettingsProvider s) async {
    if (!_formKey.currentState!.validate()) return;
    await s.setArduinoIp(_ipCtrl.text.trim());
    await s.setArduinoPort(int.parse(_portCtrl.text.trim()));
    setState(() => _connectionDirty = false);
  }

  Future<void> _testConnection(SettingsProvider s) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _testingConnection = true);
    final ip = _ipCtrl.text.trim();
    final port = int.parse(_portCtrl.text.trim());
    try {
      final res = await http
          .get(Uri.parse('http://$ip:$port/status'))
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _showSnack('✅ Connected — alert: ${data['alert']}, '
            'confidence: ${((data['confidence'] as num).toDouble() * 100).round()}%',
            isError: false);
      } else {
        _showSnack('HTTP ${res.statusCode}', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnack('Connection failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // ── Arduino Connection ─────────────────────────────────────────
            _SectionLabel('Arduino Connection'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _ipCtrl,
                      decoration: const InputDecoration(
                        labelText: 'IP Address',
                        hintText: '192.168.1.100',
                        prefixIcon: Icon(Icons.wifi_rounded),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final parts = v.trim().split('.');
                        if (parts.length != 4) return 'Use format 192.168.x.x';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _portCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: '8080',
                        prefixIcon: Icon(Icons.lan_rounded),
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        if (n == null || n < 1 || n > 65535) {
                          return 'Enter a valid port (1–65535)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (_connectionDirty)
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _applyConnection(settings),
                              icon: const Icon(Icons.save_rounded, size: 18),
                              label: const Text('Apply'),
                            ),
                          ),
                        if (_connectionDirty) const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _testingConnection
                                ? null
                                : () => _testConnection(settings),
                            icon: _testingConnection
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.bolt_rounded, size: 18),
                            label: const Text('Test Connection'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Polling Interval ───────────────────────────────────────────
            _SectionLabel('Polling Interval'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('How often to query the Arduino',
                        style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 250, label: Text('250 ms')),
                        ButtonSegment(value: 500, label: Text('500 ms')),
                        ButtonSegment(value: 1000, label: Text('1 s')),
                      ],
                      selected: {settings.pollingIntervalMs},
                      onSelectionChanged: (s) =>
                          settings.setPollingIntervalMs(s.first),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Detection ─────────────────────────────────────────────────
            _SectionLabel('Detection'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Confidence Threshold',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        _LevelChip(
                            label:
                                '≥ ${(settings.confidenceThreshold * 100).round()}%'),
                      ],
                    ),
                    Slider(
                      value: settings.confidenceThreshold,
                      min: 0.5,
                      max: 0.95,
                      divisions: 9,
                      onChanged: settings.setConfidenceThreshold,
                    ),
                    Text(
                      'Alerts below this score are ignored. '
                      'Lower = more sensitive, higher = fewer false positives.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withAlpha(140),
                          height: 1.4),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Alert Types ────────────────────────────────────────────────
            _SectionLabel('Alert Types'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _AlertToggle(
                    icon: Icons.warning_amber_rounded,
                    iconColor: const Color(0xFFFF4444),
                    title: 'Alarm',
                    subtitle: 'Fire alarms, emergency sirens',
                    value: settings.alarmEnabled,
                    onChanged: settings.setAlarmEnabled,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _AlertToggle(
                    icon: Icons.record_voice_over_rounded,
                    iconColor: const Color(0xFF4488FF),
                    title: 'Name Recognition',
                    subtitle: 'Detects when someone calls your name',
                    value: settings.ericaEnabled,
                    onChanged: settings.setEricaEnabled,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Appearance ─────────────────────────────────────────────────
            _SectionLabel('Appearance'),
            Card(
              child: _AlertToggle(
                icon: Icons.dark_mode_rounded,
                iconColor: const Color(0xFF8888FF),
                title: 'Dark Theme',
                subtitle: 'Recommended for low-light environments',
                value: settings.isDarkTheme,
                onChanged: settings.setDarkTheme,
              ),
            ),

            const SizedBox(height: 20),

            // ── About ──────────────────────────────────────────────────────
            _SectionLabel('About'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.hearing_rounded,
                            size: 30,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('NexusGen',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18)),
                            Text('v2.0.0',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withAlpha(140),
                                    fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'NexusGen pairs with a wearable Arduino device that uses '
                      'TinyML to classify environmental sounds in real time. '
                      'Detected sounds are sent to this app over WiFi, '
                      'triggering vivid visual and haptic alerts.',
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.55,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withAlpha(200)),
                    ),
                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 6),
                    _InfoRow(
                        icon: Icons.memory_rounded,
                        label: 'ML Engine',
                        value: 'TinyML / Edge Impulse'),
                    _InfoRow(
                        icon: Icons.developer_board_rounded,
                        label: 'Hardware',
                        value: 'Arduino Uno R4 WiFi'),
                    _InfoRow(
                        icon: Icons.wifi_rounded,
                        label: 'Transport',
                        value: 'HTTP over WiFi'),
                    _InfoRow(
                        icon: Icons.mic_rounded,
                        label: 'Sound classes',
                        value: 'Alarm · Name · Noise'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.3,
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  final String label;
  const _LevelChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(label,
          style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
              fontSize: 13)),
    );
  }
}

class _AlertToggle extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AlertToggle({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: CircleAvatar(
        backgroundColor: iconColor.withAlpha(30),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color:
                  Theme.of(context).colorScheme.onSurface.withAlpha(140))),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon,
              size: 15,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(130)),
          const SizedBox(width: 8),
          Text('$label  ',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(160))),
          ),
        ],
      ),
    );
  }
}
