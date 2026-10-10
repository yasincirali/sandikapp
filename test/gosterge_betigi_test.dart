import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/gosterge_betigi/betik.dart';
import 'package:portfoy_takip/services/gosterge_betigi/katalog.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';

/// Kendi göstergeni yaz — Pine Script yorumlayıcısı.
///
/// yasin (2026-10-10): "benzeri değil de birebir olsun". Bu yüzden testlerin
/// çoğu TradingView'in KENDİ yerleşik göstergelerinin kaynak kodudur
/// (Pine Editor'de "Kaynağı görüntüle") — kopyalanıp yapıştırıldığı gibi
/// çalışmalı ve uygulamanın kendi hesaplarıyla aynı sayıyı vermeli.

/// Kapanış-yalnız sentetik seri (bugünkü grafik verisi).
BetikVerisi _veri(int n) {
  final kap = [
    for (var i = 0; i < n; i++) 100 + 10 * math.sin(i / 7) + i * 0.1,
  ];
  return BetikVerisi.yalnizKapanis(
      [for (var i = 0; i < n; i++) _gun(i)], kap);
}

/// Günlük çubuk zamanı (ms).
double _gun(int i) =>
    DateTime.utc(2025, 1, 1).add(Duration(days: i)).millisecondsSinceEpoch
        .toDouble();

/// OHLCV dolu sentetik seri.
BetikVerisi _ohlc(int n) {
  final k = [
    for (var i = 0; i < n; i++) 100 + 10 * math.sin(i / 7) + i * 0.1,
  ];
  return BetikVerisi(
    x: [for (var i = 0; i < n; i++) _gun(i)],
    acilis: [for (var i = 0; i < n; i++) i == 0 ? k[0] : k[i - 1]],
    yuksek: [for (var i = 0; i < n; i++) k[i] + 1.5 + (i % 3)],
    dusuk: [for (var i = 0; i < n; i++) k[i] - 1.2 - (i % 2)],
    kapanis: k,
    hacim: [for (var i = 0; i < n; i++) 1000.0 + (i % 7) * 100],
  );
}

BetikHatasi _hataAl(String kod, [BetikVerisi? v]) {
  try {
    GostergeBetigi.calistir(kod, v ?? _veri(50));
  } on BetikHatasi catch (e) {
    return e;
  }
  fail('Hata bekleniyordu: $kod');
}

List<double> _son(List<double> l, int k) => l.sublist(l.length - k);

// ── TradingView yerleşik göstergeleri (kaynak kodu, değiştirilmeden) ───────

