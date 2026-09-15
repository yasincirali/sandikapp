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

  /// Çizgi + altında gradyan dolgu.
  mountain('Dağ', Icons.landscape_rounded),

  /// Dönem başına göre üstü kazanç, altı kayıp renginde.
  baseline('Taban', Icons.multiline_chart_rounded),

  /// Her noktada dikey çubuk.
  bar('Çubuk', Icons.bar_chart_rounded),

  /// Kova bazlı mum: gövde açılış→kapanış, fitil en düşük→en yüksek.
  candle('Mum', Icons.candlestick_chart_rounded);

  const GrafikTipi(this.etiket, this.ikon);

  /// Menüde görünen ad.
  final String etiket;

  /// Menüdeki simge.
  final IconData ikon;

  /// Uygulamanın açılış varsayılanı.
  static const varsayilan = GrafikTipi.line;
}

/// Seçili grafik tipi — OTURUM boyunca yaşar.
///
/// `ValueNotifier` seçildi: değer widget ağacının dışında yaşıyor ve
/// birden çok ekran (performans, tam ekran) aynı seçimi görmeli.
/// Provider yerine bunu kullanmanın sebebi, tercihin kalıcı olmaması ve
/// hiçbir asenkron kaynağa bağlı olmaması.
final grafikTipiNotifier = ValueNotifier<GrafikTipi>(GrafikTipi.varsayilan);
