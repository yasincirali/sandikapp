import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../utils/tr_format.dart' show dayKey, fmtTRY;
import 'fon_akisi.dart' show FonBalinaOlayi;
import 'hisse_hacmi.dart' show HacimOlayi;
import 'period_summary_service.dart';
import 'varlik_analizi.dart' show AnalizOzeti;

/// Aylık raporun sayısal yarısı (yasin 2026-11-07): "aylık raporda neden
/// sadece fonların raporları var, tüm varlıkların … para giriş çıkışları,
/// önemli haber detayları da olmalı".
///
/// ## Neden
/// Rapor, tuttuğun varlıkların aylık yapay zekâ notlarının derlemesiydi.
/// Not yalnız radar varlıklarına (fon, BIST hissesi, coin) yazılır ve
/// sunucu kapısından geçemeyen not yayımlanmaz; altın, döviz, emtia,
/// mevduat, eurobond hiç görünmüyordu. Not çıkmayan ayda kullanıcı
/// elindekilerin yarısını raporda bulamıyordu. Bu dosya üç bölümü kurar ve
/// hepsi ELDE OLAN veriden gelir; yeni kaynak, yeni formül yok:
///
///   1. **Ayın varlıkları** — tuttuğun HER varlığın ay başı → ay sonu
///      değişimi. `PeriodSummaryService.piyasaEtkisi` (Özet, Grafik kartı
///      ve varlık ekranının ortak "piyasa etkisi" hesabı): ay içindeki
///      alım/satım ayıklanır, yüzde ve ₺ aynı kaynaktan.
///   2. **Para girişi ve çıkışı** — o ayın alım, satış ve temettü toplamı;
///      tutarlar `getiriAkisi` kuralıyla (alımda maliyet, satışta ele
///      geçen, temettüde cebe giren). Net = Performans'taki "Nereden
///      geldi" köprüsünün "Net katkın" satırıyla aynı tanım
///      (`PeriodSummaryService.netInflow(temettuCikis: true)`), ikinci bir
///      hesap yolu açılmaz.
///   3. **Önemli gelişmeler** — tarihli olaylar: fonda büyük para
///      girişi/çıkışı, hisse ve coinde olağandışı hacim günü (sunucunun
///      `balina_olay` tablosu, kartların okuduğu aynı satırlar) ve kendi
///      defterindeki temettüler.
///
/// ## Uydurma yok
/// Serisi olmayan varlığın satırı yazılmaz (adı "ölçülemeyen" listesinde
/// söylenir), olay yoksa gelişme yok, akış yoksa bölüm yok.
///
/// ## Haber (0177, 2026-11-07)
/// yasin: "önemli haber akışlarıyla önemli bilgi olan varlıklar
/// görüntülenmeli". Sandık'ın lisanslı haber/KAP kaynağı hâlâ yok
/// (`docs/KAP_VERI_LISANSI_2026_09.md`); haber metni KOPYALANMAZ. Sunucu
/// (`analiz-hazirla`, `ANALIZ_HABER_ACIK=1`) kamuya açık haberleri
/// Anthropic web aramasıyla bulur, kendi cümlesiyle ve RAKAMSIZ özetletir,
/// kaynak adı ve bağlantıyı yanına koyar (`_shared/analiz_haber.ts`).
/// Haberi olan varlık "Önemli gelişmeler" kartına girer ve kartı haberi
/// kaynak bağlantısıyla gösterir; "haber yok" cümlesi yalnız hiç haber
/// gelmediğinde yazılır.

/// Bir varlığın ayı.
class AyinVarligi {
  const AyinVarligi({
    required this.anahtar,
    required this.tur,
    required this.ad,
    required this.pct,
    required this.piyasaTRY,
  });

  /// `positionKey` — ekranda `pozisyonEtiketi` ile ada çevrilir.
  final String anahtar;
  final AssetType tur;

  /// Lotun adı (mevduat gibi sembolü anlamsız pozisyonun etiketi).
  final String ad;

  /// Ay başına göre piyasa getirisi, yüzde (akış ayıklanmış).
  final double pct;

  /// Piyasanın ₺ etkisi (alım/satım düşülmüş).
  final double piyasaTRY;
}

/// Ayın para hareketleri. Tutarlar POZİTİF yazılır; yön alanın adında.
class AyinParaAkisi {
  const AyinParaAkisi({
    this.alimTRY = 0,
    this.alimSayisi = 0,
    this.satisTRY = 0,
    this.satisSayisi = 0,
    this.temettuTRY = 0,
    this.temettuSayisi = 0,
  });

