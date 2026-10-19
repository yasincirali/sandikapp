/// Zirvedeki Portföyler — SAF hesap ve cümle katmanı.
///
/// Ekran (`zirve_portfoyler_screen.dart`) ve kart (`zirve_karti.dart`)
/// sayıyı tek başına göstermez; her sayının yanında sıradan birinin
/// anlayacağı bir cümle vardır (kullanıcı kararı 2026-09-29: "normal biri
/// baktığında anlaşılabilir ifadelerle"). Cümleler burada üretilir ki
/// widget testi olmadan sınanabilsin ve iki yüzey aynı dili konuşsun.
///
/// ## Dil kuralları
/// 1. Getiri fiille söylenir: "%2,7 kazandı", "%6,4 kaybetti". ROI, Δ,
///    "p" gibi kısaltma yok; "puan" yalnızca iki yüzde arasındaki fark için.
/// 2. Dağılım önce cümle: "çoğunlukla altın, yanında kripto ve hisse".
///    Yüzdeler şeridin altında küçük.
/// 3. Fark bir yön ve bir tür olarak söylenir: "Sen fona ağırlık vermişsin,
///    zirve altına." Puanı isteyen ayrıntıya dokunur.
/// 4. Dağılım farkı iyi ya da kötü DEĞİLDİR — bu katman fark için renk
///    üretmez; renk yalnızca getiride (kazanç/kayıp).
///
/// ## Anonimlik
/// Sunucudan gelen: sıra, getiri, tür payı ve fon türünde TEFAS kodu
/// bazında pay (`zirve_portfoyleri`, 0084). Fon kodu kamuya açık bir
/// kimliktir; kullanıcının yazdığı ad/not taşınmaz, %1 altı fonlar "diğer"de
/// toplanır (kullanıcı kararı 2026-09-29). Hisse ve diğer varlıkların
/// sembolü, tutar, miktar ve kimlik hiç üretilmez.
library;

import '../utils/tr_format.dart';
import '../models/asset_categories.dart' show goldTickerMap;

/// Sunucunun snapshot aldığı dönemlerden ekranda sunulanlar.
///
/// Sunucu 7/30/180/365 gün tutar (`leaderboard-snapshot` `DONEMLER`);
/// ekran üçünü sunar (kullanıcı kararı 2026-09-29: "1 haftalık, aylık ve
/// yıllık"). 180 sunulmaz — seçici üç durakla okunur kalıyor.
enum ZirveDonem {
  hafta(7, '1H', 'Bu hafta', 'haftalık'),
  ay(30, '1A', 'Bu ay', 'aylık'),
  yil(365, '1Y', 'Bu yıl', 'yıllık');

  const ZirveDonem(this.gun, this.kisa, this.ad, this.sifat);

  /// Sunucu dönemi (`p_period_days`).
  final int gun;

  /// Seçici etiketi.
  final String kisa;

  /// Cümle başı: "Bu ay zirvedeki portföy…".
  final String ad;

  /// Alt başlık: "aylık · anonim".
  final String sifat;

  /// Performans seçicisinin (GÜNLÜK · 1H · 1A · 3A · 6A · 1Y · 5Y) gün
  /// sayısını en yakın zirve dönemine eşler. GÜNLÜK (0) → hafta; 3A → ay;
  /// 6A ve 5Y → yıl. Kart Performans'ın dönemini izler, ekran o dönemle
  /// açılır; kullanıcı orada değiştirebilir.
  static ZirveDonem yakin(int gun) {
    if (gun <= 7) return hafta;
    if (gun <= 90) return ay;
    return yil;
  }
}

/// Cetvel üzerindeki bir işaret: zirvedeki bir portföy ya da kullanıcı.
class ZirveIsaret {
  const ZirveIsaret({
    required this.anahtar,
    required this.etiket,
    required this.roi,
    this.sira,
    this.sen = false,
  });

  /// Seçim anahtarı ('1', '2', '3' ya da `ZirveKiyas.senAnahtari`).
  final String anahtar;

  /// Kısa etiket: "1." / "Sen".
  final String etiket;
  final double roi;

  /// Zirvedeki sıra (1 tabanlı); kullanıcı işaretinde null.
  final int? sira;
  final bool sen;
}

