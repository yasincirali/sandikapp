import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0133 (çoklu portföy) sözleşmesi — "canlıdaki kullanıcı etkilenmez":
/// migration yalnız EKLER, eski istemcinin okuduğu/yazdığı hiçbir şeyi
/// değiştirmez; güvenlik kapıları (RLS + GRANT + bileşik FK) yerinde.
void main() {
  final sql = File('supabase/migrations/0133_coklu_portfoy.sql')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  // Yorumlar atılmış, boşluklar tekleştirilmiş gövde.
  final govde = sql
      .split('\n')
      .where((s) => !s.trimLeft().startsWith('--'))
      .join('\n')
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();

  test('yalnız ekler: sütun düşürme/yeniden adlandırma/tip değişimi yok', () {
    for (final yasak in [
      'drop column',
      'rename column',
      'rename to',
      'alter column',
      'drop table',
      'delete from',
      'update public.assets',
      'truncate',
    ]) {
      expect(govde.contains(yasak), isFalse, reason: yasak);
    }
    expect(
        govde,
        contains(
            'alter table public.assets add column if not exists portfoy_id uuid;'));
    // NOT NULL ya da varsayılan YOK: eski istemcinin INSERT'i NULL = Ana.
    expect(govde.contains('portfoy_id uuid not null'), isFalse);
  });

  test('bileşik FK, silmede yalnız portfoy_id boşalır (lot korunur)', () {
    expect(
        govde,
        contains('foreign key (portfoy_id, user_id) references '
            'public.portfoyler(id, user_id) on delete set null (portfoy_id)'));
    expect(govde, contains('unique (id, user_id)'));
    expect(govde,
        contains('on public.assets(portfoy_id) where portfoy_id is not null'));
  });

  test('RLS zorunlu + sahip + ortak okuma; GRANT açık; anon yok', () {
    expect(govde,
        contains('alter table public.portfoyler enable row level security'));
    expect(govde,
        contains('alter table public.portfoyler force row level security'));
    expect(
        govde,
        contains(
            'for all using (auth.uid() = user_id) with check (auth.uid() = user_id)'));
    expect(govde,
        contains('"portfoyler_partner_read" on public.portfoyler for select'));
    expect(govde, contains('revoke all on table public.portfoyler from anon'));
    expect(
        govde,
        contains(
            'grant select, insert, update, delete on table public.portfoyler to authenticated'));
    // Doğrulama bloğu eksik GRANT/politikada göçü durdurur.
    expect(govde, contains("raise exception '0133: portfoyler grant eksik"));
    expect(govde,
        contains("raise exception '0133: portfoyler rls politikasi eksik"));
  });

  test('her fonksiyonda search_path; SECURITY DEFINER yok', () {
    final fonksiyonlar =
        RegExp(r'create or replace function').allMatches(govde).length;
    expect(fonksiyonlar, 3);
    expect(
        RegExp(r'set search_path = public, pg_temp').allMatches(govde).length,
        fonksiyonlar);
    expect(govde.contains('security definer'), isFalse);
  });

  test('miras tetikleyicisi yalnız AYNI kullanıcının referans lotundan', () {
    expect(govde,
        contains('if new.portfoy_id is null and new.ref_asset_id is not null'));
    expect(govde, contains('a.user_id = new.user_id'));
    expect(govde, contains('before insert on public.assets'));
  });

  test('0095 giriş anı tetikleyicisi değişmedi (taşıma ekonomik olay değil)',
      () {
    expect(govde.contains('assets_giris_ani'), isFalse);
    final t0095 =
        File('supabase/migrations/0095_yaris_twr.sql').readAsStringSync();
    expect(t0095.contains('portfoy'), isFalse);
  });

  test('ad sınırı istemciyle aynı (1–40)', () {
    expect(govde, contains('check (char_length(btrim(ad)) between 1 and 40)'));
  });
}