  final double alimTRY;
  final int alimSayisi;
  final double satisTRY;
  final int satisSayisi;
  final double temettuTRY;
  final int temettuSayisi;

  /// "Net katkın": alım − satış − temettü (`getiriAkisi` toplamı).
  double get netTRY => alimTRY - satisTRY - temettuTRY;

  bool get bos => alimSayisi == 0 && satisSayisi == 0 && temettuSayisi == 0;
}

enum AyinGelismeTuru { fonGiris, fonCikis, hacimYukselis, hacimDusus, temettu }

/// Tarihli tek gelişme satırı.
class AyinGelismesi {
  const AyinGelismesi({
    required this.tarih,
    required this.kod,
    required this.tur,
    required this.tutar,
    this.oran,
    this.kat,
    this.fiyatDegisim,
    this.dolar = false,
  });

  final DateTime tarih;

  /// Ekrandaki kısa ad ('TTE', 'THYAO', 'BTC').
  final String kod;
  final AyinGelismeTuru tur;

  /// Fonda net akış (mutlak), hacimde günün para hacmi, temettüde cebe
  /// giren TL.
  final double tutar;

  /// Fon olayında |akış| / fon büyüklüğü (0,031 = %3,1).
  final double? oran;

  /// Hacim olayında ortalamaya oranı.
  final double? kat;

  /// Hacim olayında günün kapanış değişimi (0,041 = +%4,1).
  final double? fiyatDegisim;

  /// Kripto hacmi USDT'dir; TL'ye çevrilmez (kart kuralı).
  final bool dolar;
}

/// Ayın tek haber satırı (sunucunun `varlik_analizi.haberler` öğesi).
class AyinHaberi {
  const AyinHaberi({
    required this.tarih,
    required this.anahtar,
    required this.kod,
    required this.metin,
    required this.kaynak,
    required this.url,
  });

  final DateTime tarih;

  /// Aylık not anahtarı ('THYAO.IS', 'ALTIN:GRAM'); kart bununla eşlenir.
  final String anahtar;

  /// Türkçe kısa ad ('THYAO', 'Altın', 'USD/TRY').
  final String kod;

  /// Modelin kendi cümlesiyle, rakamsız özet (sunucu kapısından geçmiş).
  final String metin;

  /// Yayın adı ('Anadolu Ajansı'); boşsa alan adı.
  final String kaynak;

  /// Dış tarayıcıda açılan https adresi.
  final Uri url;

  /// Sunucu satırı → haber. Bozuk öğe `null` (sessiz düşer; sunucu
  /// kapısı zaten süzdü, burası ikinci savunma: https olmayan bağlantı
  /// asla açılmaz).
  static AyinHaberi? satirdan(Object? ham,
      {required String anahtar, required String kod}) {
    if (ham is! Map) return null;
    final metin = ham['metin'];
    final kaynak = ham['kaynak'];
    final url = Uri.tryParse('${ham['url'] ?? ''}');
    final tarih = DateTime.tryParse('${ham['tarih'] ?? ''}');
    if (metin is! String || metin.trim().isEmpty) return null;
    if (url == null || url.scheme != 'https' || url.host.isEmpty) return null;
    if (tarih == null) return null;
    final ad = kaynak is String && kaynak.trim().isNotEmpty
        ? kaynak.trim()
        : url.host.replaceFirst(RegExp(r'^www\.'), '');
    return AyinHaberi(
      tarih: DateTime(tarih.year, tarih.month, tarih.day),
      anahtar: anahtar,
      kod: kod,
      metin: metin.trim(),
      kaynak: ad,
      url: url,
    );
  }
}

/// Ayın haberleri — SAF. [satirlar]: `(anahtar, kod, haberler jsonb)`.
/// Pencere dışı ve bozuk öğe düşer; yeniden eskiye, en çok [ust] satır.
List<AyinHaberi> ayinHaberleri({
  required DateTime bas,
  required DateTime bit,
  required List<(String, String, Object?)> satirlar,
  int ust = 10,
}) {
  final a = dayKey(bas);
  final b = dayKey(bit);
  final out = <AyinHaberi>[];
  final gorulen = <String>{};
  for (final (anahtar, kod, liste) in satirlar) {
    if (liste is! List) continue;
    for (final ham in liste) {
      final h = AyinHaberi.satirdan(ham, anahtar: anahtar, kod: kod);
      if (h == null || h.tarih.isBefore(a) || h.tarih.isAfter(b)) continue;
      // Aynı haber iki varlıkta (ör. iki banka hissesi) bir kez yazılır.
      if (!gorulen.add(h.url.toString())) continue;
      out.add(h);
    }
  }
  out.sort((x, y) {
    final t = y.tarih.compareTo(x.tarih);
    return t != 0 ? t : x.kod.compareTo(y.kod);
  });
  return out.take(ust).toList();
}

