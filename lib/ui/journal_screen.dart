import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../models.dart';
import '../wording.dart';

/// Event journal: per-day list with delivery latency, dwell summary per
/// region ("on site 3h20m, 2 exits"), type filters and JSON export.
class JournalScreen extends StatefulWidget {
  final AppState state;
  const JournalScreen({super.key, required this.state});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  DateTime _day = DateTime.now();
  final Set<String> _enabledTypes = EventType.all.toSet();
  List<GeoEvent> _events = [];
  int _loadedRevision = -1;

  static final _timeFmt = DateFormat('HH:mm:ss');

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
    _reload();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (widget.state.eventsRevision != _loadedRevision) _reload();
  }

  Future<void> _reload() async {
    _loadedRevision = widget.state.eventsRevision;
    final events = await widget.state.db.eventsForDay(_day);
    if (!mounted) return;
    setState(() => _events = events);
  }

  void _shiftDay(int delta) {
    setState(() => _day = DateTime(_day.year, _day.month, _day.day + delta));
    _reload();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _day.year == now.year && _day.month == now.month && _day.day == now.day;
  }

  /// Computes dwell per region from ENTER/EXIT pairs for the selected day.
  /// Open intervals are closed at "now" (today) or end of day (past days).
  Map<String, _Dwell> _computeDwell() {
    final result = <String, _Dwell>{};
    final dayStart = DateTime(_day.year, _day.month, _day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final closeAt = _isToday ? DateTime.now() : dayEnd;

    final byRegion = <String, List<GeoEvent>>{};
    for (final e in _events) {
      if (e.regionId == null) continue;
      if (e.type != EventType.enter && e.type != EventType.exit) continue;
      byRegion.putIfAbsent(e.regionId!, () => []).add(e);
    }

    byRegion.forEach((regionId, events) {
      var total = Duration.zero;
      var exits = 0;
      DateTime? insideSince;
      var currentlyInside = false;

      for (final e in events) {
        if (e.type == EventType.enter) {
          insideSince ??= e.eventTime;
          currentlyInside = true;
        } else {
          exits++;
          // EXIT with no preceding ENTER: assume inside since day start.
          final from = insideSince ?? dayStart;
          total += e.eventTime.difference(from);
          insideSince = null;
          currentlyInside = false;
        }
      }
      if (insideSince != null) {
        total += closeAt.difference(insideSince);
      }
      result[regionId] =
          _Dwell(total: total, exits: exits, currentlyInside: currentlyInside);
    });
    return result;
  }

  String _formatDuration(AppLocalizations t, Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return t.durationHM(h, m.toString().padLeft(2, '0'));
    if (m > 0) {
      return t.durationMS(m, (d.inSeconds % 60).toString().padLeft(2, '0'));
    }
    return t.durationS(d.inSeconds);
  }

  String _regionName(String? id) {
    if (id == null) return '';
    return widget.state.regions
        .where((r) => r.id == id)
        .map((r) => r.name)
        .firstOrNull ??
        id.substring(0, 8);
  }

  IconData _eventIcon(String type) {
    switch (type) {
      case EventType.enter:
        return Icons.login;
      case EventType.exit:
        return Icons.logout;
      case EventType.slc:
        return Icons.alt_route;
      case EventType.stateInitial:
        return Icons.flag;
      case EventType.relaunch:
        return Icons.restart_alt;
      case EventType.heartbeat:
        return Icons.monitor_heart;
      case EventType.permissionChange:
        return Icons.lock;
      default:
        return Icons.error_outline;
    }
  }

  Color _eventColor(String type) {
    switch (type) {
      case EventType.enter:
        return Colors.green;
      case EventType.exit:
        return Colors.red;
      case EventType.slc:
        return Colors.blue;
      case EventType.relaunch:
        return Colors.purple;
      case EventType.permissionChange:
      case EventType.error:
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String _delayLabel(AppLocalizations t, GeoEvent e) {
    final d = e.deliveryDelay;
    if (d.inSeconds.abs() < 1) return '';
    if (d.inMinutes.abs() >= 1) return t.delayMinSec(d.inMinutes, d.inSeconds % 60);
    return t.delaySec(d.inSeconds);
  }

  void _showDetail(GeoEvent e) {
    showDialog<void>(
      context: context,
      builder: (context) {
        String prettyDetail = e.detail ?? '';
        try {
          prettyDetail = const JsonEncoder.withIndent('  ')
              .convert(jsonDecode(e.detail ?? ''));
        } catch (_) {}
        return AlertDialog(
          title: Text(eventTypeLabel(AppLocalizations.of(context)!, e.type)),
          content: SingleChildScrollView(
            child: Text(
              'uuid: ${e.uuid}\n'
              'region: ${_regionName(e.regionId)}\n'
              'event_ts: ${e.eventTime}\n'
              'received_ts: ${e.receivedTime}\n'
              'delay: ${e.deliveryDelay}\n'
              'lat/lng: ${e.lat}, ${e.lng}\n'
              'accuracy: ${e.accuracy} m\n'
              'app_state: ${e.appState}\n'
              'battery: ${e.battery}%\n'
              '$prettyDetail',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.close),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final dayFmt = DateFormat('EEE, d MMM yyyy', t.localeName);
    final dwell = _computeDwell();
    final visible =
        _events.where((e) => _enabledTypes.contains(e.type)).toList().reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(t.tabJournal),
        actions: [
          // Builder gives the icon's own RenderBox — the share sheet popover
          // must be anchored to a real on-screen rect on iOS.
          Builder(
            builder: (iconContext) => IconButton(
              tooltip: t.exportTooltip,
              icon: const Icon(Icons.ios_share),
              onPressed: () {
                final box = iconContext.findRenderObject() as RenderBox?;
                final origin = box == null
                    ? null
                    : box.localToGlobal(Offset.zero) & box.size;
                widget.state.exportHistory(origin: origin);
              },
            ),
          ),
          IconButton(
            tooltip: t.clearHistoryTitle,
            icon: const Icon(Icons.delete_forever),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(t.clearDialogTitle),
                  content: Text(t.clearDialogBody),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(t.cancel)),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(t.clear)),
                  ],
                ),
              );
              if (confirmed == true) await widget.state.clearHistory();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Day selector.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftDay(-1)),
              Text(dayFmt.format(_day),
                  style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _isToday ? null : () => _shiftDay(1)),
            ],
          ),
          // Dwell summary — the §1b deliverable, computed locally.
          if (dwell.isNotEmpty)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.presenceTitle,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    for (final entry in dwell.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          t.dwellLine(
                                _regionName(entry.key),
                                _formatDuration(t, entry.value.total),
                                entry.value.exits,
                              ) +
                              (entry.value.currentlyInside ? t.insideNow : ''),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // Type filter chips.
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final type in EventType.all)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(eventTypeLabel(t, type),
                          style: const TextStyle(fontSize: 11)),
                      selected: _enabledTypes.contains(type),
                      onSelected: (sel) => setState(() {
                        sel ? _enabledTypes.add(type) : _enabledTypes.remove(type);
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? Center(child: Text(t.noEventsForDay))
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final e = visible[index];
                      final subtitleParts = <String>[
                        if (e.regionId != null) _regionName(e.regionId),
                        if (e.accuracy != null)
                          '±${e.accuracy!.toStringAsFixed(0)}m',
                        _delayLabel(t, e),
                        appStateLabel(t, e.appState),
                      ]..removeWhere((s) => s.isEmpty);
                      return ListTile(
                        dense: true,
                        leading: Icon(_eventIcon(e.type),
                            color: _eventColor(e.type)),
                        title: Text(
                            '${_timeFmt.format(e.eventTime)}  ${eventTypeLabel(t, e.type)}'),
                        subtitle: Text(subtitleParts.join(' · ')),
                        onTap: () => _showDetail(e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Dwell {
  final Duration total;
  final int exits;
  final bool currentlyInside;
  const _Dwell(
      {required this.total, required this.exits, required this.currentlyInside});
}
