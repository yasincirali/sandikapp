import 'dart:math' as math;

import '../utils/tr_katla.dart';

/// Mevduat formundaki banka seçicinin satırı (0129 `mevduat_bankalari`,
/// bayrak `mevduat_banka_secici`).
///
/// ## Logo yok, harf rozeti var
/// Banka adı tanımlayıcı kullanım (paranın durduğu yer); logo tescilli
/// marka ve tasarım — bankaların marka kuralları izinsiz kullanımı
/// yasaklıyor, App Review 5.2 de reddedebiliyor (yasin'e 2026-10-09
/// yanıtı). Rozet adın kendisinden üretilir ([rozet]).
class MevduatBankasi {
  const MevduatBankasi({
    required this.kod,
    required this.ad,
    required this.katilim,
    this.digerAdlar = const [],
  });

  final String kod;
  final String ad;

  /// Katılım bankası: kâr payı önceden belli bir oran değil → faiz
  /// varsayılanı YAZILMAZ ([varsayilanFaiz]).
  final bool katilim;

  /// Aramada eşleşen eski ad / marka ("Finansbank", "CEPTETEB").
  final List<String> digerAdlar;

  static MevduatBankasi? fromMap(Map<String, dynamic> m) {
    final kod = (m['kod'] as String?)?.trim();
    final ad = (m['ad'] as String?)?.trim();
    if (kod == null || kod.isEmpty || ad == null || ad.isEmpty) return null;
    return MevduatBankasi(
      kod: kod,
      ad: ad,
      katilim: m['tur'] == 'katilim',
      digerAdlar: [
        for (final x in (m['diger_adlar'] as List?) ?? const [])
          if (x is String && x.trim().isNotEmpty) x.trim(),
      ],
    );
  }

  /// Harf rozeti: "QNB", "TEB", "GB" (Garanti BBVA), "YK", "Z" (Ziraat).
  ///
  /// Kural: ilk kelime 2–4 harflik kısaltmaysa (QNB, HSBC, ICBC, TOM) o;
  /// değilse "Bank/Bankası" atılıp ilk iki kelimenin baş harfleri.
  /// "DenizBank" gibi bitişik ad büyük harften bölünür.
  String get rozet {
    final kelimeler = ad
        .replaceAllMapped(
            RegExp(r'([a-zçğıöşü])([A-ZÇĞİÖŞÜ])'), (m) => '${m[1]} ${m[2]}')
        .split(RegExp(r'\s+'))
        .where((k) => k.isNotEmpty)
        .toList();
    if (kelimeler.isEmpty) return '?';
    final ilk = kelimeler.first;
    if (ilk.length >= 2 &&
        ilk.length <= 4 &&
        ilk == ilk.toUpperCase() &&
        RegExp(r'^[A-ZÇĞİÖŞÜ]+$').hasMatch(ilk)) {
      return ilk;
    }
    const genel = {'bank', 'bankasi'};
    final anlamli =
        kelimeler.where((k) => !genel.contains(trKatla(k))).take(2).toList();
    final kaynak = anlamli.isEmpty ? kelimeler.take(1) : anlamli;
    return kaynak.map((k) => _buyukIlk(k)).join();
  }

  static String _buyukIlk(String k) {
    final c = k.substring(0, 1);
    // Türkçe büyük harf: i → İ.
    return c == 'i' ? 'İ' : c.toUpperCase();
  }

  /// Arama: ad ya da diğer adlardan biri sorguyu (Türkçe katlanmış) içeriyor.
  bool eslesir(String sorgu) {
    final q = trKatla(sorgu.trim());
    if (q.isEmpty) return true;
    if (trKatla(ad).contains(q)) return true;
    return digerAdlar.any((x) => trKatla(x).contains(q));
  }
}

/// TCMB haftalık ağırlıklı ortalama faizi, bir vade dilimi (0129
/// `mevduat_faiz_ortalama`). Bankaya özel DEĞİL.
class MevduatFaizOrtalamasi {
  const MevduatFaizOrtalamasi({
    required this.dilim,
    required this.yillikBilesik,
    required this.veriTarihi,
  });

