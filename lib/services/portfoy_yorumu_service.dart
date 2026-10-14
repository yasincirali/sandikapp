import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import '../utils/tr_format.dart';
import 'crash_reporter.dart';
import 'history_service.dart';
import 'inflation_service.dart';
import 'insight_metrics_service.dart';
import 'kiyas_service.dart';
import 'kiyas_yukleyici.dart';
import 'period_summary_service.dart';
import 'real_return_service.dart';
import 'varlik_istatistik.dart';

/// Kişiye özel AI portföy yorumu (0145, 2026-10-13) — paket, kayıt, istek.
///
/// ## Ne yapar
/// Performans › Özet'te GEÇEN HAFTA ve GEÇEN AY için 3–4 maddelik
/// betimleyici yorum. Telefon dönemin yüzdelerini hesaplar ([PortfoyYorumPaketi.kur]),
/// `portfoy-yorumla` fonksiyonu Claude'a yazdırır ve saklar.
///
/// ## Kaydet, yeniden yazma (yasin, 12 Eki)
/// "Periyodikse sonraki zamana kadar kaydedelim, her seferinde ai token
/// tüketmeyelim." Yorum KAPANMIŞ bir takvim dönemini anlatır (kayan pencere
/// her gün değişirdi); satır o dönem boyunca tablodan okunur. Pazartesi
/// alınan yorum Cumartesi de doğrudur: anlattığı hafta kapanmıştır.
/// Yalnız dönem sonundaki portföy değişirse ([parmakIzi]) yeniden yazılır —
/// geçmiş bir işlem eklemek/düzeltmek gibi. Bugünkü alım geçen ayın
/// yorumunu eskitmez.
///
/// ## Modele ne gider
/// Yalnız yüzde, puan, gün ve küçük adet; varlık adları ölçüm adında.
/// TL tutar, adet, maliyet, kimlik GİTMEZ — sunucu da aynı kuralı denetler
/// (`_shared/portfoy_yorum.ts`); burada tutar izi taşıyan ölçüm hiç
/// kurulmaz ([tutarIziVar]). Sayılar Performans'ın kullandığı servislerden
/// (`PeriodSummaryService`, `InsightMetricsService`) gelir: ekran ile
/// yorum aynı kaynaktan okur.
///
/// ## Seçili dönem ve varlık detayı (0151, 2026-10-14)
/// yasin: "daha ekonomist gibi ve varlık detayında ve varlıklar bütününde de
/// seçili dönem için data detaylı yorum yapılabilir". [YorumTuru.secili]
/// Performans'ın ve varlık detayının seçili dönemini (1H…5Y, bugün biten
/// pencere) anlatır; paket "ekonomist" bağları kurulabilsin diye enflasyon,
/// dolar/altın/BIST 100 kıyası ve oynaklık da taşır ([ekonomiOlcumleri],
/// [PortfoyYorumPaketi.varlikKur]). Kayan pencere her gün değiştiği için
/// kayıt GÜN başınadır (sunucu `bitis` gününü anahtara katar).
enum YorumTuru {
  haftalik,
  aylik,
  secili;

  String get sunucuAdi => name;
}

/// Yorumun neyi anlattığı: bütün portföy (Performans) ya da tek varlık.
enum YorumKapsami { portfoy, varlik }

/// GÜNLÜK yorumlanmaz: gün içi seri saatler içinde değişir, gün başına
/// saklanan yorum onu bayat anlatırdı (sunucu da kabul etmez).
bool seciliYorumlanabilir(SummaryPeriod p) => !p.intraday;

/// [simdi]'den önceki son kapanmış dönem; uçlar yerel gün başı.
///
/// Sunucudaki `beklenenDonem` ile AYNI kural (Pazar bile içinde bulunulan
/// hafta açık sayılır). `portfoy_yorumu_test` iki tarafı aynı örneklerle sınar.
({DateTime baslangic, DateTime bitis}) yorumDonemi(YorumTuru tur, DateTime simdi) {
  final bugun = dayKey(simdi);
  if (tur == YorumTuru.haftalik) {
    final buPazartesi = bugun.subtract(Duration(days: bugun.weekday - 1));
    final bas = DateTime(buPazartesi.year, buPazartesi.month, buPazartesi.day - 7);
    return (baslangic: bas, bitis: DateTime(bas.year, bas.month, bas.day + 6));
  }
  final bas = DateTime(bugun.year, bugun.month - 1, 1);
  return (baslangic: bas, bitis: DateTime(bugun.year, bugun.month, 0));
}

