import 'dart:math';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/technical_signal.dart';
import '../utils/tr_format.dart';

/// Gösterge kimlikleri — per-category seçim ve Premium kapısı için stable key.
///
/// ## Premium modeli (yasin, 2026-10-10)
/// *"teknik göstergelerden en yaygın 3 tanesi ücretsiz gösterilmeli, ancak
/// kalanları ve custom gösterge bununla push bildirimi feature'ı premium
/// olmalı; ayrıca var olan göstergeler de parametrik kullanılabilmeli
/// premiumda."* Üç küme bu kararı taşır; hangi kümenin hesaplanacağına
/// [izinli] karar verir (provider: `izinliGostergelerProvider`).
class IndicatorId {
  static const rsi = 'rsi';
  static const macd = 'macd';
  static const bollinger = 'bollinger';
  static const ema = 'ema';
  static const stochastic = 'stochastic';

  // İleri göstergeler
  static const adx = 'adx';
  static const williamsR = 'williams_r';
  static const cci = 'cci';

  static const all = <String>[
    rsi,
    macd,
    bollinger,
    ema,
    stochastic,
    adx,
    williamsR,
    cci,
  ];

  /// Paywall açıkken ücretsiz olan üç gösterge: en yaygın üçü (RSI, MACD,
  /// Bollinger — rakiplerin ücretsiz planlarındaki ortak küme).
  static const ucretsiz = <String>{rsi, macd, bollinger};

  /// İleri göstergeler: paywall KAPALIYKEN hiç hesaplanmaz ve ayar
  /// ekranında görünmez (bugünkü canlı davranış; anahtarları hiçbir şey
  /// yapmıyordu, "ölü anahtar" bulgusu). Paywall açıkken Premium'dadır.
  static const ileri = <String>{adx, williamsR, cci};

  /// Bu kullanıcıda HESAPLANAN göstergeler.
  ///
  /// * Paywall kapalı: ileri üçü hariç beşi (birebir eski davranış).
  /// * Paywall açık, Premium erişimi var: sekizi.
  /// * Paywall açık, ücretsiz: [ucretsiz] üçü.
  static Set<String> izinli({required bool paywall, required bool premium}) {
    if (!paywall) return all.where((id) => !ileri.contains(id)).toSet();
    return premium ? all.toSet() : ucretsiz;
  }

  /// Paywall açıkken Premium isteyen göstergeler ([ucretsiz] dışındakiler).
  static bool premiumMu(String id) => !ucretsiz.contains(id);

  static Set<String> recommendedFor(AssetType type) =>
      // BES fonu fon gibi analiz edilir (`fiyatlamaTuru`).
      switch (type.fiyatlamaTuru) {
        AssetType.hisse => {rsi, macd, bollinger, stochastic, adx},
        AssetType.fon => {ema, rsi, macd},
        AssetType.altin => {rsi, bollinger, ema, cci},
        AssetType.doviz => {ema, rsi, williamsR, stochastic},
        AssetType.emtia => {rsi, macd, bollinger, cci, adx},
        _ => {},
      };

  static String labelOf(String id) {
    switch (id) {
      case rsi:
        return 'RSI (Göreceli Güç Endeksi)';
      case macd:
        return 'MACD (Hareketli Ortalama Yakınsaması)';
      case bollinger:
        return 'Bollinger Bantları';
      case ema:
        return 'EMA Kesişim';
      case stochastic:
        return 'Stokastik Osilatör';
      case adx:
        return 'ADX (Yön Endeksi)';
      case williamsR:
        return 'Williams %R';
      case cci:
        return 'CCI (Commodity Channel Index)';
    }
    return id;
  }
}

/// Bir göstergenin kullanıcı ayarı: parametre anahtarı → tam sayı değer
/// (ör. `{'periyot': 21}`). Eksik anahtar türün varsayılanıyla hesaplanır.
typedef GostergeAyari = Map<String, int>;

/// Bir gösterge parametresinin tanımı (ayar ekranı ve doğrulama).
class GostergeParametresi {
  const GostergeParametresi(this.anahtar, this.etiket,
      {required this.enAz, required this.enCok});