/// Raporun sayısal bölümleri.
class AylikRaporOzeti {
  const AylikRaporOzeti({
    required this.bas,
    required this.bit,
    required this.surenAy,
    this.ay,
    this.varliklar = const [],
    this.olculemeyen = const [],
    this.akis = const AyinParaAkisi(),
    this.gelismeler = const [],
    this.haberler = const [],
    this.fiyatTarihi,
  });

  /// Ayın 1'i.
  final DateTime bas;

  /// Ayın son günü ya da (süren ayda) bugün.
  final DateTime bit;
  final bool surenAy;

  /// Performans › 1A ile aynı aylık özet (PDF'in getiri kutuları).
  final PeriodSummary? ay;
  final List<AyinVarligi> varliklar;

  /// Bugün tutulan ama serisi olmayan varlıkların anahtar/ad çifti.
  final List<(String, AssetType, String)> olculemeyen;
  final AyinParaAkisi akis;
  final List<AyinGelismesi> gelismeler;

  /// Aylık notların haber satırları (0177). Boşsa rapor "haber yok" der.
  final List<AyinHaberi> haberler;

  /// Fiyat serisinin pencere içindeki son ölçüm anı ("… itibarıyla").
  final DateTime? fiyatTarihi;

  bool get bos =>
      varliklar.isEmpty && akis.bos && gelismeler.isEmpty && haberler.isEmpty;

  /// Ayın 1'i ve raporun bittiği gün: kapanmış ayda ayın son günü, süren
  /// ayda bugün. Tek yerde ki ekran, PDF ve testler aynı ucu yazsın.
  static (DateTime, DateTime, bool) pencere(DateTime donem, DateTime simdi) {
    final bas = DateTime(donem.year, donem.month);
    final aySonu = DateTime(donem.year, donem.month + 1, 0);
    final suren = !dayKey(simdi).isAfter(aySonu);
    return (bas, suren ? dayKey(simdi) : aySonu, suren);
  }
}

/// Ayın para hareketleri — SAF.
///
/// Pencere `netInflow`'un gün pencereleriyle aynı: [bas] gününün 00:00'ı
/// dahil, [bit] gününün sonu dahil. Silinmiş lot ve mezar taşı
/// (`isActive`) sayılmaz; kapanmış pozisyonun satışı SAYILIR (geçmişi
/// soran yer, ham defter — `aktifLotlar` değil).
AyinParaAkisi ayinParaAkisi(List<Asset> lotlar, DateTime bas, DateTime bit) {
  final basMs = dayKey(bas).millisecondsSinceEpoch;
  final bitMs =
      DateTime(bit.year, bit.month, bit.day, 23, 59, 59).millisecondsSinceEpoch;
  var alim = 0.0, satis = 0.0, temettu = 0.0;
  var nA = 0, nS = 0, nT = 0;
  for (final a in lotlar) {
    if (!a.isActive) continue;
    final ms = a.addedDate.millisecondsSinceEpoch;
    if (ms < basMs || ms > bitMs) continue;
    if (a.isBuy) {
      alim += a.totalCostTRY;
      nA++;
    } else if (a.isSell) {
      satis += a.sellProceedsTRY;
      nS++;
    } else if (a.isDividend) {
      temettu += a.dividendTRY;
      nT++;
    }
  }
  return AyinParaAkisi(
    alimTRY: alim,
    alimSayisi: nA,
    satisTRY: satis,
    satisSayisi: nS,
    temettuTRY: temettu,
    temettuSayisi: nT,
  );
}