/// Eksen aralığı: sıfır daima içinde, iki uçta pay var.
/// Çağıranın Zirve şartlarının dolacağı anlar (0144 `zirve_katilim_durumum`).
/// Tarihler UTC; null → o şartın verisi yok (ör. hiç varlık yok).
typedef ZirveKatilimDurumu = ({
  DateTime? hesapHazir,
  DateTime? varlikHazir,
  DateTime? olcumHazir,
  int? varlikSayisi,
  bool olculdu,
  bool havuzda,
});

/// Ekrandaki bir şart satırı. [tamam] ikon ŞEKLİYLE de söylenir (renk
/// körlüğü, HIG): yalnız renge yüklenmez.
typedef ZirveSarti = ({String metin, bool tamam});

typedef ZirveEksen = ({double lo, double hi});

abstract final class ZirveKiyas {
  static const senAnahtari = 'sen';

  /// Havuz eşiği — sunucudaki `k_min` (0031/0059). Boş durum metni bunu
  /// "8 olunca zirve belli olur" diye söyler.
  static const havuzEsigi = 8;

  /// Tür anahtarı (`AssetType.name`) → küçük harf ad. Cümle içinde geçer;
  /// başlıklarda `AssetType.labelOf` kullanılır.
  static const _turAdi = {
    'altin': 'altın',
    'hisse': 'hisse',
    'fon': 'fon',
    'doviz': 'döviz',
    'emtia': 'emtia',
    'kripto': 'kripto',
  };

  /// Yönelme hâli ("altına ağırlık vermiş"). Ünlü uyumu tabloda; bilinmeyen
  /// tür için "-'a/-'e" tahmini yerine ad + "'a" (kesme) yazılır ki cümle
  /// bozulmasın.
  static const _turYonelme = {
    'altin': 'altına',
    'hisse': 'hisseye',
    'fon': 'fona',
    'doviz': 'dövize',
    'emtia': 'emtiaya',
    'kripto': 'kriptoya',
  };

  static String turAd(String anahtar) => _turAdi[anahtar] ?? anahtar;

  static String turYonelme(String anahtar) =>
      _turYonelme[anahtar] ?? "${turAd(anahtar)}'a";

  /// "%2,7" — işaretsiz, bir ondalık, Türkçe virgül.
  static String yuzde(double v) => '%${fmtNum(v.abs(), digits: 1)}';

  /// "+%2,7" / "−%6,4" — hücrelerde büyük sayı.
  static String isaretliYuzde(double v) {
    if (v.abs() < 0.05) return '%0,0';
    return '${v < 0 ? '−' : '+'}${yuzde(v)}';
  }

  /// "%2,7 kazandı" / "%6,4 kaybetti" / "yerinde saydı".
  static String getiriParcasi(double v) {
    if (v.abs() < 0.05) return 'yerinde saydı';
    return '${yuzde(v)} ${v > 0 ? 'kazandı' : 'kaybetti'}';
  }

  /// Ekranın ilk cümlesi.
  ///
  /// "Bu ay zirvedeki portföy %2,7 kazandı; seninki %6,4 kaybetti. Zirveye
  /// 9,1 puan uzaksın." Kullanıcının getirisi yoksa (yeni portföy, seri
  /// alınamadı) ikinci yarı dürüstçe söylenir; uydurma sayı yok.
  ///
  /// [benSira]: kullanıcı zirve satırlarından birindeyse sırası (sunucu
  /// `ben` işareti, 0085). 1 ise zirvedeki portföy onun.
  static String getiriCumlesi({
    required ZirveDonem donem,
    required double zirveRoi,
    required double? senRoi,
    int? benSira,
  }) {
    if (benSira == 1) {
      return '${donem.ad} zirvedeki portföy senin: ${getiriParcasi(zirveRoi)}.';
    }
    final bas = '${donem.ad} zirvedeki portföy ${getiriParcasi(zirveRoi)}';
    if (benSira != null && senRoi != null) {
      return '$bas; seninki ${getiriParcasi(senRoi)} ve zirvede $benSira. '
          'sıradasın. ${mesafeCumlesi(senRoi: senRoi, zirveRoi: zirveRoi)}';
    }
    if (senRoi == null) {
      return '$bas. Senin bu dönem getirin henüz hesaplanamıyor.';
    }
    return '$bas; seninki ${getiriParcasi(senRoi)}. '
        '${mesafeCumlesi(senRoi: senRoi, zirveRoi: zirveRoi)}';
  }

