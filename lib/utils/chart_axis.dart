import 'dart:math' as math;

/// Çizgi grafiklerin ORTAK eksen ve odak cebiri.
///
/// Buradaki iki fonksiyon önce `watchlist_chart.dart` içinde yaşıyordu.
/// Karşılaştır ekranı aynı hataları bağımsız olarak yeniden üretince
/// (interval verilmeden çizilen Y ekseni, odaklanamayan seriler) ortak bir
/// yere alındı: iki ekran aynı grafiği çiziyorsa aynı cebiri paylaşmalı,
/// yoksa biri düzelirken öteki bozuk kalıyor.
///
/// Saf fonksiyonlar — widget kurmadan test edilirler.

/// Yüzde ekseni için yuvarlak sınırlar + adım.
///
/// ## Neden gerekli
/// `fl_chart`'a `interval` verilmezse aralığı kendisi seçer ve dar bantlarda
/// etiketleri birbirine değecek kadar sıkıştırabiliyor (üretimde görüldü:
/// "+15%" ile "+16%" üst üste bindi). Ayrıca ham `span/n` adımı yuvarlak
/// olmadığı için "+3%, +6%, +9%" yerine "+2,7%, +5,4%" gibi okunması zor
/// değerler çıkabiliyor.
///
/// Çözüm `portfolio_performance_screen`'deki desenin aynısı: adımı
/// 1/2/2,5/5/10 tabanına yuvarla, sınırları o adımın katına oturt. Böylece
/// hem etiketler seyrek kalır hem de yuvarlak sayılara denk gelir.
///
/// [hedefBolme] kaç aralık istendiği (etiket sayısı = bölme + 1). 210pt'lik
/// bir grafikte 4 bölme = 5 etiket; daha fazlası sıkışık görünüyor.
///
/// **Veri her zaman eksenin içinde kalır**: sınırlar dışa doğru yuvarlanır
/// (`floor`/`ceil`), asla veriyi kesecek şekilde içeri değil.
({double min, double max, double interval, int ondalik}) yuzdeEkseni(
  double alt,
  double ust, {
  int hedefBolme = 4,
}) {
  // Dejenere aralık: tek noktalı ya da düz seri.
  if (!(ust > alt)) {
    final merkez = alt;
    return (min: merkez - 1, max: merkez + 1, interval: 1, ondalik: 0);
  }

  final hamAdim = (ust - alt) / hedefBolme;

  // 1/2/2,5/5/10 × 10ⁿ tabanına yuvarla (Heckbert "nice numbers").
  final us = math.pow(10, (math.log(hamAdim) / math.ln10).floor()).toDouble();
  final oran = hamAdim / us;
  final double carpan;
  if (oran <= 1) {
    carpan = 1;
  } else if (oran <= 2) {
    carpan = 2;
  } else if (oran <= 2.5) {
    carpan = 2.5;
  } else if (oran <= 5) {
    carpan = 5;
  } else {
    carpan = 10;
  }
  final adim = carpan * us;

  // Sınırlar adımın katına — DIŞA doğru, veri kırpılmasın.
  final yeniAlt = (alt / adim).floor() * adim;
  final yeniUst = (ust / adim).ceil() * adim;

  // Adım 1'den küçükse tam sayı etiketi tekrar eder ("+0%, +0%, +1%").
  // O durumda ondalık göster.
  final ondalik = adim >= 1 ? 0 : (adim >= 0.1 ? 1 : 2);

  return (min: yeniAlt, max: yeniUst, interval: adim, ondalik: ondalik);
}

/// Bir seriye dokunulduğunda yeni odak ne olmalı?
///
/// Aynı seriye tekrar dokunmak odağı KALDIRIR (donut grafikteki
/// `_touchedIndex` deseninin aynısı) — kullanıcı odaktan çıkmak için başka
/// bir yer aramak zorunda kalmasın.
///
/// Saf fonksiyon: dokunma davranışı widget kurmadan test edilir.
String? yeniOdak({required String? mevcut, required String dokunulan}) =>
    mevcut == dokunulan ? null : dokunulan;
