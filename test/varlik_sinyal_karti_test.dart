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

  // ── Ekranın en altındaki "Aktif Sinyal" bölümü ───────────────────────────
  //
  // Kullanıcı isteği (2026-09-10): push'a dokunup gelen kişi en altta,
  // gönderilmiş sinyalin ayrıntısını görsün. AKTİF sinyal yoksa bölüm boş
  // kalsın.
  //
  // Aktiflik iki kapıdan geçer (kullanıcı kararı): kullanıcı bildirimi
  // sildiyse VEYA kayıt 7 günden eskiyse gösterilmez.
  group('AktifSinyalBolumu.aktifKayit', () {
    final simdi = DateTime(2026, 9, 10, 20, 0);

    test('kayıt yoksa null — bölüm boş kalır', () {
      expect(
        AktifSinyalBolumu.aktifKayit(const [], _asset(type: AssetType.hisse),
            now: simdi),
        isNull,
      );
    });

    test('taze kayıt gösterilir', () {
      final a = _alert(at: simdi.subtract(const Duration(hours: 3)));
      expect(
        AktifSinyalBolumu.aktifKayit([a], _asset(type: AssetType.hisse),
            now: simdi),
        same(a),
      );
    });

    test('kullanıcı sildiyse gösterilmez', () {
      // `dismissed_at` kullanıcının "bunu gördüm, kapat" demesidir. Ekranda
      // diriltmek o kararı geri almak olurdu.
      final a = _alert(
        at: simdi.subtract(const Duration(hours: 2)),
        dismissedAt: simdi.subtract(const Duration(hours: 1)),
      );
      expect(
        AktifSinyalBolumu.aktifKayit([a], _asset(type: AssetType.hisse),
            now: simdi),
        isNull,
      );
    });

    test('7 GÜNDEN eski kayıt gösterilmez', () {
      // Teknik sinyalin ömrü kısa; iki hafta önceki bir kaydı "aktif" diye
      // sunmak kullanıcıyı yanıltır.
      final a = _alert(at: simdi.subtract(const Duration(days: 8)));
      expect(
        AktifSinyalBolumu.aktifKayit([a], _asset(type: AssetType.hisse),
            now: simdi),
        isNull,
      );
    });

    test('tam sınırda (7 gün) HÂLÂ aktif', () {
      // Sınır kapsayıcı: `> omur` ile eleniyor, `>=` değil. Bu testin
      // varlık sebebi sınırın yanlışlıkla bir gün kaydırılmasını yakalamak.
      final a = _alert(at: simdi.subtract(AktifSinyalBolumu.omur));
      expect(
        AktifSinyalBolumu.aktifKayit([a], _asset(type: AssetType.hisse),
            now: simdi),
        same(a),
      );
    });

    test('eskiyen kayıt varken YENİ kayıt gelirse yeni gösterilir', () {
      final eski = _alert(
          at: simdi.subtract(const Duration(days: 20)),
          signal: SignalType.sell);
      final yeni = _alert(
          at: simdi.subtract(const Duration(hours: 1)), signal: SignalType.buy);
      expect(
        AktifSinyalBolumu.aktifKayit(
            [eski, yeni], _asset(type: AssetType.hisse),
            now: simdi),
        same(yeni),
      );
    });

    test('EN YENİ kayıt silinmişse ESKİYE düşmez', () {
      // Bilinçli karar: `sonSinyal` en yeniyi seçer, biz onu denetleriz.
      // Silinen kaydın altından bir öncekini çıkarmak, kullanıcının
      // kapattığı konuyu başka bir kayıtla yeniden açmak olurdu.
      final eski = _alert(at: simdi.subtract(const Duration(days: 2)));
      final yeniSilinmis = _alert(
        at: simdi.subtract(const Duration(hours: 1)),
        dismissedAt: simdi,
      );
      expect(
        AktifSinyalBolumu.aktifKayit(
            [eski, yeniSilinmis], _asset(type: AssetType.hisse),
            now: simdi),
        isNull,
      );
    });

    test('başka varlığın aktif sinyali sızmaz', () {
      final baska = _alert(
          at: simdi.subtract(const Duration(hours: 1)), ticker: 'GARAN.IS');
      expect(
        AktifSinyalBolumu.aktifKayit([baska], _asset(type: AssetType.hisse),
            now: simdi),
        isNull,
      );
    });
  });

  group('AktifSinyalBolumu yerleşimi', () {
    final kaynak =
        File('lib/screens/performance_screen.dart').readAsStringSync();

    // Kaynak metni satır sonundan BAĞIMSIZ aranır: depo LF tutuyor,
    // `core.autocrlf=true` diske CRLF yazıyor. Ham `\n` aramak Windows'ta
    // her zaman kırılırdı (aynı tuzak 2026-09-10'da iki kez yaşandı).
    final duz = kaynak.replaceAll('\r\n', '\n');

    test('bölüm ekranda KULLANILIYOR', () {
      // Widget yazılıp ekrana takılmayı unutmak sessiz bir hata olurdu:
      // analyze temiz geçer, testler geçer, kullanıcı hiçbir şey görmez.
      expect(duz.contains('asset: widget.asset, icerikKey: _aktifSinyalKey'),
          isTrue,
          reason: 'Bölüm tanımlı ama ekrana eklenmemiş.');
    });

    test('teknik panelden SONRA geliyor — en altta', () {
      final panel = duz.indexOf('key: _sinyalPaneliKey, detayli: true');
      // ÇAĞRIYI ara, sınıf tanımını değil: `AktifSinyalBolumu(` ilk olarak
      // sınıfın kendi constructor'ında geçiyor ve o dosyanın BAŞINDA.
      final bolum = duz.indexOf('asset: widget.asset, icerikKey:');
      expect(panel, greaterThan(-1));
      expect(bolum, greaterThan(panel),
          reason: 'Kullanıcı "en alta" istedi; bölüm panelin üstüne çıkmış.');
    });

    test('mevduatta çizilmez', () {
      // Mevduat için teknik sinyal üretilmiyor (bkz. panel koşulu).
      // Çağrıyı ara — sınıf tanımı `class AktifSinyalBolumu extends`
      // olduğu için parantez ayırt edicidir.
      final bolum = duz.indexOf('asset: widget.asset, icerikKey:');
      expect(bolum, greaterThan(-1));
      final oncesi = duz.substring(bolum - 260, bolum);
      expect(oncesi.contains('!= AssetType.mevduat'), isTrue);
    });

    test('üstteki şerit ÖNCE en alta kaydırır', () {
      // Kullanıcı isteği (2026-09-10): "ekranın en üstündeki kısım
      // kalabilir, tıklanınca en alta inebilir."
      expect(
        duz.contains('_aktifSinyalKey.currentContext ??'),
        isTrue,
        reason: 'Şerit hâlâ yalnızca teknik panele kaydırıyor.',
      );
      // Yedek hedef şart: bölüm koşullu, aktif kayıt yokken hiç çizilmez.
      expect(duz.contains('_sinyalPaneliKey.currentContext'), isTrue);
    });

    test('kaydırma anahtarı İÇERİĞE bağlı — widget\'a değil', () {
      // İnce tuzak: aktif kayıt yokken bölüm `SizedBox.shrink()` döndürür,
      // yani ağaçta DURUR. Anahtar widget'ın kendi `key`'i olsaydı
      // `currentContext` dolu olur, kaydırma sıfır yükseklikli bir kutuya
      // gider ve `??` yedeği hiç devreye girmezdi.
      expect(duz.contains('icerikKey: _aktifSinyalKey'), isTrue,
          reason: 'Anahtar widget\'a bağlanmış; boş durumda kaydırma '
              'sessizce yanlış yere gider.');
      expect(duz.contains('key: _aktifSinyalKey,'), isFalse);
    });
  });
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
    expect(kart.contains('periodDays: 180'), isTrue);
  });

  test('yetersiz geçmişte uydurma sinyal üretilmez', () {
    // Panelle aynı eşik: 30 noktanın altında `analyze` simülasyona düşer.
    expect(kart.contains('prices.length < 30'), isTrue);
  });
}