  /// "Zirveye 9,1 puan uzaksın." / "Zirvenin 2,3 puan önündesin." /
  /// "Aranızda fark yok."
  static String mesafeCumlesi({
    required double senRoi,
    required double zirveRoi,
  }) {
    final fark = senRoi - zirveRoi;
    if (fark.abs() < 0.05) return 'Aranızda fark yok.';
    final puan = fmtNum(fark.abs(), digits: 1);
    return fark > 0
        ? 'Zirvenin $puan puan önündesin.'
        : 'Zirveye $puan puan uzaksın.';
  }

  /// Kullanıcı zirve listesine girseydi kaçıncı olurdu: 1 + kendisinden
  /// iyi olan zirve sayısı. Getirisi yoksa null.
  static int? sira({
    required double? senRoi,
    required Iterable<double> zirveRoileri,
  }) {
    if (senRoi == null) return null;
    return 1 + zirveRoileri.where((z) => z > senRoi).length;
  }

  /// Hücre alt satırı: "Zirvenin önündesin." / "Zirvede 2. olurdun." /
  /// "Zirvedeki 3 portföyün gerisindesin."
  static String konumCumlesi({
    required double? senRoi,
    required List<double> zirveRoileri,
    int? benSira,
  }) {
    if (benSira == 1) return 'Zirvenin tepesindesin';
    if (benSira != null) return 'Zirvede $benSira. sıradasın';
    final s = sira(senRoi: senRoi, zirveRoileri: zirveRoileri);
    if (s == null) return 'Getirin henüz yok';
    if (s == 1) return 'Zirvenin önündesin';
    if (s <= zirveRoileri.length) return 'Zirvede $s. olurdun';
    return 'Zirvedeki ${zirveRoileri.length} portföyün gerisindesin';
  }

  /// Payları büyükten küçüğe; %0,5 altı gürültü sayılır ve düşer.
  static List<({String tur, double pay})> sirali(Map<String, double> pay) {
    final l = [
      for (final e in pay.entries)
        if (e.value > 0.5) (tur: e.key, pay: e.value),
    ]..sort((a, b) => b.pay.compareTo(a.pay));
    return l;
  }

  /// "Bu portföy çoğunlukla altın (%56), yanında kripto ve hisse."
  ///
  /// Üç kalıp: ≥%75 "neredeyse tamamen", ≥%50 "çoğunlukla", altı "X ve Y
  /// arasında dengeli". Kullanıcı için özne "Senin portföyün".
  static String dagilimCumlesi(Map<String, double> pay, {required bool sen}) {
    final s = sirali(pay);
    if (s.isEmpty) return sen ? 'Portföyün şu an boş.' : 'Dağılım bilgisi yok.';
    final ozne = sen ? 'Senin portföyün' : 'Bu portföy';
    final ilk = s[0];
    final r0 = ilk.pay.round();
    if (ilk.pay >= 75) {
      final kalan = s.length > 1 ? ', kalanı ${turAd(s[1].tur)}.' : '.';
      return '$ozne neredeyse tamamen ${turAd(ilk.tur)} (%$r0)$kalan';
    }
    if (ilk.pay >= 50) {
      final yan = s.skip(1).take(2).map((e) => turAd(e.tur)).toList();
      final kuyruk = yan.isEmpty ? '.' : ', yanında ${yan.join(' ve ')}.';
      return '$ozne çoğunlukla ${turAd(ilk.tur)} (%$r0)$kuyruk';
    }
    final ikinci = s.length > 1 ? turAd(s[1].tur) : null;
    final ucuncu = s.length > 2 ? ', biraz ${turAd(s[2].tur)}.' : '.';
    if (ikinci == null) return '$ozne tamamen ${turAd(ilk.tur)}.';
    return '$ozne ${turAd(ilk.tur)} ve $ikinci arasında dengeli$ucuncu';
  }

