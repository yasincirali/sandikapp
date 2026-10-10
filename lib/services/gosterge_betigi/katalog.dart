/// Gösterge dilinin yardım kataloğu ve hazır şablonları.
///
/// Düzenleyici ekranın "Fonksiyonlar" listesi ve "Şablondan başla" seçenekleri
/// buradan çizilir. Açıklamalar VERİdir (iki dilli); ekran metni değil.
/// Şablonların hepsi `gosterge_betigi_test`'te derlenip çalıştırılır — dil değişip
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

/// Yardım listesi: Pine Script v5 ile birebir; TradingView'deki kod buraya
/// olduğu gibi yapıştırılır. Sıra: veri, akış, ortalamalar, osilatörler,
/// sinyaller, matematik, çizim, sınırlar.
const List<BetikFonksiyonu> kBetikFonksiyonlari = [
  BetikFonksiyonu('//@version=5 · indicator("Ad", overlay=true)',
      'TradingView\'deki Pine kodu olduğu gibi çalışır (v4, v5, v6). overlay=false: grafiğin altında ayrı panel.',
      'Pine code from TradingView runs as is (v4, v5, v6). overlay=false: separate pane below the chart.'),
  BetikFonksiyonu('close · open · high · low · volume · hl2 · time · bar_index',
      'Çubuğun verileri. x[1] bir önceki çubuktaki değer.',
      'Bar data. x[1] is the value on the previous bar.'),
  BetikFonksiyonu('input.int(14, "Uzunluk") · input.source(close)',
      'Ayar girdileri varsayılan değeriyle çalışır.',
      'Inputs run with their default value.'),
  BetikFonksiyonu('var · := · += · if / else · for i = 0 to 9 · while · switch',
      'Değişken, atama ve akış. var: değer çubuktan çubuğa taşınır. Blok 4 boşluk içeride.',
      'Variables, assignment and flow. var keeps its value across bars. Blocks are indented by 4 spaces.'),
  BetikFonksiyonu('f(x, n) => …', 'Kendi fonksiyonun; [a, b] ile birden çok değer döner.',
      'Your own function; return several values with [a, b].'),
  BetikFonksiyonu('ta.sma · ta.ema · ta.rma · ta.wma · ta.vwma · ta.hma · ta.alma',
      'Hareketli ortalamalar.', 'Moving averages.'),
  BetikFonksiyonu('ta.rsi · ta.macd · ta.stoch · ta.cci · ta.mfi · ta.cmo · ta.tsi · ta.wpr',
      'Osilatörler. ta.macd üç değer döner: [macd, sinyal, histogram].',
      'Oscillators. ta.macd returns [macd, signal, histogram].'),
  BetikFonksiyonu('ta.bb · ta.kc · ta.atr · ta.stdev · ta.supertrend · ta.sar · ta.dmi',
      'Bantlar, oynaklık ve trend. ATR, Supertrend, SAR ve DMI yüksek/düşük ister.',
      'Bands, volatility and trend. ATR, Supertrend, SAR and DMI need high/low.'),
  BetikFonksiyonu('ta.crossover · ta.crossunder · ta.pivothigh · ta.valuewhen · ta.barssince',
      'Sinyaller: kesişim, dönüş noktası, son gerçekleşme.',
      'Signals: crosses, pivots, last occurrence.'),
  BetikFonksiyonu('math.* · nz · na · str.tostring · color.new(color.red, 50) · #ff9800',
      'Matematik, boş değer ve renk. Renkler uygulamanın en yakın rengine düşer.',
      'Math, empty values and colors. Colors snap to the app palette.'),
  BetikFonksiyonu('plot · hline · plotshape · plotchar · plotarrow · fill',
      'Çizim. plot.style_columns histogram çizer.',
      'Drawing. plot.style_columns draws a histogram.'),
  BetikFonksiyonu('Çalışmayanlar',
      'Başka sembol/aralıktan veri (request.security), diziler (array), import. label/line/box/table ve bgcolor çalışır ama çizilmez; strateji emirleri yürütülmez.',
      'Not supported: data from other symbols/intervals (request.security), arrays, import. label/line/box/table and bgcolor run but are not drawn; strategy orders are not executed.'),
];

const List<BetikSablonu> kBetikSablonlari = [
  BetikSablonu(
    kimlik: 'ema_kesisim',
    adTr: 'EMA kesişimi',
    adEn: 'EMA crossover',
    kod: '''//@version=5
indicator("EMA kesişimi", overlay=true)
hizli = ta.ema(close, input.int(9, "Hızlı"))
yavas = ta.ema(close, input.int(21, "Yavaş"))
plot(hizli, "EMA 9", color.blue)
plot(yavas, "EMA 21", color.orange)
plotshape(ta.crossover(hizli, yavas), "Yukarı kesti", shape.triangleup, location.belowbar, color.green)
plotshape(ta.crossunder(hizli, yavas), "Aşağı kesti", shape.triangledown, location.abovebar, color.red)
''',
  ),
  BetikSablonu(
    kimlik: 'rsi',
    adTr: 'RSI (14)',
    adEn: 'RSI (14)',
    kod: '''//@version=5
indicator("RSI", overlay=false)
plot(ta.rsi(close, 14), "RSI", color.purple)
hline(70, "Aşırı alım", color.red)
hline(30, "Aşırı satım", color.green)
''',
  ),
  BetikSablonu(
    kimlik: 'bollinger',
    adTr: 'Bollinger bantları',
    adEn: 'Bollinger bands',
    kod: '''//@version=5
indicator("Bollinger", overlay=true)
[orta, ust, alt] = ta.bb(close, 20, 2)
plot(orta, "Orta", color.gray)
p1 = plot(ust, "Üst bant", color.blue)
p2 = plot(alt, "Alt bant", color.blue)
fill(p1, p2, color.new(color.blue, 90))
''',
  ),
  BetikSablonu(
    kimlik: 'macd',
    adTr: 'MACD',
    adEn: 'MACD',
    kod: '''//@version=5
indicator("MACD", overlay=false)
[macd, sinyal, hist] = ta.macd(close, 12, 26, 9)
plot(hist, "Histogram", hist >= 0 ? color.green : color.red, style=plot.style_columns)
plot(macd, "MACD", color.blue)
plot(sinyal, "Sinyal", color.orange)
hline(0, "Sıfır", color.gray)
''',
  ),
  BetikSablonu(
    kimlik: 'seri',
    adTr: 'Yükseliş serisi',
    adEn: 'Up streak',
    kod: '''//@version=5
indicator("Yükseliş serisi", overlay=false)
// Üst üste kaç çubuktur yükseliyor? var: değer çubuktan çubuğa taşınır.
var int seri = 0
if close > close[1]
    seri += 1
else
    seri := 0
plot(seri, "Seri", color.green, style=plot.style_columns)
''',
  ),
];
