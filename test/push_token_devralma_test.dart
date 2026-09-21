import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Push token'ı cihazı elinde tutan hesap devralır (0069, 2026-09-21).
///
/// Arıza: `user_push_tokens` PK'sı `token`, token cihaza bağlı. Aynı
/// telefonda A çıkıp B girince B'nin `upsert`'i `on conflict do update`
/// yoluna düşer, UPDATE politikasının USING'i A'nın satırına bakar → 42501.
/// B'ye push gitmez, A'nın brifingi B'nin telefonuna düşer. Canlıda ölçüldü
/// (db_logs 664946, "pushlar çalışmıyor").
///
/// RLS davranışı Dart testinde koşturulamaz; bu test iki şeyi kilitler:
///   · istemci tabloya doğrudan `upsert` etmez, RPC'yi çağırır;
///   · migration `security definer` + `set search_path` + GRANT/REVOKE +
///     kendi doğrulama bloğunu taşır (0036/0042 dersi: RLS ≠ GRANT).
/// Gerçek davranış `tool/supabase_smoke.sh` 6/6b adımlarında (CI, taze yığın).
void main() {
  final servis = File('lib/services/supabase_service.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final migration = File('supabase/migrations/0069_push_token_devralma.sql')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('istemci token yazımını RPC ile yapar, tabloya doğrudan upsert etmez',
      () {
    final i = servis.indexOf('Future<void> upsertPushToken(');
    expect(i, greaterThan(0));
    final govde = servis.substring(i, servis.indexOf('Future<void> deletePushToken', i));
    expect(govde.contains('rpc<dynamic>(') && govde.contains("'claim_push_token'"),
        isTrue,
        reason: 'token yazımı sunucuda devralma yapan RPC ile');
    // Doğrudan upsert yalnızca sürüm kayması geri dönüşünde (RPC yok →
    // PGRST202); ana yol RPC. Build 0069'dan önce indiğinde token hiç
    // yazılamamıştı (canlı, 2026-09-21 akşamı).
    final rpc = govde.indexOf("'claim_push_token'");
    final geri = govde.indexOf("e.code != 'PGRST202'");
    final upsert = govde.indexOf(".from('user_push_tokens').upsert(");
    expect(rpc, greaterThan(0));
    expect(geri, greaterThan(rpc), reason: 'geri dönüş yalnızca PGRST202');
    expect(upsert, greaterThan(geri),
        reason: 'doğrudan upsert yalnızca geri dönüşte, ana yolda değil');
    expect(govde.contains('.delete()'), isFalse,
        reason: 'bayat token temizliği sunucuda; istemci başka hesabın '
            'satırını zaten silemiyordu');
    for (final p in ['p_token', 'p_platform', 'p_device_id']) {
      expect(govde.contains("'$p'"), isTrue, reason: 'RPC parametresi $p');
    }
  });

  test('migration: security definer, search_path, GRANT/REVOKE, öz-denetim',
      () {
    expect(migration.contains('create or replace function public.claim_push_token('),
        isTrue);
    expect(migration.contains('security definer'), isTrue);
    expect(migration.contains('set search_path = public'), isTrue,
        reason: 'her SECURITY DEFINER fonksiyonunda search_path sabitlenir');
    expect(
        migration.contains(
            'grant execute on function public.claim_push_token(text, text, text) to authenticated'),
        isTrue);
    expect(
        migration.contains(
            'revoke all on function public.claim_push_token(text, text, text) from public, anon'),
        isTrue,
        reason: 'anon token yazamamalı');
    expect(migration.contains("has_function_privilege('anon'"), isTrue,
        reason: 'migration kendi GRANT durumunu denetler');
    // user_id yalnızca auth.uid()'den gelir; parametre olarak alınmaz.
    expect(migration.contains('p_user_id'), isFalse,
        reason: 'çağıran başka hesap adına yazamaz');
    expect(migration.contains('v_uid        uuid := auth.uid()'), isTrue);
  });

  test('migration: devralma yalnızca aynı token, bayat temizlik yalnızca kendi cihazı',
      () {
    expect(
        migration.contains('where token = p_token and user_id <> v_uid'), isTrue,
        reason: 'başka hesabın satırı yalnızca AYNI token için düşer');
    expect(
        migration.contains(
            'where user_id = v_uid and device_id = p_device_id and token <> p_token'),
        isTrue,
        reason: 'cihaz kimliğiyle silme yalnızca çağıranın kendi satırları');
  });

  test('migration: eski istemci için before insert tetikleyicisi', () {
    // Yayındaki build doğrudan upsert eder; tetikleyici çakışmadan önce
    // başka hesabın satırını düşürür, RLS USING hiç değerlendirilmez.
    expect(migration.contains('before insert on public.user_push_tokens'), isTrue);
    expect(migration.contains('execute function public.push_token_devral()'), isTrue);
    expect(
        migration.contains(
            'revoke all on function public.push_token_devral() from public, anon, authenticated'),
        isTrue,
        reason: 'tetikleyici fonksiyonu elle çağrılamaz');
    expect(migration.contains("tgname = 'user_push_tokens_devral'"), isTrue,
        reason: 'migration tetikleyicinin varlığını denetler');
  });

  test('duman testi RPC yolunu koşturur', () {
    final smoke = File('tool/supabase_smoke.sh').readAsStringSync();
    expect(smoke.contains('/rest/v1/rpc/claim_push_token'), isTrue);
    expect(smoke.contains('anon RPC'), isTrue);
  });
}