  /// "Sen fona ağırlık vermişsin, zirve altına."
  ///
  /// [zirveAd] cümledeki özne: 1. için "zirve", ötekiler için "2. portföy".
  static String farkCumlesi({
    required Map<String, double> senPay,
    required Map<String, double> zirvePay,
    required String zirveAd,
  }) {
    final s = sirali(senPay);
    final z = sirali(zirvePay);
    if (s.isEmpty) return 'Portföyün boş; kıyas için önce varlık ekle.';
    if (z.isEmpty) return 'Bu portföyün dağılım bilgisi yok.';
    if (s[0].tur == z[0].tur) {
      final tekTur = s.length == 1 && z.length == 1;
      return 'İkiniz de ${turYonelme(s[0].tur)} ağırlık vermişsiniz'
          '${tekTur ? '.' : '; fark kalan kısımda.'}';
    }
    return 'Sen ${turYonelme(s[0].tur)} ağırlık vermişsin, '
        '$zirveAd ${turYonelme(z[0].tur)}.';
  }

  /// İki dağılım arasında en çok ayrışan tür (mutlak puan farkı).
  /// Ayrıntı sayfasındaki "En büyük fark altın: sende %18, onda %56."
  static ({String tur, double sen, double zirve})? enBuyukFark(
    Map<String, double> senPay,
    Map<String, double> zirvePay,
  ) {
    final turler = {...senPay.keys, ...zirvePay.keys};
    ({String tur, double sen, double zirve})? en;
    var enFark = -1.0;
    for (final t in turler) {
      final s = senPay[t] ?? 0;
      final z = zirvePay[t] ?? 0;
      final f = (s - z).abs();
      if (f > enFark) {
        enFark = f;
        en = (tur: t, sen: s, zirve: z);
      }
    }
    return en;
  }

  /// "En büyük fark altın: sende %18, onda %56."
  static String enBuyukFarkCumlesi(
    Map<String, double> senPay,
    Map<String, double> zirvePay,
  ) {
    final f = enBuyukFark(senPay, zirvePay);
    if (f == null) return '';
    return 'En büyük fark ${turAd(f.tur)}: sende %${f.sen.round()}, '
        'onda %${f.zirve.round()}.';
  }

  // ── Fon kırılımı (0084) ────────────────────────────────────────────────

  /// Toplu kalem anahtarı: kodsuz/serbest metin ya da %1 altı fonlar.
  static const fonDiger = 'DIGER';

  /// Payı bunun altındaki fon adıyla yazılmaz (sunucu `FON_ESIGI_PCT`).
  static const fonEsigiPct = 1.0;

  static final _tefasKodu = RegExp(r'^[A-Z0-9]{3}$');

  /// Varlığın ticker'ından TEFAS kodu; kalıba uymayan her şey [fonDiger].
  /// Sunucudaki `fonDetayi` ile AYNI kural — "Sen" satırı zirveyle aynı
  /// ölçüyle okunsun.
  static String fonAnahtari(String? ticker) {
    final kod = (ticker ?? '').trim().toUpperCase().replaceFirst('TEFAS:', '');
    return _tefasKodu.hasMatch(kod) ? kod : fonDiger;
  }

  /// {kod: TL değeri} + portföy toplamı → {kod: toplamın %'si}, 1 ondalık;
  /// eşik altı ve kodsuzlar [fonDiger]'de.
  static Map<String, double> fonDetayiTopla(
      Map<String, double> kodDegeri, double toplam) {
    if (toplam <= 0) return const {};
    final out = <String, double>{};
    var diger = 0.0;
    for (final e in kodDegeri.entries) {
      final pct = e.value / toplam * 100;
      if (e.key == fonDiger || pct < fonEsigiPct) {
        diger += pct;
        continue;
      }
      out[e.key] = (pct * 10).round() / 10;
    }
    final d = (diger * 10).round() / 10;
    if (d > 0) out[fonDiger] = d;
    return out;
  }

  /// Büyükten küçüğe; [fonDiger] her zaman en sonda.
  static List<({String kod, double pay})> fonSirali(Map<String, double> d) {
    final l = [
      for (final e in d.entries)
        if (e.value > 0 && e.key != fonDiger) (kod: e.key, pay: e.value),
    ]..sort((a, b) => b.pay.compareTo(a.pay));
    final diger = d[fonDiger];
    if (diger != null && diger > 0) l.add((kod: fonDiger, pay: diger));
    return l;
  }

