import 'package:flutter/foundation.dart';

import '../models/asset_type.dart';
import '../models/position.dart';
import 'fon_dagilimi.dart';
import 'fon_karnesi.dart' show fonKoduOf;

/// Portföy X-Ray (Premium, yasin 2026-10-10): kullanıcının BUGÜNKÜ
/// pozisyonları, fonların içi açılarak varlık sınıfı kovalarına.
///
/// ## Kural
/// Her pozisyonun TL değeri ([PozisyonDegeri]) tek bir kovaya ya da (fon,
/// BES) fonun TEFAS dağılımıyla kovalara bölünür:
///   · hisse → BIST hisse; ABD hissesi → yabancı hisse,
///   · fon / BES → değer × (kova yüzdesi / 100),
///   · altın → kıymetli maden, döviz → döviz, kripto → kripto,
///     mevduat → mevduat, eurobond → döviz/dış borçlanma, emtia → emtia,
///     diğer → diğer.
///
/// ## X-Ray dışı — yeniden normalize EDİLMEZ
/// Dağılımı bilinmeyen fonun bütün değeri ve dağılım toplamı 100'ün
/// altında kalan fonun eksik payı "X-Ray dışı" kalır. Başka kovalara
/// orantılı dağıtmak halkayı "tam" gösterirdi ama bilinmeyen bir şeyi
/// biliyormuş gibi yapardı (araştırma raporu: "kapsanmayan pay görünür bir
/// dilim olarak kalır; halka sessizce yeniden normalize edilmez").
/// Toplam 100'ü AŞAN fonda (kaldıraç, yuvarlama) kovalar kaynaktaki gibi
/// kalır; Σ kova bu durumda bütünü kuruş kadar aşabilir — sayı uydurmak
/// yerine kaynak söylendiği gibi gösterilir.
///
/// ## Kapsam
/// Bugünkü mülkiyet sorusu: çağıran `aktifLotlar` + `aggregatePositions`
/// ile kurar ve YALNIZ kendi lotlarını verir (ortak lotları girmez —
/// `partner_aggregation_invariant`). Kapanmış pozisyon zaten listede yok.
///
/// Saf: ağ yok. Sağlayıcı `fon_xray_provider.dart`.

/// Pozisyonun bugünkü TL değeri; bilinmiyorsa (fiyat yok) `null` —
/// pozisyon X-Ray'e girmez (portföy toplamıyla aynı kural:
/// `ownerScopedTotalValue` fiyatsız pozisyonu toplamaz).
typedef PozisyonDegeri = double? Function(Position p);

/// Doğrudan tutulan varlığın kovası; fon/BES için `null` (dağılımdan).
XrayKova? dogrudanKova(Position p) {
  final a = p.representative;
  return switch (a.type) {
    AssetType.hisse =>
      a.abdHissesi ? XrayKova.yabanciHisse : XrayKova.bistHisse,
    AssetType.fon || AssetType.bes => null,
    AssetType.altin => XrayKova.kiymetliMaden,
    AssetType.doviz => XrayKova.doviz,
    AssetType.kripto => XrayKova.kripto,
    AssetType.mevduat => XrayKova.mevduat,
    AssetType.eurobond => XrayKova.dovizBorclanma,
    AssetType.emtia => XrayKova.emtia,
    AssetType.diger => XrayKova.diger,
  };
}

@immutable
class XrayDisiFon {
  const XrayDisiFon({required this.ad, required this.kod, required this.tutar});

  /// Pozisyonun adı (fon kodu bilinmiyorsa tek kimlik).
  final String ad;
  final String? kod;
  final double tutar;
}

/// Bir hissenin birden çok yerden tutulması (Katman A).
@immutable
class Ortusme {
  const Ortusme({
    required this.kod,
    required this.ad,
    required this.fonlar,
    required this.dogrudan,
    required this.tutar,
  });

  /// Borsa kodu (THYAO, AAPL US).
  final String kod;
  final String ad;

  /// İçinde tutan fon kodları (sıralı).
  final List<String> fonlar;

  /// Doğrudan da tutuluyor mu.
  final bool dogrudan;

