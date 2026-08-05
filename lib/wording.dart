import 'package:intl/intl.dart';

import 'l10n/app_localizations.dart';
import 'models.dart';

/// Shared human-readable labels for event types, app states and diagnostics
/// values. Raw technical codes stay in the DB/export; these are UI-only.

String eventTypeLabel(AppLocalizations t, String type) {
  switch (type) {
    case EventType.enter:
      return t.eventTypeEnter;
    case EventType.exit:
      return t.eventTypeExit;
    case EventType.slc:
      return t.eventTypeSlc;
    case EventType.stateInitial:
      return t.eventTypeStateInitial;
    case EventType.relaunch:
      return t.eventTypeRelaunch;
    case EventType.heartbeat:
      return t.eventTypeHeartbeat;
    case EventType.permissionChange:
      return t.eventTypePermissionChange;
    default:
      return t.eventTypeError;
  }
}

String appStateLabel(AppLocalizations t, String state) {
  switch (state) {
    case 'foreground':
      return t.appStateForeground;
    case 'background':
      return t.appStateBackground;
    case 'launching':
      return t.appStateLaunching;
    case 'terminated-relaunch':
      return t.appStateTerminatedRelaunch;
    default:
      return state;
  }
}

String authStatusLabel(AppLocalizations t, String status) {
  switch (status) {
    case 'always':
      return t.permAlways;
    case 'whenInUse':
      return t.permWhenInUse;
    case 'denied':
      return t.permDenied;
    case 'notDetermined':
      return t.permNotDetermined;
    case 'restricted':
      return t.permRestricted;
    default:
      return status;
  }
}

String boolLabel(AppLocalizations t, bool value) => value ? t.valYes : t.valNo;

/// Formats a diagnostics value for display, keyed by the native field name.
String diagValueLabel(AppLocalizations t, String key, Object? value) {
  switch (key) {
    case 'authorizationStatus':
      return authStatusLabel(t, '$value');
    case 'accuracyAuthorization':
      return value == 'fullAccuracy' ? t.accFull : t.accReduced;
    case 'heartbeatIntervalMin':
      if (value is num) return t.heartbeatIntervalValue(value.toInt());
      return '$value';
    case 'lastNativeHeartbeatTs':
      // 0 = the native heartbeat has never run on this install.
      if (value is num && value.toInt() > 0) {
        return DateFormat('dd.MM HH:mm:ss')
            .format(DateTime.fromMillisecondsSinceEpoch(value.toInt()));
      }
      return '—';
    case 'backgroundRefreshStatus':
      switch ('$value') {
        case 'available':
          return t.barAvailable;
        case 'denied':
          return t.barDenied;
        case 'restricted':
          return t.barRestricted;
        default:
          return '$value';
      }
    default:
      if (value is bool) return boolLabel(t, value);
      return '$value';
  }
}