  /// Saklama anahtarı — sunucu portuyla (`_shared/technical_analysis.ts`)
  /// aynı ad.
  final String anahtar;
  final String etiket;
  final int enAz;
  final int enCok;
}

/// Göstergelerin ayarlanabilir parametreleri (Premium, yasin 2026-10-10:
/// "var olan göstergeler de parametrik kullanılabilmeli premiumda").
///
/// Neden yalnız pencere uzunlukları: göstergelerin eşikleri (RSI 70/30,
/// CCI ±100) yorumun kendisidir ve türüne göre zaten ayarlı; kullanıcıya
/// açılan şey TradingView'deki "Length" alanının karşılığı. Sınırlar sinyal
/// penceresine (180 gün) sığacak biçimde dar: 200 günlük RSI'ın seride
/// tek noktası kalmazdı.
class GostergeParametreleri {
  GostergeParametreleri._();

  static const tanimlar = <String, List<GostergeParametresi>>{
    IndicatorId.rsi: [GostergeParametresi('periyot', 'Periyot', enAz: 2, enCok: 50)],
    IndicatorId.macd: [
      GostergeParametresi('hizli', 'Hızlı', enAz: 2, enCok: 50),
      GostergeParametresi('yavas', 'Yavaş', enAz: 3, enCok: 100),
      GostergeParametresi('sinyal', 'Sinyal', enAz: 2, enCok: 50),
    ],
    IndicatorId.bollinger: [
      GostergeParametresi('periyot', 'Periyot', enAz: 5, enCok: 60)
    ],
    IndicatorId.ema: [
      GostergeParametresi('kisa', 'Kısa', enAz: 2, enCok: 60),
      GostergeParametresi('uzun', 'Uzun', enAz: 3, enCok: 120),
    ],
    IndicatorId.stochastic: [
      GostergeParametresi('periyot', 'Periyot', enAz: 3, enCok: 50)
    ],
    IndicatorId.adx: [GostergeParametresi('periyot', 'Periyot', enAz: 3, enCok: 50)],
    IndicatorId.williamsR: [
      GostergeParametresi('periyot', 'Periyot', enAz: 3, enCok: 50)
    ],
    IndicatorId.cci: [GostergeParametresi('periyot', 'Periyot', enAz: 5, enCok: 60)],
  };

  /// Türün varsayılan değerleri — ayar ekranı alanı bununla doldurur.
  /// Hesap fonksiyonlarındaki varsayılanlarla aynı (tek doğruluk testi
  /// `gosterge_parametre_test`).
  static GostergeAyari varsayilan(String id, AssetType type) {
    final fon = type.fiyatlamaTuru == AssetType.fon;
    return switch (id) {
      IndicatorId.rsi => {'periyot': type == AssetType.doviz ? 9 : 14},
      IndicatorId.macd => {
          'hizli': fon ? 8 : 12,
          'yavas': fon ? 21 : 26,
          'sinyal': 9
        },
      IndicatorId.bollinger => {'periyot': type == AssetType.altin ? 14 : 20},
      IndicatorId.ema => switch (type) {
          AssetType.hisse => {'kisa': 20, 'uzun': 50},
          AssetType.altin => {'kisa': 14, 'uzun': 40},
          AssetType.doviz => {'kisa': 7, 'uzun': 21},
          _ when fon => {'kisa': 10, 'uzun': 30},
          _ => {'kisa': 20, 'uzun': 50},
        },
      IndicatorId.stochastic => {'periyot': type == AssetType.doviz ? 9 : 14},
      IndicatorId.adx || IndicatorId.williamsR => {'periyot': 14},
      IndicatorId.cci => {'periyot': 20},
      _ => const {},
    };
  }

