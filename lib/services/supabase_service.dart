import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/asset.dart';
import '../models/signal_alert.dart';
import '../models/signal_frequency.dart';
import '../models/signal_preference.dart';
import '../models/user_model.dart';
import 'db_logger.dart';

/// Tüm Supabase veri erişimi bu sınıf üzerinden geçer.
/// RLS kuralları Supabase tarafında uygulandığı için burada
/// ekstra kullanıcı filtresi yazmaya gerek yoktur.
class SupabaseService {
  static final SupabaseService instance = SupabaseService._();
  SupabaseService._();

  SupabaseClient get _db => Supabase.instance.client;
  final _log = DbLogger.instance;

  String? get _uid => _db.auth.currentUser?.id;
  bool? _hasPerSideHidden;

  Future<bool> _supportsPerSideHidden() async {
    final cached = _hasPerSideHidden;
    if (cached != null) return cached;
    try {
      await _db.from('partnerships').select('hidden_for_1').limit(1);
      _hasPerSideHidden = true;
    } catch (_) {
      _hasPerSideHidden = false;
    }
    return _hasPerSideHidden!;
  }

  // ── Profiles ─────────────────────────────────────────────────────────────

  Future<AppUser?> getProfile(String userId) async {
    final row = await _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.getProfile',
      table: 'profiles',
      op: 'SELECT',
      request: {'id': userId},
      call: () => _db.from('profiles').select().eq('id', userId).maybeSingle(),
    );
    if (row == null) return null;
    return AppUser.fromSupabase(row);
  }

  Future<AppUser?> getCurrentProfile() async {
    final uid = _uid;
    if (uid == null) return null;
    return getProfile(uid);
  }

  Future<void> upsertProfile(AppUser user) async {
    final body = {
      'id': user.id,
      'email': user.email,
      'display_name': user.displayName,
      'onboarding_completed': user.onboardingCompleted,
    };
    await _log.log<void>(
      source: 'SupabaseService.upsertProfile',
      table: 'profiles',
      op: 'UPSERT',
      request: body,
      call: () => _db.from('profiles').upsert(body),
    );
  }

  Future<void> markOnboardingCompleted(String userId) async {
    await _log.log<void>(
      source: 'SupabaseService.markOnboardingCompleted',
      table: 'profiles',
      op: 'UPDATE',
      request: {'id': userId, 'onboarding_completed': true},
      call: () => _db
          .from('profiles')
          .update({'onboarding_completed': true}).eq('id', userId),
    );
  }

  Future<List<AppUser>> getProfilesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    // Her profili ayrı ayrı çek — inFilter RLS policy'siyle bazen uyumsuz davranır
    final results = await Future.wait(ids.map((id) => getProfile(id)));
    return results.whereType<AppUser>().toList();
  }

  // ── Assets ───────────────────────────────────────────────────────────────

  Future<List<Asset>> fetchByUser(String userId) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchByUser',
      table: 'assets',
      op: 'SELECT',
      request: {'user_id': userId, 'order': 'added_date desc'},
      call: () => _db
          .from('assets')
          .select()
          .eq('user_id', userId)
          .order('added_date', ascending: false),
    );
    return rows.map<Asset>((r) => Asset.fromSupabase(r)).toList();
  }

  Future<void> insertAsset(Asset asset) async {
    final body = asset.toSupabase();
    await _log.log<void>(
      source: 'SupabaseService.insertAsset',
      table: 'assets',
      op: 'INSERT',
      request: {'id': body['id'], 'user_id': body['user_id'], 'ticker': body['ticker']},
      call: () => _db.from('assets').insert(body),
    );
  }

  /// Partner kodundan gelen varlığı içe aktar — zaten varsa güncelle (resync)
  Future<void> upsertAsset(Asset asset) async {
    final body = asset.toSupabase();
    await _log.log<void>(
      source: 'SupabaseService.upsertAsset',
      table: 'assets',
      op: 'UPSERT',
      request: {'id': body['id'], 'user_id': body['user_id'], 'ticker': body['ticker']},
      call: () => _db.from('assets').upsert(body),
    );
  }

  Future<void> updateAsset(Asset asset) async {
    final body = asset.toSupabase();
    await _log.log<void>(
      source: 'SupabaseService.updateAsset',
      table: 'assets',
      op: 'UPDATE',
      request: {'id': asset.id, 'ticker': body['ticker']},
      call: () => _db.from('assets').update(body).eq('id', asset.id),
    );
  }

  Future<void> deleteAsset(String id) async {
    await _log.log<void>(
      source: 'SupabaseService.deleteAsset',
      table: 'assets',
      op: 'DELETE',
      request: {'id': id},
      call: () => _db.from('assets').delete().eq('id', id),
    );
  }

  /// Yumuşak silme — satır kalır, `deleted_at` damgalanır.
  ///
  /// Varlık silmenin normal yolu budur. [deleteAsset] (fiziksel DELETE)
  /// kaydı geçmişten de yok eder; hareket listesi ham ledger'dan
  /// beslendiği için o varlığın Alım/Satım/Temettü satırlarını da
  /// götürürdü.
  Future<void> softDeleteAssets(List<String> ids, DateTime deletedAt) async {
    if (ids.isEmpty) return;
    await _log.log<void>(
      source: 'SupabaseService.softDeleteAssets',
      table: 'assets',
      op: 'UPDATE',
      request: {'ids': ids.length, 'deleted_at': deletedAt.toIso8601String()},
      call: () => _db
          .from('assets')
          .update({'deleted_at': deletedAt.toUtc().toIso8601String()})
          .inFilter('id', ids),
    );
  }

  Future<int> countAssetsForUser(String userId) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.countAssetsForUser',
      table: 'assets',
      op: 'SELECT',
      request: {'user_id': userId, 'columns': 'id'},
      call: () => _db.from('assets').select('id').eq('user_id', userId),
    );
    return rows.length;
  }

  // ── Snapshots ─────────────────────────────────────────────────────────────

  Future<void> insertSnapshot(Map<String, double> categoryValues,
      {String userId = ''}) async {
    final uid = userId.isNotEmpty ? userId : (_uid ?? '');
    if (uid.isEmpty) return;

    await _log.log<void>(
      source: 'SupabaseService.insertSnapshot',
      table: 'snapshots',
      op: 'INSERT',
      request: {'user_id': uid, 'categories': categoryValues.keys.toList()},
      call: () => _db.from('snapshots').insert({
        'user_id': uid,
        'data': categoryValues,
      }),
    );

    // 2 yıl retention
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 730))
        .toUtc()
        .toIso8601String();
    await _log.log<void>(
      source: 'SupabaseService.insertSnapshot[retention]',
      table: 'snapshots',
      op: 'DELETE',
      request: {'user_id': uid, 'lt_ts': cutoff},
      call: () =>
          _db.from('snapshots').delete().eq('user_id', uid).lt('ts', cutoff),
    );
  }

  Future<List<({int ts, Map<String, double> values})>> fetchSnapshots(
      int sinceMs,
      {String? userId}) async {
    final uid = userId ?? _uid ?? '';
    if (uid.isEmpty) return [];

    final since =
        DateTime.fromMillisecondsSinceEpoch(sinceMs).toUtc().toIso8601String();

    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchSnapshots',
      table: 'snapshots',
      op: 'SELECT',
      request: {'user_id': uid, 'since': since},
      call: () => _db
          .from('snapshots')
          .select()
          .eq('user_id', uid)
          .gte('ts', since)
          .order('ts', ascending: true),
    );

    final out = <({int ts, Map<String, double> values})>[];
    for (final r in rows) {
      try {
        final tsRaw = r['ts'];
        if (tsRaw is! String) continue;
        final ts = DateTime.parse(tsRaw).millisecondsSinceEpoch;
        final raw = r['data'];
        if (raw is! Map<String, dynamic>) continue;
        final data = <String, double>{};
        raw.forEach((k, v) {
          if (v is num) data[k] = v.toDouble();
          // Eski snapshot'larda v string olabilir — sessizce atla
        });
        if (data.isNotEmpty) out.add((ts: ts, values: data));
      } catch (_) {
        // Bozuk satır tüm fetch'i öldürmesin
        continue;
      }
    }
    return out;
  }

  // ── Partner invites ───────────────────────────────────────────────────────

  Future<void> insertInvite({
    required String id,
    required String fromUserId,
    required String code,
    required String payload,
    required DateTime expiresAt,
    String? toUserId,
    String? requesterName,
    String status = 'pending',
  }) async {
    final body = {
      'id': id,
      'from_user_id': fromUserId,
      if (toUserId != null) 'to_user_id': toUserId,
      if (requesterName != null) 'requester_name': requesterName,
      'code': code,
      'payload': payload,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'used': false,
      'status': status,
    };
    await _log.log<void>(
      source: 'SupabaseService.insertInvite',
      table: 'partner_invites',
      op: 'UPSERT',
      request: {
        'id': id,
        'from_user_id': fromUserId,
        'code': code,
        'status': status,
        'expires_at': expiresAt.toUtc().toIso8601String(),
      },
      call: () => _db.from('partner_invites').upsert(body),
    );
  }

  Future<Map<String, dynamic>?> getValidInvite(String code) async {
    return _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.getValidInvite',
      table: 'partner_invites',
      op: 'SELECT',
      request: {'code': code, 'used': false},
      call: () => _db
          .from('partner_invites')
          .select()
          .eq('code', code)
          .eq('used', false)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .maybeSingle(),
    );
  }

  Future<void> markInviteUsed(String id) async {
    await _log.log<void>(
      source: 'SupabaseService.markInviteUsed',
      table: 'partner_invites',
      op: 'UPDATE',
      request: {'id': id, 'used': true},
      call: () =>
          _db.from('partner_invites').update({'used': true}).eq('id', id),
    );
  }

  /// Kod girildiğinde davetiyeye to_user_id ve status=pending yaz
  Future<void> setInviteTarget({
    required String inviteId,
    required String toUserId,
    required String requesterName,
  }) async {
    await _log.log<void>(
      source: 'SupabaseService.setInviteTarget',
      table: 'partner_invites',
      op: 'UPDATE',
      request: {
        'id': inviteId,
        'to_user_id': toUserId,
        'requester_name': requesterName,
        'status': 'pending',
      },
      call: () => _db.from('partner_invites').update({
        'to_user_id': toUserId,
        'requester_name': requesterName,
        'status': 'pending',
      }).eq('id', inviteId),
    );
  }

  /// Kod sahibi onayladığında
  Future<void> acceptInvite(String inviteId) async {
    await _log.log<void>(
      source: 'SupabaseService.acceptInvite',
      table: 'partner_invites',
      op: 'UPDATE',
      request: {'id': inviteId, 'status': 'accepted', 'used': true},
      call: () => _db.from('partner_invites').update({
        'status': 'accepted',
        'used': true,
      }).eq('id', inviteId),
    );
  }

  /// Kod sahibi reddetti
  Future<void> rejectInvite(String inviteId) async {
    await _log.log<void>(
      source: 'SupabaseService.rejectInvite',
      table: 'partner_invites',
      op: 'UPDATE',
      request: {'id': inviteId, 'status': 'rejected', 'used': true},
      call: () => _db.from('partner_invites').update({
        'status': 'rejected',
        'used': true,
      }).eq('id', inviteId),
    );
  }

  /// Mevcut kullanıcıya gelen onay bekleyen davetleri getir
  Future<List<Map<String, dynamic>>> getPendingInvitesForMe(
      String userId) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.getPendingInvitesForMe',
      table: 'partner_invites',
      op: 'SELECT',
      request: {'from_user_id': userId, 'status': 'pending', 'used': false},
      call: () => _db
          .from('partner_invites')
          .select()
          .eq('from_user_id', userId)
          .eq('status', 'pending')
          .eq('used', false)
          .not('to_user_id', 'is', null)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String()),
    );
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Kod giren kişi için sonucu polling ile kontrol et
  Future<String?> getInviteStatus(String inviteId) async {
    final row = await _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.getInviteStatus',
      table: 'partner_invites',
      op: 'SELECT',
      request: {'id': inviteId, 'columns': 'status'},
      call: () => _db
          .from('partner_invites')
          .select('status')
          .eq('id', inviteId)
          .maybeSingle(),
    );
    return row?['status'] as String?;
  }

  Future<Map<String, dynamic>?> getInviteById(String inviteId) async {
    return _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.getInviteById',
      table: 'partner_invites',
      op: 'SELECT',
      request: {'id': inviteId},
      call: () => _db
          .from('partner_invites')
          .select()
          .eq('id', inviteId)
          .maybeSingle(),
    );
  }

  // ── Push tokens ───────────────────────────────────────────────────────────

  Future<void> upsertPushToken({
    required String userId,
    required String token,
    required String platform,
  }) async {
    await _log.log<void>(
      source: 'SupabaseService.upsertPushToken',
      table: 'user_push_tokens',
      op: 'UPSERT',
      request: {'user_id': userId, 'platform': platform},
      call: () => _db.from('user_push_tokens').upsert(
        {
          'user_id': userId,
          'token': token,
          'platform': platform,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'token',
      ),
    );
  }

  Future<void> deletePushToken(String token) async {
    await _log.log<void>(
      source: 'SupabaseService.deletePushToken',
      table: 'user_push_tokens',
      op: 'DELETE',
      request: {'token': '[redacted]'},
      call: () => _db.from('user_push_tokens').delete().eq('token', token),
    );
  }

  // ── Sinyal tercihleri ─────────────────────────────────────────────────────

  /// Kullanıcının sunucudaki sinyal tercihlerini okur.
  ///
  /// Oturum açılışında çağrılır: sunucu doğruluk kaynağıdır, cihaz onu
  /// indirir. Kayıt yoksa boş liste döner — arayan bunu "ilk kurulum"
  /// olarak yorumlayıp yerel değerleri yukarı taşır.
  Future<List<SignalPreferenceRow>> fetchSignalPreferences(
      String userId) async {
    final rows = await _log.log<List<dynamic>>(
      source: 'SupabaseService.fetchSignalPreferences',
      table: 'signal_preferences',
      op: 'SELECT',
      request: {'user_id': userId},
      call: () => _db
          .from('signal_preferences')
          .select(
              'asset_type, threshold, indicators, neutral_push, signals_enabled, frequency, notify_hours')
          .eq('user_id', userId),
    );

    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        SignalPreferenceRow(
          assetType: r['asset_type'] as String,
          threshold: (r['threshold'] as num?)?.toInt() ?? 70,
          indicators:
              (r['indicators'] as List?)?.cast<String>().toList() ?? const [],
          neutralPush: r['neutral_push'] as bool? ?? false,
          // Sütun yoksa/boşsa açık kabul et — kullanıcıyı sessizce
          // bildirimsiz bırakmaktansa varsayılanı korumak doğru.
          signalsEnabled: r['signals_enabled'] as bool? ?? true,
          frequency: SignalFrequency.fromId(r['frequency'] as String?),
          notifyHours:
              (r['notify_hours'] as List?)?.map((e) => (e as num).toInt())
                      .toList() ??
                  const [11, 15],
        ),
    ];
  }

  /// Kullanıcının bir varlık türü için eşik/gösterge tercihlerini sunucuya
  /// yazar.
  ///
  /// Neden gerekli: sinyal analizi artık sunucuda (`analyze-signals` edge
  /// function) çalışıyor ve push kararını orada veriyor. Tercihler yalnızca
  /// cihazda kalırsa sunucu kullanıcının eşiğini bilemez ve herkese aynı
  /// varsayılanı uygular.
  ///
  /// SharedPreferences yazımı korunur (çevrimdışı okuma ve anlık UI için);
  /// burası ikinci, kalıcı kopyadır.
  Future<void> upsertSignalPreference({
    required String userId,
    required String assetType,
    required int threshold,
    required List<String> indicators,
    required bool neutralPush,
    required bool signalsEnabled,
    SignalFrequency? frequency,
    List<int>? notifyHours,
  }) async {
    await _log.log<void>(
      source: 'SupabaseService.upsertSignalPreference',
      table: 'signal_preferences',
      op: 'UPSERT',
      request: {
        'user_id': userId,
        'asset_type': assetType,
        'threshold': threshold,
        'indicators': indicators.length,
        'frequency': frequency?.id,
      },
      call: () => _db.from('signal_preferences').upsert(
        {
          'user_id': userId,
          'asset_type': assetType,
          'threshold': threshold,
          'indicators': indicators,
          'neutral_push': neutralPush,
          'signals_enabled': signalsEnabled,
          // Sıklık alanları YALNIZCA verildiğinde yazılır. Her upsert'te
          // koşulsuz göndermek, sıklığı değiştirmeyen bir eşik güncellemesinin
          // kullanıcının seçtiği sıklığı varsayılana döndürmesine yol açardı.
          if (frequency != null) 'frequency': frequency.id,
          if (notifyHours != null) 'notify_hours': notifyHours,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,asset_type',
      ),
    );
  }

  // ── Edge Functions ────────────────────────────────────────────────────────

  Future<void> sendPartnerInvitePush(String inviteId) async {
    final response = await _log.log(
      source: 'SupabaseService.sendPartnerInvitePush',
      table: 'functions/send-partner-invite-push',
      op: 'FUNCTION',
      request: {'inviteId': inviteId},
      call: () => _db.functions.invoke(
        'send-partner-invite-push',
        body: {'inviteId': inviteId},
      ),
    );

    if (response.status >= 400) {
      throw Exception('Push gonderilemedi: ${response.data}');
    }
  }

  // ── Partnerships ──────────────────────────────────────────────────────────

  Future<void> insertPartnership({
    required String id,
    required String userId1,
    required String userId2,
  }) async {
    final supportsHidden = await _supportsPerSideHidden();
    final existing = await _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.insertPartnership[check]',
      table: 'partnerships',
      op: 'SELECT',
      request: {'user_id_1': userId1, 'user_id_2': userId2},
      call: () => _db
          .from('partnerships')
          .select('id')
          .or('and(user_id_1.eq.$userId1,user_id_2.eq.$userId2),and(user_id_1.eq.$userId2,user_id_2.eq.$userId1)')
          .maybeSingle(),
    );

    if (existing != null) {
      await _log.log<void>(
        source: 'SupabaseService.insertPartnership[reset-hidden]',
        table: 'partnerships',
        op: 'UPDATE',
        request: supportsHidden
            ? {'id': existing['id'], 'hidden_for_1': false, 'hidden_for_2': false}
            : {'id': existing['id'], 'active': true},
        call: () => _db
            .from('partnerships')
            .update(supportsHidden
                ? {
                    'hidden_for_1': false,
                    'hidden_for_2': false,
                  }
                : {'active': true})
            .eq('id', existing['id'] as String),
      );
    } else {
      await _log.log<void>(
        source: 'SupabaseService.insertPartnership',
        table: 'partnerships',
        op: 'INSERT',
        request: {'id': id, 'user_id_1': userId1, 'user_id_2': userId2},
        call: () => _db.from('partnerships').insert(supportsHidden
            ? {
                'id': id,
                'user_id_1': userId1,
                'user_id_2': userId2,
                'hidden_for_1': false,
                'hidden_for_2': false,
              }
            : {
                'id': id,
                'user_id_1': userId1,
                'user_id_2': userId2,
                'active': true,
              }),
      );
    }
  }

  Future<List<String>> getPartnerIds(String userId,
      {bool onlyActive = true}) async {
    final supportsHidden = await _supportsPerSideHidden();
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.getPartnerIds',
      table: 'partnerships',
      op: 'SELECT',
      request: {'user_id': userId, 'only_active': onlyActive},
      call: () => _db
          .from('partnerships')
          .select(supportsHidden
              ? 'user_id_1, user_id_2, hidden_for_1, hidden_for_2'
              : 'user_id_1, user_id_2, active')
          .or('user_id_1.eq.$userId,user_id_2.eq.$userId'),
    );

    return rows.where((r) {
      if (!onlyActive) return true;
      if (!supportsHidden) {
        return r['active'] as bool? ?? true;
      }
      final isUser1 = (r['user_id_1'] as String) == userId;
      final hidden = isUser1
          ? (r['hidden_for_1'] as bool? ?? false)
          : (r['hidden_for_2'] as bool? ?? false);
      return !hidden;
    }).map<String>((r) {
      final u1 = r['user_id_1'] as String;
      final u2 = r['user_id_2'] as String;
      return u1 == userId ? u2 : u1;
    }).toList();
  }

  Future<List<({String id, bool active})>> getPartnershipsWithStatus(
      String userId) async {
    final supportsHidden = await _supportsPerSideHidden();
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.getPartnershipsWithStatus',
      table: 'partnerships',
      op: 'SELECT',
      request: {'user_id': userId},
      call: () => _db
          .from('partnerships')
          .select(supportsHidden
              ? 'user_id_1, user_id_2, hidden_for_1, hidden_for_2'
              : 'user_id_1, user_id_2, active')
          .or('user_id_1.eq.$userId,user_id_2.eq.$userId'),
    );

    return rows.map<({String id, bool active})>((r) {
      final u1 = r['user_id_1'] as String;
      final u2 = r['user_id_2'] as String;
      final isUser1 = u1 == userId;
      if (!supportsHidden) {
        return (id: isUser1 ? u2 : u1, active: r['active'] as bool? ?? true);
      }
      final hidden = isUser1
          ? (r['hidden_for_1'] as bool? ?? false)
          : (r['hidden_for_2'] as bool? ?? false);
      return (id: isUser1 ? u2 : u1, active: !hidden);
    }).toList();
  }

  Future<bool> partnershipExists(String uid1, String uid2) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.partnershipExists',
      table: 'partnerships',
      op: 'SELECT',
      request: {'user_id_1': uid1, 'user_id_2': uid2},
      call: () => _db
          .from('partnerships')
          .select('id')
          .or('and(user_id_1.eq.$uid1,user_id_2.eq.$uid2),and(user_id_1.eq.$uid2,user_id_2.eq.$uid1)'),
    );
    return rows.isNotEmpty;
  }

  /// Sadece isteği yapan kullanıcının tarafındaki gizleme durumunu günceller.
  Future<void> setPartnershipHidden(
      String currentUserId, String partnerId, bool hidden) async {
    final supportsHidden = await _supportsPerSideHidden();
    final row = await _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.setPartnershipHidden[find]',
      table: 'partnerships',
      op: 'SELECT',
      request: {'current_user': currentUserId, 'partner': partnerId},
      call: () => _db
          .from('partnerships')
          .select('id, user_id_1, user_id_2')
          .or('and(user_id_1.eq.$currentUserId,user_id_2.eq.$partnerId),and(user_id_1.eq.$partnerId,user_id_2.eq.$currentUserId)')
          .maybeSingle(),
    );
    if (row == null) return;

    final user1 = row['user_id_1'];
    if (user1 is! String) return;
    final isUser1 = user1 == currentUserId;
    final field = isUser1 ? 'hidden_for_1' : 'hidden_for_2';
    await _log.log<void>(
      source: 'SupabaseService.setPartnershipHidden[update]',
      table: 'partnerships',
      op: 'UPDATE',
      request: supportsHidden
          ? {'id': row['id'], field: hidden}
          : {'id': row['id'], 'active': !hidden},
      call: () => _db
          .from('partnerships')
          .update(supportsHidden ? {field: hidden} : {'active': !hidden})
          .eq('id', row['id'] as String),
    );
  }

  // Eski imza — geriye dönük uyumluluk için yönlendir
  Future<void> setPartnershipActive(
      String uid1, String uid2, bool active) async {
    await setPartnershipHidden(uid1, uid2, !active);
  }

  Future<void> removePartnership(String uid1, String uid2) async {
    await _log.log<void>(
      source: 'SupabaseService.removePartnership',
      table: 'partnerships',
      op: 'DELETE',
      request: {'user_id_1': uid1, 'user_id_2': uid2},
      call: () => _db.from('partnerships').delete().or(
          'and(user_id_1.eq.$uid1,user_id_2.eq.$uid2),and(user_id_1.eq.$uid2,user_id_2.eq.$uid1)'),
    );
  }

  /// Profiles tablosunda kaydı olmayan ortaklar için partner_invites'tan isim çekip AppUser listesi döner.
  Future<List<AppUser>> resolveNamesFromInvites(
      String currentUserId, List<String> missingPartnerIds) async {
    if (missingPartnerIds.isEmpty) return [];

    final result = <AppUser>[];

    for (final partnerId in missingPartnerIds) {
      Map<String, dynamic>? row;
      try {
        row = await _log.log<Map<String, dynamic>?>(
          source: 'SupabaseService.resolveNamesFromInvites',
          table: 'partner_invites',
          op: 'SELECT',
          request: {'partner_id': partnerId},
          call: () => _db
              .from('partner_invites')
              .select('requester_name, payload, from_user_id, to_user_id')
              .or('from_user_id.eq.$partnerId,to_user_id.eq.$partnerId')
              .order('expires_at', ascending: false)
              .limit(1)
              .maybeSingle(),
        );
      } catch (_) {}

      if (row == null) continue;

      String? name;
      if ((row['to_user_id'] as String?) == partnerId) {
        name = (row['requester_name'] as String?)?.trim();
      }
      if (name == null || name.isEmpty) continue;

      final user = AppUser(
        id: partnerId,
        email: '',
        displayName: name,
        createdAt: DateTime.now(),
      );
      try {
        await upsertProfile(user);
      } catch (_) {}
      result.add(user);
    }

    return result;
  }

  // ── Signal Notifications ─────────────────────────────────────────────────

  /// Kullanıcı için son N gün içindeki (default 30) tüm sinyalleri getir.
  Future<List<SignalAlert>> fetchSignalNotifications({
    required String userId,
    int limit = 100,
  }) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchSignalNotifications',
      table: 'signal_notifications',
      op: 'SELECT',
      request: {'user_id': userId, 'limit': limit},
      call: () => _db
          .from('signal_notifications')
          .select()
          .eq('user_id', userId)
          .order('sent_at', ascending: false)
          .limit(limit),
    );
    return rows.map<SignalAlert>((r) => SignalAlert.fromMap(r)).toList();
  }

  /// Aynı asset için gönderilmiş son sinyal (dismissed dahil).
  /// De-dup için: yeni sinyal == son sinyal ise skip.
  Future<SignalAlert?> fetchLastSignalForAsset({
    required String userId,
    required String assetId,
  }) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchLastSignalForAsset',
      table: 'signal_notifications',
      op: 'SELECT',
      request: {'user_id': userId, 'asset_id': assetId},
      call: () => _db
          .from('signal_notifications')
          .select()
          .eq('user_id', userId)
          .eq('asset_id', assetId)
          .order('sent_at', ascending: false)
          .limit(1),
    );
    if (rows.isEmpty) return null;
    return SignalAlert.fromMap(rows.first);
  }

  Future<SignalAlert> insertSignalNotification({
    required String userId,
    required SignalAlert alert,
  }) async {
    final body = alert.toInsertMap(userId);
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.insertSignalNotification',
      table: 'signal_notifications',
      op: 'INSERT',
      request: {
        'user_id': userId,
        'asset_id': alert.assetId,
        'signal': body['signal'],
      },
      call: () =>
          _db.from('signal_notifications').insert(body).select().limit(1),
    );
    if (rows.isEmpty) {
      // Fallback: insert döndürmedi, çekilen değerle devam et
      return alert;
    }
    return SignalAlert.fromMap(rows.first);
  }

  Future<void> dismissSignalNotification(String id) async {
    await _log.log<void>(
      source: 'SupabaseService.dismissSignalNotification',
      table: 'signal_notifications',
      op: 'UPDATE',
      request: {'id': id, 'dismissed_at': 'now()'},
      call: () => _db
          .from('signal_notifications')
          .update({'dismissed_at': DateTime.now().toIso8601String()})
          .eq('id', id),
    );
  }

  Future<void> deleteSignalNotification(String id) async {
    await _log.log<void>(
      source: 'SupabaseService.deleteSignalNotification',
      table: 'signal_notifications',
      op: 'DELETE',
      request: {'id': id},
      call: () =>
          _db.from('signal_notifications').delete().eq('id', id),
    );
  }
}