const _tvRsi = r'''
//@version=5
indicator(title="Relative Strength Index", shorttitle="RSI", format=format.price, precision=2, timeframe="", timeframe_gaps=true)

ma(source, length, type) =>
    switch type
        "SMA" => ta.sma(source, length)
        "Bollinger Bands" => ta.sma(source, length)
        "EMA" => ta.ema(source, length)
        "SMMA (RMA)" => ta.rma(source, length)
        "WMA" => ta.wma(source, length)
        "VWMA" => ta.vwma(source, length)

rsiLengthInput = input.int(14, minval=1, title="RSI Length", group="RSI Settings")
rsiSourceInput = input.source(close, "Source", group="RSI Settings")
maTypeInput = input.string("SMA", title="MA Type", options=["SMA", "Bollinger Bands", "EMA", "SMMA (RMA)", "WMA", "VWMA"], group="MA Settings")
maLengthInput = input.int(14, title="MA Length", group="MA Settings")
bbMultInput = input.float(2.0, minval=0.001, maxval=50, title="BB StdDev", group="MA Settings")
showDivergence = input.bool(false, title="Show Divergence", group="RSI Settings")

up = ta.rma(math.max(ta.change(rsiSourceInput), 0), rsiLengthInput)
down = ta.rma(-math.min(ta.change(rsiSourceInput), 0), rsiLengthInput)
rsi = down == 0 ? 100 : up == 0 ? 0 : 100 - (100 / (1 + up / down))
rsiMA = ma(rsi, maLengthInput, maTypeInput)
isBB = maTypeInput == "Bollinger Bands"

rsiPlot = plot(rsi, "RSI", color=#7E57C2)
plot(rsiMA, "RSI-based MA", color=color.yellow)
rsiUpperBand = hline(70, "RSI Upper Band", color=#787B86)
midline = hline(50, "RSI Middle Band", color=color.new(#787B86, 50))
rsiLowerBand = hline(30, "RSI Lower Band", color=#787B86)
fill(rsiUpperBand, rsiLowerBand, color=color.rgb(126, 87, 194, 90), title="RSI Background Fill")
bbUpperBand = plot(isBB ? rsiMA + ta.stdev(rsi, maLengthInput) * bbMultInput : na, title = "Upper Bollinger Band", color=color.green)
bbLowerBand = plot(isBB ? rsiMA - ta.stdev(rsi, maLengthInput) * bbMultInput : na, title = "Lower Bollinger Band", color=color.green)
fill(bbUpperBand, bbLowerBand, color= isBB ? color.new(color.green, 90) : na, title="Bollinger Bands Background Fill")

midLinePlot = plot(50, color = na, editable = false, display = display.none)
fill(rsiPlot, midLinePlot, 100, 70, top_color = color.new(color.green, 0), bottom_color = color.new(color.green, 100),  title = "Overbought Gradient Fill")
fill(rsiPlot, midLinePlot, 30,  0,  top_color = color.new(color.red, 100), bottom_color = color.new(color.red, 0),      title = "Oversold Gradient Fill")

// Divergence
lookbackRight = 5
lookbackLeft = 5
rangeUpper = 60
rangeLower = 5
bearColor = color.red
bullColor = color.green
textColor = color.white
noneColor = color.new(color.white, 100)

plFound = na(ta.pivotlow(rsi, lookbackLeft, lookbackRight)) ? false : true
phFound = na(ta.pivothigh(rsi, lookbackLeft, lookbackRight)) ? false : true
_inRange(cond) =>
	bars = ta.barssince(cond == true)
	rangeLower <= bars and bars <= rangeUpper

//------------------------------------------------------------------------------
// Regular Bullish
// rsi: Higher Low

rsiHL = rsi[lookbackRight] > ta.valuewhen(plFound, rsi[lookbackRight], 1) and _inRange(plFound[1])

// Price: Lower Low

priceLL = low[lookbackRight] < ta.valuewhen(plFound, low[lookbackRight], 1)
bullCondAlert = priceLL and rsiHL and plFound
bullCond = showDivergence and bullCondAlert

plot(
     plFound ? rsi[lookbackRight] : na,
     offset=-lookbackRight,
     title="Regular Bullish",
     linewidth=2,
     color=(bullCond ? bullColor : noneColor),
     display = display.pane
     )

plotshape(
	 bullCond ? rsi[lookbackRight] : na,
	 offset=-lookbackRight,
	 title="Regular Bullish Label",
	 text=" Bull ",
	 style=shape.labelup,
	 location=location.absolute,
	 color=bullColor,
	 textcolor=textColor
	 )

alertcondition(bullCondAlert, title='Regular Bullish Divergence', message="Found a new Regular Bullish Divergence, `Pivot Lookback Right` number of bars to the left of the current bar.")
''';

const _tvMacd = r'''
//@version=5
indicator(title="Moving Average Convergence Divergence", shorttitle="MACD", timeframe="", timeframe_gaps=true)
// Getting inputs
fast_length = input(title="Fast Length", defval=12)
slow_length = input(title="Slow Length", defval=26)
src = input(title="Source", defval=close)
signal_length = input.int(title="Signal Smoothing",  minval = 1, maxval = 50, defval = 9)
sma_source = input.string(title="Oscillator MA Type",  defval="EMA", options=["SMA", "EMA"])
sma_signal = input.string(title="Signal Line MA Type", defval="EMA", options=["SMA", "EMA"])
// Plot colors
col_macd = input(#2962FF, "MACD Line  ", group="Color Settings", inline="MACD")
col_signal = input(#FF6D00, "Signal Line  ", group="Color Settings", inline="Signal")
col_grow_above = input(#26A69A, "Above   Grow", group="Histogram", inline="Above")
col_fall_above = input(#B2DFDB, "Fall", group="Histogram", inline="Above")
col_grow_below = input(#FFCDD2, "Below Grow", group="Histogram", inline="Below")
col_fall_below = input(#FF5252, "Fall", group="Histogram", inline="Below")
// Calculating
fast_ma = sma_source == "SMA" ? ta.sma(src, fast_length) : ta.ema(src, fast_length)
slow_ma = sma_source == "SMA" ? ta.sma(src, slow_length) : ta.ema(src, slow_length)
macd = fast_ma - slow_ma
signal = sma_signal == "SMA" ? ta.sma(macd, signal_length) : ta.ema(macd, signal_length)
hist = macd - signal
alertcondition(hist[1] >= 0 and hist < 0, title = 'Rising to falling', message = 'The MACD histogram switched from a rising to falling state')
alertcondition(hist[1] <= 0 and hist > 0, title = 'Falling to rising', message = 'The MACD histogram switched from a falling to rising state')
hline(0, "Zero Line", color=color.new(#787B86, 50))
plot(hist, title="Histogram", style=plot.style_columns, color=(hist>=0 ? (hist[1] < hist ? col_grow_above : col_fall_above) : (hist[1] < hist ? col_grow_below : col_fall_below)))
plot(macd, title="MACD", color=col_macd)
plot(signal, title="Signal", color=col_signal)
''';

