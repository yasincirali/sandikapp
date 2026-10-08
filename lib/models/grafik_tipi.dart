import 'package:flutter/material.dart';

/// Performans grafiğinin çizim biçimi.
///
/// Kullanıcı isteği (2026-09-12): TradingView'deki gibi bir tip seçici;
/// seçim **oturum boyunca** korunsun, varsayılan **Line** olsun.
///
/// ## Neden oturum bazlı (diske YAZILMIYOR)
/// Kullanıcı "session bazlı tutulmalı" dedi. Kalıcı bir tercih olsaydı
/// `SharedPreferences`'a yazmak gerekirdi; oturum içi bir görünüm tercihi
/// için o fazladan I/O ve migration yükü anlamına gelirdi. Uygulama
/// yeniden açıldığında Line'a dönmesi BEKLENEN davranış.
///
/// ## Candle (2026-09-14'e kadar YOKTU)
/// Mum grafiği açılış/en yüksek/en düşük/kapanış ister; portföy serisi her
/// zaman dilimi için TEK değer tutuyor. Menüye koyup Line çizmek yanıltıcı
/// olurdu, "şimdilik atla" denmişti. Artık OHLC eldeki noktalardan KOVA
/// bazında türetiliyor (`utils/mum_turetici.dart`: gün içi 5 dk'lık
/// noktalardan 30 dk'lık mum, günlük kapanışlardan haftalık mum). Fitiller
/// örneklenmiş noktaların uçlarıdır — etiket bu yüzden "Mum", "OHLC" değil.
enum GrafikTipi {
  /// Düz çizgi — varsayılan.
  line('Çizgi', Icons.show_chart_rounded),

  /// Kova bazlı mum: gövde açılış→kapanış, fitil en düşük→en yüksek.
  candle('Mum', Icons.candlestick_chart_rounded);

  const GrafikTipi(this.etiket, this.ikon);

  /// Menüde görünen ad.
  final String etiket;

  /// Menüdeki simge.
  final IconData ikon;

  /// Uygulamanın açılış varsayılanı.
  static const varsayilan = GrafikTipi.line;

  // ## Yalnız Çizgi ve Mum (sadeleştirme madde 5, 2026-10-04)
  // Çizgi "değer nasıl gitti"yi, Mum "dönem içinde ne kadar oynadı"yı
  // söyler — iki ayrı soru. Alan, Çizgi'nin altı boyanmış hâliydi; Taban,
  // Özet'teki dönem başı kıyasının grafikteki tekrarı; Çubuk ise portföy
  // değerinde (sürekli bir seri) yanlış bir "adet" çağrışımı yapıyordu. Beş
  // seçenek yeni kullanıcıya "hangisi doğru?" sorusu sorduruyordu. Bayrak
  // `performans_ayar_sade` açıkken seçici yalnız bu ikisini listeliyordu;
  // bayrak 2026-10-05'te kalkınca Alan/Taban/Çubuk enum'dan ve çizimden
  // silindi (seçim oturumluk, diske yazılmadığı için göç gerekmedi).

  /// Seçimden ÇİZİLECEK tipe — saf eşleme, seçimi DEĞİŞTİRMEZ.
  ///
  /// [araclar] false (sade Başlangıç): seçici yok, grafik düz çizgi —
  /// Orta'da Mum seçip Başlangıç'a geçen kullanıcı kapatamayacağı bir
  /// Mum'da kalmasın. Seçim ([grafikTipiNotifier]) olduğu gibi kalır;
  /// seviye geri gelince Mum da geri gelir.
  static GrafikTipi etkin(GrafikTipi secim, {bool araclar = true}) =>
      araclar ? secim : GrafikTipi.line;
}

/// Seçili grafik tipi — OTURUM boyunca yaşar.
///
/// `ValueNotifier` seçildi: değer widget ağacının dışında yaşıyor ve
/// birden çok ekran (performans, tam ekran) aynı seçimi görmeli.
/// Provider yerine bunu kullanmanın sebebi, tercihin kalıcı olmaması ve
/// hiçbir asenkron kaynağa bağlı olmaması.
final grafikTipiNotifier = ValueNotifier<GrafikTipi>(GrafikTipi.varsayilan);