  /// Bilinmeyen anahtarı atar, değeri sınıra kırpar; kısa ≥ uzun gibi
  /// anlamsız çiftte (MACD hızlı ≥ yavaş, EMA kısa ≥ uzun) ayarın TÜMÜ
  /// yok sayılır — yarım uygulanan ayar kullanıcının görmediği bir
  /// göstergeyi hesaplardı. Boş sonuç null. Sunucu portu aynı kuralı uygular.
  static GostergeAyari? dogrula(String id, GostergeAyari? ham) {
    if (ham == null || ham.isEmpty) return null;
    final tanim = tanimlar[id];
    if (tanim == null) return null;
    final out = <String, int>{};
    for (final t in tanim) {
      final v = ham[t.anahtar];
      if (v == null) continue;
      out[t.anahtar] = v.clamp(t.enAz, t.enCok);
    }
    if (out.isEmpty) return null;
    bool ters(String a, String b) =>
        out[a] != null && out[b] != null && out[a]! >= out[b]!;
    if (ters('hizli', 'yavas') || ters('kisa', 'uzun')) return null;
    return out;
  }
}

class TechnicalAnalysisService {
  // ── EMA ──────────────────────────────────────────────────────────────────

  static double _ema(List<double> prices, int period) {
    if (prices.isEmpty) return 0;
    final len = min(prices.length, period * 3);
    final sub = prices.sublist(prices.length - len);
    double ema =
        sub.sublist(0, min(period, sub.length)).reduce((a, b) => a + b) /
            min(period, sub.length);
    final k = 2.0 / (period + 1);
    for (int i = min(period, sub.length); i < sub.length; i++) {
      ema = sub[i] * k + ema * (1 - k);
    }
    return ema;
  }

  /// Basit hareketli ortalama serisi. İlk (period-1) elemanı NaN döner —
  /// grafik overlay çizerken bu noktalar atlanır.
  static List<double> smaSeries(List<double> prices, int period) {
    final n = prices.length;
    final out = List<double>.filled(n, double.nan);
    if (n < period || period <= 0) return out;
    double sum = 0;
    for (int i = 0; i < period; i++) {
      sum += prices[i];
    }
    out[period - 1] = sum / period;
    for (int i = period; i < n; i++) {
      sum += prices[i] - prices[i - period];
      out[i] = sum / period;
    }
    return out;
  }

  /// Üssel hareketli ortalama SERİSİ (grafik katmanı, EMA50/EMA200).
  ///
  /// Tohum ilk [period] noktanın basit ortalamasıdır (TradingView ile aynı
  /// tanım); ilk (period-1) eleman NaN döner — yetersiz veriyle çizilen bir
  /// EMA200 aslında 30 noktanın ortalamasıdır ve "uzun vadeli trend" diye
  /// okunurdu. [smaSeries] ile aynı sözleşme: çizen NaN'ı atlar.
  static List<double> emaSeries(List<double> prices, int period) {
    final n = prices.length;
    final out = List<double>.filled(n, double.nan);
    if (n < period || period <= 0) return out;
    double sum = 0;
    for (int i = 0; i < period; i++) {
      sum += prices[i];
    }
    var ema = sum / period;
    out[period - 1] = ema;
    final k = 2 / (period + 1);
    for (int i = period; i < n; i++) {
      ema = prices[i] * k + ema * (1 - k);
      out[i] = ema;
    }
    return out;
  }

  // ── 1. RSI ────────────────────────────────────────────────────────────────