const _tvBb = r'''
//@version=5
indicator(shorttitle="BB", title="Bollinger Bands", overlay=true, timeframe="", timeframe_gaps=true)
length = input.int(20, minval=1)
maType = input.string("SMA", "Basis MA Type", options = ["SMA", "EMA", "SMMA (RMA)", "WMA", "VWMA"])
src = input(close, title="Source")
mult = input.float(2.0, minval=0.001, maxval=50, title="StdDev")

ma(source, length, _type) =>
    switch _type
        "SMA" => ta.sma(source, length)
        "EMA" => ta.ema(source, length)
        "SMMA (RMA)" => ta.rma(source, length)
        "WMA" => ta.wma(source, length)
        "VWMA" => ta.vwma(source, length)

basis = ma(src, length, maType)
dev = mult * ta.stdev(src, length)
upper = basis + dev
lower = basis - dev
offset = input.int(0, "Offset", minval = -500, maxval = 500, display = display.data_window)
plot(basis, "Basis", color=#FF6D00, offset = offset)
p1 = plot(upper, "Upper", color=#2962FF, offset = offset)
p2 = plot(lower, "Lower", color=#2962FF, offset = offset)
fill(p1, p2, title = "Background", color=color.rgb(33, 150, 243, 95))
''';

const _tvSupertrend = r'''
//@version=5
indicator("Supertrend", overlay=true, timeframe="", timeframe_gaps=true)

atrPeriod = input.int(10,    "ATR Length", minval = 1)
factor =    input.float(3.0, "Factor",     minval = 0.01, step = 0.01)

[supertrend, direction] = ta.supertrend(factor, atrPeriod)

supertrend := barstate.isfirst ? na : supertrend
upTrend =    plot(direction < 0 ? supertrend : na, "Up Trend",   color = color.green, style = plot.style_linebr)
downTrend =  plot(direction < 0 ? na : supertrend, "Down Trend", color = color.red,   style = plot.style_linebr)
bodyMiddle = plot(barstate.isfirst ? na : (open + close) / 2, "Body Middle",display = display.none)

fill(bodyMiddle, upTrend,   color.new(color.green, 90), fillgaps = false)
fill(bodyMiddle, downTrend, color.new(color.red,   90), fillgaps = false)

alertcondition(direction[1] > direction, title='Downtrend to Uptrend', message='The Supertrend value switched from Downtrend to Uptrend ')
alertcondition(direction[1] < direction, title='Uptrend to Downtrend', message='The Supertrend value switched from Uptrend to Downtrend')
alertcondition(direction[1] != direction, title='Trend Change', message='The Supertrend value switched from Uptrend to Downtrend or vice versa')
''';

const _v4 = r'''
//@version=4
study("Eski sürüm", overlay=true)
len = input(14, type=input.integer, title="Length")
src = input(close, title="Source", type=input.source)
plot(sma(src, len), color=color.blue, transp=0, title="SMA")
plot(iff(change(src) > 0, src, na), color=color.green, style=plot.style_circles)
''';


// ── Topluluk göstergeleri (TradingView'de en çok kopyalananlardan) ─────────

const _squeeze = r'''
//
// @author LazyBear
// List of all my indicators: https://www.tradingview.com/v/4IneGo8h/
//
study(shorttitle = "SQZMOM_LB", title="Squeeze Momentum Indicator [LazyBear]", overlay=false)

length = input(20, title="BB Length")
mult = input(2.0,title="BB MultFactor")
lengthKC=input(20, title="KC Length")
multKC = input(1.5, title="KC MultFactor")

useTrueRange = input(true, title="Use TrueRange (KC)", type=bool)

// Calculate BB
source = close
basis = sma(source, length)
dev = multKC * stdev(source, length)
upperBB = basis + dev
lowerBB = basis - dev

// Calculate KC
ma = sma(source, lengthKC)
range = useTrueRange ? tr : (high - low)
rangema = sma(range, lengthKC)
upperKC = ma + rangema * multKC
lowerKC = ma - rangema * multKC

sqzOn  = (lowerBB > lowerKC) and (upperBB < upperKC)
sqzOff = (lowerBB < lowerKC) and (upperBB > upperKC)
noSqz  = (sqzOn == false) and (sqzOff == false)

val = linreg(source  -  avg(avg(highest(high, lengthKC), lowest(low, lengthKC)),sma(close,lengthKC)),
            lengthKC,0)

bcolor = iff( val > 0,
            iff( val > nz(val[1]), lime, green),
            iff( val < nz(val[1]), red, maroon))
scolor = noSqz ? blue : sqzOn ? black : gray
plot(val, color=bcolor, style=histogram, linewidth=4)
plot(0, color=scolor, style=cross, linewidth=2)
''';

