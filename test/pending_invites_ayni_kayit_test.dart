import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';

import 'helpers/kaynak.dart';

/// Profil'in 20 sn'lik davet yoklaması: yanıt öncekiyle aynıysa provider
/// state'i yazmaz (2026-10-01, CPU raporu — tur başına ~1,2 sn boşa CPU).
///
/// Karşılaştırma JSON üzerinden: Postgrest'ten gelen iç içe profil haritası
/// `mapEquals` ile kimlik kıyasına düşer ve hep "farklı" çıkardı.
void main() {
  test('aynı içerik: iç içe harita dahil eşit sayılır', () {
    final a = [
      {
        'id': '1',
        'from_user': {'display_name': 'Ayşe', 'avatar': null},
        'created_at': '2026-10-01T10:00:00Z',
      },
    ];
    final b = [
      {
        'id': '1',
        'from_user': {'display_name': 'Ayşe', 'avatar': null},
        'created_at': '2026-10-01T10:00:00Z',
      },
    ];
    expect(identical(a, b), isFalse);
    expect(davetKayitlariAyni(a, b), isTrue);
  });

  test('farklı uzunluk, farklı alan ya da farklı iç değer → farklı', () {
    final a = [
      {
        'id': '1',
        'from_user': {'display_name': 'Ayşe'}
      }
    ];
    expect(davetKayitlariAyni(a, const []), isFalse);
    expect(
      davetKayitlariAyni(a, [
        {
          'id': '1',
          'from_user': {'display_name': 'Fatma'}
        }
      ]),
      isFalse,
    );
    expect(
      davetKayitlariAyni(a, [
        {'id': '2', 'from_user': a[0]['from_user']}
      ]),
      isFalse,
    );
  });

  test('JSON\'a dökülemeyen değer: güvenli taraf, farklı sayılır', () {
    final a = [
      {'id': '1', 'x': Object()}
    ];
    final b = [
      {'id': '1', 'x': Object()}
    ];
    expect(davetKayitlariAyni(a, b), isFalse);
  });

  test('refresh aynı yanıtta state yazmaz (kaynak kilidi)', () {
    final kaynak = ekranKaynagiSync('lib/providers/auth_provider.dart');
    // Dosyada iki `refresh()` var (ortaklar + davetler); davetlerinki.
    final sinif = kaynak.substring(kaynak.indexOf('class PendingInvitesNotifier'));
    final govde = sinif.substring(sinif.indexOf('Future<void> refresh()'));
    final refresh = govde.substring(0, govde.indexOf('\n  }\n'));
    expect(refresh, contains('davetKayitlariAyni('),
        reason: 'refresh, yanıtı öncekiyle karşılaştırmalı.');
    expect(refresh, isNot(contains('state = await AsyncValue.guard')),
        reason: 'Yanıt doğrudan state\'e yazılmamalı; önce karşılaştır.');
  });
}
