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
  //
  // **En YAKIN adaya yuvarlanır, yukarı DEĞİL.** Eskiden her aday `<=` ile
  // taranıyordu, yani adım daima yukarı yuvarlanıyordu; ham adım 6,2 iken
  // 10'a çıkıyordu (%61 büyüme). Adım büyüdükçe bölme sayısı düşüyor, üstelik
  // sınırlar da dışa yuvarlandığı için bir bölme daha eriyordu. Sonuç: eksende
  // yalnızca İKİ etiket kalıyordu (ölçüldü: %-5..%15 bandı → "+0%, +10%";
  // %0..%3 → "+0%, +2%"). Kenar etiketleri zaten çizilmediği için
  // `hedefBolme=4` gerçekte 2 etiket demekti.
  //
  // En yakına yuvarlamak Heckbert'in özgün "nice numbers" davranışıdır ve
  // hedeflenen bölme sayısını korur.
  final us = math.pow(10, (math.log(hamAdim) / math.ln10).floor()).toDouble();
  final oran = hamAdim / us;
  const adaylar = [1.0, 2.0, 2.5, 5.0, 10.0];
  var carpan = adaylar.first;
  var enIyiFark = double.infinity;
  for (final a in adaylar) {
    // Oransal fark: 1→2 ile 5→10 aynı ağırlıkta değerlendirilsin.
    final fark = (math.log(a) - math.log(oran)).abs();
    if (fark < enIyiFark) {
      enIyiFark = fark;
      carpan = a;
    }
  }
  // Etiketler en çok 3 basamakla yazılır (daha fazlası dar eksende okunmaz),
  // bu yüzden adım da 0,001'in altına inemez — inerse ardışık etiketler aynı
  // metne yuvarlanır ve eksen "−0,001 / −0,001 / 0,000" gibi çakışır
  // (ölçüldü: ±%0,001 bandı). Bu kadar dar bir bant zaten düz çizgidir;
  // ızgarayı seyrekleştirmek bilgi kaybetmez.
  final adim = math.max(carpan * us, 0.001);

  // Sınırlar adımın katına — DIŞA doğru, veri kırpılmasın.
  final yeniAlt = (alt / adim).floor() * adim;
  final yeniUst = (ust / adim).ceil() * adim;

  // Adım 1'den küçükse tam sayı etiketi tekrar eder ("+0%, +0%, +1%").
  // O durumda ondalık göster.
  //
  // Basamak sayısı adımı TAM göstermeye yetmeli: 0,025'lik bir adım iki
  // basamakla "0,03" diye yuvarlanır ve ardışık etiketler arasındaki fark
  // eşit görünmez. Adımın kendisi kayıpsız yazılana kadar basamak eklenir
  // (en çok 3 — daha fazlası dar eksende okunmaz).
  var ondalik = adim >= 1 ? 0 : (adim >= 0.1 ? 1 : 2);
  while (ondalik < 3 &&
      (double.parse(adim.toStringAsFixed(ondalik)) - adim).abs() > 1e-9) {
    ondalik++;
  }

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
