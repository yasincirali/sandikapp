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
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE assets (
          id            TEXT    PRIMARY KEY,
          name          TEXT    NOT NULL,
          ticker        TEXT    NOT NULL,
          type          TEXT    NOT NULL,
          quantity      REAL    NOT NULL,
          purchasePrice REAL    NOT NULL,
          currency      TEXT    NOT NULL,
          currentPrice  REAL    NOT NULL,
          lastUpdated   INTEGER,
          addedDate     INTEGER NOT NULL,
          notes         TEXT    NOT NULL,
          isManualPrice INTEGER NOT NULL
        )
      '''),
    );
  }

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
      (await _database)
          .delete('assets', where: 'id = ?', whereArgs: [id]);
}
