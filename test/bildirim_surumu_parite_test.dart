// Bildirim kartı (0092) — istemci ile sunucu aynı sürümü konuşuyor mu?
//
// Kullanıcı kuralı (2026-10-01): "store kullanıcılarını etkilemesin, yeni
// versiyondan güncellenmiş olsun." Kart görseli yalnız token satırına
// `bildirim_surumu` yazan (yeni) istemciye gider. İki taraf ayrı dilde;
// biri değişip öteki unutulursa kart sessizce hiç gelmez ya da desteklemeyen
// sürüme gider. Bu test kaynakları okuyarak eşliği kilitler.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sunucu =
      File('supabase/functions/_shared/bildirim_karti.ts').readAsStringSync();
  final servis = File('lib/services/supabase_service.dart').readAsStringSync();
  final push = File('lib/services/remote_push_service.dart').readAsStringSync();
  final migration =
      File('supabase/migrations/0092_push_bildirim_surumu.sql').readAsStringSync();

  test('istemcinin yazdığı sürüm sunucunun kart eşiğini karşılıyor', () {
    final m = RegExp(r'export const KART_SURUMU = (\d+);').firstMatch(sunucu);
    expect(m, isNotNull, reason: 'sunucu eşiği bulunamadı');
    final d = RegExp(r'const int bildirimSurumu = (\d+);').firstMatch(push);
    expect(d, isNotNull, reason: 'istemci sabiti bulunamadı');
    expect(int.parse(d!.group(1)!), greaterThanOrEqualTo(int.parse(m!.group(1)!)));
  });

  test('sürüm token kaydından SONRA yazılır ve hatası kaydı düşürmez', () {
    final kayit = push.indexOf('.upsertPushToken(');
    final surum = push.indexOf('.setPushBildirimSurumu(token, bildirimSurumu)');
    expect(kayit, greaterThan(0));
    expect(surum, greaterThan(kayit),
        reason: 'satır önce bu hesaba devralınmalı (claim_push_token)');

    final i = servis.indexOf('Future<void> setPushBildirimSurumu(');
    expect(i, greaterThan(0));
    final govde = servis.substring(i, servis.indexOf('\n  }\n', i));
    expect(govde.contains("'bildirim_surumu'"), isTrue);
    expect(govde.contains("e.code == 'PGRST204' || e.code == '42703'"), isTrue,
        reason: '0092 dağıtılmamış sunucuda sessiz geçilmeli');
    expect(govde.contains('rethrow'), isFalse, reason: 'kart bir süs; asla fırlatmaz');
  });

  test('migration yalnız sütun ekler, varsayılan NULL (eski sürüm = düz metin)', () {
    expect(migration.contains('add column if not exists bildirim_surumu smallint;'),
        isTrue);
    expect(migration.contains('default'), isFalse,
        reason: 'eski satırlar NULL kalmalı; varsayılan değer kartı eski '
            'sürüme açardı');
  });
}
