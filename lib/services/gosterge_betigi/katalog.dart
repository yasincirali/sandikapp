/// Gösterge dilinin yardım kataloğu ve hazır şablonları.
///
/// Düzenleyici ekranın "Fonksiyonlar" listesi ve "Şablondan başla" seçenekleri
/// buradan çizilir. Açıklamalar VERİdir (iki dilli); ekran metni değil.
/// Şablonların hepsi `katalog_test`'te derlenip çalıştırılır — dil değişip
/// şablon kırılırsa test yakalar.
library;

class BetikFonksiyonu {
  const BetikFonksiyonu(this.imza, this.tr, this.en);
  final String imza;
  final String tr;
  final String en;
}

class BetikSablonu {
  const BetikSablonu({
    required this.kimlik,
    required this.adTr,
    required this.adEn,
    required this.kod,
  });
  final String kimlik;
  final String adTr;
  final String adEn;
  final String kod;
}

/// Yardım listesindeki sıra: önce veri, sonra ortalamalar, osilatörler,
/// sinyaller, matematik, çizim.
const List<BetikFonksiyonu> kBetikFonksiyonlari = [
  BetikFonksiyonu('close · open · high · low · volume',
      'Çubuğun kapanış, açılış, en yüksek, en düşük ve hacmi. Türkçesi: kapanis, acilis, yuksek, dusuk, hacim.',
      'Bar close, open, high, low and volume.'),
  BetikFonksiyonu('x[1]', 'Bir önceki çubuktaki değer (x[2] iki önceki…).',
      'Value on the previous bar (x[2] two bars back…).'),
  BetikFonksiyonu('sma(x, n)', 'Basit hareketli ortalama.', 'Simple moving average.'),
  BetikFonksiyonu('ema(x, n)', 'Üssel hareketli ortalama.', 'Exponential moving average.'),
  BetikFonksiyonu('wma(x, n) · rma(x, n)', 'Ağırlıklı ve Wilder ortalaması.',
      'Weighted and Wilder moving average.'),
  BetikFonksiyonu('rsi(x, n)', 'Göreceli güç endeksi (0–100).', 'Relative strength index (0–100).'),
  BetikFonksiyonu('stdev(x, n)', 'Standart sapma (Bollinger için).', 'Standard deviation.'),
  BetikFonksiyonu('highest(x, n) · lowest(x, n)', 'Son n çubuğun en yükseği / en düşüğü.',
      'Highest / lowest of the last n bars.'),
  BetikFonksiyonu('change(x, n) · mom(x, n) · roc(x, n)',
      'n çubukta değişim, momentum ve yüzde değişim.',
      'Change, momentum and percent change over n bars.'),
  BetikFonksiyonu('atr(n) · tr', 'Ortalama gerçek aralık (yüksek/düşük ister).',
      'Average true range (needs high/low).'),
  BetikFonksiyonu('crossover(a, b) · crossunder(a, b)',
      'a, b\'yi yukarı / aşağı kestiği çubukta doğru.',
      'True on the bar where a crosses above / below b.'),
  BetikFonksiyonu('a ? b : c', 'Koşul doğruysa b, değilse c.', 'b if the condition holds, else c.'),
  BetikFonksiyonu('and · or · not', 'Koşulları birleştir.', 'Combine conditions.'),
  BetikFonksiyonu('abs · sqrt · log · pow · max · min · avg · nz',
      'Matematik. nz(x) boş değeri 0 yapar.', 'Math. nz(x) turns empty values into 0.'),
  BetikFonksiyonu('plot(x, "Ad", color.green)',
      'Çizgiyi çiz. Renkler: green, red, blue, orange, yellow, gray, purple.',
      'Draw a line. Colors: green, red, blue, orange, yellow, gray, purple.'),
  BetikFonksiyonu('hline(70, "Üst")', 'Ayrı panelde sabit seviye çizgisi.',
      'Constant level line in a separate pane.'),
  BetikFonksiyonu('plotshape(koşul, "Al")', 'Koşulun doğru olduğu çubuklara işaret koy.',
      'Mark the bars where the condition holds.'),
  BetikFonksiyonu('indicator("Ad", overlay=false)',
      'overlay=false: grafiğin altında ayrı panelde çiz (RSI gibi).',
      'overlay=false: draw in a separate pane below the chart (like RSI).'),
];

const List<BetikSablonu> kBetikSablonlari = [
  BetikSablonu(
    kimlik: 'ema_kesisim',
    adTr: 'EMA kesişimi',
    adEn: 'EMA crossover',
    kod: '''// Hızlı EMA yavaşı yukarı kesince işaret koyar.
hizli = ema(close, 9)
yavas = ema(close, 21)
plot(hizli, "EMA 9", color.blue)
plot(yavas, "EMA 21", color.orange)
plotshape(crossover(hizli, yavas), "Yukarı kesti", color.green)
plotshape(crossunder(hizli, yavas), "Aşağı kesti", color.red)
''',
  ),
  BetikSablonu(
    kimlik: 'rsi',
    adTr: 'RSI (14)',
    adEn: 'RSI (14)',
    kod: '''indicator("RSI", overlay=false)
plot(rsi(close, 14), "RSI", color.purple)
hline(70, "Aşırı alım", color.red)
hline(30, "Aşırı satım", color.green)
''',
  ),
  BetikSablonu(
    kimlik: 'bollinger',
    adTr: 'Bollinger bantları',
    adEn: 'Bollinger bands',
    kod: '''orta = sma(close, 20)
sapma = 2 * stdev(close, 20)
plot(orta, "Orta", color.gray)
plot(orta + sapma, "Üst bant", color.blue)
plot(orta - sapma, "Alt bant", color.blue)
''',
  ),
  BetikSablonu(
    kimlik: 'macd',
    adTr: 'MACD',
    adEn: 'MACD',
    kod: '''indicator("MACD", overlay=false)
macd = ema(close, 12) - ema(close, 26)
sinyal = ema(macd, 9)
plot(macd, "MACD", color.blue)
plot(sinyal, "Sinyal", color.orange)
hline(0, "Sıfır", color.gray)
''',
  ),
  BetikSablonu(
    kimlik: 'momentum',
    adTr: 'Momentum (%)',
    adEn: 'Momentum (%)',
    kod: '''indicator("Momentum", overlay=false)
plot(roc(close, 10), "10 çubukta %", color.yellow)
hline(0, "Sıfır", color.gray)
''',
  ),
];