  /// "AFT %12 · TTE %16 · diğer %1" — seçili portföy bloğunun tek satırı.
  static String fonOzeti(Map<String, double> d, {int enFazla = 4}) {
    final s = fonSirali(d);
    if (s.isEmpty) return '';
    final gorunen = s.where((e) => e.kod != fonDiger).take(enFazla).toList();
    final kalan = s.fold<double>(0, (t, e) => t + e.pay) -
        gorunen.fold<double>(0, (t, e) => t + e.pay);
    final parca = [
      for (final e in gorunen) '${e.kod} %${_payYazisi(e.pay)}',
      if (kalan >= 0.05) 'diğer %${_payYazisi(kalan)}',
    ];
    return parca.join(' · ');
  }

  static String _payYazisi(double v) =>
      fmtNum(v, digits: v < 10 ? 1 : 0);

  // ── Varlık kırılımı (0158) ─────────────────────────────────────────────

  /// Sunucu vitrininde gizlenen kodun öneki (`?1`, `?2`… — 0158
  /// `zirve_detay_maske`). Gerçek sembol hiçbir zaman `?` ile başlamaz.
  static bool kilitliMi(String kod) => kod.startsWith('?');

  static final _piyasaSembolu = RegExp(r'^[A-Z0-9.=_:-]{1,20}$');

  static bool mevduatMi(String? ticker) =>
      (ticker ?? '').trim().toUpperCase().startsWith('MEVDUAT:');

  /// Fon dışı varlığın gösterilebilir sembolü; sunucudaki `piyasaSembolu`
  /// ile aynı kalıp. Altında kod alt kategoriden (`goldTickerMap`) de
  /// çözülür. Uymayan her şey [fonDiger].
  static String varlikAnahtari(String tur, String? ticker, String? alt) {
    var kod = (ticker ?? '').trim();
    if (tur == 'altin' && !kod.startsWith('ALTIN_') && kod != 'XAUUSD=X') {
      kod = goldTickerMap[(alt ?? '').trim()] ?? '';
    }
    kod = kod.toUpperCase();
    return _piyasaSembolu.hasMatch(kod) ? kod : fonDiger;
  }

  static final _altinAdi = {
    for (final e in goldTickerMap.entries) e.value: e.key,
  };

  /// Sembolün ekranda okunan adı: "THYAO.IS" → "THYAO", "BTCUSDT" → "BTC",
  /// "USDTRY=X" → "USD", "ALTIN_CEYREK" → "Çeyrek Altın". Kilitli kod ve
  /// [fonDiger] için "Diğer".
  static String varlikAdi(String kod) {
    if (kod == fonDiger || kilitliMi(kod)) return 'Diğer';
    final altin = _altinAdi[kod];
    if (altin != null) return altin;
    var k = kod;
    if (k.endsWith('.IS')) k = k.substring(0, k.length - 3);
    final kur = RegExp(r'^([A-Z]{3})TRY=X$').firstMatch(k);
    if (kur != null) return kur.group(1)!;
    for (final son in const ['USDT', 'TRY', 'USD']) {
      if (k.length > son.length + 1 &&
          k.endsWith(son) &&
          !k.contains('.') &&
          !k.contains('=')) {
        return k.substring(0, k.length - son.length);
      }
    }
    if (k.endsWith('=F') || k.endsWith('=X')) k = k.substring(0, k.length - 2);
    return k;
  }

  /// Fon + diğer türlerin kalemleri tek listede, büyükten küçüğe; kilitliler
  /// yerinde kalır (oranları açık), "diğer"ler ayrı toplanır.
  static List<({String tur, String kod, double pay})> tumKalemler(
      Map<String, double> fon, Map<String, Map<String, double>> varlik) {
    final l = [
      for (final e in fon.entries)
        if (e.key != fonDiger && e.value > 0)
          (tur: 'fon', kod: e.key, pay: e.value),
      for (final t in varlik.entries)
        for (final e in t.value.entries)
          if (e.key != fonDiger && e.value > 0)
            (tur: t.key, kod: e.key, pay: e.value),
    ]..sort((a, b) => b.pay.compareTo(a.pay));
    return l;
  }

