// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'geo_probe';

  @override
  String get tabMap => 'Map';

  @override
  String get tabJournal => 'Journal';

  @override
  String get tabSettings => 'Settings';

  @override
  String get tabDiagnostics => 'Diagnostics';

  @override
  String get regionLimitWarning =>
      'iOS limit: max 20 monitored zones. Deactivate one first.';

  @override
  String get newRegionTitle => 'New zone';

  @override
  String get regionNameLabel => 'Name';

  @override
  String radiusLabel(int meters) {
    return 'Radius: $meters m';
  }

  @override
  String radiusValue(int meters) {
    return '$meters m';
  }

  @override
  String get radiusHint =>
      'Apple/Google recommend ≥100–150 m. Below that, events are unreliable.';

  @override
  String regionDefaultName(int number) {
    return 'Zone $number';
  }

  @override
  String get zonesTitle => 'Zones';

  @override
  String get noZonesYet => 'No zones yet — long-press the map to create one';

  @override
  String get cancel => 'Cancel';

  @override
  String get create => 'Create';

  @override
  String get close => 'Close';

  @override
  String get delete => 'Delete';

  @override
  String get activate => 'Activate';

  @override
  String get deactivate => 'Deactivate';

  @override
  String get eventTypeEnter => 'Zone enter';

  @override
  String get eventTypeExit => 'Zone exit';

  @override
  String get eventTypeSlc => 'Significant movement (SLC)';

  @override
  String get eventTypeStateInitial => 'Initial zone state';

  @override
  String get eventTypeRelaunch => 'Relaunch by location event';

  @override
  String get eventTypeHeartbeat => 'Diagnostics snapshot';

  @override
  String get eventTypePermissionChange => 'Location permission change';

  @override
  String get eventTypeError => 'Location error';

  @override
  String get valYes => 'Yes';

  @override
  String get valNo => 'No';

  @override
  String get permAlways => 'Always';

  @override
  String get permWhenInUse => 'When in use';

  @override
  String get permDenied => 'Denied';

  @override
  String get permNotDetermined => 'Not requested';

  @override
  String get permRestricted => 'Restricted';

  @override
  String get accFull => 'Precise';

  @override
  String get accReduced => 'Approximate';

  @override
  String get barAvailable => 'Enabled';

  @override
  String get barDenied => 'Disabled';

  @override
  String get barRestricted => 'Restricted';

  @override
  String get appStateForeground => 'app active';

  @override
  String get appStateBackground => 'in background';

  @override
  String get appStateLaunching => 'during launch';

  @override
  String get appStateTerminatedRelaunch => 'relaunched from terminated';

  @override
  String get sectionTelegram => 'Telegram logger';

  @override
  String get tgEnabledTitle => 'Send events to Telegram';

  @override
  String get tgTokenLabel => 'Bot token';

  @override
  String get tgChatIdLabel => 'Chat ID';

  @override
  String get tgHint =>
      'Create a bot via @BotFather and paste the token. Send /start to the bot, then find your chat ID (e.g. via @userinfobot). Live events are sent while iOS lets the app run; events accumulated in background are sent as one message on the next open.';

  @override
  String get tgSaved => 'Telegram settings saved';

  @override
  String get save => 'Save';

  @override
  String get exportTooltip => 'Export all history as JSON';

  @override
  String get presenceTitle => 'Presence';

  @override
  String dwellLine(String region, String duration, int exits) {
    String _temp0 = intl.Intl.pluralLogic(
      exits,
      locale: localeName,
      other: '# exits',
      one: '# exit',
    );
    return '$region: on site $duration, $_temp0';
  }

  @override
  String get insideNow => ' · inside now';

  @override
  String get noEventsForDay => 'No events for this day';

  @override
  String delayMinSec(int minutes, int seconds) {
    return 'delay ${minutes}m ${seconds}s';
  }

  @override
  String delaySec(int seconds) {
    return 'delay ${seconds}s';
  }

  @override
  String durationHM(int hours, String minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String durationMS(int minutes, String seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String durationS(int seconds) {
    return '${seconds}s';
  }

  @override
  String get sectionGeofencing => 'Geofence zones';

  @override
  String get regionMonitoringTitle => 'Track enter and exit';

  @override
  String get regionMonitoringSubtitle =>
      'Log an event when you enter or leave a zone';

  @override
  String get notifyOnEntryTitle => 'React to entering';

  @override
  String get notifyOnExitTitle => 'React to leaving';

  @override
  String get sectionSlc => 'Movement tracking (SLC)';

  @override
  String get slcTitle => 'Track significant movement';

  @override
  String get slcSubtitle =>
      'Coarse accuracy (~500 m–1 km). Keeps working even after the app is closed.';

  @override
  String get sectionDiagnostics => 'Diagnostics';

  @override
  String get localNotificationsTitle => 'Event notifications';

  @override
  String get localNotificationsSubtitle =>
      'Show a banner on every enter, exit and movement';

  @override
  String get sectionHeartbeat => 'Background heartbeat';

  @override
  String get heartbeatTitle => 'Periodic status report';

  @override
  String get heartbeatSubtitle =>
      'Background task: permission status, location and battery — as a notification and to Telegram. iOS chooses the actual timing.';

  @override
  String get heartbeatIntervalTitle => 'Minimum interval';

  @override
  String heartbeatIntervalValue(int minutes) {
    return '$minutes min';
  }

  @override
  String get heartbeatNowTitle => 'Send heartbeat now';

  @override
  String get heartbeatNowSubtitle =>
      'Test the notification and Telegram delivery';

  @override
  String get heartbeatSent => 'Heartbeat sent';

  @override
  String get sectionActions => 'Actions';

  @override
  String get requestPermissionsTitle => 'Request permissions';

  @override
  String get requestPermissionsSubtitle =>
      'Notifications and location (\"Always\")';

  @override
  String permissionResult(String status) {
    return 'Location permission: $status';
  }

  @override
  String get resyncTitle => 'Refresh zones in the system';

  @override
  String get resyncDone => 'Zones refreshed';

  @override
  String get clearHistoryTitle => 'Clear event history';

  @override
  String get clearDialogTitle => 'Clear history?';

  @override
  String get clearDialogBody =>
      'All logged events will be deleted. Zones are kept.';

  @override
  String get clear => 'Clear';

  @override
  String get refreshTooltip => 'Refresh';

  @override
  String lastHeartbeat(String time) {
    return 'Last check: $time';
  }

  @override
  String get countersHeader => 'Total events';

  @override
  String get noDiagnosticsYet => 'No data yet — tap refresh';

  @override
  String get noEventsYet => 'No events recorded yet';

  @override
  String regionStats(int active, int total) {
    return 'Active zones: $active / 20 (iOS limit)\nZones total: $total';
  }

  @override
  String get diagAuthorizationStatus => 'Location permission';

  @override
  String get diagAccuracyAuthorization => 'Location accuracy';

  @override
  String get diagLocationServicesEnabled => 'Location services';

  @override
  String get diagBackgroundRefreshStatus => 'Background App Refresh';

  @override
  String get diagNotificationsAuthorized => 'Notifications allowed';

  @override
  String get diagMonitoredRegionsCount => 'Zones monitored by iOS';

  @override
  String get diagSlcEnabled => 'Movement tracking (SLC)';

  @override
  String get diagRegionMonitoringEnabled => 'Enter/exit tracking';

  @override
  String get diagLaunchedByLocation => 'Launched by a location event';

  @override
  String get diagAppVersion => 'App version';

  @override
  String get diagOsVersion => 'iOS version';

  @override
  String get diagBatteryPercent => 'Battery, %';

  @override
  String get diagHeartbeatEnabled => 'Background heartbeat';

  @override
  String get diagHeartbeatInterval => 'Heartbeat interval';

  @override
  String get diagLastNativeHeartbeat => 'Last background heartbeat';

  @override
  String get diagBgTaskRegistered => 'Background task registered';

  @override
  String get diagBgTaskPending => 'Next background task';

  @override
  String get diagBgTaskSubmitError => 'Scheduling error';

  @override
  String get bgTaskNotQueued => 'not queued';

  @override
  String get bgTaskDueNow => 'due, waiting for iOS';

  @override
  String bgTaskPendingIn(int min) {
    return 'in $min min';
  }
}
