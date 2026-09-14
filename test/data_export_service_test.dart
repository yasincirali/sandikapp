import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/data_export_service.dart';

/// `DataExportService` — Supabase istemcisi olmadan (Faz 3.17).
///
/// GDPR 20 / KVKK 11 "tam döküm"ün sözleşmesi: her tablo belgede bir
/// anahtar, bir tablo çekilemezse belge o tabloda yer tutucu taşır ama
/// ham hata metni (tablo adı, URL) dosyaya girmez ve export durmaz.
void main() {
  Future<List<Map<String, dynamic>>> bosCek(String t, String c) async => [];

  test('her tablo belgede kendi anahtarıyla yer alır', () async {
    final veri = await DataExportService.topla(
      userId: 'u1',
      cek: (t, c) async => [
        {'table': t, 'filter': c}
      ],
      ortakliklariCek: () async => [
        {'user_id_1': 'u1'}
      ],
    );
    expect(veri.keys, containsAll([
      'profile',
      'assets',
      'snapshots',
      'partner_invites_sent',
      'partnerships',
      'push_tokens',
      'disclaimer_acceptances',
      'watchlist',
      'price_alerts',
      'signal_preferences',
      'signal_notifications',
      'milestones',
      'live_activity_sessions',
    ]));
    expect(veri.length, DataExportService.tablolar.length + 1);
    // Süzgeç sütunu tabloya göre: profil `id`, davetler `from_user_id`.
    expect(veri['profile']!.single['filter'], 'id');
    expect(veri['partner_invites_sent']!.single['filter'], 'from_user_id');
    expect(veri['assets']!.single['filter'], 'user_id');
  });

  test('bir tablo hata verirse export durmaz, yer tutucu yazılır, hata raporlanır',
      () async {
    final raporlar = <String>[];
    final veri = await DataExportService.topla(
      userId: 'u1',
      cek: (t, c) async {
        if (t == 'snapshots') throw StateError('relation "snapshots" 42P01');
        return [
          {'ok': t}
        ];
      },
      ortakliklariCek: () async => throw StateError('kırık'),
      raporla: (e, st, reason) => raporlar.add(reason),
    );
    expect(veri['snapshots'], DataExportService.tabloHatasi);
    expect(veri['partnerships'], DataExportService.tabloHatasi);
    expect(veri['assets']!.single, {'ok': 'assets'});
    expect(raporlar,
        containsAll(['DataExportService.snapshots', 'DataExportService.partnerships']));
    // Ham hata metni belgeye sızmaz (L8).
    expect(jsonEncode(veri).contains('42P01'), isFalse);
  });

  test('belge sürüm, kullanıcı, not ve veri taşır; JSON\'a çevrilebilir',
      () async {
    final veri = await DataExportService.topla(
        userId: 'u1', cek: bosCek, ortakliklariCek: () async => []);
    final belge = DataExportService.belgeKur(
      userId: 'u1',
      email: 'a@b.c',
      veri: veri,
      simdi: DateTime.utc(2026, 9, 14, 10, 30),
    );
    expect(belge['export_version'], DataExportService.exportVersion);
    expect(belge['exported_at'], '2026-09-14T10:30:00.000Z');
    expect((belge['user'] as Map)['email'], 'a@b.c');
    expect(belge['note'].toString(), contains('KVKK'));
    final json = jsonEncode(belge);
    expect(jsonDecode(json), isA<Map<String, dynamic>>());
  });

  test('dosya adı iki nokta içermez, milisaniye taşımaz', () {
    final ad = DataExportService.dosyaAdi(DateTime(2026, 9, 14, 10, 30, 5, 123));
    expect(ad, 'sandik-veri-export-2026-09-14T10-30-05.json');
    expect(ad.contains(':'), isFalse);
  });
}