  /// "THYAO %18 · BTC %12 · •••• %9 · diğer %21" — seçili portföy bloğunun
  /// tek satırı. Kilitli kalem "••••" ile yazılır (sembol cihaza hiç gelmez).
  static String ayrintiOzeti(
      Map<String, double> fon, Map<String, Map<String, double>> varlik,
      {int enFazla = 4}) {
    final l = tumKalemler(fon, varlik);
    if (l.isEmpty) return '';
    final gorunen = l.take(enFazla).toList();
    final toplam = [
      ...fon.values,
      for (final t in varlik.values) ...t.values,
    ].fold<double>(0, (s, v) => s + v);
    final kalan =
        toplam - gorunen.fold<double>(0, (s, e) => s + e.pay);
    final parca = [
      for (final e in gorunen)
        '${kilitliMi(e.kod) ? kilitliYer : (e.tur == 'fon' ? e.kod : varlikAdi(e.kod))} '
            '%${_payYazisi(e.pay)}',
      if (kalan >= 0.05) 'diğer %${_payYazisi(kalan)}',
    ];
    return parca.join(' · ');
  }

  /// Kilitli kalemin yer tutucusu (ekran okuyucu "Premium'da görünür" duyar).
  static const kilitliYer = '••••';

  /// İki portföyün ortak açık kalemleri, ortak payı büyükten küçüğe
  /// (benzerlik = Σ min; sunucu `zirve_benzerlik_hesapla` ile aynı kural).
  static List<({String tur, String kod, double sen, double zirve})>
      ortakKalemler({
    required Map<String, double> senFon,
    required Map<String, Map<String, double>> senVarlik,
    required Map<String, double> zirveFon,
    required Map<String, Map<String, double>> zirveVarlik,
  }) {
    Map<String, double> duz(
        Map<String, double> f, Map<String, Map<String, double>> v) => {
          for (final e in f.entries)
            if (e.key != fonDiger) 'fon:${e.key}': e.value,
          for (final t in v.entries)
            for (final e in t.value.entries)
              if (e.key != fonDiger && !kilitliMi(e.key))
                '${t.key}:${e.key}': e.value,
        };
    final a = duz(senFon, senVarlik);
    final b = duz(zirveFon, zirveVarlik);
    final l = [
      for (final k in a.keys)
        if (b.containsKey(k))
          (
            tur: k.substring(0, k.indexOf(':')),
            kod: k.substring(k.indexOf(':') + 1),
            sen: a[k]!,
            zirve: b[k]!,
          ),
    ]..sort((x, y) => (y.sen < y.zirve ? y.sen : y.zirve)
        .compareTo(x.sen < x.zirve ? x.sen : x.zirve));
    return l;
  }

  /// "Seninle %24 benzer: aynı varlıkların ortak payı." / ortak yoksa
  /// "Seninle ortak varlığı yok."
  static String benzerlikCumlesi(double b) => b < 0.05
      ? 'Seninle ortak varlığı yok.'
      : 'Seninle %${_payYazisi(b)} benzer: aynı varlıklarda ortak payınız.';

  /// Σ min(sen, zirve) — [ortakKalemler] üzerinden, 1 ondalık.
  static double benzerlik(
          List<({String tur, String kod, double sen, double zirve})> ortak) =>
      (ortak.fold<double>(
                  0, (s, e) => s + (e.sen < e.zirve ? e.sen : e.zirve)) *
              10)
          .round() /
      10;

  /// Ayna kıyasındaki fon satırlarının sırası: iki taraftaki kodların
  /// birleşimi, büyük olan payına göre büyükten küçüğe; [fonDiger] sonda.
  static List<String> fonKiyasSirasi(
      Map<String, double> sen, Map<String, double> zirve) {
    double enBuyuk(String k) {
      final a = sen[k] ?? 0;
      final b = zirve[k] ?? 0;
      return a > b ? a : b;
    }

    final l = {...sen.keys, ...zirve.keys}
        .where((k) => k != fonDiger && enBuyuk(k) > 0)
        .toList()
      ..sort((a, b) => enBuyuk(b).compareTo(enBuyuk(a)));
    if (enBuyuk(fonDiger) > 0) l.add(fonDiger);
    return l;
  }

