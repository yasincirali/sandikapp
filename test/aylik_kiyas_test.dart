import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/services/aylik_getiri_tablosu.dart';
import 'package:portfoy_takip/services/disa_aktarim/aylik_rapor_belgesi.dart';
import 'package:portfoy_takip/widgets/aylik_rapor_bolumleri.dart';

/// Aylık raporun kişisel kıyas satırı (2026-11-12, Ar-Ge 12 Kas #7): ayın,
/// kullanıcının kendi son 12 ayı içindeki yeri. Hücreler Performans'ın
/// aylık getiri tablosu (yeni formül yok); kısa geçmişte satır yok.
final _tr = AppLocalizationsTr();

/// 2026 Ocak..[son] ayları verilen yüzdelerle; ilk ay Ocak 2026.
AylikGetiriTablosu _tablo(Map<int, List<double?>> aylar, DateTime buAy) =>
    AylikGetiriTablosu(
      aylar: aylar,
      yilToplami: const {},
      ilkAy: DateTime(aylar.keys.reduce((a, b) => a < b ? a : b), 1),
      buAy: buAy,
      olculenAySayisi: aylar.values
          .expand((l) => l)
          .where((v) => v != null)
          .length,
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  // Kasım 2025 .. Ekim 2026 = 12 ay.
  final t = _tablo({
    2025: [null, null, null, null, null, null, null, null, null, null, 2, -1],
    2026: [3, 1.5, -2, 4, 0.5, -0.5, 1, 2.5, -3, 0.8, null, null],
  }, DateTime(2026, 10));

  group('aylikKiyas', () {
    test('orta ay: artıdaki ay sayısı ve sıra', () {
      final k = aylikKiyas(t, DateTime(2026, 10))!;
      expect(k.olculen, 12);
      expect(k.arti, 8);
      // 0,8'den yüksek: 2, 3, 1.5, 4, 1, 2.5 → 6 → 7. sıra.
      expect(k.sira, 7);
      expect(k.enIyi, isFalse);
      expect(k.enZayif, isFalse);
      expect(aylikKiyasCumlesi(_tr, k),
          'Son 12 ayda 8 ay artıdaydın; bu ay 12 ay içinde 7. sırada.');
    });

    test('en iyi ay', () {
      final k = aylikKiyas(t, DateTime(2026, 4))!;
      expect(k.enIyi, isTrue);
      expect(k.sira, 1);
      // Nisan penceresi: Mayıs 2025..Nisan 2026, ölçülen 6 ay.
      expect(k.olculen, 6);
      expect(aylikKiyasCumlesi(_tr, k),
          'Bu ay son 6 ayın en iyisi; 6 ayda 4 ay artıdaydın.');
    });

    test('en zayıf ay yumuşak: ardından artıdaki aylar', () {
      final k = aylikKiyas(t, DateTime(2026, 9))!;
      expect(k.enZayif, isTrue);
      expect(aylikKiyasCumlesi(_tr, k),
          'Bu ay son 11 ayın en zayıfı; 11 ayda 7 ay artıdaydın.');
    });

    test('ölçülen ay asgari eşiğin altında → satır yok', () {
      // Mart penceresi: Kasım 2025..Mart 2026 = 5 ay < 6.
      expect(aylikKiyas(t, DateTime(2026, 3)), isNull);
    });

    test('ayın hücresi yoksa satır yok', () {
      expect(aylikKiyas(t, DateTime(2026, 11)), isNull);
    });

    test('hiç artı ay yoksa sayı yerine düz cümle', () {
      const enIyi = AylikKiyas(
          olculen: 8, arti: 0, sira: 1, enIyi: true, enZayif: false);
      expect(aylikKiyasCumlesi(_tr, enIyi), 'Bu ay son 8 ayın en iyisi.');
      const orta = AylikKiyas(
          olculen: 8, arti: 0, sira: 3, enIyi: false, enZayif: false);
      expect(aylikKiyasCumlesi(_tr, orta),
          'Son 8 ayda artıda kapanan ay olmadı; bu ay 8 ay içinde 3. sırada.');
      expect(aylikKiyasCumlesi(AppLocalizationsEn(), orta),
          contains('ranks 3 of 8'));
    });
  });

  test('PDF: kıyas cümlesi öne çıkanlarda, yoksa yazılmaz', () {
    List<String> kur(String? k) => aylikRaporBelgesi(
          donem: DateTime(2026, 10),
          notlar: const [],
          ozetCumlesi: 'Özet.',
          eksikCumlesi: null,
          kim: 'test',
          olusturma: DateTime(2026, 11, 12),
          getiriPct: 0.8,
          kiyasCumlesi: k,
        ).oneCikanlar;
    const c = 'Son 12 ayda 8 ay artıdaydın; bu ay 12 ay içinde 7. sırada.';
    expect(kur(c), ['Özet.', c]);
    expect(kur(null), ['Özet.']);
  });
}
