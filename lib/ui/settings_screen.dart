import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../wording.dart';

/// Engine settings: region monitoring, SignificantLocationChange and
/// entry/exit notifications.
class SettingsScreen extends StatelessWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.tabSettings)),
      // Rebuild on AppState changes so switch/dropdown values reflect the
      // config that setConfig just persisted (same pattern as MapScreen).
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final config = state.config;
          return ListView(
            children: [
              _SectionHeader(t.sectionGeofencing),
              SwitchListTile(
                title: Text(t.regionMonitoringTitle),
                subtitle: Text(t.regionMonitoringSubtitle),
                value: config.regionMonitoringEnabled,
                onChanged: (v) => state
                    .setConfig(config.copyWith(regionMonitoringEnabled: v)),
              ),
              SwitchListTile(
                title: Text(t.notifyOnEntryTitle),
                value: config.notifyOnEntry,
                onChanged: config.regionMonitoringEnabled
                    ? (v) => state.setConfig(config.copyWith(notifyOnEntry: v))
                    : null,
              ),
              SwitchListTile(
                title: Text(t.notifyOnExitTitle),
                value: config.notifyOnExit,
                onChanged: config.regionMonitoringEnabled
                    ? (v) => state.setConfig(config.copyWith(notifyOnExit: v))
                    : null,
              ),
              _SectionHeader(t.sectionSlc),
              SwitchListTile(
                title: Text(t.slcTitle),
                subtitle: Text(t.slcSubtitle),
                value: config.slcEnabled,
                onChanged: (v) =>
                    state.setConfig(config.copyWith(slcEnabled: v)),
              ),
              _SectionHeader(t.sectionDiagnostics),
              SwitchListTile(
                title: Text(t.localNotificationsTitle),
                subtitle: Text(t.localNotificationsSubtitle),
                value: config.localNotifications,
                onChanged: (v) =>
                    state.setConfig(config.copyWith(localNotifications: v)),
              ),
              _SectionHeader(t.sectionHeartbeat),
              SwitchListTile(
                title: Text(t.heartbeatTitle),
                subtitle: Text(t.heartbeatSubtitle),
                value: config.heartbeatEnabled,
                onChanged: (v) =>
                    state.setConfig(config.copyWith(heartbeatEnabled: v)),
              ),
              ListTile(
                title: Text(t.heartbeatIntervalTitle),
                trailing: DropdownButton<int>(
                  // The stored value always stays selectable even if it is
                  // not one of the presets.
                  value: config.heartbeatIntervalMin,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final minutes in ({30, 60, 120, 360}
                          ..add(config.heartbeatIntervalMin))
                        .toList()
                      ..sort())
                      DropdownMenuItem(
                        value: minutes,
                        child: Text(t.heartbeatIntervalValue(minutes)),
                      ),
                  ],
                  onChanged: config.heartbeatEnabled
                      ? (v) {
                          if (v != null) {
                            state.setConfig(
                                config.copyWith(heartbeatIntervalMin: v));
                          }
                        }
                      : null,
                ),
              ),
              _SectionHeader(t.sectionActions),
              ListTile(
                leading: const Icon(Icons.lock_open),
                title: Text(t.requestPermissionsTitle),
                subtitle: Text(t.requestPermissionsSubtitle),
                onTap: () async {
                  final status = await state.bridge.requestPermissions();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            t.permissionResult(authStatusLabel(t, status)))));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.sync),
                title: Text(t.resyncTitle),
                onTap: () async {
                  await state.resyncRegions();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(t.resyncDone)));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.monitor_heart),
                title: Text(t.heartbeatNowTitle),
                subtitle: Text(t.heartbeatNowSubtitle),
                onTap: () async {
                  await state.bridge.heartbeatNow();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t.heartbeatSent)));
                  }
                },
              ),
              _SectionHeader(t.sectionTelegram),
              _TelegramSection(state: state),
            ],
          );
        },
      ),
    );
  }
}

class _TelegramSection extends StatefulWidget {
  final AppState state;
  const _TelegramSection({required this.state});

  @override
  State<_TelegramSection> createState() => _TelegramSectionState();
}

class _TelegramSectionState extends State<_TelegramSection> {
  late final TextEditingController _tokenController;
  late final TextEditingController _chatIdController;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.state.tgToken);
    _chatIdController = TextEditingController(text: widget.state.tgChatId);
    _enabled = widget.state.tgEnabled;
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _chatIdController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.state.setTelegram(
      enabled: _enabled,
      token: _tokenController.text,
      chatId: _chatIdController.text,
    );
    if (mounted) {
      final t = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.tgSaved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      children: [
        SwitchListTile(
          title: Text(t.tgEnabledTitle),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              TextField(
                controller: _tokenController,
                enabled: _enabled,
                decoration: InputDecoration(labelText: t.tgTokenLabel),
                autocorrect: false,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _chatIdController,
                enabled: _enabled,
                decoration: InputDecoration(labelText: t.tgChatIdLabel),
                keyboardType: TextInputType.text,
                autocorrect: false,
              ),
              const SizedBox(height: 8),
              Text(t.tgHint,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(t.save),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