  /// Toplam maruziyet (TL): fon değeri × ağırlık + doğrudan değer.
  final double tutar;

  int get kaynakSayisi => fonlar.length + (dogrudan ? 1 : 0);
}

@immutable
class PortfoyXray {
  const PortfoyXray({
    required this.toplam,
    required this.kovalar,
    required this.xrayDisi,
    required this.xrayDisiFonlar,
    required this.fonTarihleri,
    required this.ortusmeler,
    required this.kalemDonemi,
    this.gorunen = const {},
    this.kaynaklar = const {},
    this.disiKaynaklar = const {},
  });

  /// X-Ray'e giren pozisyonların TL değeri (fiyatı bilinenler).
  final double toplam;

  /// Kova → TL, büyükten küçüğe sıralı liste olarak [siraliKovalar].
  final Map<XrayKova, double> kovalar;

  /// Dağılımı bilinmeyen fonlar + kaynak toplamı 100'ün altındaki fark.
  final double xrayDisi;

  /// Dağılımı hiç bulunamayan fon pozisyonları.
  final List<XrayDisiFon> xrayDisiFonlar;

  /// Kullanılan TEFAS dağılımlarının tarihleri (en eski, en yeni); fon
  /// yoksa `null`.
  final (DateTime, DateTime)? fonTarihleri;

  /// En az iki yerden tutulan hisseler (Katman A açıksa), tutara göre.
  final List<Ortusme> ortusmeler;

  /// Örtüşmede kullanılan KAP raporlarının en yeni ay sonu.
  final DateTime? kalemDonemi;

  /// "Tuttukların": fon AÇILMADAN, kullanıcının listesinde gördüğü türlere
  /// göre TL (fon fon olarak, hisse hisse olarak). X-Ray'in değeri bu
  /// görünüm ile [kovalar] arasındaki fark (yasin 2026-10-12, tasarım B).
  final Map<AssetType, double> gorunen;

  /// Kova → kaynak adı → TL: o sınıftaki paranın hangi fondan (fon kodu)
  /// ya da hangi doğrudan pozisyondan geldiği. Bir kovanın kaynakları
  /// toplamı o kovanın tutarıdır (sınıfa dokununca açılan sayfa).
  final Map<XrayKova, Map<String, double>> kaynaklar;

  /// X-Ray dışı payın kaynakları: dağılımı bulunamayan fonun tamamı ya da
  /// kaynak toplamı 100'ü tutmayan fondaki fark. Toplamı [xrayDisi].
  final Map<String, double> disiKaynaklar;

  bool get bos => toplam <= 0;

  /// Fon (ya da BES) var mı: yoksa "tuttukların" ile gerçek dağılım aynı
  /// şeydir, karşılaştırma ve içgörü gösterilmez.
  bool get fonVar =>
      (gorunen[AssetType.fon] ?? 0) > 0 || (gorunen[AssetType.bes] ?? 0) > 0;

  List<MapEntry<AssetType, double>> get siraliGorunen =>
      gorunen.entries.where((e) => e.value > 0).toList()
        ..sort((a, b) {
          final f = b.value.compareTo(a.value);
          return f != 0 ? f : a.key.index.compareTo(b.key.index);
        });

  /// Bir kovanın kaynakları, büyükten küçüğe.
  List<MapEntry<String, double>> kaynaklariSirali(XrayKova? k) =>
      (k == null ? disiKaynaklar : (kaynaklar[k] ?? const {}))
          .entries
          .where((e) => e.value > 0)
          .toList()
        ..sort((a, b) {
          final f = b.value.compareTo(a.value);
          return f != 0 ? f : a.key.compareTo(b.key);
        });

