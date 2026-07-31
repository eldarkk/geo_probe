import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Local SQLite storage: regions, event history, key-value config.
class ProbeDb {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'geo_probe.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE regions(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            radius REAL NOT NULL,
            active INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE events(
            uuid TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            region_id TEXT,
            lat REAL,
            lng REAL,
            accuracy REAL,
            event_ts INTEGER NOT NULL,
            received_ts INTEGER NOT NULL,
            app_state TEXT,
            battery INTEGER,
            detail TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_events_ts ON events(event_ts)');
        await db.execute('CREATE INDEX idx_events_type ON events(type)');
        await db.execute('''
          CREATE TABLE config(
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  // ---- Regions ----

  Future<List<Region>> getRegions() async {
    final db = await database;
    final rows = await db.query('regions', orderBy: 'name');
    return rows.map(Region.fromMap).toList();
  }

  Future<void> upsertRegion(Region region) async {
    final db = await database;
    await db.insert('regions', region.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteRegion(String id) async {
    final db = await database;
    await db.delete('regions', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Events ----

  /// Inserts events, ignoring duplicates by uuid (idempotent — duplicate
  /// EXITs and the iOS post-reboot double-fire are documented behaviours).
  /// Returns only the events that were NOT already stored, so callers can
  /// react (Telegram, counters) to genuinely new events: everything drained
  /// from the native JSONL was possibly already ingested via the live stream.
  Future<List<GeoEvent>> insertEvents(Iterable<GeoEvent> events) async {
    final incoming = events.toList();
    if (incoming.isEmpty) return const [];
    final db = await database;
    final known = <String>{};
    for (var i = 0; i < incoming.length; i += 500) {
      final chunk = incoming.sublist(
          i, i + 500 > incoming.length ? incoming.length : i + 500);
      final rows = await db.query('events',
          columns: ['uuid'],
          where: 'uuid IN (${List.filled(chunk.length, '?').join(',')})',
          whereArgs: chunk.map((e) => e.uuid).toList());
      known.addAll(rows.map((r) => r['uuid'] as String));
    }
    final fresh = <GeoEvent>[];
    for (final e in incoming) {
      if (known.add(e.uuid)) fresh.add(e);
    }
    if (fresh.isEmpty) return const [];
    final batch = db.batch();
    for (final e in fresh) {
      batch.insert('events', e.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    return fresh;
  }

  Future<List<GeoEvent>> eventsForDay(DateTime day, {Set<String>? types}) async {
    final db = await database;
    final start = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final end = DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch;
    var where = 'event_ts >= ? AND event_ts < ?';
    final args = <Object>[start, end];
    if (types != null && types.isNotEmpty) {
      where += ' AND type IN (${List.filled(types.length, '?').join(',')})';
      args.addAll(types);
    }
    final rows = await db.query('events',
        where: where, whereArgs: args, orderBy: 'event_ts ASC');
    return rows.map(GeoEvent.fromMap).toList();
  }

  Future<List<GeoEvent>> allEvents() async {
    final db = await database;
    final rows = await db.query('events', orderBy: 'event_ts ASC');
    return rows.map(GeoEvent.fromMap).toList();
  }

  Future<Map<String, int>> eventCountsByType() async {
    final db = await database;
    final rows = await db
        .rawQuery('SELECT type, COUNT(*) AS c FROM events GROUP BY type');
    return {
      for (final r in rows) r['type'] as String: (r['c'] as num).toInt(),
    };
  }

  Future<void> clearEvents() async {
    final db = await database;
    await db.delete('events');
  }

  // ---- Config ----

  Future<String?> getConfigValue(String key) async {
    final db = await database;
    final rows =
        await db.query('config', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> setConfigValue(String key, String value) async {
    final db = await database;
    await db.insert('config', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
