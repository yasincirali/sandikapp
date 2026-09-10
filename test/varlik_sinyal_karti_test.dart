import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/technical_signal.dart';
import 'package:portfoy_takip/screens/performance_screen.dart';

/// Varlık performans ekranındaki sinyal şeridi.
///
/// İki ayrı şeyi kilitler:
///   1. `sonSinyal` — kayıtlı bir bildirimi bu varlıkla eşleştirme kuralı,
///   2. şeridin kayıt YOKKEN canlı göstergelere düşmesi (aşağıdaki kaynak
///      denetimi).
///
/// Kritik nokta: sinyal kaydı bir LOT id'si taşır ve o lot bu ekrandaki
/// pozisyonun temsilcisi OLMAYABİLİR (kullanıcı birkaç kez almış olabilir,
/// sunucu kendi temsilcisini seçer). Eşleşme bu yüzden id ile değil,
/// ticker + tür ile yapılır.

Asset _asset({
  required AssetType type,
  String ticker = 'THYAO.IS',
  String name = 'Türk Hava Yolları',
  String id = 'lot-1',
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: name,
      ticker: ticker,
      type: type,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
    );

SignalAlert _alert({
  required DateTime at,
  String ticker = 'THYAO.IS',
  String name = 'Türk Hava Yolları',
  AssetType type = AssetType.hisse,
  SignalType signal = SignalType.buy,
  String assetId = 'baska-lot',
  DateTime? dismissedAt,
}) =>
    SignalAlert(
      assetId: assetId,
      assetName: name,
      assetTicker: ticker,
      assetType: type,
      signal: signal,
      buyCount: 4,
      sellCount: 2,
      confidence: 67,
      detectedAt: at,
      dismissedAt: dismissedAt,
    );

void main() {
  group('AssetSignalCard.sonSinyal', () {
    test('kayıt yoksa null — kart hiç çizilmez', () {
      expect(
        AssetSignalCard.sonSinyal(const [], _asset(type: AssetType.hisse)),
        isNull,
      );
    });

    test('ticker eşleşen kaydı bulur — lot id FARKLI olsa bile', () {
      // Asıl hata buydu: sunucu kendi temsilci lot\'unu yazıyor, ekran
      // başka bir lot\'la açılıyor. id karşılaştırması hiç eşleşmezdi.
      final a = _alert(at: DateTime(2026, 9, 9, 11), assetId: 'sunucu-lot');
      final bulunan = AssetSignalCard.sonSinyal(
          [a], _asset(type: AssetType.hisse, id: 'ekran-lot'));
      expect(bulunan, same(a));
    });

    test('EN YENİ kayıt kazanır', () {
      final eski = _alert(at: DateTime(2026, 9, 1), signal: SignalType.sell);
      final yeni = _alert(at: DateTime(2026, 9, 9), signal: SignalType.buy);
      final bulunan = AssetSignalCard.sonSinyal(
          [eski, yeni], _asset(type: AssetType.hisse));
      expect(bulunan, same(yeni));
    });

    test('başka varlığın sinyali sızmaz', () {
      final baska = _alert(at: DateTime(2026, 9, 9), ticker: 'GARAN.IS');
      expect(
        AssetSignalCard.sonSinyal([baska], _asset(type: AssetType.hisse)),
        isNull,
      );
    });

    test('aynı ticker farklı TÜR eşleşmez', () {
      // Aynı kod hem hisse hem fon olabilir; tür ayrımı olmadan biri
      // ötekinin sinyalini gösterirdi.
      final fonSinyali = _alert(
          at: DateTime(2026, 9, 9), ticker: 'ABC', type: AssetType.fon);
      expect(
        AssetSignalCard.sonSinyal(
            [fonSinyali], _asset(type: AssetType.hisse, ticker: 'ABC')),
        isNull,
      );
    });

    test('ticker büyük/küçük harf ve boşluk farkını yutar', () {
      final a = _alert(at: DateTime(2026, 9, 9), ticker: ' thyao.is ');
      expect(
        AssetSignalCard.sonSinyal([a], _asset(type: AssetType.hisse)),
        same(a),
      );
    });

    test('ticker\'ı olmayan varlıkta İSİM eşleşmesine düşer', () {
      // Altın alt kategorileri ve "diğer" varlıkların ticker\'ı yok.
      final a = _alert(
          at: DateTime(2026, 9, 9),
          ticker: '',
          name: 'Gram Altın',
          type: AssetType.altin);
      final bulunan = AssetSignalCard.sonSinyal(
        [a],
        _asset(type: AssetType.altin, ticker: '', name: 'gram altın'),
      );
      expect(bulunan, same(a));
    });
  });

  group('AssetSignalCard kaynak denetimi', _kaynakTestleri);
}

// ── Şerit KAYIT BEKLEMEZ ─────────────────────────────────────────────────────
//
// İlk sürüm yalnızca `signal_notifications` satırı varsa çiziliyordu:
//
//     final alert = sonSinyal(alerts, asset);
//     if (alert == null) return const SizedBox.shrink();
//
// O satır ancak bir sinyal güven eşiğini geçtiğinde VE öncekinden farklı
// olduğunda yazılır — yani çoğu varlıkta çoğu zaman YOKTUR. Sonuç: sinyal
// bilgisi pratikte yalnızca sayfanın dibindeki panelde kalıyordu
// (kullanıcı bildirimi 2026-09-10: "sinyaller varlık performansta gözükmeli").
//
// Doğrusu: kayıt yoksa CANLI göstergelere düşmek. Bu davranış widget testiyle
// doğrulanamıyor — canlı yol ağ istiyor ve test ortamında `HistoryService`
// boş seri döndürüp yine gizlenmeye düşüyor. Bu yüzden kaynak metni
// denetleniyor; projede aynı örüntü var (bkz. watchlist_detail_test.dart,
// remote_config_defaults_test.dart).

void _kaynakTestleri() {
  final kaynak = File('lib/screens/performance_screen.dart').readAsStringSync();
  // Yalnızca kartın gövdesi — dosyanın geri kalanındaki eşleşmeler saymasın.
  final bas = kaynak.indexOf('class AssetSignalCard');
  final son = kaynak.indexOf('/// Teknik gösterge paneli.');
  final kart = kaynak.substring(bas, son);

  test('kart, kayıt yoksa erken dönmez', () {
    expect(
      kart.contains('if (alert == null) return const SizedBox.shrink();'),
      isFalse,
      reason: 'Kayıtlı bildirim yokluğunda şerit gizleniyor — canlı '
          'göstergelere düşmesi gerek.',
    );
  });

  test('kart canlı göstergeleri KENDİ hesaplar', () {
    expect(kart.contains('TechnicalAnalysisService.analyzeSeries'), isTrue,
        reason: 'Şerit canlı sinyali hesaplamıyor; yalnızca kayda bakıyorsa '
            'çoğu varlıkta boş kalır.');
    expect(kart.contains('TechnicalAnalysisService.summarize'), isTrue);
  });

  test('şerit ile panel AYNI fiyat serisini ister', () {
    // Farklı pencere (ör. 90 gün) kullanılsaydı üstteki özet ile alttaki
    // panel aynı varlık için farklı sinyal gösterebilirdi.
    // Pencere 180'den 90'a çekildi (2026-09-10): 180 gün HAFTALIK katmana
    // düşüyor ve nokta sayısı eşiğin altına iniyordu — göstergeler hiçbir
    // varlıkta çizilmiyordu. Ayrıntı: `sinyal_penceresi_test.dart`.
    expect(kart.contains('periodDays: kSinyalPenceresiGun'), isTrue);
  });

  test('yetersiz geçmişte uydurma sinyal üretilmez', () {
    // Panelle aynı eşik: 30 noktanın altında `analyze` simülasyona düşer.
    expect(kart.contains('prices.length < 30'), isTrue);
  });

  test('bildirimin SAATİ de yazılır — tarih tek başına yetmez', () {
    // Kullanıcı isteği (2026-09-10): "bir üstteki kısma bildirim zaman ve
    // tarihini ekle bunu kaçırmaması lazım."
    //
    // Ekranın altındaki ayrıntılı "Aktif Sinyal" bölümü kaldırıldı; artık
    // bildirimin NE ZAMAN geldiği YALNIZCA bu şeritte görünüyor. Aynı gün
    // içinde iki sinyal gelebildiği için tarih tek başına ayırt etmiyor.
    //
    // ## Yapı 2026-09-10'da değişti
    // Önce iki yerde de MUTLAK tarih vardı ve bu test iki kopyayı
    // sayıyordu. Şerit tasarım örneğine uyarlanınca sol satır GÖRELİ
    // zamana geçti ("10 dk önce"), mutlak tarih sağ sütunda TEK yerde
    // toplandı. Kopya saymak artık yapıyı değil, tesadüfü ölçer.
    //
    // Değişmez aynı kaldı: saat bilgisi hiçbir kolda düşmemeli. İki
    // koşul birlikte bunu garanti eder — mutlak biçim saat içerir ve
    // sağ sütunda koşulsuz çizilir.
    expect(kart.contains("'d MMM · HH:mm'"), isTrue,
        reason: 'Mutlak zaman biçimi saatsiz kalmış.');
    expect(kart.contains('goreliZaman(kayit.detectedAt'), isTrue,
        reason: 'Göreli zaman ifadesi kayıp.');

    // Kayıt satırı `canli` koşuluna BAĞLANMAMALI: fiyat geçmişi
    // çekilemediğinde şerit kaydın kendisini gösterir ve o kolda satır
    // gizlenirse bildirimin yönü + göreli zamanı tamamen kaybolur
    // (2026-09-10'da render testiyle yakalandı).
    expect(kart.contains('final kayitSatiri = (canli &&'), isFalse,
        reason: '`canli` koşulu geri gelmiş — çevrimdışı kolda bildirim '
            'bilgisi kayboluyor.');
  });

  test('kaldırılan bölüm GERİ GELMEZ', () {
    // Kullanıcı kararı (2026-09-10): ekranın en altındaki büyük "AKTİF
    // SİNYAL" kartı kaldırıldı — "aşağı trend bilgisi çok bağırıyor ve
    // itici duruyor ekran".
    //
    // Bilgi kaybolmadı: yön, güven ve gösterge sayısı üstteki şeritte
    // zaten var; zaman/tarih de oraya taşındı (yukarıdaki test).
    final tam = File('lib/screens/performance_screen.dart').readAsStringSync();
    expect(tam.contains('class AktifSinyalBolumu'), isFalse,
        reason: 'Kaldırılan bölüm geri gelmiş.');
    expect(tam.contains("'AKTİF SİNYAL'"), isFalse);
    expect(tam.contains('_aktifSinyalKey'), isFalse,
        reason: 'Bölümün kaydırma anahtarı ölü kod olarak kalmış.');
  });
}
