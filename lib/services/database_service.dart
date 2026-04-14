import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/asset.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dbPath = join(await getDatabasesPath(), 'portfoy.db');
    return openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE assets (
            id            TEXT    PRIMARY KEY,
            name          TEXT    NOT NULL,
            ticker        TEXT    NOT NULL,
            type          TEXT    NOT NULL,
            subCategory   TEXT,
            unitType      TEXT    DEFAULT 'piece',
            quantity      REAL    NOT NULL,
            purchasePrice REAL    NOT NULL,
            currency      TEXT    NOT NULL,
            currentPrice  REAL    NOT NULL,
            lastUpdated   INTEGER,
            addedDate     INTEGER NOT NULL,
            notes         TEXT    NOT NULL,
            isManualPrice INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE snapshots (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            ts        INTEGER NOT NULL,
            data      TEXT    NOT NULL
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_snapshots_ts ON snapshots(ts)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE assets ADD COLUMN subCategory TEXT');
          await db.execute(
              'ALTER TABLE assets ADD COLUMN unitType TEXT DEFAULT "piece"');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS snapshots (
              id   INTEGER PRIMARY KEY AUTOINCREMENT,
              ts   INTEGER NOT NULL,
              data TEXT    NOT NULL
            )
          ''');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_snapshots_ts ON snapshots(ts)');
        }
      },
    );
  }

  // ── Assets ──────────────────────────────────────────────────────────────

  Future<List<Asset>> fetchAll() async {
    final rows =
        await (await _database).query('assets', orderBy: 'addedDate DESC');
    return rows.map(Asset.fromMap).toList();
  }

  Future<void> insert(Asset asset) async =>
      (await _database).insert('assets', asset.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> update(Asset asset) async =>
      (await _database).update('assets', asset.toMap(),
          where: 'id = ?', whereArgs: [asset.id]);

  Future<void> delete(String id) async =>
      (await _database).delete('assets', where: 'id = ?', whereArgs: [id]);

  // ── Portfolio snapshots ──────────────────────────────────────────────────

  /// Saves a portfolio snapshot with category-level TRY values.
  Future<void> insertSnapshot(Map<String, double> categoryValues) async {
    final db = await _database;
    final data = jsonEncode(categoryValues);
    await db.insert('snapshots', {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    });
    // Prune snapshots older than 2 years to keep DB small
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 730))
        .millisecondsSinceEpoch;
    await db.delete('snapshots', where: 'ts < ?', whereArgs: [cutoff]);
  }

  /// Fetches snapshots from [sinceMs] (epoch ms) to now, ordered ascending.
  Future<List<({int ts, Map<String, double> values})>> fetchSnapshots(
      int sinceMs) async {
    final rows = await (await _database).query(
      'snapshots',
      where: 'ts >= ?',
      whereArgs: [sinceMs],
      orderBy: 'ts ASC',
    );

    return rows.map((r) {
      final data =
          (jsonDecode(r['data'] as String) as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()));
      return (ts: r['ts'] as int, values: data);
    }).toList();
  }
}
