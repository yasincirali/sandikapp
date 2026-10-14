import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import '../utils/tr_format.dart';
import 'crash_reporter.dart';
import 'history_service.dart';
import 'insight_metrics_service.dart';
import 'period_summary_service.dart';

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
enum YorumTuru {
  haftalik,
  aylik;

  String get sunucuAdi => name;
}

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
  });

  final YorumTuru tur;
  final DateTime baslangic;
  final DateTime bitis;
  final String parmakIzi;
  final List<YorumOlcumu> olcumler;

  /// Yorum yazmaya değer mi? Dönemde seri yoksa (portföy yeni, veri yok)
  /// model çağrılmaz — "bu hafta %0" diye uydurma bir yorum çıkmasın.
  bool get yeterli => olcumler.any((o) => o.anahtar == 'getiri') && olcumler.length >= 2;

  Map<String, Object> toJson() => {
        'tur': tur.sunucuAdi,
        'baslangic': isoGun(baslangic),
        'bitis': isoGun(bitis),
        'parmak_izi': parmakIzi,
        'olcumler': [for (final o in olcumler) o.toJson()],
      };

  /// SAF: dönem özeti + seri → ölçümler. Test `portfoy_yorumu_test`.
  ///
  /// [ozet] `PeriodSummaryService.compute(pencereBaslangici: baslangic,
  /// now: bitis 23:59:59)` ile kurulmuş olmalı (çağıran [PortfoyYorumuService.paketHazirla]).
  static PortfoyYorumPaketi kur({
    required YorumTuru tur,
    required DateTime baslangic,
    required DateTime bitis,
    required PeriodSummary ozet,
    required PortfolioHistoryBreakdown breakdown,
    required String Function(String positionKey) etiket,
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

    return PortfoyYorumPaketi(
      tur: tur,
      baslangic: baslangic,
      bitis: bitis,
      parmakIzi: portfoyParmakIzi(sonDegerler),
      olcumler: o.take(30).toList(),
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
      final tur = r['tur'] == 'aylik' ? YorumTuru.aylik : YorumTuru.haftalik;
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
const portfoyYorumRizaSurumu = '2026-10-14';

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