  /// "Getiride o 6,1 puan önde." / "Getiride sen 2,0 puan öndesin." /
  /// "Getiride başa baş." Kullanıcının getirisi yoksa boş.
  static String getiriFarkiCumlesi({
    required double? senRoi,
    required double zirveRoi,
  }) {
    if (senRoi == null) return '';
    final fark = zirveRoi - senRoi;
    if (fark.abs() < 0.05) return 'Getiride başa baş.';
    final puan = fmtNum(fark.abs(), digits: 1);
    return fark > 0
        ? 'Getiride o $puan puan önde.'
        : 'Getiride sen $puan puan öndesin.';
  }

  /// Cetvel ekseni: sıfır daima görünür, iki uçta payın %12'si kadar
  /// (en az 0,5 puan) boşluk — uçtaki işaret kenara yapışmasın.
  static ZirveEksen eksen(Iterable<double> degerler) {
    var lo = 0.0;
    var hi = 0.0;
    for (final v in degerler) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final pay = ((hi - lo) * 0.12).clamp(0.5, double.infinity);
    return (lo: lo - pay, hi: hi + pay);
  }

  /// Çakışan işaretleri katlara ayırır.
  ///
  /// [konumlar] 0–1 arası eksen oranları (giriş sırası korunur). Aynı katta
  /// [asgariAralik]'tan yakın iki işaret olamaz; yakın olan bir üst kata
  /// çıkar. Ölçüldü: 2. (−%3,30) ile 3. (−%3,32) aynı noktaya düşüyor —
  /// katsız çizimde biri ötekini örtüyor ve dokunulamıyordu.
  static List<int> katlar(List<double> konumlar, {double asgariAralik = 0.1}) {
    final sira = List<int>.generate(konumlar.length, (i) => i)
      ..sort((a, b) => konumlar[a].compareTo(konumlar[b]));
    final katlar = List<int>.filled(konumlar.length, 0);
    final yerlesen = <({double x, int kat})>[];
    for (final i in sira) {
      var kat = 0;
      while (yerlesen.any(
          (y) => y.kat == kat && (y.x - konumlar[i]).abs() < asgariAralik)) {
        kat++;
      }
      katlar[i] = kat;
      yerlesen.add((x: konumlar[i], kat: kat));
    }
    return katlar;
  }

  // ── Katılım şartları (0144, kullanıcı bulgusu 2026-10-12) ─────────────────
  //
  // yasin eski tarihli varlıklarla üç hesap açtı; havuz artmadı çünkü hesap
  // 7 günlük değildi ve ekran bu şartı hiç söylemiyordu. Havuzda olmayan
  // katılımcı artık şartlarını ve dolacakları günü görür. Kural sunucuda
  // (0091 `zirve_havuzu_uygun`, 0085 `zirve_havuz`, leaderboard-snapshot
  // `donemTwr`); burada yalnız anlatılır.

  /// Türkiye saati (UTC+3, yaz saati yok) — ölçüm saatleri bu saatle yazılır.
  static const _trFark = Duration(hours: 3);

