// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'geo_probe';

  @override
  String get tabMap => 'Карта';

  @override
  String get tabJournal => 'Журнал';

  @override
  String get tabSettings => 'Настройки';

  @override
  String get tabDiagnostics => 'Диагностика';

  @override
  String get regionLimitWarning =>
      'Лимит iOS: максимум 20 зон. Сначала отключите одну.';

  @override
  String get newRegionTitle => 'Новая зона';

  @override
  String get regionNameLabel => 'Название';

  @override
  String radiusLabel(int meters) {
    return 'Радиус: $meters м';
  }

  @override
  String radiusValue(int meters) {
    return '$meters м';
  }

  @override
  String get radiusHint =>
      'Apple/Google рекомендуют ≥100–150 м. При меньшем радиусе события ненадёжны.';

  @override
  String regionDefaultName(int number) {
    return 'Зона $number';
  }

  @override
  String get zonesTitle => 'Зоны';

  @override
  String get noZonesYet => 'Зон пока нет — создайте долгим тапом по карте';

  @override
  String get cancel => 'Отмена';

  @override
  String get create => 'Создать';

  @override
  String get close => 'Закрыть';

  @override
  String get delete => 'Удалить';

  @override
  String get activate => 'Включить';

  @override
  String get deactivate => 'Отключить';

  @override
  String get eventTypeEnter => 'Вход в зону';

  @override
  String get eventTypeExit => 'Выход из зоны';

  @override
  String get eventTypeSlc => 'Значимое перемещение (SLC)';

  @override
  String get eventTypeStateInitial => 'Стартовое состояние зоны';

  @override
  String get eventTypeRelaunch => 'Перезапуск по геособытию';

  @override
  String get eventTypeHeartbeat => 'Диагностический снимок';

  @override
  String get eventTypePermissionChange => 'Смена разрешения геолокации';

  @override
  String get eventTypeError => 'Ошибка геолокации';

  @override
  String get valYes => 'Да';

  @override
  String get valNo => 'Нет';

  @override
  String get permAlways => 'Всегда';

  @override
  String get permWhenInUse => 'При использовании';

  @override
  String get permDenied => 'Запрещено';

  @override
  String get permNotDetermined => 'Не запрошено';

  @override
  String get permRestricted => 'Ограничено';

  @override
  String get accFull => 'Точная';

  @override
  String get accReduced => 'Приблизительная';

  @override
  String get barAvailable => 'Включено';

  @override
  String get barDenied => 'Выключено';

  @override
  String get barRestricted => 'Ограничено';

  @override
  String get appStateForeground => 'приложение активно';

  @override
  String get appStateBackground => 'в фоне';

  @override
  String get appStateLaunching => 'при запуске';

  @override
  String get appStateTerminatedRelaunch => 'перезапуск из выгруженного';

  @override
  String get sectionTelegram => 'Логгер в Telegram';

  @override
  String get tgEnabledTitle => 'Отправлять события в Telegram';

  @override
  String get tgTokenLabel => 'Токен бота';

  @override
  String get tgChatIdLabel => 'Chat ID';

  @override
  String get tgHint =>
      'Создайте бота через @BotFather и вставьте токен. Напишите боту /start, затем узнайте свой chat ID (например, через @userinfobot). Живые события уходят, пока iOS даёт приложению работать; накопленное в фоне отправится одним сообщением при следующем открытии.';

  @override
  String get tgSaved => 'Настройки Telegram сохранены';

  @override
  String get save => 'Сохранить';

  @override
  String get exportTooltip => 'Экспортировать историю в JSON';

  @override
  String get presenceTitle => 'Присутствие';

  @override
  String dwellLine(String region, String duration, int exits) {
    String _temp0 = intl.Intl.pluralLogic(
      exits,
      locale: localeName,
      other: '# выхода',
      many: '# выходов',
      few: '# выхода',
      one: '# выход',
    );
    return '$region: на объекте $duration, $_temp0';
  }

  @override
  String get insideNow => ' · сейчас внутри';

  @override
  String get noEventsForDay => 'Нет событий за этот день';

  @override
  String delayMinSec(int minutes, int seconds) {
    return 'задержка $minutesм $secondsс';
  }

  @override
  String delaySec(int seconds) {
    return 'задержка $secondsс';
  }

  @override
  String durationHM(int hours, String minutes) {
    return '$hoursч $minutesм';
  }

  @override
  String durationMS(int minutes, String seconds) {
    return '$minutesм $secondsс';
  }

  @override
  String durationS(int seconds) {
    return '$secondsс';
  }

  @override
  String get sectionGeofencing => 'Геозоны';

  @override
  String get regionMonitoringTitle => 'Отслеживать вход и выход';

  @override
  String get regionMonitoringSubtitle =>
      'Записывать событие при входе в зону и выходе из неё';

  @override
  String get notifyOnEntryTitle => 'Реагировать на вход';

  @override
  String get notifyOnExitTitle => 'Реагировать на выход';

  @override
  String get sectionSlc => 'Отслеживание перемещений (SLC)';

  @override
  String get slcTitle => 'Отслеживать значимые перемещения';

  @override
  String get slcSubtitle =>
      'Грубая точность (~500 м–1 км). Работает даже после закрытия приложения.';

  @override
  String get sectionDiagnostics => 'Диагностика';

  @override
  String get localNotificationsTitle => 'Уведомления о событиях';

  @override
  String get localNotificationsSubtitle =>
      'Показывать баннер при каждом входе, выходе и перемещении';

  @override
  String get sectionActions => 'Действия';

  @override
  String get requestPermissionsTitle => 'Запросить разрешения';

  @override
  String get requestPermissionsSubtitle =>
      'Уведомления и геолокация («Всегда»)';

  @override
  String permissionResult(String status) {
    return 'Разрешение на геолокацию: $status';
  }

  @override
  String get resyncTitle => 'Обновить зоны в системе';

  @override
  String get resyncDone => 'Зоны обновлены';

  @override
  String get clearHistoryTitle => 'Очистить историю событий';

  @override
  String get clearDialogTitle => 'Очистить историю?';

  @override
  String get clearDialogBody =>
      'Все записанные события будут удалены. Зоны сохранятся.';

  @override
  String get clear => 'Очистить';

  @override
  String get refreshTooltip => 'Обновить';

  @override
  String lastHeartbeat(String time) {
    return 'Последняя проверка: $time';
  }

  @override
  String get countersHeader => 'Событий всего';

  @override
  String get noDiagnosticsYet => 'Данных пока нет — нажмите «обновить»';

  @override
  String get noEventsYet => 'События ещё не записаны';

  @override
  String regionStats(int active, int total) {
    return 'Активных зон: $active / 20 (лимит iOS)\nВсего зон: $total';
  }

  @override
  String get diagAuthorizationStatus => 'Разрешение на геолокацию';

  @override
  String get diagAccuracyAuthorization => 'Точность геолокации';

  @override
  String get diagLocationServicesEnabled => 'Службы геолокации';

  @override
  String get diagBackgroundRefreshStatus => 'Фоновое обновление';

  @override
  String get diagNotificationsAuthorized => 'Уведомления разрешены';

  @override
  String get diagMonitoredRegionsCount => 'Зон отслеживается системой';

  @override
  String get diagSlcEnabled => 'Отслеживание перемещений (SLC)';

  @override
  String get diagRegionMonitoringEnabled => 'Отслеживание входа/выхода';

  @override
  String get diagLaunchedByLocation => 'Запущено геособытием';

  @override
  String get diagAppVersion => 'Версия приложения';

  @override
  String get diagOsVersion => 'Версия iOS';

  @override
  String get diagBatteryPercent => 'Батарея, %';
}