  /// "Sandığın ile gerçeğin farkı" cümleleri: fonların içi açılınca payı
  /// en az [XrayIcgoru.esik] puan büyüyen gruplar, farka göre, en çok iki.
  /// Hesaplanır; metin uydurulmaz (bkz. [XrayIcgoru]).
  List<XrayIcgoru> get icgoruler {
    if (!fonVar || toplam <= 0) return const [];
    double g(Iterable<AssetType> t) =>
        t.fold(0.0, (s, x) => s + (gorunen[x] ?? 0));
    double r(Iterable<XrayKova> k) =>
        k.fold(0.0, (s, x) => s + (kovalar[x] ?? 0));
    final adaylar = [
      for (final (tur, gor, ger) in [
        (XrayIcgoruTuru.hisse, g([AssetType.hisse]),
            r([XrayKova.bistHisse, XrayKova.yabanciHisse])),
        (XrayIcgoruTuru.altin, g([AssetType.altin]),
            r([XrayKova.kiymetliMaden])),
        (XrayIcgoruTuru.doviz, g([AssetType.doviz, AssetType.eurobond]),
            r([XrayKova.doviz, XrayKova.dovizBorclanma])),
        (XrayIcgoruTuru.faiz, g([AssetType.mevduat]),
            r([
              XrayKova.mevduat,
              XrayKova.devletBorclanma,
              XrayKova.ozelBorclanma,
              XrayKova.paraPiyasasi,
            ])),
      ])
        if (pay(ger) - pay(gor) >= XrayIcgoru.esik)
          XrayIcgoru(tur: tur, gorunenPay: pay(gor), gercekPay: pay(ger)),
    ]..sort((a, b) => b.fark.compareTo(a.fark));
    return adaylar.take(2).toList();
  }

  List<MapEntry<XrayKova, double>> get siraliKovalar =>
      kovalar.entries.where((e) => e.value != 0).toList()
        ..sort((a, b) {
          final f = b.value.compareTo(a.value);
          return f != 0 ? f : a.key.index.compareTo(b.key.index);
        });

  /// Toplamın yüzdesi; toplam 0 ise 0.
  double pay(double tutar) => toplam > 0 ? tutar / toplam * 100 : 0;
}

enum XrayIcgoruTuru { hisse, altin, doviz, faiz }

/// "Hisse payın %24 görünüyor, fonlarınla birlikte %47,8." Görünen pay
/// kullanıcının tuttuğu türden ([PortfoyXray.gorunen]), gerçek pay fonlar
/// açıldıktan sonraki kovalardan. Fon içi para yalnız EKLENİR (doğrudan
/// tutulan bir şey fonla azalmaz), bu yüzden yalnız büyüyen yön var.
@immutable
class XrayIcgoru {
  const XrayIcgoru(
      {required this.tur, required this.gorunenPay, required this.gercekPay});

  /// Gösterme eşiği (puan): daha küçük fark "bilgi" değil gürültü.
  static const double esik = 3;

  final XrayIcgoruTuru tur;
  final double gorunenPay;
  final double gercekPay;

  double get fark => gercekPay - gorunenPay;
}

