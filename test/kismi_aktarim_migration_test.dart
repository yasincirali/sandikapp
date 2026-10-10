import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0136 (portföyler arası kısmi aktarım) sözleşmesi. Davranış yerel
/// Postgres'te denendi: 0.4 oranında alım/satış/temettü iki portföye
/// 40/60 bölündü, satışın referansı yeni alım kopyasına eşlendi, silinmiş
/// lot kaynakta kaldı, iki taraftaki `created_at` korundu; başkasının
/// satırı, oran 1, aynı portföy ve başkasının portföyü reddedildi; işlem
/// sonrası normal miktar değişimi giriş anını yine yeniledi.
void main() {
  final sql = File('supabase/migrations/0136_pozisyon_kismi_aktarim.sql')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final govde = sql
      .split('\n')
      .where((s) => !s.trimLeft().startsWith('--'))
      .join('\n')
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();

  test('yalnız ekler: şema/veri değişimi yok', () {
    for (final yasak in [
      'drop column',
      'alter table',
      'drop table',
      'delete from',
      'drop policy',
      'drop trigger',
      'truncate',
    ]) {
      expect(govde.contains(yasak), isFalse, reason: yasak);
    }
  });

  test('RPC SECURITY INVOKER (RLS), anon yok, doğrulama bloğu', () {
    expect(govde.contains('security definer'), isFalse);
    expect(govde, contains('set search_path = public, pg_temp'));
    expect(
        govde,
        contains('revoke all on function public.pozisyon_kismi_aktar'
            '(uuid[], double precision, uuid) from public, anon'));
    expect(govde, contains("raise exception '0136: pozisyon_kismi_aktar"));
  });

  test('oran açık aralık, sahiplik ve sözleşme kapıları', () {
    expect(govde, contains('not (p_oran > 0 and p_oran < 1)'));
    expect(govde, contains('a.user_id = v_uid'));
    expect(govde, contains("'sozlesmeli_bolunmez'"));
    expect(govde, contains("'ayni_portfoy'"));
  });

  test('her satır aynı oranla: miktar ve tutarlar, iki taraf', () {
    for (final alan in ['quantity', 'commission', 'dividend_amount']) {
      expect(govde, contains('yeni.$alan := r.$alan * p_oran'), reason: alan);
      expect(govde, contains('$alan = a.$alan * (1 - p_oran)'), reason: alan);
    }
    expect(govde, contains("a.kind in ('buy', 'sell', 'dividend')"));
    expect(govde, contains('a.deleted_at is null'));
  });

  test('giriş anı yalnız bu işlemde korunur, eski dal birebir', () {
    expect(govde,
        contains("perform set_config('sandik.giris_ani_koru', 'on', true)"));
    expect(govde, contains("current_setting('sandik.giris_ani_koru', true)"));
    // 0095 davranışı: ayar yokken INSERT ve miktar değişimi now().
    expect(govde,
        contains("if tg_op = 'insert' then new.created_at := now(); return new;"));
    expect(govde, contains('> 1e-9 * greatest(abs(old.quantity), 1)'));
  });
}