String isoGun(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Ölçüm adında tutar izi: para birimi ya da 4+ haneli sayı (sunucudaki
/// `TUTAR_IZI` ile aynı). Varlık adı böyleyse ('TR 2030 Eurobond') ölçüm
/// hiç kurulmaz — sunucu bütün paketi reddedeceğine o satır düşer.
bool tutarIziVar(String metin) =>
    RegExp(r'[₺$€£]|\bTL\b|\bTRY\b|\bUSD\b|\d{4,}|\d{1,3}(?:\.\d{3})+')
        .hasMatch(metin);

class YorumOlcumu {
  const YorumOlcumu(this.anahtar, this.ad, this.gosterim);
  final String anahtar;
  final String ad;
  final String gosterim;

  Map<String, String> toJson() => {'anahtar': anahtar, 'ad': ad, 'gosterim': gosterim};

  static YorumOlcumu? fromJson(Object? j) {
    if (j is! Map) return null;
    final a = j['anahtar'], ad = j['ad'], g = j['gosterim'];
    if (a is! String || ad is! String || g is! String) return null;
    return YorumOlcumu(a, ad, g);
  }
}

class PortfoyYorumPaketi {
  const PortfoyYorumPaketi({
    required this.tur,
    required this.baslangic,
    required this.bitis,
    required this.parmakIzi,
    required this.olcumler,
    this.kapsam = YorumKapsami.portfoy,
    this.donemKodu,
    this.varlikIzi,
    this.varlikAdi,
  });

  final YorumTuru tur;
  final DateTime baslangic;
  final DateTime bitis;
  final String parmakIzi;
  final List<YorumOlcumu> olcumler;
  final YorumKapsami kapsam;

  /// Yalnız [YorumTuru.secili]: `SummaryPeriod.label` (1H…5Y).
  final String? donemKodu;

  /// Yalnız [YorumKapsami.varlik]: [varlikIziOf].
  final String? varlikIzi;

  /// Yalnız [YorumKapsami.varlik]: modelin varlığı adıyla anması için.
  final String? varlikAdi;

  /// Yorum yazmaya değer mi? Dönemde seri yoksa (portföy yeni, veri yok)
  /// model çağrılmaz — "bu hafta %0" diye uydurma bir yorum çıkmasın.
  /// Varlıkta ana ölçüm dönem değişimi ('degisim').
  bool get yeterli =>
      olcumler.any((o) => o.anahtar == 'getiri' || o.anahtar == 'degisim') &&
      olcumler.length >= 2;

  Map<String, Object> toJson() => {
        'tur': tur.sunucuAdi,
        'baslangic': isoGun(baslangic),
        'bitis': isoGun(bitis),
        'parmak_izi': parmakIzi,
        'olcumler': [for (final o in olcumler) o.toJson()],
        // Eski sözleşme (0145) bu alanları tanımaz: kapanmış dönem portföy
        // yorumunda HİÇ gönderilmez.
        if (tur == YorumTuru.secili) 'donem_kodu': donemKodu!,
        if (kapsam == YorumKapsami.varlik) ...{
          'kapsam': 'varlik',
          'varlik_izi': varlikIzi!,
          if (varlikAdi != null) 'varlik_adi': varlikAdi!,
        },
      };

  /// SAF: dönem özeti + seri → ölçümler. Test `portfoy_yorumu_test`.
  ///
  /// [ozet] `PeriodSummaryService.compute(pencereBaslangici: baslangic,
  /// now: bitis 23:59:59)` ile kurulmuş olmalı (çağıran [PortfoyYorumuService.paketHazirla]).
  ///
  /// [ekOlcumler] seçili dönemin "ekonomist" ölçümleri ([ekonomiOlcumleri]);
  /// temel ölçümlerden SONRA eklenir (30 sınırında önce onlar düşer).
  static PortfoyYorumPaketi kur({
    required YorumTuru tur,
    required DateTime baslangic,
    required DateTime bitis,
    required PeriodSummary ozet,
    required PortfolioHistoryBreakdown breakdown,
    required String Function(String positionKey) etiket,
    String? donemKodu,
    List<YorumOlcumu> ekOlcumler = const [],
  }) {
    final fromMs = baslangic.millisecondsSinceEpoch;
    final toMs = DateTime(bitis.year, bitis.month, bitis.day, 23, 59, 59).millisecondsSinceEpoch;
    final o = <YorumOlcumu>[];
    void ekle(String anahtar, String ad, String gosterim) {
      if (tutarIziVar(ad)) return;
      o.add(YorumOlcumu(anahtar, ad, gosterim));
    }

    String pct(double v) => fmtPctIsaretli(v, digits: 1);
    String pay(double v) => fmtPct(v, digits: 1);

    final getiri = ozet.getiriPct;
    if (getiri != null && getiri.isFinite) ekle('getiri', 'Dönem getirisi', pct(getiri));
    final iyi = ozet.enIyi, zayif = ozet.enZayif;
    if (iyi != null && iyi.changePct.isFinite) {
      ekle('en_iyi', 'Dönemin en çok değer kazanan varlığı: ${iyi.name}', pct(iyi.changePct));
    }
    if (zayif != null && zayif.changePct.isFinite && zayif.name != iyi?.name) {
      ekle('en_zayif', 'Dönemin en zayıf varlığı: ${zayif.name}', pct(zayif.changePct));
    }

    // Dönem SONU dağılımı (tür) — yüzdeye çevrilir; TL gitmez.
    final dag = ozet.dagilimSonu;
    if (dag != null) {
      final toplam = dag.values.where((v) => v > 0).fold<double>(0, (a, b) => a + b);
      if (toplam > 0) {
        final sirali = dag.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        for (final e in sirali.take(4)) {
          ekle('tur_payi_${e.key.name}', 'Dönem sonunda ${e.key.label} payı',
              pay(e.value / toplam * 100));
        }
      }
    }

    // Dönem sonu pozisyon payları: en büyük pay + pozisyon sayısı + parmak izi.
    final sonDegerler = <String, double>{};
    breakdown.byPosition.forEach((k, seri) {
      final v = _sonDeger(seri, fromMs, toMs);
      if (v != null && v > 0) sonDegerler[k] = v;
    });
    final posToplam = sonDegerler.values.fold<double>(0, (a, b) => a + b);
    if (posToplam > 0) {
      final enBuyuk = sonDegerler.entries.reduce((a, b) => a.value >= b.value ? a : b);
      ekle('en_buyuk_pay', 'Dönem sonunda en büyük pay: ${etiket(enBuyuk.key)}',
          pay(enBuyuk.value / posToplam * 100));
      if (sonDegerler.length < 1000) {
        ekle('pozisyon_sayisi', 'Dönem sonunda varlık sayısı', '${sonDegerler.length}');
      }
      // Yoğunlaşma (yalnız seçili dönem; kapanmış dönem paketi 0145'teki
      // gibi kalır): ilk üç varlığın toplam payı. Model toplayamaz (sayı
      // kapısı), toplamı biz veririz.
      if (tur == YorumTuru.secili && sonDegerler.length >= 4) {
        final sirali = sonDegerler.values.toList()..sort((a, b) => b.compareTo(a));
        final ilkUc = sirali.take(3).fold<double>(0, (a, b) => a + b);
        ekle('ilk_uc_pay', 'Dönem sonunda en büyük 3 varlığın toplam payı',
            pay(ilkUc / posToplam * 100));
      }
    }

    // Dönem içindeki en derin geri çekilme (değer serisi, pencere içi).
    final pencere = <int, double>{
      for (final e in breakdown.total.entries)
        if (e.key >= fromMs && e.key <= toMs) e.key: e.value,
    };
    final dd = InsightMetricsService.maxDrawdown(pencere);
    if (dd != null && !dd.isFlat) {
      ekle('en_derin_dusus', 'Dönem içindeki en derin geri çekilme',
          fmtPctIsaretli(-dd.yuzde, digits: 1));
      final g = dd.toparlanmaGun;
      if (g != null && g < 1000) ekle('toparlanma', 'Geri çekilmeden toparlanma süresi', '$g gün');
    }

    final goruldu = {for (final x in o) x.anahtar};
    for (final x in ekOlcumler) {
      if (goruldu.add(x.anahtar) && !tutarIziVar(x.ad)) o.add(x);
    }

    return PortfoyYorumPaketi(
      tur: tur,
      baslangic: baslangic,
      bitis: bitis,
      parmakIzi: portfoyParmakIzi(sonDegerler),
      olcumler: o.take(30).toList(),
      donemKodu: donemKodu,
    );
  }

  /// SAF: varlık detayının seçili dönemi → ölçümler. Test `portfoy_yorumu_test`.
  ///
  /// Sayılar varlık detayının gösterdiği değerlerden gelir ([ist] dönem
  /// istatistiği, [donemPct] fiyatın altındaki dönem yüzdesi): ekran ile
  /// yorum ayrışmaz. Fiyat ve tutar GİTMEZ; zirveye/dibe uzaklık yüzdedir.
  static PortfoyYorumPaketi varlikKur({
    required SummaryPeriod period,
    required DateTime baslangic,
    required DateTime bitis,
    required String positionKey,
    required double miktar,
    required String varlikAdi,
    required DonemIstatistigi? ist,
    required double? donemPct,
    required double? canliBirim,
    double? portfoyPayi,
    double? pozisyonGetirisi,
    int? eldeGun,
    Map<KiyasVarligi, double> kiyasDegisimi = const {},
    YorumTufesi? tufe,
  }) {
    final o = <YorumOlcumu>[];
    void ekle(String anahtar, String ad, String gosterim) {
      if (tutarIziVar(ad)) return;
      o.add(YorumOlcumu(anahtar, ad, gosterim));
    }

    String pct(double v) => fmtPctIsaretli(v, digits: 1);
    String pay(double v) => fmtPct(v, digits: 1);

    if (donemPct != null && donemPct.isFinite) {
      ekle('degisim', 'Dönem içinde fiyat değişimi', pct(donemPct));
    }
    if (ist != null) {
      if (ist.enBuyukDususPct < -0.05) {
        ekle('en_derin_dusus', 'Dönem içindeki en derin geri çekilme',
            pct(ist.enBuyukDususPct));
      }
      final oyn = ist.oynaklikPct;
      if (oyn != null && oyn.isFinite) {
        ekle('oynaklik', 'Yıllıklandırılmış oynaklık', pay(oyn));
      }
      final canli = (canliBirim != null && canliBirim > 0) ? canliBirim : ist.son;
      if (ist.dusuk > 0 && ist.yuksek > ist.dusuk) {
        ekle('zirveye_uzaklik', 'Fiyatın dönem zirvesine uzaklığı',
            pct((canli / ist.yuksek - 1) * 100));
        ekle('dibe_uzaklik', 'Fiyatın dönem dibine uzaklığı',
            pct((canli / ist.dusuk - 1) * 100));
      }
    }
    if (portfoyPayi != null && portfoyPayi.isFinite && portfoyPayi > 0) {
      ekle('portfoy_payi', 'Portföy içindeki payı', pay(portfoyPayi));
    }
    if (pozisyonGetirisi != null && pozisyonGetirisi.isFinite) {
      ekle('pozisyon_getirisi', 'İlk alımdan bu yana pozisyonun getirisi',
          pct(pozisyonGetirisi));
    }
    if (eldeGun != null && eldeGun > 0 && eldeGun < 10000) {
      ekle('elde_tutma', 'İlk alımdan bu yana geçen süre', '$eldeGun gün');
    }
    for (final e in kiyasDegisimi.entries) {
      if (!e.value.isFinite) continue;
      final ad = kiyasVarligiAdi(e.key);
      ekle('kiyas_${e.key.name}', 'Aynı dönemde $ad değişimi', pct(e.value));
      if (donemPct != null && donemPct.isFinite) {
        final fark = puanGosterimi(donemPct - e.value);
        if (fark != null) {
          ekle('kiyas_${e.key.name}_fark', 'Varlığın $ad değişimine göre farkı', fark);
        }
      }
    }
    if (tufe != null) {
      for (final x in tufe.olcumler()) {
        ekle(x.anahtar, x.ad, x.gosterim);
      }
    }

    return PortfoyYorumPaketi(
      tur: YorumTuru.secili,
      baslangic: baslangic,
      bitis: bitis,
      parmakIzi: varlikParmakIzi(positionKey, miktar),
      olcumler: o.take(30).toList(),
      kapsam: YorumKapsami.varlik,
      donemKodu: period.label,
      varlikIzi: varlikIziOf(positionKey),
      varlikAdi: tutarIziVar(varlikAdi) ? null : varlikAdi,
    );
  }

  static double? _sonDeger(Map<int, double> seri, int fromMs, int toMs) {
    int? sonTs;
    double? son;
    seri.forEach((ts, v) {
      if (ts < fromMs || ts > toMs) return;
      if (sonTs == null || ts > sonTs!) {
        sonTs = ts;
        son = v;
      }
    });
    return son;
  }
}

/// Dönem sonundaki portföyün izi: pozisyon anahtarları + 5 puana yuvarlanmış
/// paylar, SHA-256 ile özetlenir. Sunucuya ham anahtar GİTMEZ (izi okuyan
/// portföyü geri kuramaz). 5 puan: fiyatın küçük oynaması (ya da bugünkü
/// bir alım) kapanmış dönemin yorumunu eskitmesin; geçmiş bir işlemin
/// eklenmesi/düzeltilmesi eskitsin.
String portfoyParmakIzi(Map<String, double> sonDegerler) {
  final toplam = sonDegerler.values.fold<double>(0, (a, b) => a + b);
  final parcalar = <String>[];
  if (toplam > 0) {
    for (final e in sonDegerler.entries) {
      final pay5 = ((e.value / toplam * 100) / 5).round() * 5;
      parcalar.add('${e.key}=$pay5');
    }
  }
  parcalar.sort();
  final ozet = sha256.convert(utf8.encode(parcalar.join('|'))).toString();
  return 'v1:${ozet.substring(0, 24)}';
}

/// Varlık kapsamının sunucu anahtarı: pozisyon anahtarının özeti. Ham
/// anahtar (sembol, mevduat sözleşme UUID'si) sunucuya GİTMEZ.
String varlikIziOf(String positionKey) =>
    'v1:${sha256.convert(utf8.encode(positionKey)).toString().substring(0, 24)}';

/// Varlık yorumunun parmak izi: pozisyon + miktar. Miktar değişirse (alım/
/// satış) aynı günün yorumu eskir; fiyat oynaması eskitmez.
String varlikParmakIzi(String positionKey, double miktar) {
  final ozet = sha256.convert(utf8.encode('$positionKey|${miktar.toStringAsPrecision(10)}'));
  return 'v1:${ozet.toString().substring(0, 24)}';
}

/// Puan farkı gösterimi: '+8,2 puan' / '−3,1 puan'. Sunucunun puan biçimi
/// (en çok 3 tam hane); dışındaysa `null` (ölçüm kurulmaz).
String? puanGosterimi(double v) {
  if (!v.isFinite || v.abs() >= 999.95) return null;
  final metin = fmtNum(v.abs(), digits: 1);
  if (metin == fmtNum(0, digits: 1)) return '$metin puan';
  return '${v > 0 ? '+' : '\u2212'}$metin puan';
}

/// Kıyas varlığının modele giden Türkçe adı (arayüz dili ne olursa olsun;
/// talimat Türkçe).
///
/// "dolar/TL" DEĞİL: ölçüm adında "TL" tutar izi sayılır ve ölçüm düşerdi
/// (`tutarIziVar`, sunucuda `TUTAR_IZI`).
String kiyasVarligiAdi(KiyasVarligi k) => switch (k) {
      KiyasVarligi.dolar => 'Amerikan doları',
      KiyasVarligi.altin => 'gram altın',
      KiyasVarligi.bist100 => 'BIST 100',
    };

const _aylar = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

/// Yorumun TÜFE ölçümleri — Performans'ın reel getiri kartıyla AYNI pencere
/// (`InflationService.pencere`, son açıklanmış aylar) ve AYNI hizalı
/// nominal (`RealReturnService.hizaliGetiri`). Pencere seçili dönemle
/// örtüşmez (TÜFE aylık açıklanır); ad bu yüzden ayları açıkça yazar ki
/// model "aynı dönemde" demesin. Yıl yazılmaz: 4 haneli sayı tutar kapısına
/// takılır.
class YorumTufesi {
  const YorumTufesi({
    required this.enflasyonPct,
    required this.ilkAy,
    required this.sonAy,
    this.nominalPct,
    this.reelPct,
    this.nominalAdi = 'portföyün',
  });

  final double enflasyonPct;

  /// `InflationWindow.ilkAy` (taban ayı; ölçülen aylar bir sonrakinden başlar).
  final DateTime ilkAy;
  final DateTime sonAy;
  final double? nominalPct;
  final double? reelPct;

  /// 'portföyün' ya da 'pozisyonun'.
  final String nominalAdi;

  String get aralik {
    final bas = DateTime(ilkAy.year, ilkAy.month + 1, 1);
    final a = _aylar[bas.month - 1], b = _aylar[sonAy.month - 1];
    return bas.year == sonAy.year && bas.month == sonAy.month ? a : '$a–$b';
  }

  List<YorumOlcumu> olcumler() {
    final o = <YorumOlcumu>[];
    if (!enflasyonPct.isFinite) return o;
    o.add(YorumOlcumu('tufe', 'Son açıklanan aylarda TÜFE ($aralik)',
        fmtPct(enflasyonPct, digits: 1)));
    final n = nominalPct;
    if (n != null && n.isFinite) {
      o.add(YorumOlcumu('tufe_nominal', 'Aynı aylarda ($aralik) $nominalAdi getirisi',
          fmtPctIsaretli(n, digits: 1)));
      final fark = puanGosterimi(InflationService.spreadPoints(n, enflasyonPct));
      if (fark != null) {
        o.add(YorumOlcumu('tufe_fark', 'Aynı aylarda getirinin TÜFE\'ye göre farkı', fark));
      }
    }
    final r = reelPct;
    if (r != null && r.isFinite) {
      o.add(YorumOlcumu('reel_getiri', 'Aynı aylarda enflasyondan arındırılmış (reel) getiri',
          fmtPctIsaretli(r, digits: 1)));
    }
    return o;
  }
}

/// SAF: seçili dönem portföy yorumunun "ekonomist" ölçümleri — paranın
/// başka yerdeki karşılığı (PME kıyası), enflasyon, oynaklık, akış oranı.
/// Hepsi Performans'ın kartlarındaki hesaplardan okunur, burada formül yok.
List<YorumOlcumu> ekonomiOlcumleri({
  required PeriodSummary ozet,
  KiyasOzeti? kiyas,
  YorumTufesi? tufe,
  double? oynaklik,
}) {
  final o = <YorumOlcumu>[];
  String pct(double v) => fmtPctIsaretli(v, digits: 1);

  final yillik = ozet.yillikGetiriPct;
  if (yillik != null && yillik.isFinite) {
    o.add(YorumOlcumu('yillik_getiri', 'Yıllık bileşik getiri', pct(yillik)));
  }
  for (final e in kiyas?.satirlar.entries ?? const <MapEntry<KiyasVarligi, KiyasHesabi>>[]) {
    final ad = kiyasVarligiAdi(e.key);
    if (e.value.getiriPct.isFinite) {
      o.add(YorumOlcumu('kiyas_${e.key.name}',
          'Aynı paralar aynı günlerde $ad yatırılsaydı getiri', pct(e.value.getiriPct)));
    }
    final f = e.value.farkPuan;
    final fark = f == null ? null : puanGosterimi(f);
    if (fark != null) {
      o.add(YorumOlcumu('kiyas_${e.key.name}_fark', 'Portföyün $ad kıyasına göre farkı', fark));
    }
  }
  if (tufe != null) o.addAll(tufe.olcumler());
  if (oynaklik != null && oynaklik.isFinite && oynaklik > 0) {
    o.add(YorumOlcumu('oynaklik', 'Portföyün yıllıklandırılmış oynaklığı',
        fmtPct(oynaklik, digits: 1)));
  }
  final katki = ozet.katkiTRY, bas = ozet.baslangicTRY;
  if (katki != null && bas != null && bas > 0 && (katki / bas).abs() >= 0.001) {
    o.add(YorumOlcumu('net_katki_orani',
        'Dönemde eklenen net para, dönem başı değere oranla', pct(katki / bas * 100)));
  }
  return o;
}

/// Saklanmış yorum (tablo satırı ya da fonksiyon yanıtı).
class PortfoyYorumu {
  const PortfoyYorumu({
    required this.tur,
    required this.baslangic,
    required this.bitis,
    required this.parmakIzi,
    required this.baslik,
    required this.maddeler,
    required this.olcumler,
    required this.olusturuldu,
  });

  final YorumTuru tur;
  final DateTime baslangic;
  final DateTime bitis;
  final String parmakIzi;
  final String baslik;
  final List<({String metin, List<String> kanit})> maddeler;
  final List<YorumOlcumu> olcumler;
  final DateTime olusturuldu;

  static PortfoyYorumu? fromRow(Map<String, dynamic> r) {
    try {
      final tur = switch (r['tur']) {
        'aylik' => YorumTuru.aylik,
        'secili' => YorumTuru.secili,
        _ => YorumTuru.haftalik,
      };
      final m = r['maddeler'];
      final ol = r['olcumler'];
      return PortfoyYorumu(
        tur: tur,
        baslangic: DateTime.parse(r['donem'] as String),
        bitis: DateTime.parse(r['bitis'] as String),
        parmakIzi: r['parmak_izi'] as String,
        baslik: (r['baslik'] as String?) ?? '',
        maddeler: [
          if (m is List)
            for (final x in m)
              if (x is Map && x['metin'] is String)
                (
                  metin: x['metin'] as String,
                  kanit: [
                    if (x['kanit'] is List)
                      for (final k in x['kanit'] as List)
                        if (k is String) k
                  ],
                ),
        ],
        olcumler: [
          if (ol is List)
            for (final x in ol)
              if (YorumOlcumu.fromJson(x) case final o?) o,
        ],
        olusturuldu: DateTime.tryParse(r['olusturuldu'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Bir maddenin kanıt çipleri (ölçüm adı · gösterim).
  List<YorumOlcumu> kanitlar(List<String> anahtarlar) => [
        for (final a in anahtarlar)
          if (olcumler.where((o) => o.anahtar == a).firstOrNull case final o?) o,
      ];
}

/// Fonksiyonun döndüğü kullanıcıya gösterilebilir neden.
enum YorumHataTuru { riza, premium, kota, reddedildi, kapali, diger }

class PortfoyYorumHatasi implements Exception {
  const PortfoyYorumHatasi(this.tur);
  final YorumHataTuru tur;
  @override
  String toString() => 'PortfoyYorumHatasi(${tur.name})';
}

/// Açık rıza kartı metninin sürümü (`pyzRizaMetin`; sunucu kaydı
/// `portfoy_yorum_rizalari.metin_surumu`). Kart metni değişince artar.
///
/// 2026-10-14: taslak → yayın. Kartın anlattığı aktarım Gizlilik 1.11 §5.5
/// ve KVKK 1.11 §5.2'ye yazıldı (0149). Genel "Onay sürümü" artmadı, Açık
/// Rıza Metni'ne bölüm eklenmedi: rıza işlemi isteyenden, ilk kullanımda bu
/// kartla alınır (yasin 2026-10-13, CLAUDE.md yasal metin istisnası).
///
/// 2026-10-14.2: kart metni seçili dönem ve varlık yorumunu da kapsıyor
/// (oynaklık, enflasyon ve piyasa kıyasları; Gizlilik/KVKK 1.12, 0152).
/// Yeni rızalar bu sürümle kaydedilir; önceki rızalar geçerli kalır:
/// gönderilen veri türü (yüzdeler) ve alıcı (Anthropic) aynı, piyasa
/// kıyasları kişisel veri değil.
const portfoyYorumRizaSurumu = '2026-10-14.2';

class PortfoyYorumuService {
  PortfoyYorumuService._();
  static final instance = PortfoyYorumuService._();

  SupabaseClient get _db => Supabase.instance.client;

  /// Dönemin paketi. Seri `HistoryService`'ten (Performans'la aynı önbellek).
  Future<PortfoyYorumPaketi> paketHazirla({
    required YorumTuru tur,
    required List<Asset> lotlar,
    required String Function(String positionKey, AssetType tur) etiket,
    DateTime? simdi,
  }) async {
    final d = yorumDonemi(tur, simdi ?? DateTime.now());
    final son = DateTime(d.bitis.year, d.bitis.month, d.bitis.day, 23, 59, 59);
    final gun = son.difference(d.baslangic).inHours / 24;
    final bd = await HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
      assets: lotlar,
      from: d.baslangic,
      to: son,
      tier: ResolutionTierMeta.pickForSpan(gun),
    );
    String et(String k) => etiket(k, bd.positionType[k] ?? AssetType.diger);
    final ozet = PeriodSummaryService.compute(
      period: tur == YorumTuru.haftalik ? SummaryPeriod.birHafta : SummaryPeriod.birAy,
      assets: lotlar,
      breakdown: bd,
      now: son,
      pencereBaslangici: d.baslangic,
      etiket: et,
    );
    return PortfoyYorumPaketi.kur(
      tur: tur,
      baslangic: d.baslangic,
      bitis: d.bitis,
      ozet: ozet,
      breakdown: bd,
      etiket: et,
    );
  }

  /// Seçili dönemin paketi (Performans, bütün portföy). Seri, pencere ve
  /// çözünürlük Özet'in kanonik serisiyle aynı (`_ozetSerisiniCek`); kıyas
  /// ve TÜFE Özet kartlarının servislerinden. Ekonomi ölçümlerinden biri
  /// kurulamazsa (ağ, endeks yok) o ölçüm düşer, yorum yine yazılır.
  Future<PortfoyYorumPaketi> seciliPaketHazirla({
    required SummaryPeriod period,
    required List<Asset> lotlar,
    required String Function(String positionKey, AssetType tur) etiket,
    double? canliSon,
    Map<AssetType, double>? canliDagilim,
    DateTime? simdi,
  }) async {
    final now = simdi ?? DateTime.now();
    final w = PeriodSummaryService.pencere(period, now);
    final tier = ResolutionTierMeta.pickForSpan(period.days.toDouble());
    final bd = await HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
      assets: lotlar,
      from: w.start,
      to: now,
      tier: tier,
    );
    String et(String k) => etiket(k, bd.positionType[k] ?? AssetType.diger);
    final ozet = PeriodSummaryService.compute(
      period: period,
      assets: lotlar,
      breakdown: bd,
      now: now,
      canliSon: canliSon,
      canliDagilim: canliDagilim,
      etiket: et,
    );

    KiyasOzeti? kiyas;
    final girdi = KiyasGirdisi.kur(
        period: period, lotlar: lotlar, seri: bd.total, now: now, canliSon: canliSon);
    if (girdi != null) {
      try {
        kiyas = KiyasService.ozet(girdi, await KiyasYukleyici.serileriGetir(period));
      } catch (e, st) {
        CrashReporter.report(e, st, reason: 'portfoy_yorumu_kiyas');
      }
    }
    final tufe = await _tufe(period, lotlar, nominalAdi: 'portföyün');
    double? oynaklik;
    if (period.days >= DonemIstatistigi.oynaklikIcinAsgariDonemGun) {
      oynaklik = InsightMetricsService.annualizedVolatility(
        bd.total,
        barSuresiGun: tier.barSuresi.inMinutes / (60 * 24),
        lotlar: lotlar,
      );
    }

    return PortfoyYorumPaketi.kur(
      tur: YorumTuru.secili,
      baslangic: w.start,
      bitis: dayKey(now),
      ozet: ozet,
      breakdown: bd,
      etiket: et,
      donemKodu: period.label,
      ekOlcumler: ekonomiOlcumleri(
          ozet: ozet, kiyas: kiyas, tufe: tufe, oynaklik: oynaklik),
    );
  }

  /// Varlık detayının seçili dönem paketi. Dönem istatistiği ve yüzdesi
  /// ekrandan gelir (ekranda görünenle aynı sayı); kıyas varlıklarının aynı
  /// penceredeki değişimi ve TÜFE burada eklenir.
  Future<PortfoyYorumPaketi> varlikPaketHazirla({
    required SummaryPeriod period,
    required String positionKey,
    required double miktar,
    required String varlikAdi,
    required List<Asset> pozisyonLotlari,
    required DonemIstatistigi? ist,
    required double? donemPct,
    required double? canliBirim,
    double? portfoyPayi,
    double? pozisyonGetirisi,
    int? eldeGun,
    DateTime? simdi,
  }) async {
    final now = simdi ?? DateTime.now();
    final w = PeriodSummaryService.pencere(period, now);
    final kiyas = <KiyasVarligi, double>{};
    try {
      final seriler = await KiyasYukleyici.serileriGetir(period);
      for (final e in seriler.entries) {
        final bas = KiyasService.fiyatAt(e.value, w.start.millisecondsSinceEpoch);
        final son = KiyasService.fiyatAt(e.value, now.millisecondsSinceEpoch);
        if (bas != null && son != null && bas > 0) kiyas[e.key] = (son / bas - 1) * 100;
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'varlik_yorumu_kiyas');
    }
    final tufe = await _tufe(period, pozisyonLotlari, nominalAdi: 'pozisyonun');
    return PortfoyYorumPaketi.varlikKur(
      period: period,
      baslangic: w.start,
      bitis: dayKey(now),
      positionKey: positionKey,
      miktar: miktar,
      varlikAdi: varlikAdi,
      ist: ist,
      donemPct: donemPct,
      canliBirim: canliBirim,
      portfoyPayi: portfoyPayi,
      pozisyonGetirisi: pozisyonGetirisi,
      eldeGun: eldeGun,
      kiyasDegisimi: kiyas,
      tufe: tufe,
    );
  }

  /// Performans'ın reel getiri kartıyla AYNI pencere kuralı
  /// (`ozet_yan_veri`): 1H'de TÜFE sorulmaz (aylık açıklanır), 1A'da son
  /// açıklanan ay, 5Y'de endeks yetmezse veri olan en erken aya kısaltılır.
  Future<YorumTufesi?> _tufe(SummaryPeriod period, List<Asset> lotlar,
      {required String nominalAdi}) async {
    if (period.days < SummaryPeriod.birAy.days) return null;
    try {
      final svc = InflationService.instance;
      var w = await svc.pencere(period == SummaryPeriod.birAy ? 30 : period.days);
      if (w == null && period.days > SummaryPeriod.birYil.days) {
        w = await svc.pencereKapsayan(period.days,
            enErken: PeriodSummaryService.ilkAlimTarihi(lotlar));
      }
      if (w == null) return null;
      final g = lotlar.isEmpty ? null : await RealReturnService.hizaliGetiri(lotlar, w);
      return YorumTufesi(
        enflasyonPct: w.pct,
        ilkAy: w.ilkAy,
        sonAy: w.sonAy,
        nominalPct: g?.nominal,
        reelPct: g?.reel,
        nominalAdi: nominalAdi,
      );
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'portfoy_yorumu_tufe');
      return null;
    }
  }

  /// Seçili dönemin bugünkü saklı yorumu (kapsam + varlık + dönem + bitiş
  /// günü). Yoksa null — dünkü pencere bugünün yorumu sayılmaz.
  Future<PortfoyYorumu?> kayitliSeciliYorum({
    required YorumKapsami kapsam,
    required String donemKodu,
    required DateTime bitis,
    String? varlikIzi,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    var q = _db
        .from('portfoy_yorumlari')
        .select('tur, donem, bitis, parmak_izi, baslik, maddeler, olcumler, olusturuldu')
        .eq('user_id', uid)
        .eq('tur', YorumTuru.secili.sunucuAdi)
        .eq('kapsam', kapsam.name)
        .eq('donem_kodu', donemKodu)
        .eq('bitis', isoGun(bitis));
    q = varlikIzi == null ? q.isFilter('varlik_izi', null) : q.eq('varlik_izi', varlikIzi);
    final rows = await q.order('olusturuldu', ascending: false).limit(1);
    if (rows.isEmpty) return null;
    return PortfoyYorumu.fromRow(rows.first);
  }

  /// Dönemin saklı yorumu (RLS: yalnız kendi yayındaki satırı). Yoksa null.
  Future<PortfoyYorumu?> kayitliYorum(YorumTuru tur, DateTime baslangic) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    final rows = await _db
        .from('portfoy_yorumlari')
        .select('tur, donem, bitis, parmak_izi, baslik, maddeler, olcumler, olusturuldu')
        .eq('user_id', uid)
        .eq('tur', tur.sunucuAdi)
        .eq('donem', isoGun(baslangic))
        .order('olusturuldu', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return PortfoyYorumu.fromRow(rows.first);
  }

  /// Geçerli açık rıza var mı? Hata → null (ekran rıza varsaymaz).
  Future<bool?> rizaVarMi() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return null;
      final rows = await _db
          .from('portfoy_yorum_rizalari')
          .select('geri_cekildi_at')
          .eq('user_id', uid);
      if (rows.isEmpty) return false;
      return rows.first['geri_cekildi_at'] == null;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'portfoy_yorum_rizasi_okunamadi');
      return null;
    }
  }

  /// Rıza ver / geri çek. Geri çekme sunucuda yorumları da siler (0145).
  Future<void> rizaAyarla(bool ver) => _db.rpc<dynamic>(
        'portfoy_yorum_rizasi_ayarla',
        params: {'p_ver': ver, 'p_metin_surumu': portfoyYorumRizaSurumu},
      );

  /// Yorum yazdır (ya da sunucudaki kaydı al). 2xx dışı → [PortfoyYorumHatasi].
  Future<PortfoyYorumu> yorumla(PortfoyYorumPaketi paket) async {
    try {
      final res = await _db.functions.invoke('portfoy-yorumla', body: paket.toJson());
      final data = res.data;
      final satir = data is Map ? data['yorum'] : null;
      final y = satir is Map ? PortfoyYorumu.fromRow(Map<String, dynamic>.from(satir)) : null;
      if (y == null) throw const PortfoyYorumHatasi(YorumHataTuru.diger);
      return y;
    } on FunctionException catch (e, st) {
      final neden = e.details is Map ? (e.details as Map)['neden'] : null;
      final tur = switch (neden) {
        'riza' => YorumHataTuru.riza,
        'premium' => YorumHataTuru.premium,
        'gunluk_hak' || 'tavan' => YorumHataTuru.kota,
        'reddedildi' => YorumHataTuru.reddedildi,
        'kapali' => YorumHataTuru.kapali,
        _ => YorumHataTuru.diger,
      };
      if (tur == YorumHataTuru.diger) {
        CrashReporter.report(e, st, reason: 'portfoy_yorumla_${e.status}');
      }
      throw PortfoyYorumHatasi(tur);
    }
  }
}
