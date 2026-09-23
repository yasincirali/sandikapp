import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// Altın kalibrasyon çarpanının DEĞİŞMEZLERİ.
///
/// ## Bu dosya bir kez YANLIŞ şeyi kilitledi — kaydı burada duruyor
///
/// **Belirti 1 (2026-09-23 sabah):** *"Ben seçiliyken Bugün kartında −76 ile
/// 366 arasında oynuyor."* Çarpan serinin son noktasından türetiliyor, o
/// nokta her fetch'te oynuyor ve TÜM seriyi ölçeklediği için gün başı da
/// yerinden kayıyordu.
///
/// **O turda çapa seans başına taşındı.** Salınım durdu ama grafiğin ŞEKLİ
/// bozuldu.
///
/// **Belirti 2 (aynı gün):** *"Altın kategorisini seçip diğerleriyle
/// karşılaştırdım, çok alakasız."* Ölçüldü: seans içinde %2 yükselen bir
/// seride SAĞ UÇTA **−%1,96**'lık yapay basamak. Sebep: seri seans başına
/// hizalanırken son nokta `liveTotal` ile canlı kotasyona eziliyor —
/// aradaki gün içi hareket kadar makas açılıyor.
///
/// **Çapa GERİ ALINDI.** Son nokta çapası basamağı sıfırlar (ölçüldü:
/// %0,0000) çünkü hizalanan uç ile ezilen uç AYNI noktadır.
///
/// ## Salınım ne oldu
/// Kök neden çarpan DEĞİLDİ: iki yüzey serilerini farklı anlarda
/// tazeliyordu. `TazelikRitmi` ile ritimler hizalandı ve `BugunKarti` kendi
/// tick'ini aldı (bkz. `bugun_karti_seri_yasi_test`). Çarpan artık her
/// yerde AYNI serinin son noktasından geliyor, yani aynı sayıyı veriyor.
Asset _altin({
  String ticker = 'ALTIN_CEYREK',
  double cur = 8000,
  double qty = 20,
}) =>
    Asset(
      id: 'a_$ticker',
      userId: 'ben',
      name: ticker,
      ticker: ticker,
      type: AssetType.altin,
      subCategory: ticker,
      quantity: qty,
      purchasePrice: 7500,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: cur,
      addedDate: DateTime(2026, 1, 1),
    );

/// Seans başı sabit, uç oynak — gerçek tazeleme davranışı.
Map<int, double> _seri({required double sonGram, double gunBasiGram = 4980}) => {
      DateTime(2026, 9, 23, 10).millisecondsSinceEpoch: gunBasiGram,
      DateTime(2026, 9, 23, 14).millisecondsSinceEpoch: sonGram,
    };

