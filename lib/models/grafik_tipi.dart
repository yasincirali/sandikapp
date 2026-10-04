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
  ///
  /// Etiket 2026-10-04'e kadar "Dağ"dı (İngilizce "mountain"ın çevirisi).
  /// Türkçe grafik araçlarındaki yerleşik ad "Alan" (alan grafiği);
  /// kullanıcı "Dağ"ı bir grafik türü olarak tanımıyordu (sadeleştirme 2).
  /// "Taban" kaldı: Türkçe araçlardaki "taban çizgisi" ile aynı ad.
  mountain('Alan', Icons.landscape_rounded),

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

  /// Sade küme (bayrak `performans_ayar_sade`, sadeleştirme madde 5):
  /// yalnız Çizgi ve Mum.
  ///
  /// Neden bu ikisi: Çizgi "değer nasıl gitti"yi, Mum "dönem içinde ne
  /// kadar oynadı"yı söyler — iki ayrı soru. Alan, Çizgi'nin altı boyanmış
  /// hâli; Taban, Özet'teki dönem başı kıyasının grafikteki tekrarı; Çubuk
  /// ise portföy değerinde (sürekli bir seri) yanlış bir "adet" çağrışımı
  /// yapıyor. Beş seçenek yeni kullanıcıya "hangisi doğru?" sorusu
  /// sorduruyordu; cevap verilebilir iki seçenek kaldı.
  static const sadeKume = [GrafikTipi.line, GrafikTipi.candle];

  /// Seçicide listelenen tipler.
  static List<GrafikTipi> secilebilir({required bool sade}) =>
      sade ? sadeKume : GrafikTipi.values;

  /// Seçimden ÇİZİLECEK tipe — saf eşleme, seçimi DEĞİŞTİRMEZ.
  ///
  /// Seçim ([grafikTipiNotifier]) olduğu gibi kalır; yalnız okunurken
  /// eşlenir. Böylece bayrak kapanınca kullanıcının eski seçimi (ör. Alan)
  /// geri gelir — eşleme yazılsaydı bayrak geri alındığında tercih
  /// sessizce kaybolurdu.
  ///   * [araclar] false (sade Başlangıç, `seviye_anketi`): seçici yok,
  ///     grafik düz çizgi — Orta'da Mum seçip Başlangıç'a geçen kullanıcı
  ///     kapatamayacağı bir Mum'da kalmasın.
  ///   * [sade] true: kümede olmayan tip Çizgi'ye düşer.
  static GrafikTipi etkin(GrafikTipi secim,
      {required bool sade, bool araclar = true}) {
    if (!araclar) return GrafikTipi.line;
    if (sade && !sadeKume.contains(secim)) return GrafikTipi.line;
    return secim;
  }
}

/// Seçili grafik tipi — OTURUM boyunca yaşar.
///
/// `ValueNotifier` seçildi: değer widget ağacının dışında yaşıyor ve
/// birden çok ekran (performans, tam ekran) aynı seçimi görmeli.
/// Provider yerine bunu kullanmanın sebebi, tercihin kalıcı olmaması ve
/// hiçbir asenkron kaynağa bağlı olmaması.
final grafikTipiNotifier = ValueNotifier<GrafikTipi>(GrafikTipi.varsayilan);
