import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0059: Yarış / yüzdelik havuzu Sybil'e karşı "zaman maliyeti" kuralı.
///
/// Bu test SQL'i koşturamaz; iki RPC'nin de AYNI uygunluk kümesini
/// kullandığını ve 0031 değişmezlerinin (k_min=8, n_max=4) korunduğunu
/// kaynak üstünden doğrular. Biri eligibility'siz kalırsa saldırı yüzeyi
/// sessizce geri gelir.
void main() {
  final sql = File('supabase/migrations/0059_leaderboard_sybil_eligibility.sql')
      .readAsStringSync();

  test('uygunluk fonksiyonu tek kaynak ve istemciye kapalı', () {
    expect(sql.contains('FUNCTION public.leaderboard_eligible_users()'), isTrue);
    expect(
      sql.contains(
          'REVOKE ALL ON FUNCTION public.leaderboard_eligible_users() FROM public, anon, authenticated'),
      isTrue,
      reason: 'uygun kullanıcı listesi kendisi bir sızıntı olurdu',
    );
    expect(sql.contains("interval '7 days'"), isTrue, reason: 'hesap yaşı');
    expect(sql.contains('>= 5'), isTrue, reason: 'farklı gün sayısı');
    expect(sql.contains('type_count >= 2'), isTrue);
  });

  test('iki RPC de havuzu uygunluk kümesiyle JOIN\'liyor', () {
    final joins = 'JOIN public.leaderboard_eligible_users() e'
        .allMatches(sql)
        .length;
    // percentile: latest_per_user; top-gainers: v_total sayımı + latest_roi.
    expect(joins, 3, reason: 'bir havuz uygunluksuz kalırsa Sybil geri gelir');
    expect(sql.contains('e.user_id = auth.uid()'), isTrue,
        reason: 'çağıranın kendisi de uygun olmalı');
  });

  test('k_min / n_max değişmezi 0031 ile aynı', () {
    expect('k_min INTEGER := 8'.allMatches(sql).length, 2);
    expect(sql.contains('n_max INTEGER := 4'), isTrue);
  });

  test('GRANT/REVOKE çifti iki RPC için de tazeleniyor', () {
    expect('GRANT EXECUTE ON FUNCTION'.allMatches(sql).length, 2);
    expect('has_function_privilege'.allMatches(sql).length, 2);
  });
}
