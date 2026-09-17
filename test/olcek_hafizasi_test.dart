import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';

/// **"Kaynak değişti diye sayı zıplamasın."**
///
/// Kullanıcı bildirimi (TestFlight, 2026-09-17): "Çok kısa zaman içerisinde
/// yüksek sıçramalar ve düşüşler gösteriyordu. Canlı etkinliklerden fark
/// ettim: bir eksi de bir artı da gözüküyordu."
///
/// Ölçülen sebep: canlı altın fiyatı BİRİNCİL kaynaktan (truncgil, yurt içi
/// kotasyon) gelir; o kaynak bir tur cevap vermezse yedek yol devreye girer
/// ve **başka bir ölçekten** (uluslararası spot/vadeli çevrimi) sayı üretir.
/// İki ölçek arasında kalıcı ~%1-2 makas var. 45 saniyelik kotasyon
/// önbelleğiyle birlikte bu, dakikalar içinde ileri geri zıplayan bir fiyat
/// demek: portföy toplamı, grafiğin son noktası ve Live Activity'nin
/// "bugünkü değişim"i aynı anda işaret değiştirir. Fiyat hareketi yok —
/// ÖLÇEK değişiyor.
///
/// Bu test, yedeğin birincilin ölçeğine taşındığını ve oranın grafik
/// yollarından ÜCRETSİZ öğrenildiğini kilitler.
void main() {
  setUp(() => OlcekHafizasi.instance.temizle());
  tearDown(() => OlcekHafizasi.instance.temizle());

  Asset altin(String ticker, double canli) => Asset(
        id: 'a',
        userId: 'u',
        name: ticker,
        ticker: ticker,
        type: AssetType.altin,
        quantity: 1,
        purchasePrice: canli,
        currency: 'TRY',
        notes: '',
        currentPrice: canli,
        addedDate: DateTime(2026, 1, 1),
      );

  group('yedek kaynak birincilin ölçeğine taşınır', () {
    test('öğrenilen oranla yedeğin sayısı hizalanır', () {
      // Birincil (yurt içi) 6.142; yedek (spot çevrimi) 6.250 → makas %1,76.
      OlcekHafizasi.instance.ogren(
        'ALTIN_GRAM',
        FiyatKaynagiEtiketi.spot,
        birincil: 6142.0,
        yedek: 6250.0,
      );

      // Yedek kaynak bir tur sonra 6.275 diyor (gerçek %0,4'lük yükseliş).
      final hizali = OlcekHafizasi.instance
          .hizala('ALTIN_GRAM', FiyatKaynagiEtiketi.spot, 6275.0);

      // Beklenen: aynı ölçekte ~6.166 — yani kullanıcı %1,76'lık bir
      // ZIPLAMA değil, gerçek %0,4'lük hareketi görür.
      expect(hizali, closeTo(6275.0 * (6142.0 / 6250.0), 1e-9));
      expect((hizali - 6142.0) / 6142.0, closeTo(0.004, 0.001));
    });

    test('spot ile vadeli AYRI hatırlanır', () {
      // Tek "yedek" etiketi ikisini karıştırsaydı, vadeli yol devreye
      // girdiğinde spot oranıyla düzeltme yapılır ve zıplama sürerdi.
      OlcekHafizasi.instance.ogren('ALTIN_GRAM', FiyatKaynagiEtiketi.spot,
          birincil: 6142.0, yedek: 6250.0);
      OlcekHafizasi.instance.ogren('ALTIN_GRAM', FiyatKaynagiEtiketi.vadeli,
          birincil: 6142.0, yedek: 6375.0);

      expect(OlcekHafizasi.instance.oran('ALTIN_GRAM', FiyatKaynagiEtiketi.spot),
          isNot(OlcekHafizasi.instance
              .oran('ALTIN_GRAM', FiyatKaynagiEtiketi.vadeli)));
    });

    test('sembol başına ayrı — çeyreğin primi grama yayılmaz', () {
      OlcekHafizasi.instance.ogren('ALTIN_GRAM', FiyatKaynagiEtiketi.spot,
          birincil: 6142.0, yedek: 6250.0);
      expect(
          OlcekHafizasi.instance
              .hizala('ALTIN_CEYREK', FiyatKaynagiEtiketi.spot, 11000.0),
          11000.0,
          reason: 'Öğrenilmemiş sembole başka sembolün oranı uygulanmış.');
    });

    test('oran bilinmiyorsa HAM döner — uydurma çarpan yok', () {
      expect(
          OlcekHafizasi.instance
              .hizala('ALTIN_GRAM', FiyatKaynagiEtiketi.spot, 6250.0),
          6250.0);
    });

    test('ölçek HATASI hafızaya yazılmaz', () {
      // Ağırlık çarpanı atlanmış bir yedek (7,2 kat) "makas" değildir;
      // oran olarak öğrenilirse hata kalıcılaşır ve parite testleri körleşir.
      OlcekHafizasi.instance.ogren('ALTIN_RESAT', FiyatKaynagiEtiketi.spot,
          birincil: 44000.0, yedek: 6100.0);
      expect(
          OlcekHafizasi.instance
              .hizala('ALTIN_RESAT', FiyatKaynagiEtiketi.spot, 6100.0),
          6100.0,
          reason: 'Sınır dışı oran uygulanmış — hata gizleniyor.');
    });

    test('bozuk değerler hizalamayı bozmaz', () {
      OlcekHafizasi.instance.ogren('ALTIN_GRAM', FiyatKaynagiEtiketi.spot,
          birincil: 6142.0, yedek: 6250.0);
      expect(
          OlcekHafizasi.instance
              .hizala('ALTIN_GRAM', FiyatKaynagiEtiketi.spot, 0),
          0);
      expect(
          OlcekHafizasi.instance
              .hizala('ALTIN_GRAM', FiyatKaynagiEtiketi.spot, double.nan)
              .isNaN,
          isTrue);
    });
  });

  group('oran ÜCRETSİZ öğrenilir — grafik zaten hesaplıyor', () {
    test('altın kalibrasyonu ölçek hafızasını besler', () {
      final seri = {1: 6200.0, 2: 6250.0}; // gram22k serisi
      altinKalibrasyonHaritasi(
        assets: [altin('ALTIN_GRAM', 6142.0)],
        gramSerisi: seri,
        kaynak: AltinSeriKaynagi.spotTry,
      );

      final o =
          OlcekHafizasi.instance.oran('ALTIN_GRAM', FiyatKaynagiEtiketi.spot);
      expect(o, isNotNull,
          reason: 'Grafik oranı hesaplıyor ama hafıza öğrenmiyor — canlı '
              'kaynak düştüğünde ölçek yine bilinmeyecek.');
      expect(o, closeTo(6142.0 / 6250.0, 1e-12));
    });

    test('kaynak bilinmiyorsa öğrenilmez — yanlış etikete yazmaktansa boş',
        () {
      altinKalibrasyonHaritasi(
        assets: [altin('ALTIN_GRAM', 6142.0)],
        gramSerisi: {1: 6250.0},
      );
      expect(
          OlcekHafizasi.instance.oran('ALTIN_GRAM', FiyatKaynagiEtiketi.spot),
          isNull);
      expect(
          OlcekHafizasi.instance
              .oran('ALTIN_GRAM', FiyatKaynagiEtiketi.vadeli),
          isNull);
    });

    test('kur hizalaması da öğretir', () {
      kurSerisiniHizala({1: 41.5, 2: 42.0}, 41.8);
      expect(
          OlcekHafizasi.instance
              .oran(FiyatKaynagi.usdTry, FiyatKaynagiEtiketi.spot),
          closeTo(41.8 / 42.0, 1e-12));
    });
  });

  group('sonuç: kaynak değişimi kullanıcıya ZIPLAMA olarak yansımaz', () {
    test('birincil → yedek geçişinde fark, gerçek hareket kadardır', () {
      // Senaryo: t0'da truncgil 6.142 diyor, spot serisi 6.250.
      // t1'de truncgil cevap vermiyor; spot 6.250 (hiç hareket yok).
      OlcekHafizasi.instance.ogren('ALTIN_GRAM', FiyatKaynagiEtiketi.spot,
          birincil: 6142.0, yedek: 6250.0);

      final t1 = OlcekHafizasi.instance
          .hizala('ALTIN_GRAM', FiyatKaynagiEtiketi.spot, 6250.0);

      expect(t1, closeTo(6142.0, 1e-9),
          reason: 'Fiyat hareket etmediği hâlde kaynak değişimi sayıyı '
              'oynatıyor — Live Activity işaret değiştirir.');
    });
  });
}
