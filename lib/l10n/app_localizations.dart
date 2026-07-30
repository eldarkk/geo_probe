import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'geo_probe'**
  String get appTitle;

  /// No description provided for @tabMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get tabMap;

  /// No description provided for @tabJournal.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get tabJournal;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @tabDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get tabDiagnostics;

  /// No description provided for @regionLimitWarning.
  ///
  /// In en, this message translates to:
  /// **'iOS limit: max 20 monitored zones. Deactivate one first.'**
  String get regionLimitWarning;

  /// No description provided for @newRegionTitle.
  ///
  /// In en, this message translates to:
  /// **'New zone'**
  String get newRegionTitle;

  /// No description provided for @regionNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get regionNameLabel;

  /// No description provided for @radiusLabel.
  ///
  /// In en, this message translates to:
  /// **'Radius: {meters} m'**
  String radiusLabel(int meters);

  /// No description provided for @radiusValue.
  ///
  /// In en, this message translates to:
  /// **'{meters} m'**
  String radiusValue(int meters);

  /// No description provided for @radiusHint.
  ///
  /// In en, this message translates to:
  /// **'Apple/Google recommend ≥100–150 m. Below that, events are unreliable.'**
  String get radiusHint;

  /// No description provided for @regionDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Zone {number}'**
  String regionDefaultName(int number);

  /// No description provided for @zonesTitle.
  ///
  /// In en, this message translates to:
  /// **'Zones'**
  String get zonesTitle;

  /// No description provided for @noZonesYet.
  ///
  /// In en, this message translates to:
  /// **'No zones yet — long-press the map to create one'**
  String get noZonesYet;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @activate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get activate;

  /// No description provided for @deactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get deactivate;

  /// No description provided for @eventTypeEnter.
  ///
  /// In en, this message translates to:
  /// **'Zone enter'**
  String get eventTypeEnter;

  /// No description provided for @eventTypeExit.
  ///
  /// In en, this message translates to:
  /// **'Zone exit'**
  String get eventTypeExit;

  /// No description provided for @eventTypeSlc.
  ///
  /// In en, this message translates to:
  /// **'Significant movement (SLC)'**
  String get eventTypeSlc;

  /// No description provided for @eventTypeStateInitial.
  ///
  /// In en, this message translates to:
  /// **'Initial zone state'**
  String get eventTypeStateInitial;

  /// No description provided for @eventTypeRelaunch.
  ///
  /// In en, this message translates to:
  /// **'Relaunch by location event'**
  String get eventTypeRelaunch;

  /// No description provided for @eventTypeHeartbeat.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics snapshot'**
  String get eventTypeHeartbeat;

  /// No description provided for @eventTypePermissionChange.
  ///
  /// In en, this message translates to:
  /// **'Location permission change'**
  String get eventTypePermissionChange;

  /// No description provided for @eventTypeError.
  ///
  /// In en, this message translates to:
  /// **'Location error'**
  String get eventTypeError;

  /// No description provided for @valYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get valYes;

  /// No description provided for @valNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get valNo;

  /// No description provided for @permAlways.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get permAlways;

  /// No description provided for @permWhenInUse.
  ///
  /// In en, this message translates to:
  /// **'When in use'**
  String get permWhenInUse;

  /// No description provided for @permDenied.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get permDenied;

  /// No description provided for @permNotDetermined.
  ///
  /// In en, this message translates to:
  /// **'Not requested'**
  String get permNotDetermined;

  /// No description provided for @permRestricted.
  ///
  /// In en, this message translates to:
  /// **'Restricted'**
  String get permRestricted;

  /// No description provided for @accFull.
  ///
  /// In en, this message translates to:
  /// **'Precise'**
  String get accFull;

  /// No description provided for @accReduced.
  ///
  /// In en, this message translates to:
  /// **'Approximate'**
  String get accReduced;

  /// No description provided for @barAvailable.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get barAvailable;

  /// No description provided for @barDenied.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get barDenied;

  /// No description provided for @barRestricted.
  ///
  /// In en, this message translates to:
  /// **'Restricted'**
  String get barRestricted;

  /// No description provided for @appStateForeground.
  ///
  /// In en, this message translates to:
  /// **'app active'**
  String get appStateForeground;

  /// No description provided for @appStateBackground.
  ///
  /// In en, this message translates to:
  /// **'in background'**
  String get appStateBackground;

  /// No description provided for @appStateLaunching.
  ///
  /// In en, this message translates to:
  /// **'during launch'**
  String get appStateLaunching;

  /// No description provided for @appStateTerminatedRelaunch.
  ///
  /// In en, this message translates to:
  /// **'relaunched from terminated'**
  String get appStateTerminatedRelaunch;

  /// No description provided for @sectionTelegram.
  ///
  /// In en, this message translates to:
  /// **'Telegram logger'**
  String get sectionTelegram;

  /// No description provided for @tgEnabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Send events to Telegram'**
  String get tgEnabledTitle;

  /// No description provided for @tgTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'Bot token'**
  String get tgTokenLabel;

  /// No description provided for @tgChatIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Chat ID'**
  String get tgChatIdLabel;

  /// No description provided for @tgHint.
  ///
  /// In en, this message translates to:
  /// **'Create a bot via @BotFather and paste the token. Send /start to the bot, then find your chat ID (e.g. via @userinfobot). Live events are sent while iOS lets the app run; events accumulated in background are sent as one message on the next open.'**
  String get tgHint;

  /// No description provided for @tgSaved.
  ///
  /// In en, this message translates to:
  /// **'Telegram settings saved'**
  String get tgSaved;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @exportTooltip.
  ///
  /// In en, this message translates to:
  /// **'Export all history as JSON'**
  String get exportTooltip;

  /// No description provided for @presenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Presence'**
  String get presenceTitle;

  /// No description provided for @dwellLine.
  ///
  /// In en, this message translates to:
  /// **'{region}: on site {duration}, {exits, plural, one {# exit} other {# exits}}'**
  String dwellLine(String region, String duration, int exits);

  /// No description provided for @insideNow.
  ///
  /// In en, this message translates to:
  /// **' · inside now'**
  String get insideNow;

  /// No description provided for @noEventsForDay.
  ///
  /// In en, this message translates to:
  /// **'No events for this day'**
  String get noEventsForDay;

  /// No description provided for @delayMinSec.
  ///
  /// In en, this message translates to:
  /// **'delay {minutes}m {seconds}s'**
  String delayMinSec(int minutes, int seconds);

  /// No description provided for @delaySec.
  ///
  /// In en, this message translates to:
  /// **'delay {seconds}s'**
  String delaySec(int seconds);

  /// No description provided for @durationHM.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String durationHM(int hours, String minutes);

  /// No description provided for @durationMS.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s'**
  String durationMS(int minutes, String seconds);

  /// No description provided for @durationS.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String durationS(int seconds);

  /// No description provided for @sectionGeofencing.
  ///
  /// In en, this message translates to:
  /// **'Geofence zones'**
  String get sectionGeofencing;

  /// No description provided for @regionMonitoringTitle.
  ///
  /// In en, this message translates to:
  /// **'Track enter and exit'**
  String get regionMonitoringTitle;

  /// No description provided for @regionMonitoringSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Log an event when you enter or leave a zone'**
  String get regionMonitoringSubtitle;

  /// No description provided for @notifyOnEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'React to entering'**
  String get notifyOnEntryTitle;

  /// No description provided for @notifyOnExitTitle.
  ///
  /// In en, this message translates to:
  /// **'React to leaving'**
  String get notifyOnExitTitle;

  /// No description provided for @sectionSlc.
  ///
  /// In en, this message translates to:
  /// **'Movement tracking (SLC)'**
  String get sectionSlc;

  /// No description provided for @slcTitle.
  ///
  /// In en, this message translates to:
  /// **'Track significant movement'**
  String get slcTitle;

  /// No description provided for @slcSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Coarse accuracy (~500 m–1 km). Keeps working even after the app is closed.'**
  String get slcSubtitle;

  /// No description provided for @sectionDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get sectionDiagnostics;

  /// No description provided for @localNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Event notifications'**
  String get localNotificationsTitle;

  /// No description provided for @localNotificationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show a banner on every enter, exit and movement'**
  String get localNotificationsSubtitle;

  /// No description provided for @sectionActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get sectionActions;

  /// No description provided for @requestPermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Request permissions'**
  String get requestPermissionsTitle;

  /// No description provided for @requestPermissionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications and location (\"Always\")'**
  String get requestPermissionsSubtitle;

  /// No description provided for @permissionResult.
  ///
  /// In en, this message translates to:
  /// **'Location permission: {status}'**
  String permissionResult(String status);

  /// No description provided for @resyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Refresh zones in the system'**
  String get resyncTitle;

  /// No description provided for @resyncDone.
  ///
  /// In en, this message translates to:
  /// **'Zones refreshed'**
  String get resyncDone;

  /// No description provided for @clearHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear event history'**
  String get clearHistoryTitle;

  /// No description provided for @clearDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear history?'**
  String get clearDialogTitle;

  /// No description provided for @clearDialogBody.
  ///
  /// In en, this message translates to:
  /// **'All logged events will be deleted. Zones are kept.'**
  String get clearDialogBody;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @refreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshTooltip;

  /// No description provided for @lastHeartbeat.
  ///
  /// In en, this message translates to:
  /// **'Last check: {time}'**
  String lastHeartbeat(String time);

  /// No description provided for @countersHeader.
  ///
  /// In en, this message translates to:
  /// **'Total events'**
  String get countersHeader;

  /// No description provided for @noDiagnosticsYet.
  ///
  /// In en, this message translates to:
  /// **'No data yet — tap refresh'**
  String get noDiagnosticsYet;

  /// No description provided for @noEventsYet.
  ///
  /// In en, this message translates to:
  /// **'No events recorded yet'**
  String get noEventsYet;

  /// No description provided for @regionStats.
  ///
  /// In en, this message translates to:
  /// **'Active zones: {active} / 20 (iOS limit)\nZones total: {total}'**
  String regionStats(int active, int total);

  /// No description provided for @diagAuthorizationStatus.
  ///
  /// In en, this message translates to:
  /// **'Location permission'**
  String get diagAuthorizationStatus;

  /// No description provided for @diagAccuracyAuthorization.
  ///
  /// In en, this message translates to:
  /// **'Location accuracy'**
  String get diagAccuracyAuthorization;

  /// No description provided for @diagLocationServicesEnabled.
  ///
  /// In en, this message translates to:
  /// **'Location services'**
  String get diagLocationServicesEnabled;

  /// No description provided for @diagBackgroundRefreshStatus.
  ///
  /// In en, this message translates to:
  /// **'Background App Refresh'**
  String get diagBackgroundRefreshStatus;

  /// No description provided for @diagNotificationsAuthorized.
  ///
  /// In en, this message translates to:
  /// **'Notifications allowed'**
  String get diagNotificationsAuthorized;

  /// No description provided for @diagMonitoredRegionsCount.
  ///
  /// In en, this message translates to:
  /// **'Zones monitored by iOS'**
  String get diagMonitoredRegionsCount;

  /// No description provided for @diagSlcEnabled.
  ///
  /// In en, this message translates to:
  /// **'Movement tracking (SLC)'**
  String get diagSlcEnabled;

  /// No description provided for @diagRegionMonitoringEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enter/exit tracking'**
  String get diagRegionMonitoringEnabled;

  /// No description provided for @diagLaunchedByLocation.
  ///
  /// In en, this message translates to:
  /// **'Launched by a location event'**
  String get diagLaunchedByLocation;

  /// No description provided for @diagAppVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get diagAppVersion;

  /// No description provided for @diagOsVersion.
  ///
  /// In en, this message translates to:
  /// **'iOS version'**
  String get diagOsVersion;

  /// No description provided for @diagBatteryPercent.
  ///
  /// In en, this message translates to:
  /// **'Battery, %'**
  String get diagBatteryPercent;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
