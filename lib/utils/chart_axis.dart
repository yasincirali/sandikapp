import 'dart:math' as math;

import 'package:intl/intl.dart';

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

/// Nice-number adımı — **YUKARI** yuvarlar (1/2/2,5/5/10 × 10ⁿ).
///
/// Performans ekranının X ekseni bu kuralla çalışıyordu ve kendi özel
/// kopyasını (`_niceRoundNumber`) taşıyordu. Takip/Karşılaştır grafiği ise
/// ham `span/4` kullanıyordu: eksen "14:30 · 20:30 · 02:30 · 08:30" gibi
/// yuvarlak olmayan anlara denk geliyordu. Aynı soruyu iki ekranda iki farklı
/// eksen mantığıyla cevaplamamak için kural buraya alındı.
///
/// [yuzdeEkseni]'ndeki EN YAKIN'a yuvarlama ile bilinçli olarak farklı:
/// yüzde ekseninde hedef bölme sayısını korumak (etiket sayısını sabit
/// tutmak) önemliydi; zaman ekseninde ise adımın küçülmesi etiketlerin
/// üst üste binmesi demek, o yüzden yukarı yuvarlanır.
double yuvarlakAdim(double ham) {
  if (ham <= 0) return 1;
  final us = math.pow(10, (math.log(ham) / math.ln10).floor()).toDouble();
  final oran = ham / us;
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
  return carpan * us;
}

/// Gün içi ("GÜNLÜK") X ekseninin adımı — dakika.
///
/// 4 saat: 00:00 · 04:00 · 08:00 · 12:00 · 16:00 · 20:00. Telefon genişliğinde
/// bundan sık etiketler yan yana sıkışıyor.
const double gunIciEksenAdimiDk = 240.0;

/// Gün içi ("GÜNLÜK") X ekseninin SAĞ ucu — gün başlangıcından dakika.
///
/// **Neden 1440'tan (tam günden) küçük olamaz:** GÜNLÜK bir TAKVİM GÜNÜDÜR.
/// Ekseni son veri noktasında bitirmek sabah 09:00'da grafiği 9 saatlik bir
/// pencereye sıkıştırır ve gün ilerledikçe eksen büyür — kullanıcı aynı
/// sekmeye her baktığında farklı bir zaman ölçeği görür. Gün sabit
/// kaldığında hareket gün içindeki YERİYLE birlikte okunur.
///
/// **Neden bazen 1440'tan büyük:** son nokta ekranın en sağ kenarına
/// yapışırsa hem işaretçisi kırpılır hem de "daha devam ediyor" hissi
/// kaybolur. Nokta viewport'un ~%82'sinde tutulur; bu ancak 19:41'den sonra
/// (1440 × 0,82) günü aşan bir eksen üretir.
///
/// [sonNoktaDk] serinin son noktasının gün başından dakika cinsinden uzaklığı.
double gunIciEksenSonuDk(double sonNoktaDk) {
  final gereken = sonNoktaDk > 0 ? sonNoktaDk / 0.82 : 240.0;
  return gereken > 1440.0 ? gereken : 1440.0;
}

/// Zaman (X) ekseninin ORTAK kuralı — performans ekranı ile
/// Takip/Karşılaştır grafiği aynı cebri paylaşsın diye.
///
/// Girdi ve çıktı **epoch milisaniye**; performans ekranı kendi X uzayını
/// (gün içi → dakika, diğerleri → kesirli gün) kullandığı için oradan
/// yalnızca [gunIciEksenSonuDk] ve [yuvarlakAdim] çağrılır — kural aynı,
/// birim farklı.
///
/// [baseline] fl_chart'ın `baselineX`'ine verilir: tick'ler `baseline`'ın
/// katlarına oturur. Verilmezse fl_chart 0'ı (1970-01-01 UTC) taban alır ve
/// UTC+3'te etiketler 03:00 · 07:00 · 11:00 gibi kayar.
({double min, double max, double interval, double baseline, bool gunIci})
    zamanEkseni({
  required double ilkMs,
  required double sonMs,
  required int periodDays,
}) {
  const dkMs = 60 * 1000.0;
  const gunMs = 24 * 60 * dkMs;

  if (periodDays <= 1) {
    // Çapa `now` değil SON NOKTANIN GÜNÜ — `clipToPeriod` ile aynı kural.
    // Borsa hafta sonu kapalıdır; `now`'dan saymak Pazar günü bugünün boş
    // eksenini çizip Cuma seansını dışarıda bırakırdı.
    final son = DateTime.fromMillisecondsSinceEpoch(sonMs.round());
    final geceYarisi = DateTime(son.year, son.month, son.day);
    final bas = geceYarisi.millisecondsSinceEpoch.toDouble();
    final sonDk = (sonMs - bas) / dkMs;
    return (
      min: bas,
      max: bas + gunIciEksenSonuDk(sonDk) * dkMs,
      interval: gunIciEksenAdimiDk * dkMs,
      baseline: bas,
      gunIci: true,
    );
  }

  final span = sonMs - ilkMs;
  // Beş bölme — performans ekranındaki `span / 5` ile aynı hedef.
  final spanGun = span <= 0 ? 1.0 : span / gunMs;
  final adimGun = math.max(yuvarlakAdim(spanGun / 5), 1.0);
  // Tick'ler gün sınırına (yerel gece yarısı) otursun; aksi halde "3 Eyl"
  // etiketi günün ortasındaki bir ana denk gelir.
  final ilk = DateTime.fromMillisecondsSinceEpoch(ilkMs.round());
  return (
    min: ilkMs,
    max: sonMs,
    interval: adimGun * gunMs,
    baseline: DateTime(ilk.year, ilk.month, ilk.day)
        .millisecondsSinceEpoch
        .toDouble(),
    gunIci: false,
  );
}

/// Zaman ekseni etiketi — iki ekranda AYNI biçim.
///
/// Kural performans ekranından geldi; takip grafiği kendi (daha kaba)
/// kopyasını taşıyordu ve yıl hiç göstermiyordu.
///
/// [spanGun] görünür pencerenin gün cinsinden genişliği (zoom'a göre değişir).
String zamanEtiketi(
  DateTime t, {
  required double spanGun,
  required bool gunIci,
}) {
  if (gunIci) return DateFormat('HH:mm', 'tr_TR').format(t);
  if (spanGun > 400) return DateFormat('MMM yy', 'tr_TR').format(t);
  if (spanGun < 3) return DateFormat('d MMM HH:mm', 'tr_TR').format(t);
  final yilFarkli = t.year != DateTime.now().year;
  return DateFormat(yilFarkli ? 'd MMM yy' : 'd MMM', 'tr_TR').format(t);
}

/// Eksenin iki ucundaki etiket ÇİZİLMEZ.
///
/// fl_chart tick'i etiketin ortasına yerleştirir; kenara çok yakın bir tick'in
/// etiketi çizim alanının dışına taşar ve kırpılır. Payın viewport
/// genişliğinin oranı olması zoom'da da çalışmasını sağlar — sabit bir eşik
/// yakınlaştırıldığında ya çok geniş ya da etkisiz kalırdı.
///
/// Oran performans ekranından alındı (%6).
bool eksenKenarinda(double deger, double min, double max) {
  final pay = (max - min).abs() * 0.06;
  return deger <= min + pay || deger >= max - pay;
}
