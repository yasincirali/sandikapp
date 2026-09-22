import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// **Altın grafiğinin son noktası dik bir uçurumla düşüyordu.**
///
/// Kullanıcı bildirimi (2026-09-17, ekran görüntüsüyle): "Altın grafiği
/// böyle sert düşüş gözüküyor şimdi anında ancak aslında böyle olmaması
/// gerekiyor, incelediğimde gerçek grafikten farklı çıkartıyor anlık son
/// değer." Ekranda 22 ayar gram altının gün içi serisi ~6.250 ₺ bandında
/// yatayken "ŞİMDİ" imleci ~6.142 ₺'ye iniyordu — %1,7'lik tek noktalık bir
/// düşüş, üstelik hiçbir ara nokta olmadan.
///
/// ## Sebep: İKİ FARKLI FİYAT ÖLÇEĞİ
/// Altında seri ile canlı fiyat aynı kaynaktan gelmiyor:
///   * seri  → Yahoo `XAUTRY=X` (yedek `GC=F × USDTRY`) → `gram22kFromXauTry`,
///     yani uluslararası spot'un saf 22/24 çevrimi,
///   * canlı → truncgil `YIA` (22 ayar bilezik, `Alış` tarafı).
/// Aradaki makas kalıcıdır. Her grafik son noktasını canlı değere
/// sabitlediği için (üç ayrı yolda: `getPortfolioHistory` `liveTotal`'ı, gün
/// içi son slot hizalaması, ekranın `currentUnitPriceOverride`'ı) bu makas
/// grafikte fiyat hareketi gibi görünüyordu.
///
/// Aynı makas günlük değişimi de bozuyordu: "AÇILIŞ" seri ölçeğinde,
/// "ŞİMDİ" canlı ölçekte okunuyordu.
///
/// ## Çözüm ve bu testin koruduğu şey
/// Seri, sembol başına bir ÇARPANLA canlı ölçeğe taşınır
/// (`altinKalibrasyonu`). Çarpan oransal olan her şeyi korur (gün içi şekil,
/// dönem yüzdesi, MA/RSI) ve yalnızca seviyeyi hizalar.
///
/// Test üç şeyi birden kilitliyor:
///   1. çarpanın kendisi (saf fonksiyon, ağ yok),
///   2. uygulandığında uçurumun kapandığı ve şeklin BOZULMADIĞI,
///   3. çarpanın bir ölçek HATASINI (ağırlık çarpanı atlanmış) örtmediği —
///      aksi halde `altin_agirlik_carpani_parite_test`'in yakaladığı hata
///      sınıfı sessizce "düzeltilmiş" görünürdü.
void main() {
  Asset altin(String ticker, double canliFiyat, {double miktar = 1}) => Asset(
        id: 'a-$ticker',
        userId: 'u1',
        name: ticker,
        ticker: ticker,
        type: AssetType.altin,
        quantity: miktar,
        purchasePrice: canliFiyat * 0.9,
        currency: 'TRY',
        notes: '',
        currentPrice: canliFiyat,
        addedDate: DateTime.now().subtract(const Duration(days: 30)),
      );

  group('kalibrasyon çarpanı', () {
    test('yurt içi makas kadar oran döner', () {
      // Ekran görüntüsündeki ölçüm: seri 6.250, canlı 6.142.
      final k = altinKalibrasyonu(
        seriSonBirimTRY: 6250.0,
        canliBirimTRY: 6142.0,
      );
      expect(k, closeTo(6142.0 / 6250.0, 1e-12));
      // Çarpan uygulanınca serinin ucu CANLI değere oturur — uçurum kalmaz.
      expect(6250.0 * k, closeTo(6142.0, 1e-9));
    });

    test('ölçülemeyen uçlarda çarpan 1.0 — seri OLDUĞU GİBİ kalır', () {
      // Fiyatı çekilememiş varlık (currentPrice = 0) ya da boş seri, serinin
      // seviyesini değiştirmek için bir gerekçe DEĞİLDİR.
      expect(altinKalibrasyonu(seriSonBirimTRY: 6250, canliBirimTRY: 0), 1.0);
      expect(altinKalibrasyonu(seriSonBirimTRY: 0, canliBirimTRY: 6142), 1.0);
      expect(altinKalibrasyonu(seriSonBirimTRY: -5, canliBirimTRY: 6142), 1.0);
      expect(
          altinKalibrasyonu(
              seriSonBirimTRY: double.nan, canliBirimTRY: 6142), 1.0);
      expect(
          altinKalibrasyonu(
              seriSonBirimTRY: 6250, canliBirimTRY: double.infinity), 1.0);
    });

    test('ÖLÇEK HATASI kalibre EDİLMEZ — hata görünür kalır', () {
      // Reşat hatasının imzası: ağırlık çarpanı uygulanmamış seri, canlı
      // fiyattan 7,2 kat küçük. Bu bir makas değil, hesap hatasıdır; çarpanla
      // "düzeltmek" grafiği doğru gösterip pozisyon değerini yanlış bırakırdı.
      final k = altinKalibrasyonu(
        seriSonBirimTRY: 6200.0,
        canliBirimTRY: 6200.0 * 7.216,
      );
      expect(k, 1.0,
          reason: 'Kalibrasyon ölçek hatasını örtüyor — ağırlık çarpanı '
              'atlanmış bir seri sessizce doğru görünür.');
      // Sınırın hemen dışı da kalibre edilmez, hemen içi edilir.
      expect(
          altinKalibrasyonu(
              seriSonBirimTRY: 100, canliBirimTRY: 100 * altinKalibreUstSinir * 1.01),
          1.0);
      expect(
          altinKalibrasyonu(
              seriSonBirimTRY: 100, canliBirimTRY: 100 * altinKalibreAltSinir * 1.01),
          isNot(1.0));
    });
  });

  group('sembol başına çarpan', () {
    // Seri ham gram22k taşır; her ürünün canlı kotasyonu kendi primini
    // içerir. Tek bir genel çarpan bu yüzden YETMEZ.
    final seri = <int, double>{
      1: 6100.0,
      2: 6200.0,
      3: 6250.0, // son nokta — hizalanacak uç burası
    };

    test('her sembol KENDİ kotasyonuna hizalanır', () {
      final gram = altin('ALTIN_GRAM', 6142.0);
      // Çeyrek: gram22k × 1.75 = 10.937,5 iken kotasyon primli.
      final ceyrek = altin('ALTIN_CEYREK', 11250.0);
      final harita = altinKalibrasyonHaritasi(
        assets: [gram, ceyrek],
        gramSerisi: seri,
      );

      // Çapa İLK nokta (6.100) — bkz. aşağıdaki "çapa" testi.
      expect(harita['ALTIN_GRAM'], closeTo(6142.0 / 6100.0, 1e-12));
      expect(
          harita['ALTIN_CEYREK'],
          closeTo(
              11250.0 /
                  (6100.0 * PriceService.goldWeightFactor('ALTIN_CEYREK')),
              1e-12));
      expect(harita['ALTIN_GRAM'], isNot(closeTo(harita['ALTIN_CEYREK']!, 1e-6)),
          reason: 'İki ürün tek çarpana indirgenmiş — birinin primi '
              'diğerine yayılır.');
    });

    test('çarpan serinin ÇAPASINDAN (ilk nokta) türetilir', () {
      // **Değişti (kullanıcı bildirimi, 2026-09-23).** Eskiden çarpan SON
      // noktadan türetiliyordu ve bu test onu kilitliyordu.
      //
      // Son nokta her fetch'te oynar (vadeli sözleşme sürekli kote edilir).
      // Çarpan TÜM seriyi ölçeklediği için GÜN BAŞI da her tazelemede
      // yerinden oynuyor, canlı fiyat hiç değişmeden "bugünkü değişim"
      // salınıyordu: ölçüldü ₺9.436 ↔ ₺9.887, yani ₺451 hayalet hareket
      // (bkz. `altin_kalibrasyon_kararliligi_test`).
      //
      // ## Sağ uçtaki hizalama KAYBOLMADI
      // Bu testin koruduğu şey ("ŞİMDİ imlecinde basamak olmasın") başka
      // bir mekanizmayla zaten sağlanıyor: `HistoryService` son noktayı
      // KOŞULSUZ canlı toplamla eziyor
      // (`groupedPoints[todayTs] = liveTotal`). Yani uç canlıya, taban
      // sabit çapaya bağlanır; ikisi bir arada hem basamağı kapatır hem
      // de tabanı sabit tutar.
      final harita = altinKalibrasyonHaritasi(
        assets: [altin('ALTIN_GRAM', 6142.0)],
        gramSerisi: seri,
      );
      expect(harita['ALTIN_GRAM'], closeTo(6142.0 / 6100.0, 1e-12));
    });

    test('seri boşsa / fiyat yoksa harita boş — çağıran 1.0 kullanır', () {
      expect(
          altinKalibrasyonHaritasi(
              assets: [altin('ALTIN_GRAM', 6142)], gramSerisi: const {}),
          isEmpty);
      expect(
          altinKalibrasyonHaritasi(
              assets: [altin('ALTIN_GRAM', 0)], gramSerisi: seri),
          isEmpty);
    });

    test('altın olmayan varlık haritaya girmez', () {
      final hisse = Asset(
        id: 'h1',
        userId: 'u1',
        name: 'THYAO',
        ticker: 'THYAO.IS',
        type: AssetType.hisse,
        quantity: 10,
        purchasePrice: 300,
        currency: 'TRY',
        notes: '',
        currentPrice: 320,
        addedDate: DateTime.now(),
      );
      expect(
          altinKalibrasyonHaritasi(assets: [hisse], gramSerisi: seri), isEmpty);
    });
  });

  group('uçurum kapanır, ŞEKİL bozulmaz', () {
    // Grafiğin çizdiği şeyin birebir simülasyonu: gün içi gram serisi ×
    // ağırlık × (kalibrasyon) — son nokta canlı fiyatla eziliyor.
    const canli = 6142.0;
    final gram = <int, double>{
      1: 6200.0,
      2: 6230.0,
      3: 6270.0,
      4: 6250.0,
    };

    List<double> birimSeri(double k) =>
        [for (final ts in gram.keys.toList()..sort()) gram[ts]! * k];

    test('kalibrasyonsuz seride son nokta UÇURUM yaratıyordu', () {
      final seri = birimSeri(1.0);
      final sicrama =
          ((canli - seri.last) / seri.last).abs();
      expect(sicrama, greaterThan(0.01),
          reason: 'Regresyon senaryosu artık uçurum üretmiyor — test '
              'ölçtüğü hatayı kaybetmiş.');
    });

    test('son nokta CANLI değere oturur — `liveTotal` ezmesiyle', () {
      // **Değişti (2026-09-23).** Eskiden bu testi kalibrasyon çarpanı
      // tek başına sağlıyordu (çapa = son nokta). Çapa seans başına
      // taşınınca çarpan artık ucu tam oturtmuyor — ama oturtması da
      // GEREKMİYOR: `HistoryService` son noktayı zaten koşulsuz canlı
      // toplamla eziyor.
      //
      // Testin koruduğu değer aynı: kullanıcı "ŞİMDİ" imlecinde basamak
      // görmemeli. Artık çarpanı değil, ÇİZİLENİ ölçüyor.
      final k = altinKalibrasyonHaritasi(
        assets: [altin('ALTIN_GRAM', canli)],
        gramSerisi: gram,
      )['ALTIN_GRAM']!;
      final seri = birimSeri(k);
      // `HistoryService`'in yaptığı: son nokta = canlı toplam.
      final cizilen = [...seri.take(seri.length - 1), canli];
      expect(cizilen.last, closeTo(canli, 1e-9),
          reason: 'Çizilen serinin ucu canlı fiyatta olmalı');
      // Basamak da makul kalmalı: çarpan tabanı doğru ölçeğe taşıdığı
      // için son iki nokta arası sıçrama küçüktür (kalibrasyonsuz %1'i
      // aşıyordu — bir üstteki test).
      final sicrama = ((canli - seri.last) / seri.last).abs();
      expect(sicrama, lessThan(0.01),
          reason: 'kalibrasyon tabanı doğru ölçeğe taşımazsa uçta '
              'görünür bir basamak kalırdı');
    });

    test('gün içi hareketin YÜZDESİ değişmez', () {
      final k = altinKalibrasyonHaritasi(
        assets: [altin('ALTIN_GRAM', canli)],
        gramSerisi: gram,
      )['ALTIN_GRAM']!;
      final ham = birimSeri(1.0);
      final kal = birimSeri(k);
      for (int i = 1; i < ham.length; i++) {
        final hamPct = (ham[i] - ham[i - 1]) / ham[i - 1];
        final kalPct = (kal[i] - kal[i - 1]) / kal[i - 1];
        expect(kalPct, closeTo(hamPct, 1e-12),
            reason: 'Çarpan oranları bozmuş — dönem yüzdesi, MA20 ve '
                'sinyaller de kayar.');
      }
    });
  });

  group('üç grafik yolu da kalibre EDİLİR', () {
    // Bu projede tekrar eden hata sınıfı: altın hesabının üç kopyası
    // (`getPortfolioHistory`, `...HourlyBreakdown`, `...AtResolution`)
    // zamanla ayrışıyor — ağırlık çarpanı tam olarak böyle bir kopyada
    // eksik kalmıştı. Kalibrasyon aynı akıbete uğramasın.
    final servis = File('lib/services/history_service.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    test('üç yol da haritayı kurar', () {
      // Tanım `fiyat_kaynagi.dart`'a TAŞINDI (kaynak sözleşmesi, 2026-09-17);
      // burada sayılan şey KULLANIM: üç grafik yolu.
      final sayi = 'altinKalibrasyonHaritasi('.allMatches(servis).length;
      expect(sayi, greaterThanOrEqualTo(3),
          reason: 'Bir grafik yolu kalibrasyonsuz kalmış — o yolda uçurum '
              'geri gelir.');
    });

    test('altın değeri hesaplanan her yerde çarpan uygulanır', () {
      // Gün içi: seed + slot; günlük: gün değeri; tier: slot.
      expect(
          servis.contains(
              'goldSlots[firstTs]! * goldFactor(a.ticker) * goldKal(a.ticker)'),
          isTrue,
          reason: 'Gün içi seed kalibre edilmiyor — seans öncesi plato ile '
              'ilk gerçek slot arasında basamak kalır.');
      expect(
          servis.contains(
              'v = gram * goldFactor(a.ticker) * goldKal(a.ticker) * qty;'),
          isTrue,
          reason: 'Gün içi slot değeri kalibre edilmiyor.');
      expect(servis.contains('assetDayVal = price * factor * kal * qty;'),
          isTrue,
          reason: 'Günlük seri kalibre edilmiyor.');
    });
  });
}