void main() {
  group('ŞEKİL bozulmaz — sağ uçta basamak YOK', () {
    // Bu grubun tamamı ikinci belirtinin (grafik şekli) kilididir.
    const agirlik = 1.75; // ALTIN_CEYREK

    test('seans içi hareket varken son nokta ZIPLAMAZ', () {
      // Seri %2 yükseliyor; canlı kotasyon son seviyeye + %2 yurt içi prim.
      final seri = <int, double>{};
      for (var s = 0; s <= 10; s++) {
        seri[DateTime(2026, 9, 23, 10 + s).millisecondsSinceEpoch] =
            5000.0 + s * 10.0;
      }
      final canli = 5100.0 * agirlik * 1.02;

      final k = altinKalibrasyonHaritasi(
        assets: [_altin(cur: canli)],
        gramSerisi: seri,
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;

      // Serinin SON noktası çarpanla ölçeklendiğinde canlıya OTURMALI;
      // `liveTotal` o noktayı ezdiği için aksi hâlde basamak kalır.
      final seriSon = 5100.0 * agirlik * k;
      expect(seriSon, closeTo(canli, 0.01),
          reason: 'ölçüldü (çapa=gün başı iken): −%1,96 basamak — '
              'kullanıcı "çok alakasız" dedi');
    });

    test('ÇAPA=gün başı olsaydı basamak OLUŞURDU (regresyon kanıtı)', () {
      final gunBasi = 5000.0;
      final son = 5100.0;
      final canli = son * agirlik * 1.02;

      // Geri alınan davranış: çarpan İLK noktadan.
      final capaK = canli / (gunBasi * agirlik);
      final seriSonCapali = son * agirlik * capaK;
      final sicrama = (canli / seriSonCapali - 1).abs();

      expect(sicrama, greaterThan(0.005),
          reason: 'gün içi hareket kadar makas açılıyordu');
      expect(sicrama, closeTo(0.0196, 0.001),
          reason: 'ölçülen belirti: −%1,96');
    });

    test('ŞEKİL çarpandan BAĞIMSIZ — yüzde değişmez', () {
      // Çarpan oransaldır: seviyeyi kaydırır, şekli korur.
      final seri = _seri(sonGram: 5100, gunBasiGram: 5000);
      final k = altinKalibrasyonHaritasi(
        assets: [_altin()],
        gramSerisi: seri,
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;

      final hamPct = 5100.0 / 5000.0 - 1;
      final kalibrePct = (5100.0 * agirlik * k) / (5000.0 * agirlik * k) - 1;
      expect(kalibrePct, closeTo(hamPct, 1e-12),
          reason: 'MA20/RSI/gün içi yüzde korunmalı');
    });
  });

  group('çarpan son noktadan gelir', () {
    test('serinin UCU oynayınca çarpan DEĞİŞİR (beklenen)', () {
      // Salınım bu yüzden oluşuyordu; çözümü çarpanı dondurmak DEĞİL,
      // serinin tazelik ritmini hizalamaktı (`TazelikRitmi`).
      final a = altinKalibrasyonHaritasi(
        assets: [_altin()],
        gramSerisi: _seri(sonGram: 4990),
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      final b = altinKalibrasyonHaritasi(
        assets: [_altin()],
        gramSerisi: _seri(sonGram: 5010),
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      expect(a, isNot(closeTo(b, 1e-9)));
    });

    test('AYNI seri → AYNI çarpan (belirleyici)', () {
      // Ritimler hizalandığı için iki yüzey aynı seriyi görür ve aynı
      // çarpanı hesaplar — parite buradan gelir.
      final seri = _seri(sonGram: 5000);
      final a = altinKalibrasyonHaritasi(
        assets: [_altin()],
        gramSerisi: seri,
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      final b = altinKalibrasyonHaritasi(
        assets: [_altin()],
        gramSerisi: seri,
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      expect(a, b);
    });

    test('CANLI fiyat oynayınca çarpan değişir (doğru davranış)', () {
      final ucuz = altinKalibrasyonHaritasi(
        assets: [_altin(cur: 8000)],
        gramSerisi: _seri(sonGram: 5000),
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      final pahali = altinKalibrasyonHaritasi(
        assets: [_altin(cur: 8200)],
        gramSerisi: _seri(sonGram: 5000),
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      expect(ucuz, isNot(closeTo(pahali, 1e-9)));
    });
  });

  group('sembol başına EN TAZE lot seçilir', () {
    // Kullanıcı bildirimi (2026-09-23): *"Loggedin user'ın altın
    // grafiğinde bir sorun var, ortaklarınıki doğruyken."*
    //
    // Eskiden `containsKey` ile LİSTEDEKİ İLK lot kazanıyordu.
    // `fetchByUser` `added_date DESC` döndürüyor ve yerel mutasyonlar yeni
    // lotu BAŞA ekliyor — yani "ilk lot" çoğu zaman EN YENİ eklenen,
    // henüz fiyatlanmamış olandı.
    //
    // Ölçüldü: ilk lot %3 bayat `currentPrice` taşıdığında çarpan 1,03
    // yerine 0,9991 çıkıyor ve TÜM SERİ %3 aşağı kayıyordu — şekil değil
    // SEVİYE yanlış oluyordu.
    const agirlik = 1.75;
    final tekNoktaliSeri = {
      DateTime(2026, 9, 23, 14).millisecondsSinceEpoch: 5100.0
    };

    Asset lot(double cur, DateTime? guncelleme) => Asset(
          id: 'c-${cur.toStringAsFixed(0)}-${guncelleme?.hour ?? 0}',
          userId: 'ben',
          name: 'ALTIN_CEYREK',
          ticker: 'ALTIN_CEYREK',
          type: AssetType.altin,
          subCategory: 'ALTIN_CEYREK',
          quantity: 10,
          purchasePrice: 1,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          purchaseFxRate: 1,
          currentPrice: cur,
          lastUpdated: guncelleme,
          addedDate: DateTime(2026, 1, 1),
        );

    test('BAYAT lot ilk sırada olsa bile TAZE olan kazanır', () {
      final dogru = 5100.0 * agirlik * 1.03;
      final k = altinKalibrasyonHaritasi(
        assets: [
          lot(dogru * 0.97, DateTime(2026, 9, 23, 10)), // bayat, İLK
          lot(dogru, DateTime(2026, 9, 23, 17)), // taze
        ],
        gramSerisi: tekNoktaliSeri,
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;

      final cizilen = 5100.0 * agirlik * k;
      expect(cizilen, closeTo(dogru, 0.01),
          reason: 'ölçüldü (düzeltme öncesi): tüm seri %3 aşağı kayıyordu');
    });

    test('ALTI lotluk gerçek senaryo (kullanıcının defteri)', () {
      // Ortak defterlerinde ayar başına 1-2 lot var; kendi defterinde altı.
      // İki lotta "ilk" ile "en taze" çoğu zaman aynı, altıda ayrışıyor —
      // belirtinin yalnızca kendi portföyünde görülmesinin sebebi bu.
      final dogru = 5100.0 * agirlik * 1.03;
      final lotlar = [
        lot(dogru * 0.97, DateTime(2026, 9, 23, 9)), // yeni eklenen, fiyatsız
        for (var i = 0; i < 5; i++) lot(dogru, DateTime(2026, 9, 23, 17)),
      ];
      final k = altinKalibrasyonHaritasi(
        assets: lotlar,
        gramSerisi: tekNoktaliSeri,
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      expect(5100.0 * agirlik * k, closeTo(dogru, 0.01));
    });

    test('tarihsiz aday mevcudu DEVİRMEZ (davranış korunur)', () {
      final dogru = 5100.0 * agirlik * 1.03;
      final k = altinKalibrasyonHaritasi(
        assets: [
          lot(dogru, DateTime(2026, 9, 23, 17)), // taze, tarihli
          lot(dogru * 0.90, null), // tarihsiz — seçilmemeli
        ],
        gramSerisi: tekNoktaliSeri,
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      expect(5100.0 * agirlik * k, closeTo(dogru, 0.01));
    });

    test('hepsi tarihsizse LİSTE SIRASI korunur (eski davranış)', () {
      final ilk = 5100.0 * agirlik * 1.03;
      final k = altinKalibrasyonHaritasi(
        assets: [lot(ilk, null), lot(ilk * 0.90, null)],
        gramSerisi: tekNoktaliSeri,
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      expect(5100.0 * agirlik * k, closeTo(ilk, 0.01),
          reason: 'tarih bilgisi yoksa davranış DEĞİŞMEMELİ');
    });
  });

  group('bozulmadı (regresyon)', () {
    test('tek noktalı seride çarpan yine hesaplanır', () {
      final k = altinKalibrasyonHaritasi(
        assets: [_altin()],
        gramSerisi: {DateTime(2026, 9, 23, 14).millisecondsSinceEpoch: 5000.0},
        kaynak: AltinSeriKaynagi.vadeliUsd,
      );
      expect(k['ALTIN_CEYREK'], isNotNull);
      expect(k['ALTIN_CEYREK'], greaterThan(0));
    });

    test('boş seri boş harita döndürür', () {
      expect(
          altinKalibrasyonHaritasi(assets: [_altin()], gramSerisi: const {}),
          isEmpty);
    });

    test('fiyatsız altın çarpan almaz — uydurma yok', () {
      expect(
          altinKalibrasyonHaritasi(
            assets: [_altin(cur: 0)],
            gramSerisi: _seri(sonGram: 5000),
          ),
          isEmpty);
    });

    test('her AYAR kendi çarpanını alır', () {
      final k = altinKalibrasyonHaritasi(
        assets: [
          _altin(ticker: 'ALTIN_GRAM', cur: 5000),
          _altin(ticker: 'ALTIN_CEYREK', cur: 8200),
        ],
        gramSerisi: _seri(sonGram: 5000),
        kaynak: AltinSeriKaynagi.vadeliUsd,
      );
      expect(k.keys, containsAll(['ALTIN_GRAM', 'ALTIN_CEYREK']),
          reason: 'gram ile çeyreğin makası aynı değildir');
      expect(PriceService.goldWeightFactor('ALTIN_CEYREK'), 1.75);
    });
  });
}
