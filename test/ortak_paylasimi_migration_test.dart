import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0135 (ortak hangi portföyleri görür) sözleşmesi. Davranış yerel
/// Postgres'te denendi (satır yok = hepsi; Ana + Emeklilik seçilince ortak
/// Çocuk'un lotunu, adını ve ona bağlı mevduat sözleşmesini göremez; öbür
/// ortak etkilenmez; ortak satırı okur, yazamaz; anon hiçbir şey). Burada
/// metin düzeyinde kilitlenenler: yalnız ekler, varsayılan "hepsi",
/// politikaların ortaklık koşulu korunur, güvenlik kapıları yerinde.
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

  test('dört ortak okuma politikası süzgeçli, ortaklık koşulu korunur', () {
    for (final t in [
      'assets',
      'portfoyler',
      'sozlesmeler',
      'mevduat_donemleri',
    ]) {
      expect(govde, contains('create policy "${t}_partner_read" on public.$t '
          'for select using ( exists ( select 1 from public.partnerships p '
          'where p.active = true'), reason: t);
    }
    expect(
        govde,
        contains('and public.ortak_portfoyu_gorur(assets.user_id, '
            'assets.portfoy_id)'));
    expect(
        govde,
        contains('and public.ortak_portfoyu_gorur(portfoyler.user_id, '
            'portfoyler.id)'));
  });

  test('RLS zorunlu; sahip yazar, ortak yalnız okur; anon yok', () {
    expect(govde,
        contains('alter table public.ortak_paylasimlari force row level security'));
    expect(
        govde,
        contains('for all using (auth.uid() = sahip_id) '
            'with check (auth.uid() = sahip_id)'));
    expect(govde, contains('for select using (auth.uid() = ortak_id)'));
    expect(govde,
        contains('revoke all on table public.ortak_paylasimlari from anon'));
    expect(govde, contains("raise exception '0135: ortak_paylasimlari grant"));
    expect(govde, contains("raise exception '0135: assets_partner_read"));
  });

  test('her fonksiyonda search_path; SECURITY DEFINER yok', () {
    final n = RegExp(r'create or replace function').allMatches(govde).length;
    expect(n, 3);
    expect(RegExp(r'set search_path = public, pg_temp').allMatches(govde).length,
        n);
    expect(govde.contains('security definer'), isFalse);
  });
}