const _waveTrend = r'''
//
// @author LazyBear
//
study(title="WaveTrend [LazyBear]", shorttitle="WT_LB")
n1 = input(10, "Channel Length")
n2 = input(21, "Average Length")
obLevel1 = input(60, "Over Bought Level 1")
obLevel2 = input(53, "Over Bought Level 2")
osLevel1 = input(-60, "Over Sold Level 1")
osLevel2 = input(-53, "Over Sold Level 2")

ap = hlc3
esa = ema(ap, n1)
d = ema(abs(ap - esa), n1)
ci = (ap - esa) / (0.015 * d)
tci = ema(ci, n2)

wt1 = tci
wt2 = sma(wt1,4)

plot(0, color=gray)
plot(obLevel1, color=red)
plot(osLevel1, color=green)
plot(obLevel2, color=red, style=3)
plot(osLevel2, color=green, style=3)

plot(wt1, color=green)
plot(wt2, color=red, style=3)
plot(wt1-wt2, color=blue, style=area, transp=80)
''';

const _utBot = r'''
//@version=4
study(title="UT Bot Alerts", overlay = true)

// Inputs
a = input(1,     title = "Key Vaule. 'This changes the sensitivity'")
c = input(10,    title = "ATR Period")
h = input(false, title = "Signals from Heikin Ashi Candles")

xATR  = atr(c)
nLoss = a * xATR

src = h ? security(heikinashi(syminfo.tickerid), timeframe.period, close, lookahead = false) : close

xATRTrailingStop = 0.0
xATRTrailingStop := iff(src > nz(xATRTrailingStop[1], 0) and src[1] > nz(xATRTrailingStop[1], 0), max(nz(xATRTrailingStop[1]), src - nLoss),
   iff(src < nz(xATRTrailingStop[1], 0) and src[1] < nz(xATRTrailingStop[1], 0), min(nz(xATRTrailingStop[1]), src + nLoss),
   iff(src > nz(xATRTrailingStop[1], 0), src - nLoss, src + nLoss)))

pos = 0
pos :=	iff(src[1] < nz(xATRTrailingStop[1], 0) and src > nz(xATRTrailingStop[1], 0), 1,
   iff(src[1] > nz(xATRTrailingStop[1], 0) and src < nz(xATRTrailingStop[1], 0), -1, nz(pos[1], 0)))

xcolor = pos == -1 ? color.red: pos == 1 ? color.green : color.blue

ema   = ema(src,1)
above = crossover(ema, xATRTrailingStop)
below = crossover(xATRTrailingStop, ema)

buy  = src > xATRTrailingStop and above
sell = src < xATRTrailingStop and below

barbuy  = src > xATRTrailingStop
barsell = src < xATRTrailingStop

plotshape(buy,  title = "Buy",  text = 'Buy',  style = shape.labelup,   location = location.belowbar, color= color.green, textcolor = color.white, transp = 0, size = size.tiny)
plotshape(sell, title = "Sell", text = 'Sell', style = shape.labeldown, location = location.abovebar, color= color.red,   textcolor = color.white, transp = 0, size = size.tiny)

barcolor(barbuy  ? color.green : na)
barcolor(barsell ? color.red   : na)

alertcondition(buy,  "UT Long",  "UT Long")
alertcondition(sell, "UT Short", "UT Short")
''';

const _ichimoku = r'''
//@version=5
indicator(title="Ichimoku Cloud", shorttitle="Ichimoku", overlay=true)
conversionPeriods = input.int(9, minval=1, title="Conversion Line Length")
basePeriods = input.int(26, minval=1, title="Base Line Length")
laggingSpan2Periods = input.int(52, minval=1, title="Leading Span B Length")
displacement = input.int(26, minval=1, title="Lagging Span")
donchian(len) => math.avg(ta.lowest(len), ta.highest(len))
conversionLine = donchian(conversionPeriods)
baseLine = donchian(basePeriods)
leadLine1 = math.avg(conversionLine, baseLine)
leadLine2 = donchian(laggingSpan2Periods)
plot(conversionLine, color=#2962FF, title="Conversion Line")
plot(baseLine, color=#B71C1C, title="Base Line")
plot(close, offset = -displacement + 1, color=#43A047, title="Lagging Span")
p1 = plot(leadLine1, offset = displacement - 1, color=#A5D6A7,
	 title="Leading Span A")
p2 = plot(leadLine2, offset = displacement - 1, color=#EF9A9A,
	 title="Leading Span B")
plot(leadLine1 > leadLine2 ? leadLine1 : leadLine2, offset = displacement - 1, title = "Kumo Cloud Upper Line", display = display.none)
plot(leadLine1 < leadLine2 ? leadLine1 : leadLine2, offset = displacement - 1, title = "Kumo Cloud Lower Line", display = display.none)
fill(p1, p2, color = leadLine1 > leadLine2 ? color.rgb(67, 160, 71, 90) : color.rgb(244, 67, 54, 90))
''';