/// Hesap. [dagilimlar] ve [kalemler] fon koduna göre (`fonKoduOf`).
PortfoyXray portfoyXray({
  required List<Position> pozisyonlar,
  required PozisyonDegeri deger,
  required Map<String, FonDagilimi> dagilimlar,
  Map<String, FonKalemleri> kalemler = const {},
}) {
  var toplam = 0.0;
  var disi = 0.0;
  final kovalar = <XrayKova, double>{};
  final gorunen = <AssetType, double>{};
  final kaynaklar = <XrayKova, Map<String, double>>{};
  final disiKaynaklar = <String, double>{};
  final disiFonlar = <XrayDisiFon>[];
  DateTime? enEski;
  DateTime? enYeni;

  // Örtüşme için: hisse kodu → (ad, fonlar, doğrudan, tutar).
  final maruziyet = <String,
      ({String ad, Set<String> fonlar, bool dogrudan, double tutar})>{};
  DateTime? kalemDonemi;
  void maruz(String kod, String ad, {String? fon, required double tutar}) {
    final o = maruziyet[kod];
    maruziyet[kod] = (
      ad: o?.ad ?? ad,
      fonlar: {...?o?.fonlar, if (fon != null) fon},
      dogrudan: (o?.dogrudan ?? false) || fon == null,
      tutar: (o?.tutar ?? 0) + tutar,
    );
  }

  void ekle(XrayKova k, double tutar, String kaynak) {
    kovalar[k] = (kovalar[k] ?? 0) + tutar;
    final m = kaynaklar.putIfAbsent(k, () => <String, double>{});
    m[kaynak] = (m[kaynak] ?? 0) + tutar;
  }

  void disiEkle(String kaynak, double tutar) {
    disi += tutar;
    disiKaynaklar[kaynak] = (disiKaynaklar[kaynak] ?? 0) + tutar;
  }

  for (final p in pozisyonlar) {
    final d = deger(p);
    if (d == null || !d.isFinite || d <= 0) continue;
    toplam += d;
    final a = p.representative;
    gorunen[a.type] = (gorunen[a.type] ?? 0) + d;
    final kova = dogrudanKova(p);
    if (kova != null) {
      // Kaynak adı: hissede kısa kod (THYAO), diğerlerinde pozisyonun adı.
      final ad = a.type == AssetType.hisse
          ? a.ticker.trim().toUpperCase().replaceFirst(RegExp(r'\.IS$'), '')
          : a.name;
      ekle(kova, d, ad.isEmpty ? a.name : ad);
      if (a.type == AssetType.hisse) {
        // `ASELS.IS` → `ASELS`: KAP raporundaki kodla aynı biçim. ABD
        // hissesi raporda "AAPL US" yazar; doğrudan tutulan Apple ile fon
        // içindeki Apple'ın eşleşmesi için " US" eklenir.
        final ham = a.ticker.trim().toUpperCase();
        final kod =
            a.abdHissesi ? '$ham US' : ham.replaceFirst(RegExp(r'\.IS$'), '');
        if (kod.isNotEmpty) maruz(kod, a.name, tutar: d);
      }
      continue;
    }
    final fonKodu = fonKoduOf(tur: a.type, ticker: a.ticker);
    final dag = fonKodu == null ? null : dagilimlar[fonKodu];
    final fonAdi = fonKodu ?? a.name;
    if (dag == null) {
      disiEkle(fonAdi, d);
      disiFonlar.add(XrayDisiFon(ad: a.name, kod: fonKodu, tutar: d));
      continue;
    }
    if (enEski == null || dag.tarih.isBefore(enEski)) enEski = dag.tarih;
    if (enYeni == null || dag.tarih.isAfter(enYeni)) enYeni = dag.tarih;
    for (final kp in dag.kovalar) {
      ekle(kp.kova, d * kp.yuzde / 100, fonAdi);
    }
    final eksik = 100 - dag.toplam;
    if (eksik > 0) disiEkle(fonAdi, d * eksik / 100);

    final kl = kalemler[fonKodu];
    if (kl != null) {
      if (kalemDonemi == null || kl.donem.isAfter(kalemDonemi)) {
        kalemDonemi = kl.donem;
      }
      for (final k in kl.kalemler) {
        final anahtar = k.hisseAnahtari;
        if (anahtar == null) continue;
        maruz(anahtar, k.ad, fon: fonKodu, tutar: d * k.agirlik / 100);
      }
    }
  }

  final ortusmeler = [
    for (final e in maruziyet.entries)
      if (e.value.fonlar.length + (e.value.dogrudan ? 1 : 0) >= 2 &&
          e.value.fonlar.isNotEmpty)
        Ortusme(
          kod: e.key,
          ad: e.value.ad,
          fonlar: e.value.fonlar.toList()..sort(),
          dogrudan: e.value.dogrudan,
          tutar: e.value.tutar,
        ),
  ]..sort((a, b) => b.tutar.compareTo(a.tutar));

  disiFonlar.sort((a, b) => b.tutar.compareTo(a.tutar));
  return PortfoyXray(
    toplam: toplam,
    kovalar: kovalar,
    xrayDisi: disi,
    xrayDisiFonlar: List.unmodifiable(disiFonlar),
    fonTarihleri: enEski == null ? null : (enEski, enYeni!),
    ortusmeler: List.unmodifiable(ortusmeler),
    kalemDonemi: ortusmeler.isEmpty ? null : kalemDonemi,
    gorunen: Map.unmodifiable(gorunen),
    kaynaklar: Map.unmodifiable(kaynaklar),
    disiKaynaklar: Map.unmodifiable(disiKaynaklar),
  );
}
