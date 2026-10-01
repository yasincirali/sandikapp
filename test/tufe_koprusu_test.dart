import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/services/bugun_service.dart';
import 'package:portfoy_takip/services/tufe_koprusu.dart';
import 'package:portfoy_takip/services/tuik_takvimi.dart';
import 'package:portfoy_takip/widgets/aralik_cipi.dart';

/// TÜİK takvimi (tek kural), köprü satırının saf kapıları ve aralık çipi
/// metinleri (D2, 2026-10-01).
void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
  });

  group('TuikTakvimi — ayın 3\'ü 10:00', () {
    test('bir ayın verisi ertesi ayın 3\'ünde açıklanır', () {
      expect(TuikTakvimi.aciklamaTarihi(DateTime(2026, 9)),
          DateTime(2026, 10, 3, 10));
      // Yıl dönümü: Aralık → 3 Ocak.
      expect(TuikTakvimi.aciklamaTarihi(DateTime(2026, 12, 31)),
          DateTime(2027, 1, 3, 10));
    });

    test('sonraki açıklama: 3\'ü 10:00 geçmediyse bu ay, geçtiyse gelecek ay',
        () {
      expect(TuikTakvimi.sonrakiAciklama(DateTime(2026, 10, 1)),
          DateTime(2026, 10, 3, 10));
      expect(TuikTakvimi.sonrakiAciklama(DateTime(2026, 10, 3, 9, 59)),
          DateTime(2026, 10, 3, 10));
      expect(TuikTakvimi.sonrakiAciklama(DateTime(2026, 10, 3, 10, 1)),
          DateTime(2026, 11, 3, 10));
    });

    test('Bugün kartı aynı kuralı okur (tek kaynak)', () {
      final olay = BugunService.yaklasanOlaylar(DateTime(2026, 10, 1, 12))
          .where((o) => o.tur == BugunOlayTuru.tuikAciklamasi)
          .single;
      expect(olay.tarih, TuikTakvimi.sonrakiAciklama(DateTime(2026, 10, 1)));
    });
  });

  group('TufeKoprusu', () {
    final k = TufeKoprusu(pencereSonu: DateTime(2026, 8, 31), getiriPct: -5.15);

    test('eksik ay pencerenin ertesi ayı, açıklaması onun ertesi ayın 3\'ü',
        () {
      expect(k.eksikAy, DateTime(2026, 9));
      expect(k.aciklamaTarihi, DateTime(2026, 10, 3, 10));
    });

    test('pencere sonu ile bugün arasında ≥1 TAKVİM günü yoksa ölçülmez', () {
      final son = DateTime(2026, 8, 31);
      expect(
          TufeKoprusu.olculebilir(son, DateTime(2026, 8, 31, 23, 59)), isFalse);
      expect(TufeKoprusu.olculebilir(son, DateTime(2026, 9, 1, 0, 1)), isTrue);
      expect(TufeKoprusu.olculebilir(son, DateTime(2026, 10, 1)), isTrue);
    });

    test('ölçülemiyorsa ağa çıkmadan null (boş varlık, aynı gün)', () async {
      expect(
        await TufeKoprusu.olc(const [],
            pencereSonu: DateTime(2026, 8, 31), now: DateTime(2026, 10, 1)),
        isNull,
      );
    });
  });

  group('AralikMetni', () {
    final tr = AppLocalizationsTr();
    final en = AppLocalizationsEn();
    final simdi = DateTime(2026, 10, 1, 12);

    test('gün çözünürlüğü: bugünde biten pencere "bugün" der', () {
      expect(
        AralikMetni.gunlu(tr, 'tr_TR',
            bas: DateTime(2025, 10, 1),
            son: DateTime(2026, 10, 1),
            simdi: simdi),
        '1 Eki 25 - bugün',
      );
      expect(
        AralikMetni.gunlu(en, 'en_US',
            bas: DateTime(2025, 10, 1),
            son: DateTime(2026, 10, 1),
            simdi: simdi),
        '1 Oct 25 - today',
      );
      expect(
        AralikMetni.gunlu(tr, 'tr_TR',
            bas: DateTime(2025, 10, 1),
            son: DateTime(2026, 9, 30),
            simdi: simdi),
        '1 Eki 25 - 30 Eyl 26',
      );
    });

    test('ay çözünürlüğü: aralık kısa, tek ay tam adıyla', () {
      expect(
        AralikMetni.aylik(tr, 'tr_TR',
            bas: DateTime(2025, 8, 31), bitis: DateTime(2026, 8, 31)),
        'Ağu 25 - Ağu 26',
      );
      expect(
        AralikMetni.aylik(tr, 'tr_TR',
            bas: DateTime(2026, 7, 31), bitis: DateTime(2026, 8, 31)),
        'Ağustos 2026',
      );
    });

    test('tek gün: bugünse "Bugün", değilse tarih', () {
      expect(
          AralikMetni.tekGun(tr, 'tr_TR', gun: simdi, simdi: simdi), 'Bugün');
      expect(
        AralikMetni.tekGun(tr, 'tr_TR',
            gun: DateTime(2026, 9, 26), simdi: simdi),
        '26 Eylül',
      );
    });
  });
}
