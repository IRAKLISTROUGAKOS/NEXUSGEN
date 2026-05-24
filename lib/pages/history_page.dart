import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../providers/alert_provider.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AlertProvider>();
    final history = provider.history;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          history.isEmpty
              ? 'Alert History'
              : 'Alert History  (${history.length})',
        ),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear all',
              onPressed: () => _confirmClear(context, provider),
            ),
        ],
      ),
      body: history.isEmpty
          ? const _EmptyState()
          : Column(
              children: [
                _SummaryBar(history: history),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _AlertCard(record: history[i]),
                  ),
                ),
              ],
            ),
    );
  }

  void _confirmClear(BuildContext context, AlertProvider provider) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Remove all recorded alerts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              provider.clearHistory();
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).textTheme.bodySmall;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded,
              size: 72,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(60)),
          const SizedBox(height: 16),
          Text('No alerts recorded',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(160))),
          const SizedBox(height: 8),
          Text(
            'Alerts from the wearable device\nwill appear here.',
            textAlign: TextAlign.center,
            style: sub?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withAlpha(100)),
          ),
        ],
      ),
    );
  }
}

// ── Summary bar ───────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final List<AlertRecord> history;
  const _SummaryBar({required this.history});

  int _count(AlertType t) => history.where((r) => r.type == t).length;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: AlertType.values
            .map((t) => _SummaryChip(type: t, count: _count(t)))
            .toList(),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final AlertType type;
  final int count;
  const _SummaryChip({required this.type, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: type.accentColor.withAlpha(35),
          child: Text(
            '$count',
            style: TextStyle(
              color: type.accentColor,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(type.label,
            style: TextStyle(
                fontSize: 10,
                color:
                    Theme.of(context).colorScheme.onSurface.withAlpha(140))),
      ],
    );
  }
}

// ── Alert card ────────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final AlertRecord record;
  const _AlertCard({required this.record});

  Color _confidenceColor(double c) {
    if (c >= 0.85) return const Color(0xFF44FF88);
    if (c >= 0.65) return const Color(0xFFFFCC44);
    return const Color(0xFFFF6644);
  }

  @override
  Widget build(BuildContext context) {
    final type = record.type;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A2E)
            : Theme.of(context).colorScheme.surface,
        border: Border(left: BorderSide(color: type.accentColor, width: 3.5)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 40 : 15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: type.accentColor.withAlpha(30),
          child: Icon(type.icon, color: type.accentColor, size: 20),
        ),
        title: Text(
          type.displayTitle,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '${DateFormat('EEE, MMM d · HH:mm:ss').format(record.timestamp)}'
            '   •   ${(record.confidence * 100).round()}% confidence',
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withAlpha(140)),
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: type.accentColor.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: type.accentColor.withAlpha(70)),
              ),
              child: Text(type.label,
                  style: TextStyle(
                      color: type.accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            Text(
              '${(record.confidence * 100).round()}%',
              style: TextStyle(
                color: _confidenceColor(record.confidence),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