  /// 'ay1' | 'ay3' | 'ay6' | 'yil1' | 'yil1_ustu'.
  final String dilim;

  /// TCMB tanımı: yıl bazına getirilmiş (BİLEŞİK) yıllık oran, %.
  final double yillikBilesik;

  /// Verinin ait olduğu hafta.
  final DateTime veriTarihi;

  /// Faiz/tarih yoksa ya da veri [simdi]'den 45 günden eskiyse `null` —
  /// uydurma ya da bayat sayı forma girmez. Sunucu EVDS'ye ulaşamadığı
  /// turda (`evds_hata`) eski değeri korur; o değer taze olduğu sürece
  /// geçerlidir.
  static MevduatFaizOrtalamasi? fromMap(Map<String, dynamic> m,
      {required DateTime simdi}) {
    final dilim = m['vade_dilimi'] as String?;
    final faiz = (m['yillik_faiz'] as num?)?.toDouble();
    final tarih = DateTime.tryParse('${m['veri_tarihi'] ?? ''}');
    if (dilim == null ||
        faiz == null ||
        faiz <= 0 ||
        tarih == null ||
        simdi.difference(tarih).inDays > 45) {
      return null;
    }
    return MevduatFaizOrtalamasi(
        dilim: dilim, yillikBilesik: faiz, veriTarihi: tarih);
  }
}

/// Vade (gün) → TCMB vade dilimi. Vadesiz/günlük faizli hesap için `null`:
/// TCMB'nin vadesiz serisi bu tabloda yok, varsayılan yazılmaz.
///
/// Sınırlar: bankaların "32 gün" ürünü TCMB'nin "1 aya kadar" diliminde
/// raporlanır; 92 → "3 aya kadar", 184 → "6 aya kadar", 366 → "1 yıla kadar".
String? mevduatVadeDilimi(int? gun) {
  if (gun == null || gun <= 0) return null;
  if (gun <= 32) return 'ay1';
  if (gun <= 92) return 'ay3';
  if (gun <= 184) return 'ay6';
  if (gun <= 366) return 'yil1';
  return 'yil1_ustu';
}

/// Bileşik yıllık oranı (TCMB) [gun] vadeli mevduatın BASİT yıllık oranına
/// çevirir — bankanın yazdığı ve uygulamanın hesapladığı oran basittir
/// (`MevduatHesabi`, 365 gün).
///
/// Neden: TCMB ortalaması yıl bazına bileşiklendirilmiş; 32 günlükte %45
/// bileşik ≈ %37,8 basit. Çevirmeden yazmak getiriyi ~7 puan şişirirdi.
/// basit = ((1 + b)^(gün/365) − 1) × 365/gün
double bilesiktenBasitYillik(double bilesikYuzde, int gun) {
  final b = bilesikYuzde / 100;
  final donem = math.pow(1 + b, gun / 365).toDouble() - 1;
  return donem * 365 / gun * 100;
}

/// Formun yazacağı varsayılan yıllık brüt faiz (basit, %) ve kaynağın
/// haftası; yazılmayacaksa `null`.
///
/// Yazılmaz: banka seçilmemiş, katılım bankası (kâr payı önceden belli
/// değil), vadesiz hesap, o dilimin ortalaması yok/bayat.
({double oran, DateTime hafta})? mevduatVarsayilanFaiz({
  required MevduatBankasi? banka,
  required int? gun,
  required Map<String, MevduatFaizOrtalamasi> ortalamalar,
}) {
  if (banka == null || banka.katilim) return null;
  final dilim = mevduatVadeDilimi(gun);
  if (dilim == null || gun == null) return null;
  final o = ortalamalar[dilim];
  if (o == null) return null;
  return (
    oran: bilesiktenBasitYillik(o.yillikBilesik, gun),
    hafta: o.veriTarihi
  );
}
