import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/asset.dart';
import '../models/user_model.dart';

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
      version: 6,
      onCreate: (db, _) async {
        await _createAllTables(db);
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
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS users (
              id            TEXT PRIMARY KEY,
              email         TEXT NOT NULL UNIQUE,
              display_name  TEXT NOT NULL,
              password_hash TEXT NOT NULL,
              created_at    INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS partner_invites (
              id           TEXT PRIMARY KEY,
              from_user_id TEXT NOT NULL,
              code         TEXT NOT NULL,
              expires_at   INTEGER NOT NULL,
              used         INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS partnerships (
              id         TEXT PRIMARY KEY,
              user_id_1  TEXT NOT NULL,
              user_id_2  TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');
          await db.execute(
              'ALTER TABLE assets ADD COLUMN userId TEXT NOT NULL DEFAULT ""');
        }
        if (oldVersion < 6) {
          try {
            await db.execute(
                'ALTER TABLE partnerships ADD COLUMN active INTEGER NOT NULL DEFAULT 1');
          } catch (e) {
            // Sütun zaten eklenmiş olabilir
          }
        }
      },
    );
  }

  Future<void> _createAllTables(Database db) async {
    await db.execute('''
      CREATE TABLE assets (
        id            TEXT    PRIMARY KEY,
        userId        TEXT    NOT NULL DEFAULT "",
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
    await db.execute('CREATE INDEX idx_snapshots_ts ON snapshots(ts)');
    await db.execute('''
      CREATE TABLE users (
        id            TEXT PRIMARY KEY,
        email         TEXT NOT NULL UNIQUE,
        display_name  TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        created_at    INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE partner_invites (
        id           TEXT PRIMARY KEY,
        from_user_id TEXT NOT NULL,
        code         TEXT NOT NULL,
        expires_at   INTEGER NOT NULL,
        used         INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE partnerships (
        id         TEXT PRIMARY KEY,
        user_id_1  TEXT NOT NULL,
        user_id_2  TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        active     INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  // ── Assets ──────────────────────────────────────────────────────────────

  Future<List<Asset>> fetchByUser(String userId) async {
    final rows = await (await _database).query(
      'assets',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'addedDate DESC',
    );
    return rows.map(Asset.fromMap).toList();
  }

  /// Eski varlıkları da getirir (userId boş olanlar dahil) — geriye dönük uyumluluk
  Future<List<Asset>> fetchAll() async {
    final rows =
        await (await _database).query('assets', orderBy: 'addedDate DESC');
    return rows.map(Asset.fromMap).toList();
  }

  /// userId = '' olan yetim varlıkları verilen kullanıcıya atar.
  /// Kullanıcı sistemi öncesinden kalan varlıkları migrate etmek için kullanılır.
  Future<int> claimOrphanedAssets(String userId) async {
    return (await _database).update(
      'assets',
      {'userId': userId},
      where: "userId = '' OR userId IS NULL",
    );
  }

  Future<int> countAssetsForUser(String userId) async {
    final rows = await (await _database).rawQuery(
      'SELECT COUNT(*) AS c FROM assets WHERE userId = ?',
      [userId],
    );
    final value = rows.isEmpty ? null : rows.first['c'];
    return value is int ? value : (value as num?)?.toInt() ?? 0;
  }

  Future<int> countOrphanedAssets() async {
    final rows = await (await _database).rawQuery(
      "SELECT COUNT(*) AS c FROM assets WHERE userId = '' OR userId IS NULL",
    );
    final value = rows.isEmpty ? null : rows.first['c'];
    return value is int ? value : (value as num?)?.toInt() ?? 0;
  }

  Future<int> claimLegacySnapshots(String userId) async {
    final db = await _database;
    final rows = await db.query(
      'snapshots',
      orderBy: 'ts ASC',
    );

    var updatedCount = 0;
    for (final row in rows) {
      final id = row['id'] as int?;
      final rawData = row['data'] as String?;
      if (id == null || rawData == null) continue;

      try {
        final decoded = jsonDecode(rawData) as Map<String, dynamic>;
        final snapshotUserId = (decoded['_userId'] as String?)?.trim() ?? '';
        if (snapshotUserId.isNotEmpty) continue;

        decoded['_userId'] = userId;
        await db.update(
          'snapshots',
          {'data': jsonEncode(decoded)},
          where: 'id = ?',
          whereArgs: [id],
        );
        updatedCount++;
      } catch (_) {
        // Bozuk snapshot varsa olduğu gibi bırak.
      }
    }

    return updatedCount;
  }

  Future<void> insert(Asset asset) async =>
      (await _database).insert('assets', asset.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  /// Ortak kodundan gelen varlığı içe aktar — zaten varsa üzerine yaz (resync için).
  Future<void> insertAssetSnapshot(Asset asset) async =>
      (await _database).insert('assets', asset.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> update(Asset asset) async => (await _database)
      .update('assets', asset.toMap(), where: 'id = ?', whereArgs: [asset.id]);

  Future<void> delete(String id) async =>
      (await _database).delete('assets', where: 'id = ?', whereArgs: [id]);

  // ── Portfolio snapshots ──────────────────────────────────────────────────

  Future<void> insertSnapshot(Map<String, double> categoryValues,
      {String userId = ''}) async {
    final db = await _database;
    final data = jsonEncode({...categoryValues, '_userId': userId});
    await db.insert('snapshots', {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    });
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 730))
        .millisecondsSinceEpoch;
    await db.delete('snapshots', where: 'ts < ?', whereArgs: [cutoff]);
  }

  Future<List<({int ts, Map<String, double> values})>> fetchSnapshots(
      int sinceMs,
      {String? userId}) async {
    final rows = await (await _database).query(
      'snapshots',
      where: 'ts >= ?',
      whereArgs: [sinceMs],
      orderBy: 'ts ASC',
    );

    return rows
        .map((r) {
          try {
            final raw =
                (jsonDecode(r['data'] as String) as Map<String, dynamic>);
            final snapshotUserId = (raw['_userId'] as String?)?.trim() ?? '';

            if (userId != null &&
                userId.isNotEmpty &&
                snapshotUserId != userId) {
              return null;
            }

            // _userId meta alanını çıkar, sadece varlık kategorilerini bırak
            final data = <String, double>{};
            for (final entry in raw.entries) {
              if (entry.key == '_userId') continue;
              if (entry.value is num) {
                data[entry.key] = (entry.value as num).toDouble();
              }
            }

            return (ts: r['ts'] as int, values: data);
          } catch (e) {
            // Hatalı bir snapshot tüm grafik akışını bozmasın
            return null;
          }
        })
        .whereType<({int ts, Map<String, double> values})>()
        .where((s) => s.values.isNotEmpty)
        .toList();
  }

  // ── Users ────────────────────────────────────────────────────────────────

  Future<void> insertUser(AppUser user) async =>
      (await _database).insert('users', user.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort);

  Future<AppUser?> getUserByEmail(String email) async {
    final rows = await (await _database).query(
      'users',
      where: 'email = ?',
      whereArgs: [email.toLowerCase().trim()],
    );
    if (rows.isEmpty) return null;
    return AppUser.fromMap(rows.first);
  }

  Future<AppUser?> getUserById(String id) async {
    try {
      final rows = await (await _database).query(
        'users',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return null;
      return AppUser.fromMap(rows.first);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateUser(AppUser user) async {
    final db = await _database;
    await db.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<List<AppUser>> getUsersByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final placeholders = ids.map((_) => '?').join(',');
    final rows = await (await _database).rawQuery(
      'SELECT * FROM users WHERE id IN ($placeholders)',
      ids,
    );
    return rows.map(AppUser.fromMap).toList();
  }

  Future<List<AppUser>> getAllUsers() async {
    final rows = await (await _database).query(
      'users',
      orderBy: 'created_at ASC',
    );
    return rows.map(AppUser.fromMap).toList();
  }

  // ── Partner invites ──────────────────────────────────────────────────────

  Future<void> insertInvite({
    required String id,
    required String fromUserId,
    required String code,
    required DateTime expiresAt,
  }) async {
    await (await _database).insert(
        'partner_invites',
        {
          'id': id,
          'from_user_id': fromUserId,
          'code': code,
          'expires_at': expiresAt.millisecondsSinceEpoch,
          'used': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Kodu geçerli, süresi dolmamış, kullanılmamış bir davet olarak arar.
  Future<Map<String, dynamic>?> getValidInvite(String code) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await (await _database).query(
      'partner_invites',
      where: 'code = ? AND used = 0 AND expires_at > ?',
      whereArgs: [code, now],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> markInviteUsed(String id) async => (await _database).update(
        'partner_invites',
        {'used': 1},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<int> countDistinctInviteSenders(List<String> userIds) async {
    if (userIds.isEmpty) return 0;

    final placeholders = userIds.map((_) => '?').join(',');
    final rows = await (await _database).rawQuery(
      '''
      SELECT COUNT(DISTINCT from_user_id) AS sender_count
      FROM partner_invites
      WHERE from_user_id IN ($placeholders)
      ''',
      userIds,
    );

    final value = rows.isEmpty ? null : rows.first['sender_count'];
    return value is int ? value : (value as num?)?.toInt() ?? 0;
  }

  // ── Partnerships ─────────────────────────────────────────────────────────

  Future<void> insertPartnership({
    required String id,
    required String userId1,
    required String userId2,
  }) async {
    await (await _database).insert(
        'partnerships',
        {
          'id': id,
          'user_id_1': userId1,
          'user_id_2': userId2,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<String>> getPartnerIds(String userId,
      {bool onlyActive = true}) async {
    final db = await _database;
    final rows = await db.rawQuery(
      '''SELECT user_id_1, user_id_2 FROM partnerships
         WHERE (user_id_1 = ? OR user_id_2 = ?)${onlyActive ? ' AND active = 1' : ''}''',
      [userId, userId],
    );
    return rows.map((r) {
      final u1 = r['user_id_1'] as String;
      final u2 = r['user_id_2'] as String;
      return u1 == userId ? u2 : u1;
    }).toList();
  }

  Future<List<({String id, bool active})>> getPartnershipsWithStatus(
      String userId) async {
    final db = await _database;
    final rows = await db.rawQuery(
      '''SELECT user_id_1, user_id_2, active FROM partnerships
         WHERE user_id_1 = ? OR user_id_2 = ?''',
      [userId, userId],
    );
    return rows.map((r) {
      final u1 = r['user_id_1'] as String;
      final u2 = r['user_id_2'] as String;
      final active = (r['active'] as int) == 1;
      return (id: u1 == userId ? u2 : u1, active: active);
    }).toList();
  }

  Future<void> setPartnershipActive(
      String uid1, String uid2, bool active) async {
    final db = await _database;
    await db.rawUpdate(
      '''UPDATE partnerships SET active = ? 
         WHERE (user_id_1 = ? AND user_id_2 = ?) 
            OR (user_id_1 = ? AND user_id_2 = ?)''',
      [active ? 1 : 0, uid1, uid2, uid2, uid1],
    );
  }

  Future<bool> partnershipExists(String uid1, String uid2) async {
    final rows = await (await _database).rawQuery(
      '''SELECT id FROM partnerships
         WHERE (user_id_1 = ? AND user_id_2 = ?)
            OR (user_id_1 = ? AND user_id_2 = ?)''',
      [uid1, uid2, uid2, uid1],
    );
    return rows.isNotEmpty;
  }

  Future<void> removePartnership(String uid1, String uid2) async =>
      (await _database).rawDelete(
        '''DELETE FROM partnerships
           WHERE (user_id_1 = ? AND user_id_2 = ?)
              OR (user_id_1 = ? AND user_id_2 = ?)''',
        [uid1, uid2, uid2, uid1],
      );
}