  static TechnicalIndicator rsi(List<double> prices, AssetType type,
      {GostergeAyari? par}) {
    final period = par?['periyot'] ?? (type == AssetType.doviz ? 9 : 14);
    final label = 'RSI ($period)';
    if (prices.length < period + 1) {
      return TechnicalIndicator(
          name: label,
          value: 50,
          signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    double gains = 0, losses = 0;
    for (int i = prices.length - period; i < prices.length; i++) {
      final d = prices[i] - prices[i - 1];
      if (d > 0) {
        gains += d;
      } else {
        losses -= d;
      }
    }
    final avgG = gains / period;
    final avgL = losses / period;
    final value = avgL == 0 ? 100.0 : 100 - (100 / (1 + avgG / avgL));

    final overbought = type == AssetType.hisse ? 70.0 : 72.0;
    final oversold = type == AssetType.hisse ? 30.0 : 28.0;

    final signal = value < oversold
        ? SignalType.buy
        : value > overbought
            ? SignalType.sell
            : SignalType.neutral;

    final desc = value < oversold
        ? 'Aşırı satım bölgesi (${fmtNum(value, digits: 1)})'
        : value > overbought
            ? 'Aşırı alım bölgesi (${fmtNum(value, digits: 1)})'
            : 'Nötr bölge (${fmtNum(value, digits: 1)})';

    return TechnicalIndicator(
        name: label, value: value, signal: signal, description: desc);
  }

  // ── 2. MACD ───────────────────────────────────────────────────────────────

  static TechnicalIndicator macd(List<double> prices, AssetType type,
      {GostergeAyari? par}) {
    final fast =
        par?['hizli'] ?? (type.fiyatlamaTuru == AssetType.fon ? 8 : 12);
    final slow =
        par?['yavas'] ?? (type.fiyatlamaTuru == AssetType.fon ? 21 : 26);
    final sig = par?['sinyal'] ?? 9;
    final label = 'MACD ($fast,$slow,$sig)';

    if (prices.length < slow + sig) {
      return TechnicalIndicator(
          name: label,
          value: 0,
          signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final macdLine = _ema(prices, fast) - _ema(prices, slow);

    final macdSeries = <double>[];
    for (int i = slow; i <= prices.length; i++) {
      final sub = prices.sublist(0, i);
      macdSeries.add(_ema(sub, fast) - _ema(sub, slow));
    }
    final signalLine = _ema(macdSeries, sig);
    final histogram = macdLine - signalLine;

    final signal = histogram > 0
        ? SignalType.buy
        : histogram < 0
            ? SignalType.sell
            : SignalType.neutral;

    final desc = histogram > 0
        ? 'MACD çizgisi sinyal üzerinde (+${fmtNum(histogram, digits: 2)})'
        : histogram < 0
            ? 'MACD çizgisi sinyal altında (${fmtNum(histogram, digits: 2)})'
            : 'Kesişim noktasında';

    return TechnicalIndicator(
        name: label, value: histogram, signal: signal, description: desc);
  }

  // ── 3. Bollinger Bantları ─────────────────────────────────────────────────

  static TechnicalIndicator bollingerBands(
      List<double> prices, AssetType type,
      {GostergeAyari? par}) {
    final period = par?['periyot'] ?? (type == AssetType.altin ? 14 : 20);
    final mult = type == AssetType.doviz ? 1.5 : 2.0;
    final label = 'Bollinger ($period, $multσ)';

    if (prices.length < period) {
      return TechnicalIndicator(
          name: label,
          value: 50,
          signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final recent = prices.sublist(prices.length - period);
    final sma = recent.reduce((a, b) => a + b) / period;
    final variance =
        recent.map((p) => pow(p - sma, 2)).reduce((a, b) => a + b) / period;
    final stdDev = sqrt(variance);
    final upper = sma + stdDev * mult;
    final lower = sma - stdDev * mult;
    final current = prices.last;

    final pctB =
        (upper - lower) > 0 ? (current - lower) / (upper - lower) : 0.5;

    final signal = current < lower
        ? SignalType.buy
        : current > upper
            ? SignalType.sell
            : SignalType.neutral;

    final desc = current < lower
        ? 'Alt bantın altında: potansiyel dönüş'
        : current > upper
            ? 'Üst bantın üzerinde: potansiyel düzeltme'
            : '%B: ${fmtNum(pctB * 100, digits: 0)} (bant içi)';

    return TechnicalIndicator(
        name: label, value: pctB * 100, signal: signal, description: desc);
  }

  // ── 4. Hareketli Ortalama (EMA Kesişimi) ─────────────────────────────────

  static TechnicalIndicator movingAverage(List<double> prices, AssetType type,
      {GostergeAyari? par}) {
    int shortP, longP;
    if (type == AssetType.hisse) {
      shortP = 20;
      longP = 50;
    } else if (type.fiyatlamaTuru == AssetType.fon) {
      shortP = 10;
      longP = 30;
    } else if (type == AssetType.altin) {
      shortP = 14;
      longP = 40;
    } else if (type == AssetType.doviz) {
      shortP = 7;
      longP = 21;
    } else {
      shortP = 20;
      longP = 50;
    }
    shortP = par?['kisa'] ?? shortP;
    longP = par?['uzun'] ?? longP;
    final label = 'EMA Kesişim ($shortP/$longP)';

    if (prices.length < longP) {
      return TechnicalIndicator(
          name: label,
          value: 0,
          signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final shortEma = _ema(prices, shortP);
    final longEma = _ema(prices, longP);
    final current = prices.last;
    final diff = ((shortEma - longEma) / longEma * 100);

    final signal = shortEma > longEma && current > shortEma
        ? SignalType.buy
        : shortEma < longEma && current < shortEma
            ? SignalType.sell
            : SignalType.neutral;

    // Açıklama SİNYALLE aynı şeyi söylemeli. Sinyal iki koşul ister
    // (ortalamaların sırası + fiyatın kısa ortalamanın doğru tarafında);
    // açıklama yalnız ilkine bakıyordu: panelde "NÖTR" rozetinin yanında
    // "EMA20 > EMA50 — yükseliş trendi" yazıyordu (2026-09-29 emülatör
    // testi #31). Hesap değişmedi; teyitsiz durum adıyla söylenir.
    // TS portu (`supabase/functions/_shared/technical_analysis.ts`) ile
    // birebir — altın vektörler (`ta_golden_vectors`) ikisini de bağlar.
    final desc = signal == SignalType.buy
        ? 'EMA$shortP > EMA$longP: yükseliş trendi'
        : signal == SignalType.sell
            ? 'EMA$shortP < EMA$longP: düşüş trendi'
            : shortEma > longEma
                ? 'EMA$shortP > EMA$longP, fiyat EMA$shortP altında, teyit yok'
                : shortEma < longEma
                    ? 'EMA$shortP < EMA$longP, fiyat EMA$shortP üstünde, teyit yok'
                    : 'Ortalamalarda kesişim bölgesi';

    return TechnicalIndicator(
        name: label, value: diff, signal: signal, description: desc);
  }

  // ── 5. Stokastik Osilatör ─────────────────────────────────────────────────

  static TechnicalIndicator stochastic(List<double> prices, AssetType type,
      {GostergeAyari? par}) {
    final period = par?['periyot'] ?? (type == AssetType.doviz ? 9 : 14);
    const overbought = 80.0;
    const oversold = 20.0;
    final label = 'Stokastik %K ($period)';

    if (prices.length < period) {
      return TechnicalIndicator(
          name: label,
          value: 50,
          signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final recent = prices.sublist(prices.length - period);
    final lowest = recent.reduce((a, b) => a < b ? a : b);
    final highest = recent.reduce((a, b) => a > b ? a : b);
    final current = prices.last;
    final range = highest - lowest;
    final k = range == 0 ? 50.0 : ((current - lowest) / range) * 100;

    final signal = k < oversold
        ? SignalType.buy
        : k > overbought
            ? SignalType.sell
            : SignalType.neutral;

    final desc = k < oversold
        ? 'Aşırı satım (%K: ${fmtNum(k, digits: 1)})'
        : k > overbought
            ? 'Aşırı alım (%K: ${fmtNum(k, digits: 1)})'
            : 'Nötr bölge (%K: ${fmtNum(k, digits: 1)})';

    return TechnicalIndicator(
        name: label, value: k, signal: signal, description: desc);
  }

  // ── 6. ADX — trend gücü (PREMIUM) ─────────────────────────────────────────
  //
  // Basitleştirilmiş ADX: |ΔP| ortalamasının fiyat range'ine oranı. Klasik ADX
  // için OHLC gerekli; bizde sadece close var — proxy hesap kullanılır.

  static TechnicalIndicator adx(List<double> prices, AssetType type,
      {GostergeAyari? par}) {
    final period = par?['periyot'] ?? 14;
    final label = 'ADX ($period)';

    if (prices.length < period + 1) {
      return TechnicalIndicator(
          name: label,
          value: 0,
          signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final recent = prices.sublist(prices.length - period - 1);
    double sumUp = 0, sumDown = 0, sumRange = 0;
    for (int i = 1; i < recent.length; i++) {
      final d = recent[i] - recent[i - 1];
      if (d > 0) {
        sumUp += d;
      } else {
        sumDown -= d;
      }
      sumRange += d.abs();
    }
    if (sumRange == 0) {
      return TechnicalIndicator(
          name: label,
          value: 0,
          signal: SignalType.neutral,
          description: 'Yatay (trend yok)');
    }
    final directional = ((sumUp - sumDown).abs() / sumRange) * 100;

    final signal = directional > 25
        ? (sumUp > sumDown ? SignalType.buy : SignalType.sell)
        : SignalType.neutral;

    final desc = directional > 40
        ? 'Güçlü trend (${fmtNum(directional, digits: 0)})'
        : directional > 25
            ? 'Trend başlıyor (${fmtNum(directional, digits: 0)})'
            : 'Zayıf trend (${fmtNum(directional, digits: 0)})';

    return TechnicalIndicator(
        name: label, value: directional, signal: signal, description: desc);
  }

  // ── 7. Williams %R — aşırı alım/satım osilatörü (PREMIUM) ─────────────────

  static TechnicalIndicator williamsR(List<double> prices, AssetType type,
      {GostergeAyari? par}) {
    final period = par?['periyot'] ?? 14;
    final label = 'Williams %R ($period)';

    if (prices.length < period) {
      return TechnicalIndicator(
          name: label,
          value: -50,
          signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final recent = prices.sublist(prices.length - period);
    final highest = recent.reduce((a, b) => a > b ? a : b);
    final lowest = recent.reduce((a, b) => a < b ? a : b);
    final current = prices.last;
    final range = highest - lowest;
    final wr = range == 0 ? -50.0 : ((highest - current) / range) * -100;

    final signal = wr < -80
        ? SignalType.buy
        : wr > -20
            ? SignalType.sell
            : SignalType.neutral;

    final desc = wr < -80
        ? 'Aşırı satım (${fmtNum(wr, digits: 0)})'
        : wr > -20
            ? 'Aşırı alım (${fmtNum(wr, digits: 0)})'
            : 'Nötr bölge (${fmtNum(wr, digits: 0)})';

    return TechnicalIndicator(
        name: label, value: wr, signal: signal, description: desc);
  }

  // ── 8. CCI (Commodity Channel Index) (PREMIUM) ────────────────────────────

  static TechnicalIndicator cci(List<double> prices, AssetType type,
      {GostergeAyari? par}) {
    final period = par?['periyot'] ?? 20;
    final label = 'CCI ($period)';

    if (prices.length < period) {
      return TechnicalIndicator(
          name: label,
          value: 0,
          signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final recent = prices.sublist(prices.length - period);
    final sma = recent.reduce((a, b) => a + b) / period;
    final meanDev =
        recent.map((p) => (p - sma).abs()).reduce((a, b) => a + b) / period;
    final current = prices.last;
    final value = meanDev == 0 ? 0.0 : (current - sma) / (0.015 * meanDev);

    final signal = value < -100
        ? SignalType.buy
        : value > 100
            ? SignalType.sell
            : SignalType.neutral;

    final desc = value < -100
        ? 'Aşırı satım (${fmtNum(value, digits: 0)})'
        : value > 100
            ? 'Aşırı alım (${fmtNum(value, digits: 0)})'
            : 'Nötr bölge (${fmtNum(value, digits: 0)})';

    return TechnicalIndicator(
        name: label, value: value, signal: signal, description: desc);
  }

  // ── Ana analiz fonksiyonu ─────────────────────────────────────────────────

  /// [priceHistory]: gerçek fiyat geçmişi (eski→yeni sıralı). Boşsa simülasyon.
  /// [enabledIds]: null ise varsayılan set (temel 5). Aksi halde bu set'teki
  /// göstergeler hesaplanır; [izinli] dışındakiler atlanır (bkz.
  /// [IndicatorId.izinli]). [parametreler]: Premium'da kullanıcının
  /// gösterge ayarları (bkz. [GostergeParametreleri]); null = varsayılan.
  static List<TechnicalIndicator> analyze(
    Asset asset,
    List<double> priceHistory, {
    Set<String>? enabledIds,
    Set<String>? izinli,
    Map<String, GostergeAyari>? parametreler,

    /// Fiyat geçmişi boşken UYDURMA seri üretilsin mi? Varsayılan `false`.
    /// Yalnızca demo/önizleme yüzeyleri için `true` verilmeli — gerçek
    /// sinyal üreten hiçbir yol bunu açmamalı.
    bool allowSimulation = false,
  }) {
    // ⚠️ SİMÜLASYONA DÜŞME — yalnızca AÇIKÇA istendiğinde.
    //
    // Burada eskiden koşulsuz `priceHistory.isNotEmpty ? ... : _simulate(asset)`
    // vardı. `_simulate` `Random` ile UYDURMA fiyat üretir; boş liste veren
    // her çağıran farkında olmadan sahte veriden sinyal hesaplıyordu.
    // İki gerçek çağıran da (`asset_detail_screen` paneli ve
    // `signal_provider.analyzePortfolio`) `const []` geçiyordu — yani
    // ekrandaki sinyal ve DB'ye yazılan sinyal rastgeleydi. Sunucudan gelen
    // push ise GERÇEK piyasa serisinden üretildiği için ikisi çelişiyordu:
    // push "yukarı yönlü" derken ekran "SAT" gösteriyordu (2026-08-31).
    //
    // Artık varsayılan davranış: veri yoksa BOŞ liste döndür (sinyal yok).
    // Sunucu tarafındaki kural da budur — bkz. `technical_analysis_test.ts`
    // → "fiyat geçmişi yoksa sinyal üretilmez (simülasyona düşmez)".
    if (priceHistory.isEmpty && !allowSimulation) return const [];
    final prices = priceHistory.isNotEmpty ? priceHistory : _simulate(asset);
    return analyzeSeries(
      prices,
      asset.type,
      enabledIds: enabledIds,
      izinli: izinli,
      parametreler: parametreler,
    );
  }

  /// Göstergeleri YALNIZCA fiyat serisi + varlık türünden hesaplar.
  ///
  /// [analyze] ile aynı matematik; farkı bir [Asset] İSTEMEMESİ. Göstergelerin
  /// hiçbiri miktar, alış fiyatı veya alış tarihi kullanmaz — yalnızca kapanış
  /// serisini ve eşikleri belirleyen türü okurlar. [analyze] zaten bu metoda
  /// devrediyor, yani iki yüzey tek koddan besleniyor.
  ///
  /// Bu ayrım takip listesi için gerekli: izlenen varlığın `Asset`'i YOKTUR
  /// (miktarı ve maliyeti yoktur). Sahte bir `Asset` üretmek, o nesnenin
  /// yanlışlıkla bir portföy toplamına girmesi riskini doğururdu — bkz.
  /// `watchlist_isolation_test.dart`.
  ///
  /// Boş seride boş liste döner: uydurma veriden gösterge üretilmez.
  static List<TechnicalIndicator> analyzeSeries(
    List<double> prices,
    AssetType type, {
    Set<String>? enabledIds,
    Set<String>? izinli,
    Map<String, GostergeAyari>? parametreler,
  }) {
    if (prices.isEmpty) return const [];
    final ids = enabledIds ?? defaultEnabledFor(type);
    // Varsayılan: paywall kapalı kümesi (ileri üçü hesaplanmaz).
    final izin = izinli ?? IndicatorId.izinli(paywall: false, premium: false);

    final result = <TechnicalIndicator>[];
    for (final id in ids) {
      if (!izin.contains(id)) continue;
      final ind = _computeById(id, prices, type,
          GostergeParametreleri.dogrula(id, parametreler?[id]));
      if (ind != null) result.add(ind);
    }
    return result;
  }

  static TechnicalIndicator? _computeById(
      String id, List<double> prices, AssetType type, GostergeAyari? par) {
    switch (id) {
      case IndicatorId.rsi:
        return rsi(prices, type, par: par);
      case IndicatorId.macd:
        return macd(prices, type, par: par);
      case IndicatorId.bollinger:
        return bollingerBands(prices, type, par: par);
      case IndicatorId.ema:
        return movingAverage(prices, type, par: par);
      case IndicatorId.stochastic:
        return stochastic(prices, type, par: par);
      case IndicatorId.adx:
        return adx(prices, type, par: par);
      case IndicatorId.williamsR:
        return williamsR(prices, type, par: par);
      case IndicatorId.cci:
        return cci(prices, type, par: par);
    }
    return null;
  }

  /// Her varlık türü için varsayılan aktif göstergeler.
  static Set<String> defaultEnabledFor(AssetType type) {
    return <String>{
      IndicatorId.rsi,
      IndicatorId.macd,
      IndicatorId.bollinger,
      IndicatorId.ema,
      IndicatorId.stochastic,
    };
  }

  // ── Simülasyon (fiyat geçmişi yoksa) ──────────────────────────────────────

  static List<double> _simulate(Asset asset, {int days = 120}) {
    final today = DateTime.now();
    final seed = asset.ticker.hashCode.abs() ^
        (today.year * 10000 + today.month * 100 + today.day);
    final rng = Random(seed);

    final price = asset.currentPrice > 0 ? asset.currentPrice : 100.0;

    final vol = switch (asset.type) {
      AssetType.hisse => 0.022,
      AssetType.fon => 0.010,
      AssetType.altin => 0.013,
      AssetType.doviz => 0.007,
      _ => 0.018,
    };

    final dirSeed = rng.nextDouble();
    final double drift;
    if (dirSeed < 0.40) {
      drift = 0.003;
    } else if (dirSeed < 0.70) {
      drift = -0.003;
    } else {
      drift = 0.0;
    }

    final prices = <double>[];
    double p = price * pow(1 - drift, days).toDouble();
    for (int i = 0; i < days; i++) {
      prices.add(p);
      final noise = (rng.nextDouble() - 0.5) * vol;
      p = (p * (1 + drift + noise)).clamp(price * 0.3, price * 3.0);
    }

    if (prices.isNotEmpty && prices.last != 0) {
      final factor = price / prices.last;
      return prices.map((v) => v * factor).toList();
    }
    return prices;
  }

  /// Genel sinyal özeti. Toplam gösterge sayısı değişken olduğundan eşik
  /// oransal hesaplanır (%60+ buy → BUY).
  ///
  /// [confidence] **0-100 ölçeğindedir** (oran değil). Kullanıcının seçtiği
  /// eşikler de yüzdedir (50/70/85), karşılaştırma aynı ölçekte olmalı.
  ///
  /// Not: bu değer önceden 0..1 oranı dönüyordu ve `signal_provider`
  /// içindeki `confidence < threshold` kontrolü her zaman doğru oluyordu —
  /// yani hiçbir sinyal eşiği geçemiyor, push hiç gönderilmiyordu.
  static ({SignalType signal, int buyCount, int sellCount, double confidence})
      summarize(List<TechnicalIndicator> indicators) {
    final buy = indicators.where((i) => i.signal == SignalType.buy).length;
    final sell = indicators.where((i) => i.signal == SignalType.sell).length;
    final total = indicators.length;

    if (total == 0) {
      return (
        signal: SignalType.neutral,
        buyCount: 0,
        sellCount: 0,
        confidence: 0.0
      );
    }
    final buyRatio = buy / total;
    final sellRatio = sell / total;

    final signal = buyRatio >= 0.6
        ? SignalType.buy
        : sellRatio >= 0.6
            ? SignalType.sell
            : SignalType.neutral;

    final confidence = max(buyRatio, sellRatio) * 100;

    return (
      signal: signal,
      buyCount: buy,
      sellCount: sell,
      confidence: confidence
    );
  }
}