void main() {
  group('TradingView yerleşik göstergeleri olduğu gibi çalışır', () {
    test('RSI (divergence dahil) — uygulamanın RSI\'ıyla aynı sayı', () {
      final v = _veri(300);
      final s = GostergeBetigi.calistir(_tvRsi, v);
      expect(s.fiyatUstunde, isFalse);
      expect(s.baslik, 'Relative Strength Index');
      final rsi = s.cizgiler.firstWhere((c) => c.ad == 'RSI');
      final beklenen = GostergeBetigi.calistir(
              '//@version=5\nindicator("x")\nplot(ta.rsi(close, 14))', v)
          .cizgiler
          .single
          .degerler;
      for (var i = 0; i < v.uzunluk; i++) {
        if (beklenen[i].isNaN) continue;
        expect(rsi.degerler[i], closeTo(beklenen[i], 1e-9));
      }
      expect(rsi.degerler.where((x) => !x.isNaN), isNotEmpty);
      expect(rsi.renk, 'mor'); // #7E57C2
      expect(s.yataylar.map((y) => y.deger), [70, 50, 30]);
      // display.none ile çizilen 50 çizgisi gizli; fill için duruyor.
      expect(s.cizgiler.where((c) => c.gizli), isNotEmpty);
      expect(s.dolgular.where((d) => d.yatayA != null), hasLength(1));
      // Bollinger seçilmediği için BB çizgileri boş.
      expect(
          s.cizgiler
              .firstWhere((c) => c.ad == 'Upper Bollinger Band')
              .degerler
              .every((x) => x.isNaN),
          isTrue);
      // Divergence low kullanıyor → yalnız kapanış seride eksik veri.
      expect(s.eksikVeri, contains('dusuk'));
    });

    test('MACD — iki renkli histogram + iki çizgi', () {
      final v = _veri(300);
      final s = GostergeBetigi.calistir(_tvMacd, v);
      expect(s.cizgiler.map((c) => c.ad), ['Histogram', 'MACD', 'Signal']);
      final h = s.cizgiler[0];
      expect(h.stil, BetikCizgiStili.histogram);
      expect(h.renk, isNotNull);
      expect(h.eksiRenk, isNotNull);
      expect(h.renk, isNot(h.eksiRenk));
      final hizli = TechnicalAnalysisService.emaSeries(v.kapanis, 12);
      final yavas = TechnicalAnalysisService.emaSeries(v.kapanis, 26);
      final son = v.uzunluk - 1;
      expect(s.cizgiler[1].degerler[son],
          closeTo(hizli[son] - yavas[son], 1e-9));
      expect(s.yataylar.single.deger, 0);
    });

    test('Bollinger Bands — fiyatın üstünde, dolgu ile', () {
      final v = _veri(200);
      final s = GostergeBetigi.calistir(_tvBb, v);
      expect(s.fiyatUstunde, isTrue);
      final sma = TechnicalAnalysisService.smaSeries(v.kapanis, 20);
      expect(s.cizgiler[0].degerler.last, closeTo(sma.last, 1e-9));
      expect(s.cizgiler[1].degerler.last, greaterThan(sma.last));
      expect(s.cizgiler[2].degerler.last, lessThan(sma.last));
      expect(s.dolgular.single.a, 1);
      expect(s.dolgular.single.b, 2);
      expect(s.cizgiler[0].renk, 'turuncu');
      expect(s.cizgiler[1].renk, 'mavi');
    });

    test('Supertrend — demet, := ve linebr; OHLC varken iz sürer', () {
      final s = GostergeBetigi.calistir(_tvSupertrend, _ohlc(200));
      expect(s.eksikVeri, isEmpty);
      final yukari = s.cizgiler[0].degerler.where((x) => !x.isNaN);
      final asagi = s.cizgiler[1].degerler.where((x) => !x.isNaN);
      expect(yukari.length + asagi.length, greaterThan(150));
      expect(s.cizgiler[2].gizli, isTrue);
    });

    test('v4 sözdizimi (study, input type=, öneksiz sma/change, iff)', () {
      final v = _veri(60);
      final s = GostergeBetigi.calistir(_v4, v);
      expect(s.fiyatUstunde, isTrue);
      final sma = TechnicalAnalysisService.smaSeries(v.kapanis, 14);
      expect(s.cizgiler[0].degerler.last, closeTo(sma.last, 1e-9));
      expect(s.cizgiler[1].stil, BetikCizgiStili.nokta);
    });
  });


  group('topluluk göstergeleri olduğu gibi çalışır', () {
    test('Squeeze Momentum [LazyBear] (v2/v3 sözdizimi)', () {
      final s = GostergeBetigi.calistir(_squeeze, _ohlc(300));
      expect(s.eksikVeri, isEmpty);
      final val = s.cizgiler[0];
      expect(val.stil, BetikCizgiStili.histogram);
      expect(val.degerler.last.isFinite, isTrue);
      expect({val.renk, val.eksiRenk}, everyElement(isNotNull));
      expect(s.cizgiler[1].stil, BetikCizgiStili.nokta);
    });

    test('WaveTrend [LazyBear]', () {
      final s = GostergeBetigi.calistir(_waveTrend, _ohlc(300));
      expect(s.cizgiler, hasLength(8));
      expect(s.cizgiler[5].degerler.last.isFinite, isTrue);
      expect(s.cizgiler[7].stil, BetikCizgiStili.alan);
    });

    test('UT Bot Alerts (iz süren stop, := geçmişi, işaretler)', () {
      final s = GostergeBetigi.calistir(_utBot, _ohlc(300));
      expect(s.notlar, contains(BetikNotu.boyama));
      final al = s.isaretler.firstWhere((m) => m.ad == 'Buy');
      final sat = s.isaretler.firstWhere((m) => m.ad == 'Sell');
      expect(al.indeksler, isNotEmpty);
      expect(sat.indeksler, isNotEmpty);
      expect(al.renk, 'yesil');
    });

    test('Ichimoku Cloud (offset, 1 argümanlı ta.lowest, fill)', () {
      final v = _ohlc(200);
      final s = GostergeBetigi.calistir(_ichimoku, v);
      final gecikme = s.cizgiler.firstWhere((c) => c.ad == 'Lagging Span');
      // offset -25: bugünkü kapanış 25 çubuk geride çizilir.
      expect(gecikme.degerler[v.uzunluk - 26], v.kapanis.last);
      expect(s.dolgular.single.a, 3);
      expect(s.cizgiler.where((c) => c.gizli), hasLength(2));
    });
  });

  group('dil', () {
    test('var, if/else if, +=, :=, for döngüsü ve x[n]', () {
      final d = BetikVerisi.yalnizKapanis(
          [for (var i = 0; i < 8; i++) _gun(i)],
          [1, 2, 3, 2, 3, 4, 5, 4]);
      final s = GostergeBetigi.calistir('''
//@version=5
indicator("Sayaç")
var int sayac = 0
if close > close[1]
    sayac += 1
else if close < close[1]
    sayac := 0
toplam = 0.0
for i = 0 to 2
    toplam += close[i]
plot(sayac, "Sayaç")
plot(toplam / 3 - ta.sma(close, 3), "Fark")
plot(sayac[1], "Önceki")
''', d);
      expect(s.cizgiler[0].degerler, [0, 1, 2, 0, 1, 2, 3, 0]);
      expect(_son(s.cizgiler[1].degerler, 6).every((x) => x.abs() < 1e-9),
          isTrue);
      expect(s.cizgiler[2].degerler.sublist(1), [0, 1, 2, 0, 1, 2, 3]);
    });

    test('fonksiyonun her çağrı yeri kendi durumunu tutar', () {
      final s = GostergeBetigi.calistir('''
//@version=5
indicator("x")
f(src) =>
    e = ta.ema(src, 10)
    e
a = f(close)
b = f(close * 2)
plot(b - 2 * a)
''', _veri(100));
      final d = s.cizgiler.single.degerler.where((x) => !x.isNaN);
      expect(d, isNotEmpty);
      expect(d.every((x) => x.abs() < 1e-9), isTrue);
    });

    test('switch (konusuz), while, break/continue, çok satırlı üçlü', () {
      final s = GostergeBetigi.calistir('''
//@version=5
indicator("x")
k = 0
i = 0
while true
    i += 1
    if i % 2 == 0
        continue
    if i > 7
        break
    k += i
renk = close > open ?
     color.green :
     color.red
seviye = switch
    close > 105 => 2
    close > 95 => 1
    => 0
plot(k, color = renk)
plot(seviye)
''', _veri(30));
      expect(s.cizgiler[0].degerler.first, 1 + 3 + 5 + 7);
      expect(s.cizgiler[1].degerler.toSet().difference({0.0, 1.0, 2.0}),
          isEmpty);
    });

    test('demet dönen kullanıcı fonksiyonu', () {
      final s = GostergeBetigi.calistir('''
//@version=5
indicator("x", overlay=true)
bant(src, n) =>
    m = ta.sma(src, n)
    [m + 1, m - 1]
[ust, alt] = bant(close, 5)
plot(ust - alt)
''', _veri(20));
      expect(s.cizgiler.single.degerler.last, 2);
    });

    test('renkler tasarım rengine düşer: #hex, color.new, color.rgb', () {
      final s = GostergeBetigi.calistir('''
//@version=5
indicator("x", overlay=true)
plot(close, color=#00ff00)
plot(close, color=color.new(color.red, 30))
plot(close, color=color.rgb(255, 165, 0))
plot(close, color=color.new(color.blue, 100))
''', _veri(5));
      expect(s.cizgiler.map((c) => c.renk),
          ['yesil', 'kirmizi', 'turuncu', 'mavi']);
      expect(s.cizgiler[3].gizli, isTrue);
    });

    test('plotshape/plotchar/plotarrow işaretleri', () {
      final d = BetikVerisi.yalnizKapanis(
          [for (var i = 0; i < 5; i++) _gun(i)], [1, 2, 3, 2, 4]);
      final s = GostergeBetigi.calistir('''
//@version=5
indicator("x", overlay=true)
plotshape(ta.crossover(close, 2.5), "Yukarı", shape.triangleup, location.belowbar, color.green)
plotchar(close < close[1], "Düşüş", "▼", location.abovebar, color.red)
plotarrow(close - close[1])
''', d);
      expect(s.isaretler[0].indeksler, [2, 4]);
      expect(s.isaretler[0].renk, 'yesil');
      expect(s.isaretler[1].indeksler, [3]);
      expect(s.isaretler[2].indeksler, [1, 2, 4]);
      expect(s.isaretler[3].indeksler, [3]);
    });

    test('çizim nesneleri, bgcolor ve strateji çalışır ama not düşer', () {
      final s = GostergeBetigi.calistir('''
//@version=5
strategy("Strateji", overlay=true)
var label lbl = na
if barstate.islast
    lbl := label.new(bar_index, high, "son")
bgcolor(close > open ? color.new(color.green, 90) : na)
if ta.crossover(close, ta.sma(close, 5))
    strategy.entry("Al", strategy.long)
plot(ta.sma(close, 5))
''', _veri(50));
      expect(s.notlar, containsAll([
        BetikNotu.cizimNesnesi,
        BetikNotu.boyama,
        BetikNotu.strateji,
      ]));
      expect(s.cizgiler.single.degerler.last.isNaN, isFalse);
    });

    test('request.security aynı sembol ve aralıkta çalışır', () {
      final s = GostergeBetigi.calistir('''
//@version=5
indicator("x", overlay=true)
s = request.security(syminfo.tickerid, timeframe.period, ta.sma(close, 3))
plot(s)
''', _veri(10));
      expect(s.cizgiler.single.degerler.last.isNaN, isFalse);
    });

    test('ta kütüphanesi: bb/kc/stoch/dmi/sar/atr OHLC ile sayı üretir', () {
      final s = GostergeBetigi.calistir('''
//@version=5
indicator("x")
[m, u, l] = ta.bb(close, 20, 2)
[km, ku, kl] = ta.kc(close, 20, 1.5)
[artı, eksi, adx] = ta.dmi(14, 14)
plot(u - l)
plot(ku - kl)
plot(ta.stoch(close, high, low, 14))
plot(adx)
plot(ta.sar(0.02, 0.02, 0.2))
plot(ta.atr(14))
plot(ta.cci(close, 20))
plot(ta.mfi(hlc3, 14))
plot(ta.obv)
plot(ta.vwap(hlc3))
plot(ta.hma(close, 9))
plot(ta.alma(close, 9, 0.85, 6))
plot(ta.linreg(close, 20, 0))
plot(ta.wpr(14))
plot(ta.cmo(close, 9))
plot(ta.tsi(close, 13, 25))
''', _ohlc(300));
      for (final c in s.cizgiler) {
        expect(c.degerler.last.isFinite, isTrue, reason: c.ad);
      }
    });

    test('pivothigh/valuewhen/barssince', () {
      final d = BetikVerisi.yalnizKapanis(
          [for (var i = 0; i < 9; i++) _gun(i)],
          [1, 2, 5, 2, 1, 2, 6, 2, 1]);
      final s = GostergeBetigi.calistir('''
//@version=5
indicator("x")
ph = ta.pivothigh(close, 2, 2)
plot(ph)
plot(ta.valuewhen(not na(ph), ph, 0))
plot(ta.barssince(not na(ph)))
''', d);
      expect(s.cizgiler[0].degerler[4], 5);
      expect(s.cizgiler[0].degerler[8], 6);
      expect(s.cizgiler[1].degerler.last, 6);
      expect(s.cizgiler[2].degerler.last, 0);
      expect(s.cizgiler[2].degerler[7], 3);
    });
  });

  group('eksik veri dürüstçe söylenir', () {
    test('yalnız kapanış varken high/volume na ve eksikVeri dolu', () {
      final s = GostergeBetigi.calistir(
          'plot(ta.atr(14))\nplot(ta.sma(volume, 5))', _veri(40));
      expect(s.cizgiler.every((c) => c.degerler.every((x) => x.isNaN)),
          isTrue);
      expect(s.eksikVeri, containsAll(['yuksek', 'hacim']));
      expect(s.bos, isTrue);
    });

    test('OHLC gelince atr çizilir', () {
      const n = 40;
      final v = BetikVerisi(
        x: [for (var i = 0; i < n; i++) _gun(i)],
        acilis: [for (var i = 0; i < n; i++) 100.0 + i],
        yuksek: [for (var i = 0; i < n; i++) 102.0 + i],
        dusuk: [for (var i = 0; i < n; i++) 99.0 + i],
        kapanis: [for (var i = 0; i < n; i++) 101.0 + i],
        hacim: [for (var i = 0; i < n; i++) 1000.0],
      );
      final s = GostergeBetigi.calistir('plot(ta.atr(14))', v);
      expect(s.eksikVeri, isEmpty);
      expect(s.cizgiler.first.degerler.last, closeTo(3, 1e-9));
    });
  });

  group('güvenlik: dil kaçamaz, sınırlar tutar', () {
    for (final (kod, parca) in [
      ('import user/lib/1 as l\nplot(close)', 'import'),
      ('x = request.security("BINANCE:BTCUSDT", "D", close)\nplot(x)',
          'sembol'),
      ('x = request.security(syminfo.tickerid, "60", close)\nplot(x)',
          'aralık'),
      ('a = array.new_float(0)\nplot(close)', 'Diziler'),
      ('float[] a = na\nplot(close)', 'Diziler'),
      ('method f(float x) => x\nplot(close)', 'method'),
      ('type P\n    float x\nplot(close)', 'type'),
      ('indicator("x", timeframe="W")\nplot(close)', 'zaman aralığında'),
    ]) {
      test('reddedilir: ${kod.split('\n').first}', () {
        expect(_hataAl(kod).mesaj, contains(parca));
      });
    }

    test('sonsuz döngü bütçede durur', () {
      expect(_hataAl('x = 0\nwhile true\n    x += 1\nplot(x)').mesaj,
          contains('ağır'));
    });

    test('özyineleme yok (fonksiyon kendini göremez)', () {
      expect(_hataAl('f(x) => f(x)\nplot(f(close))').mesaj,
          contains('Bilinmeyen'));
    });

    test('plot yerel kapsamda kullanılamaz (Pine kuralı)', () {
      expect(_hataAl('if close > 1\n    plot(close)').mesaj,
          contains('yerel'));
    });

    test('çok uzun kod', () {
      expect(_hataAl('plot(close)\n${'x' * kBetikAzamiKarakter}').mesaj,
          contains('uzun'));
    });

    test('dev pencere reddedilir', () {
      expect(_hataAl('plot(ta.sma(close, 100000))').mesaj,
          contains('arasında'));
    });

    test('çok iç içe ifade', () {
      expect(_hataAl('plot(${'(' * 200}1${')' * 200})').mesaj,
          contains('iç içe'));
    });

    test('fazla plot kırmaz, not düşer', () {
      final s = GostergeBetigi.calistir(
          List.filled(kBetikAzamiCizgi + 3, 'plot(close)').join('\n'),
          _veri(10));
      expect(s.cizgiler, hasLength(kBetikAzamiCizgi));
      expect(s.notlar, contains(BetikNotu.fazlaCizgi));
    });

    test('çok çubuk sondan kırpılır', () {
      final v = _veri(8000);
      final s = GostergeBetigi.calistir('plot(close)', v);
      expect(s.x.length, kBetikAzamiCubuk);
      expect(s.x.last, v.x.last);
    });
  });

  group('yardımcı hata mesajları', () {
    test('yazım hatasına öneri', () {
      final h = _hataAl('plot(ta.smaa(close, 3))');
      expect(h.mesaj, contains("'ta.sma'"));
      expect(h.satir, 1);
    });
    test('satır/sütun', () {
      final h = _hataAl('x = 1\nplot(close +)');
      expect(h.satir, 2);
    });
    test('plot yoksa', () {
      expect(_hataAl('x = ta.sma(close, 5)').mesaj, contains('plot'));
    });
    test('tanımlanmadan := ', () {
      expect(_hataAl('x := 2\nplot(x)').mesaj, contains('tanımlanmadan'));
    });
    test('girinti hizası', () {
      expect(_hataAl('if close > 1\n        x = 1\n    y = 2\nplot(close)')
              .mesaj,
          contains('Girinti'));
    });
    test('İngilizce mesaj da var', () {
      expect(_hataAl('plot(foo)').mesajEn, contains('Undefined'));
    });
  });

  test('bütün şablonlar derlenir ve bir şey çizer', () {
    for (final s in kBetikSablonlari) {
      final r = GostergeBetigi.calistir(s.kod, _veri(300));
      expect(r.bos, isFalse, reason: s.kimlik);
    }
  });
}
