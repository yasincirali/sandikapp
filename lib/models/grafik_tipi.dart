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
/// ## Candle neden YOK
/// Mum grafiği açılış/en yüksek/en düşük/kapanış ister. Portföy serisi
/// her zaman dilimi için TEK değer tutuyor (`Map<int, double>` — o andaki
/// toplam portföy değeri); OHLC veri katmanında hiç üretilmiyor.
/// Menüye koyup tıklanınca Line çizmek kullanıcıyı yanıltırdı. Gün içi
/// 5 dakikalık noktalardan türetilebilir ama bu ayrı bir seri ve ayrı
/// bir iş (bkz. TECHNICAL_DEBT).
enum GrafikTipi {
  /// Düz çizgi — varsayılan.
  line('Çizgi', Icons.show_chart_rounded),

  /// Çizgi + altında gradyan dolgu.
  mountain('Dağ', Icons.landscape_rounded),

  /// Dönem başına göre üstü kazanç, altı kayıp renginde.
  baseline('Taban', Icons.multiline_chart_rounded),

  /// Her noktada dikey çubuk.
  bar('Çubuk', Icons.bar_chart_rounded);

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
