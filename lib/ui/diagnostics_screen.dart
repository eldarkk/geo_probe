import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../wording.dart';

/// Diagnostics: the heartbeat snapshot (§6.2 of the spec) — everything that
/// can silently kill background location, plus event counters.
class DiagnosticsScreen extends StatefulWidget {
  final AppState state;
  const DiagnosticsScreen({super.key, required this.state});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Map<String, int> _counts = {};

  static final _tsFmt = DateFormat('HH:mm:ss');

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.state.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final counts = await widget.state.db.eventCountsByType();
    if (!mounted) return;
    setState(() => _counts = counts);
  }

  /// Human-readable labels for the diagnostics keys reported by native code.
  String _diagLabel(AppLocalizations t, String key) {
    switch (key) {
      case 'authorizationStatus':
        return t.diagAuthorizationStatus;
      case 'accuracyAuthorization':
        return t.diagAccuracyAuthorization;
      case 'locationServicesEnabled':
        return t.diagLocationServicesEnabled;
      case 'backgroundRefreshStatus':
        return t.diagBackgroundRefreshStatus;
      case 'notificationsAuthorized':
        return t.diagNotificationsAuthorized;
      case 'monitoredRegionsCount':
        return t.diagMonitoredRegionsCount;
      case 'slcEnabled':
        return t.diagSlcEnabled;
      case 'regionMonitoringEnabled':
        return t.diagRegionMonitoringEnabled;
      case 'launchedByLocationThisRun':
        return t.diagLaunchedByLocation;
      case 'appVersion':
        return t.diagAppVersion;
      case 'osVersion':
        return t.diagOsVersion;
      case 'batteryPercent':
        return t.diagBatteryPercent;
      case 'heartbeatEnabled':
        return t.diagHeartbeatEnabled;
      case 'heartbeatIntervalMin':
        return t.diagHeartbeatInterval;
      case 'lastNativeHeartbeatTs':
        return t.diagLastNativeHeartbeat;
      default:
        return key;
    }
  }

  /// Highlights the states that break background delivery entirely.
  Color? _valueColor(String key, String value) {
    final bad = {
      'authorizationStatus': {'denied', 'restricted', 'notDetermined', 'whenInUse'},
      'backgroundRefreshStatus': {'denied', 'restricted'},
      'locationServicesEnabled': {'false'},
      'notificationsAuthorized': {'false'},
      'accuracyAuthorization': {'reducedAccuracy'},
    };
    if (bad[key]?.contains(value) ?? false) return Colors.red;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final state = widget.state;
    final diag = state.diagnostics.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Scaffold(
      appBar: AppBar(
        title: Text(t.tabDiagnostics),
        actions: [
          IconButton(
            tooltip: t.refreshTooltip,
            icon: const Icon(Icons.refresh),
            onPressed: state.heartbeat,
          ),
        ],
      ),
      body: ListView(
        children: [
          if (state.lastHeartbeat != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                t.lastHeartbeat(_tsFmt.format(state.lastHeartbeat!)),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (final entry in diag)
                  ListTile(
                    dense: true,
                    title: Text(_diagLabel(t, entry.key)),
                    trailing: Text(
                      diagValueLabel(t, entry.key, entry.value),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        // Color decisions stay keyed on the RAW value.
                        color: _valueColor(entry.key, '${entry.value}'),
                      ),
                    ),
                  ),
                if (diag.isEmpty)
                  ListTile(title: Text(t.noDiagnosticsYet)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              t.countersHeader.toUpperCase(),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (final entry in (_counts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value))))
                  ListTile(
                    dense: true,
                    title: Text(eventTypeLabel(t, entry.key)),
                    trailing: Text('${entry.value}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                if (_counts.isEmpty)
                  ListTile(title: Text(t.noEventsYet)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              t.regionStats(state.activeRegionCount, state.regions.length),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
