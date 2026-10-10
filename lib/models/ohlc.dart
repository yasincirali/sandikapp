/// Gerçek mum verisi (açılış / en yüksek / en düşük / kapanış) — sağlayıcıdan
/// ÇEKİLEN, kapanışlardan türetilmeyen.
///
/// ## Neden ayrı bir model (yasin, 2026-10-10)
/// *"Mum grafik de TradingView'deki gibi çalışmalı: 1 dk, 1 saat, 4 saat,
/// günlük, haftalık, aylık grafik verisi çekilebilmeli."*
///
/// O güne kadar uygulamada hiç OHLC yoktu; mumlar çizginin kapanış
/// noktalarından kova bazında türetiliyordu (`utils/mum_turetici.dart`,
/// `Mum`). `Mum` bir ÇİZİM nesnesidir (X'i grafiğin uzayında, kova genişliği
/// ekran biriminde). [OhlcBar] ise VERİDİR: epoch ms ve TL, ekrandan
/// bağımsız. Özel gösterge katmanı (ayrı iş, aynı grafik) da bu modeli okur;
/// hacim bu yüzden şimdiden taşınıyor, çizimde kullanılmasa da.
library;

/// Tek bir mum, sağlayıcının verdiği hâliyle (TL'ye çevrilmiş).
class OhlcBar {
  const OhlcBar({
    required this.t,
    required this.acilis,
    required this.enYuksek,
    required this.enDusuk,
    required this.kapanis,
    this.hacim,
  });

  /// Barın AÇILIŞ anı (epoch ms).
  final int t;
  final double acilis;
  final double enYuksek;
  final double enDusuk;
  final double kapanis;

  /// İşlem hacmi (adet/lot). Endeks ve döviz paritelerinde yoktur.
  final double? hacim;

  bool get gecerli =>
      acilis.isFinite &&
      enYuksek.isFinite &&
      enDusuk.isFinite &&
      kapanis.isFinite &&
      acilis > 0 &&
      kapanis > 0 &&
      enDusuk > 0 &&
      enYuksek >= enDusuk;

  /// Dört fiyatı aynı çarpanla taşır (kur çevrimi, ölçek hizası). Oransal
  /// dönüşüm mumun şeklini değiştirmez; hacim adettir, çarpılmaz.
  OhlcBar carp(double k) => OhlcBar(
        t: t,
        acilis: acilis * k,
        enYuksek: enYuksek * k,
        enDusuk: enDusuk * k,
        kapanis: kapanis * k,
        hacim: hacim,
      );

  @override
  bool operator ==(Object other) =>
      other is OhlcBar &&
      other.t == t &&
      other.acilis == acilis &&
      other.enYuksek == enYuksek &&
      other.enDusuk == enDusuk &&
      other.kapanis == kapanis &&
      other.hacim == hacim;

  @override
  int get hashCode =>
      Object.hash(t, acilis, enYuksek, enDusuk, kapanis, hacim);

  @override
  String toString() =>
      'OhlcBar($t o=$acilis h=$enYuksek l=$enDusuk c=$kapanis v=$hacim)';
}

/// Mum aralığı — TradingView'in zaman dilimleri, yasin'in saydığı altısı.
///
/// Sağlayıcı adları burada (tek yer): Yahoo `interval` ve `kripto-seri`
/// aralığı. Ölçüm (2026-10-10, `tool/ohlc_olcum.py`, GitHub Actions):
/// Yahoo altısını da GERÇEK OHLC ile veriyor (`4h` belgelenmemiş ama
/// çalışıyor; 1 dk yalnız son ~7 gün, 1 sa/4 sa ~730 gün); Binance altısını
/// da doğrudan veriyor (`1m 1h 4h 1d 1w 1M`).
enum MumAraligi {
  dk1(1, '1m', '1m'),
  saat1(60, '60m', '1h'),
  saat4(240, '4h', '4h'),
  gun1(1440, '1d', '1d'),
  hafta1(7 * 1440, '1wk', '1wk'),
  // Ay 30 gün sayılır: yalnız SEÇİM ve beklenen mum sayısı için. Çizimde
  // her ayın gerçek uzunluğu kullanılır (`ayUzunluguMs`).
  ay1(30 * 1440, '1mo', '1mo');

  const MumAraligi(this.dakika, this.yahooInterval, this.kriptoAraligi);

  /// Bir barın (yaklaşık) süresi, dakika.
  final int dakika;

  /// Yahoo `v8/finance/chart` `interval` değeri.
  final String yahooInterval;

  /// `kripto-seri` fonksiyonunun `aralik` değeri (Yahoo adlarıyla aynı
  /// aile; sunucu Binance karşılığına çevirir).
  final String kriptoAraligi;

  int get ms => dakika * 60 * 1000;

  /// Gün içi (gün altı) aralık mı? Seansı olan piyasada gece boşluğu
  /// bırakır; günlük ve üstü bırakmaz.
  bool get gunIci => dakika < 1440;

  /// Tercih anahtarında saklanan sıra numarası; bilinmeyen → null.
  static MumAraligi? sirayla(int i) =>
      (i >= 0 && i < values.length) ? values[i] : null;
}

/// [t] anında başlayan [aralik] barının gerçek uzunluğu (ms). Aylık barda
/// takvim ayı (28–31 gün); diğerlerinde sabit.
int barUzunluguMs(int t, MumAraligi aralik) {
  if (aralik != MumAraligi.ay1) return aralik.ms;
  final d = DateTime.fromMillisecondsSinceEpoch(t);
  final bas = DateTime(d.year, d.month, 1);
  final son = DateTime(d.year, d.month + 1, 1);
  return son.difference(bas).inMilliseconds;
}
