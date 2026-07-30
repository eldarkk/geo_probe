import 'package:flutter/material.dart';

import 'app_state.dart';
import 'l10n/app_localizations.dart';
import 'ui/diagnostics_screen.dart';
import 'ui/journal_screen.dart';
import 'ui/map_screen.dart';
import 'ui/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GeoProbeApp());
}

class GeoProbeApp extends StatefulWidget {
  const GeoProbeApp({super.key});

  @override
  State<GeoProbeApp> createState() => _GeoProbeAppState();
}

class _GeoProbeAppState extends State<GeoProbeApp> with WidgetsBindingObserver {
  final AppState _appState = AppState();
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appState.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appState.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    // On resume: drain natively-buffered events + write a heartbeat.
    if (lifecycleState == AppLifecycleState.resumed) {
      _appState.onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'geo_probe',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: Builder(
        builder: (context) {
          final t = AppLocalizations.of(context)!;
          return Scaffold(
            body: IndexedStack(
              index: _tabIndex,
              children: [
                MapScreen(state: _appState),
                JournalScreen(state: _appState),
                SettingsScreen(state: _appState),
                DiagnosticsScreen(state: _appState),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (i) => setState(() => _tabIndex = i),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.map),
                  label: t.tabMap,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.list_alt),
                  label: t.tabJournal,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings),
                  label: t.tabSettings,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.monitor_heart),
                  label: t.tabDiagnostics,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
