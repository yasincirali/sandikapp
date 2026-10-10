import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0135 (ortak hangi portföyleri görür) sözleşmesi. Davranış yerel
/// Postgres'te denendi (satır yok = hepsi; Ana + Emeklilik seçilince ortak
/// Çocuk'un lotunu ve ona bağlı mevduat sözleşmesini göremez; hiçbir
/// portföy ADI ve paylaşım satırı okuyamaz; öbür ortak etkilenmez). Burada
/// metin düzeyinde kilitlenenler: yalnız ekler, varsayılan "hepsi",
/// ortak portföy varlığını öğrenemez, güvenlik kapıları yerinde.
void main() {
  final sql = File('supabase/migrations/0135_ortak_portfoy_paylasimi.sql')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final govde = sql
      .split('\n')
      .where((s) => !s.trimLeft().startsWith('--'))
      .join('\n')
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();

  test('yalnız ekler: veri/sütun değişimi yok', () {
    for (final yasak in [
      'drop column',
      'rename column',
      'rename to',
      'alter column',
      'drop table',
      'delete from',
      'update public.',
      'insert into public.',
      'truncate',
    ]) {
      expect(govde.contains(yasak), isFalse, reason: yasak);
    }
  });

  test('satır yoksa ortak her şeyi görür (0135 öncesi davranış)', () {
    expect(govde, contains('tumu boolean not null default true'));
    expect(govde, contains('ana boolean not null default true'));
    // Fonksiyon satır bulamazsa true döner.
    expect(govde, contains('), true);'));
  });

  test('üç ortak okuma politikası süzgeçli, ortaklık koşulu korunur', () {
    for (final t in ['assets', 'sozlesmeler', 'mevduat_donemleri']) {
      expect(
          govde,
          contains('create policy "${t}_partner_read" on public.$t '
              'for select using ( exists ( select 1 from public.partnerships p '
              'where p.active = true'),
          reason: t);
    }
    expect(
        govde,
        contains('and ozel.ortak_portfoyu_gorur(assets.user_id, '
            'assets.portfoy_id)'));
  });

  test('ortak portföy varlığını öğrenemez: ad yok, satır yok, RPC yok', () {
    expect(
        govde,
        contains(
            'drop policy if exists "portfoyler_partner_read" on public.portfoyler;'));
    expect(govde.contains('create policy "portfoyler_partner_read"'), isFalse);
    expect(govde.contains('create policy "ortak_paylasimlari_ortak_read"'),
        isFalse);
    // Süzgeç API'de görünmeyen şemada (config.toml schemas = public, …).
    expect(govde.contains('public.ortak_portfoyu_gorur'), isFalse);
    expect(govde.contains('public.ortak_paylasimi_kisitli'), isFalse);
    final config = File('supabase/config.toml').readAsStringSync();
    expect(config, contains('schemas = ["public", "graphql_public"]'));
  });

  test('RLS zorunlu; sahip yazar, ortak yalnız okur; anon yok', () {
    expect(
        govde,
        contains(
            'alter table public.ortak_paylasimlari force row level security'));
    expect(
        govde,
        contains('for all using (auth.uid() = sahip_id) '
            'with check (auth.uid() = sahip_id)'));
    expect(govde,
        contains('revoke all on table public.ortak_paylasimlari from anon'));
    expect(govde, contains("raise exception '0135: ortak_paylasimlari grant"));
    expect(govde, contains("raise exception '0135: assets_partner_read"));
  });

  test('her fonksiyonda search_path; DEFINER yalnız ozel şemasında', () {
    final n = RegExp(r'create or replace function').allMatches(govde).length;
    expect(n, 3);
    expect(
        RegExp(r'set search_path = public, pg_temp').allMatches(govde).length,
        n);
    expect(RegExp(r'security definer').allMatches(govde).length, 2);
    expect(govde, contains('revoke all on schema ozel from public, anon'));
    expect(
        govde, contains("raise exception '0135: suzgec fonksiyonunun sahibi"));
  });
}
