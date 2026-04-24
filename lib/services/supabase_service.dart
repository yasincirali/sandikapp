import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/asset.dart';
import '../models/user_model.dart';

/// Tüm Supabase veri erişimi bu sınıf üzerinden geçer.
/// RLS kuralları Supabase tarafında uygulandığı için burada
/// ekstra kullanıcı filtresi yazmaya gerek yoktur.
class SupabaseService {
  static final SupabaseService instance = SupabaseService._();
  SupabaseService._();

  SupabaseClient get _db => Supabase.instance.client;

  String? get _uid => _db.auth.currentUser?.id;

  // ── Profiles ─────────────────────────────────────────────────────────────

  Future<AppUser?> getProfile(String userId) async {
    final row =
        await _db.from('profiles').select().eq('id', userId).maybeSingle();
    if (row == null) return null;
    return AppUser.fromSupabase(row);
  }

  Future<AppUser?> getCurrentProfile() async {
    final uid = _uid;
    if (uid == null) return null;
    return getProfile(uid);
  }

  Future<void> upsertProfile(AppUser user) async {
    await _db.from('profiles').upsert({
      'id': user.id,
      'email': user.email,
      'display_name': user.displayName,
    });
  }

  Future<List<AppUser>> getProfilesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    // Her profili ayrı ayrı çek — inFilter RLS policy'siyle bazen uyumsuz davranır
    final results = await Future.wait(ids.map((id) => getProfile(id)));
    return results.whereType<AppUser>().toList();
  }

  // ── Assets ───────────────────────────────────────────────────────────────

  Future<List<Asset>> fetchByUser(String userId) async {
    final rows = await _db
        .from('assets')
        .select()
        .eq('user_id', userId)
        .order('added_date', ascending: false);
    return rows.map<Asset>((r) => Asset.fromSupabase(r)).toList();
  }

  Future<void> insertAsset(Asset asset) async {
    await _db.from('assets').insert(asset.toSupabase());
  }

  /// Partner kodundan gelen varlığı içe aktar — zaten varsa güncelle (resync)
  Future<void> upsertAsset(Asset asset) async {
    await _db.from('assets').upsert(asset.toSupabase());
  }

  Future<void> updateAsset(Asset asset) async {
    await _db.from('assets').update(asset.toSupabase()).eq('id', asset.id);
  }

  Future<void> deleteAsset(String id) async {
    await _db.from('assets').delete().eq('id', id);
  }

  Future<int> countAssetsForUser(String userId) async {
    final rows = await _db.from('assets').select('id').eq('user_id', userId);
    return rows.length;
  }

  // ── Snapshots ─────────────────────────────────────────────────────────────

  Future<void> insertSnapshot(Map<String, double> categoryValues,
      {String userId = ''}) async {
    final uid = userId.isNotEmpty ? userId : (_uid ?? '');
    if (uid.isEmpty) return;

    await _db.from('snapshots').insert({
      'user_id': uid,
      'data': categoryValues,
    });

    // 2 yıl retention
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 730))
        .toUtc()
        .toIso8601String();
    await _db.from('snapshots').delete().eq('user_id', uid).lt('ts', cutoff);
  }

  Future<List<({int ts, Map<String, double> values})>> fetchSnapshots(
      int sinceMs,
      {String? userId}) async {
    final uid = userId ?? _uid ?? '';
    if (uid.isEmpty) return [];

    final since =
        DateTime.fromMillisecondsSinceEpoch(sinceMs).toUtc().toIso8601String();

    final rows = await _db
        .from('snapshots')
        .select()
        .eq('user_id', uid)
        .gte('ts', since)
        .order('ts', ascending: true);

    return rows
        .map<({int ts, Map<String, double> values})>((r) {
          final ts = DateTime.parse(r['ts'] as String).millisecondsSinceEpoch;
          final raw = r['data'] as Map<String, dynamic>;
          final data = raw.map((k, v) => MapEntry(k, (v as num).toDouble()));
          return (ts: ts, values: data);
        })
        .where((s) => s.values.isNotEmpty)
        .toList();
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
    await _db.from('partner_invites').upsert({
      'id': id,
      'from_user_id': fromUserId,
      if (toUserId != null) 'to_user_id': toUserId,
      if (requesterName != null) 'requester_name': requesterName,
      'code': code,
      'payload': payload,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'used': false,
      'status': status,
    });
  }

  Future<Map<String, dynamic>?> getValidInvite(String code) async {
    final row = await _db
        .from('partner_invites')
        .select()
        .eq('code', code)
        .eq('used', false)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .maybeSingle();
    return row;
  }

  Future<void> markInviteUsed(String id) async {
    await _db.from('partner_invites').update({'used': true}).eq('id', id);
  }

  /// Kod girildiğinde davetiyeye to_user_id ve status=pending yaz
  Future<void> setInviteTarget({
    required String inviteId,
    required String toUserId,
    required String requesterName,
  }) async {
    await _db.from('partner_invites').update({
      'to_user_id': toUserId,
      'requester_name': requesterName,
      'status': 'pending',
    }).eq('id', inviteId);
  }

  /// Kod sahibi onayladığında
  Future<void> acceptInvite(String inviteId) async {
    await _db.from('partner_invites').update({
      'status': 'accepted',
      'used': true,
    }).eq('id', inviteId);
  }

  /// Kod sahibi reddetti
  Future<void> rejectInvite(String inviteId) async {
    await _db.from('partner_invites').update({
      'status': 'rejected',
      'used': true,
    }).eq('id', inviteId);
  }

  /// Mevcut kullanıcıya gelen onay bekleyen davetleri getir
  Future<List<Map<String, dynamic>>> getPendingInvitesForMe(
      String userId) async {
    final rows = await _db
        .from('partner_invites')
        .select()
        .eq('from_user_id', userId)
        .eq('status', 'pending')
        .eq('used', false)
        .not('to_user_id', 'is', null) // sadece birisi kodu girdiyse göster
        .gt('expires_at', DateTime.now().toUtc().toIso8601String());
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Kod giren kişi için sonucu polling ile kontrol et
  Future<String?> getInviteStatus(String inviteId) async {
    final row = await _db
        .from('partner_invites')
        .select('status')
        .eq('id', inviteId)
        .maybeSingle();
    return row?['status'] as String?;
  }

  Future<Map<String, dynamic>?> getInviteById(String inviteId) async {
    return await _db
        .from('partner_invites')
        .select()
        .eq('id', inviteId)
        .maybeSingle();
  }

  // ── Partnerships ──────────────────────────────────────────────────────────

  Future<void> upsertPushToken({
    required String userId,
    required String token,
    required String platform,
  }) async {
    await _db.from('user_push_tokens').upsert(
      {
        'user_id': userId,
        'token': token,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'token',
    );
  }

  Future<void> deletePushToken(String token) async {
    await _db.from('user_push_tokens').delete().eq('token', token);
  }

  Future<void> sendPartnerInvitePush(String inviteId) async {
    final response = await _db.functions.invoke(
      'send-partner-invite-push',
      body: {'inviteId': inviteId},
    );

    if (response.status >= 400) {
      throw Exception('Push gonderilemedi: ${response.data}');
    }
  }

  Future<void> insertPartnership({
    required String id,
    required String userId1,
    required String userId2,
  }) async {
    // Önce aynı çiftle silinmiş/var olan kayıt var mı kontrol et
    // Varsa güncelle, yoksa ekle — duplicate constraint'i önlemek için
    final existing = await _db.from('partnerships').select('id').or(
        'and(user_id_1.eq.$userId1,user_id_2.eq.$userId2),and(user_id_1.eq.$userId2,user_id_2.eq.$userId1)').maybeSingle();

    if (existing != null) {
      // Yeniden eklenince her iki taraf için gizlemeyi sıfırla
      await _db.from('partnerships').update({
        'hidden_for_1': false,
        'hidden_for_2': false,
      }).eq('id', existing['id'] as String);
    } else {
      await _db.from('partnerships').insert({
        'id': id,
        'user_id_1': userId1,
        'user_id_2': userId2,
        'hidden_for_1': false,
        'hidden_for_2': false,
      });
    }
  }

  Future<List<String>> getPartnerIds(String userId,
      {bool onlyActive = true}) async {
    final rows = await _db
        .from('partnerships')
        .select('user_id_1, user_id_2, hidden_for_1, hidden_for_2')
        .or('user_id_1.eq.$userId,user_id_2.eq.$userId');

    return rows.where((r) {
      if (!onlyActive) return true;
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
    final rows = await _db
        .from('partnerships')
        .select('user_id_1, user_id_2, hidden_for_1, hidden_for_2')
        .or('user_id_1.eq.$userId,user_id_2.eq.$userId');

    return rows.map<({String id, bool active})>((r) {
      final u1 = r['user_id_1'] as String;
      final u2 = r['user_id_2'] as String;
      final isUser1 = u1 == userId;
      // active = bu kullanıcı tarafından gizlenmemiş
      final hidden = isUser1
          ? (r['hidden_for_1'] as bool? ?? false)
          : (r['hidden_for_2'] as bool? ?? false);
      return (id: isUser1 ? u2 : u1, active: !hidden);
    }).toList();
  }

  Future<bool> partnershipExists(String uid1, String uid2) async {
    final rows = await _db.from('partnerships').select('id').or(
        'and(user_id_1.eq.$uid1,user_id_2.eq.$uid2),and(user_id_1.eq.$uid2,user_id_2.eq.$uid1)');
    return rows.isNotEmpty;
  }

  /// Sadece isteği yapan kullanıcının (uid1) tarafındaki gizleme durumunu günceller.
  Future<void> setPartnershipHidden(
      String currentUserId, String partnerId, bool hidden) async {
    // Hangi sırada kayıt var bul
    final row = await _db
        .from('partnerships')
        .select('id, user_id_1, user_id_2')
        .or('and(user_id_1.eq.$currentUserId,user_id_2.eq.$partnerId),and(user_id_1.eq.$partnerId,user_id_2.eq.$currentUserId)')
        .maybeSingle();
    if (row == null) return;

    final isUser1 = (row['user_id_1'] as String) == currentUserId;
    final field = isUser1 ? 'hidden_for_1' : 'hidden_for_2';
    await _db
        .from('partnerships')
        .update({field: hidden})
        .eq('id', row['id'] as String);
  }

  // Eski imza — geriye dönük uyumluluk için yönlendir
  Future<void> setPartnershipActive(
      String uid1, String uid2, bool active) async {
    await setPartnershipHidden(uid1, uid2, !active);
  }

  Future<void> removePartnership(String uid1, String uid2) async {
    await _db.from('partnerships').delete().or(
        'and(user_id_1.eq.$uid1,user_id_2.eq.$uid2),and(user_id_1.eq.$uid2,user_id_2.eq.$uid1)');
  }

  /// Profiles tablosunda kaydı olmayan ortaklar için partner_invites'tan
  /// requester_name veya payload'dan isim çekip AppUser listesi döner.
  /// Bulunan profiller profiles tablosuna da upsert edilir (sonraki çekişler hızlı olsun).
  Future<List<AppUser>> resolveNamesFromInvites(
      String currentUserId, List<String> missingPartnerIds) async {
    if (missingPartnerIds.isEmpty) return [];

    final result = <AppUser>[];

    for (final partnerId in missingPartnerIds) {
      // 1) Ortak kod gönderen tarafsa: from_user_id = partnerId, to_user_id = currentUserId
      // 2) Ortak kodu giren tarafsa: from_user_id = currentUserId, to_user_id = partnerId — requester_name dolmuş olur
      Map<String, dynamic>? row;
      try {
        row = await _db
            .from('partner_invites')
            .select('requester_name, payload, from_user_id, to_user_id')
            .or('from_user_id.eq.$partnerId,to_user_id.eq.$partnerId')
            .order('expires_at', ascending: false)
            .limit(1)
            .maybeSingle();
      } catch (_) {}

      if (row == null) continue;

      String? name;

      // Eğer ortak kodu giren tarafsa requester_name dolu olabilir
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
      // Sonraki sorgular için profiles'a yaz
      try {
        await upsertProfile(user);
      } catch (_) {}
      result.add(user);
    }

    return result;
  }
}