  static const _aylar = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];

  /// Ay adına bulunma eki: "Ekim'de", "Kasım'da", "Mart'ta".
  static const _aylarDe = [
    "Ocak'ta", "Şubat'ta", "Mart'ta", "Nisan'da", "Mayıs'ta", "Haziran'da",
    "Temmuz'da", "Ağustos'ta", "Eylül'de", "Ekim'de", "Kasım'da", "Aralık'ta",
  ];

  /// "19 Ekim'de" — tarih Türkiye saatine göre.
  static String gunde(DateTime an) {
    final tr = an.toUtc().add(_trFark);
    return '${tr.day} ${_aylarDe[tr.month - 1]}';
  }

  /// "19 Ekim" — tarih Türkiye saatine göre.
  static String gun(DateTime an) {
    final tr = an.toUtc().add(_trFark);
    return '${tr.day} ${_aylar[tr.month - 1]}';
  }

  /// Sunucu ölçümü (leaderboard-snapshot cron'u, 0082) 10:00 ve 15:00 TR =
  /// 07:00 ve 12:00 UTC. [an]'dan SONRAKİ ilk ölçüm.
  static DateTime sonrakiOlcum(DateTime an) {
    final u = an.toUtc();
    for (var g = 0; g < 2; g++) {
      for (final saat in const [7, 12]) {
        final t = DateTime.utc(u.year, u.month, u.day + g, saat);
        if (t.isAfter(u)) return t;
      }
    }
    return DateTime.utc(u.year, u.month, u.day + 2, 7);
  }

  /// İlk varlık şartı: 5 günlük varlık (0091) ve asgari ölçüm süresi (0128)
  /// aynı ilk alımdan sayılır; ekranda tek satır, geç dolan tarihle.
  static DateTime? _varlikTarihi(ZirveKatilimDurumu d) {
    final a = d.varlikHazir;
    final b = d.olcumHazir;
    if (a == null || b == null) return a ?? b;
    return a.isAfter(b) ? a : b;
  }

  /// Havuza giriş şartları, kullanıcının okuyacağı sırayla.
  static List<ZirveSarti> katilimSartlari(
    ZirveKatilimDurumu d, {
    required DateTime simdi,
    required int asgariGun,
    required ZirveDonem donem,
  }) {
    bool doldu(DateTime t) => !t.isAfter(simdi);
    final hesap = d.hesapHazir;
    final varlik = _varlikTarihi(d);
    final n = d.varlikSayisi;
    return [
      if (hesap != null)
        doldu(hesap)
            ? (metin: 'Hesabın en az 7 günlük', tamam: true)
            : (
                metin: 'Hesabın en az 7 günlük olmalı · ${gunde(hesap)} tamam',
                tamam: false,
              ),
      if (varlik == null)
        (metin: 'Portföyüne en az bir varlık eklemelisin', tamam: false)
      else if (doldu(varlik))
        (metin: 'İlk varlığını $asgariGun günden önce edinmişsin', tamam: true)
      else
        (
          metin: 'İlk varlığını edinmenin üzerinden $asgariGun gün geçmeli · '
              '${gunde(varlik)} tamam',
          tamam: false,
        ),
      if (n != null && n >= 2)
        (metin: 'En az 2 farklı varlığın var', tamam: true)
      else if (n != null)
        (metin: 'En az 2 farklı varlığın olmalı · şu an $n', tamam: false)
      else
        (
          metin: 'En az 2 farklı varlığın olmalı · ilk ölçümde sayılır',
          tamam: false,
        ),
      d.olculdu
          ? (metin: '${donem.ad} getirin ölçüldü', tamam: true)
          : (
              metin: '${donem.ad} getirin henüz ölçülmedi · ölçüm her gün '
                  '10:00 ve 15:00',
              tamam: false,
            ),
    ];
  }

  /// Şartlar yolunda giderse havuza en erken ne zaman girilir; bilinemiyorsa
  /// (varlık yok, 2'den az varlık) null.
  ///
  /// Hesap ve 5 gün şartı OKUMA anında bakılır (0091): getiri zaten
  /// ölçülüyorsa gün dolunca hemen girer. Asgari ölçüm süresi ise ölçümde
  /// bakılır (`donemTwr`): dolduktan sonraki ilk ölçümde girer.
  static DateTime? tahminiGiris(ZirveKatilimDurumu d, {required DateTime simdi}) {
    final hesap = d.hesapHazir;
    final varlik = d.varlikHazir;
    final olcum = d.olcumHazir;
    if (hesap == null || varlik == null || olcum == null) return null;
    final n = d.varlikSayisi;
    if (n != null && n < 2) return null;
    // Süre dolmuş ama bu dönem ölçülemiyor (ör. fiyatı bilinen gün yok):
    // ne zaman düzeleceği bilinmez, tarih uydurulmaz.
    if (!olcum.isAfter(simdi) && !d.olculdu) return null;
    var giris = olcum.isAfter(simdi) ? sonrakiOlcum(olcum) : simdi;
    for (final t in [hesap, varlik]) {
      if (t.isAfter(giris)) giris = t;
    }
    return giris.isAfter(simdi) ? giris : null;
  }

  /// Kartın özet cümlesi.
  static String girisCumlesi(ZirveKatilimDurumu d, {required DateTime simdi}) {
    final t = tahminiGiris(d, simdi: simdi);
    if (t == null) {
      return 'Eksik şartlar tamamlanınca portföyün havuza kendiliğinden girer.';
    }
    return 'Başka bir şey değişmezse portföyün ${gunde(t)} havuza '
        'kendiliğinden girer.';
  }
}
