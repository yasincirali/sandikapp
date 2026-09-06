import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'milestone_service.dart';

/// Kilometre taşlarının kalıcılığı ve kutlama sıklığı.
///
/// Hesap [MilestoneService] içinde saf; burada yalnızca "bu eşik daha önce
/// geçildi mi", "kutlandı mı" ve "bu ay kaç kutlama yapıldı" tutulur.
class MilestoneRepository {
  MilestoneRepository._();
  static final MilestoneRepository instance = MilestoneRepository._();

  /// Ayda EN FAZLA bir kutlama.
  ///
  /// Kutlamanın değeri seyrekliğinden gelir. Portföyü hızla büyüyen bir
  /// kullanıcı bir ayda beş eşik geçebilir; hepsini göstermek kutlamayı
  /// bildirim yağmuruna çevirir ve altıncısında kimse bakmaz.
  static const _kSonKutlamaAy = 'milestone_last_celebrated_month';

  SupabaseClient get _db => Supabase.instance.client;

  /// Kullanıcının daha önce ULAŞTIĞI eşikler (`kind:value` kümesi).
  Future<Set<String>> fetchReached(String userId) async {
    try {
      final rows =
          await _db.from('milestones').select('kind, value').eq('user_id', userId);
      return {
        for (final r in rows as List) '${r['kind']}:${r['value']}',
      };
    } catch (_) {
      // Okunamıyorsa hiçbir şey kutlanmaz — yanlışlıkla ikinci kez
      // kutlamaktansa hiç kutlamamak yeğdir.
      return {'__hata__'};
    }
  }

  /// Yeni geçilen eşikleri kaydeder. Çakışma sessizce yutulur (idempotent).
  Future<void> recordReached(String userId, List<Milestone> yeniler) async {
    if (yeniler.isEmpty) return;
    try {
      await _db.from('milestones').upsert(
        [
          for (final m in yeniler)
            {'user_id': userId, 'kind': m.kind, 'value': m.value},
        ],
        onConflict: 'user_id,kind,value',
        ignoreDuplicates: true,
      );
    } catch (_) {
      // Kaydedilemezse bir sonraki turda yeniden denenir.
    }
  }

  Future<void> markShown(String userId, Milestone m) async {
    try {
      await _db
          .from('milestones')
          .update({'shown_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', userId)
          .eq('kind', m.kind)
          .eq('value', m.value);
    } catch (_) {/* ikincil */}
  }

  /// Bu ay kutlama yapılabilir mi?
  static Future<bool> canCelebrate({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final t = now ?? DateTime.now();
    final buAy = '${t.year}-${t.month.toString().padLeft(2, '0')}';
    return prefs.getString(_kSonKutlamaAy) != buAy;
  }

  static Future<void> markCelebrated({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final t = now ?? DateTime.now();
    await prefs.setString(
      _kSonKutlamaAy,
      '${t.year}-${t.month.toString().padLeft(2, '0')}',
    );
  }

  /// Testler arası sızıntıyı engeller.
  static Future<void> resetForTest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSonKutlamaAy);
  }
}