/// Ayın varlık satırları — SAF. Her pozisyonun kendi serisinden
/// `piyasaEtkisi`; yüzdesi ölçülemeyen satır çıkmaz. Sıra: piyasanın ₺
/// etkisi büyükten küçüğe (en çok kazandıran üstte, en çok düşüren altta;
/// Performans'taki en iyi / en zayıf diliyle aynı yön).
List<AyinVarligi> ayinVarliklari({
  required Map<String, Map<int, double>> byPosition,
  required Map<String, AssetType> positionType,
  required List<Asset> lotlar,
  required DateTime bas,
  required DateTime son,
}) {
  final lotlarAnahtara = <String, List<Asset>>{};
  for (final a in lotlar) {
    (lotlarAnahtara[positionKey(a)] ??= []).add(a);
  }
  final out = <AyinVarligi>[];
  byPosition.forEach((k, seri) {
    final l = lotlarAnahtara[k] ?? const <Asset>[];
    final r = PeriodSummaryService.piyasaEtkisi(
        seri: seri, lotlar: l, start: bas, end: son);
    final pct = r?.pct;
    if (r == null || pct == null || !pct.isFinite) return;
    out.add(AyinVarligi(
      anahtar: k,
      tur: positionType[k] ?? (l.isEmpty ? AssetType.diger : l.first.type),
      ad: l.isEmpty ? k : l.first.name,
      pct: pct,
      piyasaTRY: r.piyasa,
    ));
  });
  out.sort((a, b) => b.piyasaTRY.compareTo(a.piyasaTRY));
  return out;
}

/// Ayın gelişmeleri — SAF. Olaylar pencere içinde süzülür (sorgu alt
/// sınırı gevşek olabilir), yeniden eskiye sıralanır, en çok [ust] satır.
List<AyinGelismesi> ayinGelismeleri({
  required DateTime bas,
  required DateTime bit,
  Map<String, List<FonBalinaOlayi>> fonOlaylari = const {},
  Map<String, List<HacimOlayi>> hacimOlaylari = const {},
  Set<String> dolarKodlari = const {},
  List<Asset> lotlar = const [],
  int ust = 12,
}) {
  final a = dayKey(bas);
  final b = dayKey(bit);
  bool icinde(DateTime t) {
    final g = dayKey(t);
    return !g.isBefore(a) && !g.isAfter(b);
  }

  final out = <AyinGelismesi>[];
  fonOlaylari.forEach((kod, liste) {
    for (final o in liste) {
      if (!icinde(o.tarih)) continue;
      out.add(AyinGelismesi(
        tarih: o.tarih,
        kod: kod,
        tur: o.giris ? AyinGelismeTuru.fonGiris : AyinGelismeTuru.fonCikis,
        tutar: o.tutar.abs(),
        oran: o.buyuklukOrani,
      ));
    }
  });
  hacimOlaylari.forEach((kod, liste) {
    for (final o in liste) {
      if (!icinde(o.tarih)) continue;
      out.add(AyinGelismesi(
        tarih: o.tarih,
        kod: kod,
        tur: o.yukselis
            ? AyinGelismeTuru.hacimYukselis
            : AyinGelismeTuru.hacimDusus,
        tutar: o.paraHacmi,
        kat: o.ortalamaKati,
        fiyatDegisim: o.fiyatDegisim,
        dolar: dolarKodlari.contains(kod),
      ));
    }
  });
  for (final l in lotlar) {
    if (!l.isActive || !l.isDividend || !icinde(l.addedDate)) continue;
    if (!(l.dividendTRY > 0)) continue;
    out.add(AyinGelismesi(
      tarih: l.addedDate,
      kod: pozisyonKodu(l.ticker.trim().isEmpty ? l.name : l.ticker),
      tur: AyinGelismeTuru.temettu,
      tutar: l.dividendTRY,
    ));
  }
  out.sort((x, y) {
    final t = y.tarih.compareTo(x.tarih);
    return t != 0 ? t : x.kod.compareTo(y.kod);
  });
  return out.take(ust).toList();
}

/// Notların dayandığı verinin aralığı: en erken başlangıç → en geç bitiş
/// (sunucunun `girdi.baslangic/bitis`'i; fonda iş günleri, hissede seans
/// günleri). Hiçbir not aralık taşımıyorsa `null` — satır yazılmaz.
(DateTime, DateTime)? notVeriAraligi(Iterable<AnalizOzeti> notlar) {
  DateTime? bas, bit;
  for (final n in notlar) {
    final b = n.veriBaslangic, s = n.veriBitis;
    if (b != null && (bas == null || b.isBefore(bas))) bas = b;
    if (s != null && (bit == null || s.isAfter(bit))) bit = s;
  }
  if (bas == null || bit == null) return null;
  return (bas, bit);
}

/// İşaretli tam TL: "+₺1.250", "−₺480", yarım liranın altı "₺0". Ekran ve
/// PDF aynı yazsın (köprü cümlesinin `isaretli`'siyle aynı kural).
String isaretliTL(double v) =>
    v.abs() < 0.5 ? fmtTRY(0) : '${v > 0 ? '+' : '−'}${fmtTRY(v.abs())}';
