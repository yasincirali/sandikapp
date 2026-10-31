import '../utils/tr_format.dart' show parseTrNumber;
import 'disa_aktarim/dosya_adi.dart';
import 'fiyat_kaynagi.dart' show KiyasVarligi;
import 'portfoy_yorumu_service.dart';

/// AI yorumunun "Tamamını oku" sayfası ve PDF notu için düzeni (2026-10-14).
///
/// yasin (14 Eki): "pdf ile paylaşılabilir bir tasarımla gösterilebilir mi,
/// popup sayfa ya da yeni sayfa olabilir" → seçilen ikili 1A (açılır sayfa)
/// + 2A (A4 değerlendirme notu), "pdf'te logomuz olmalı". Tasarım:
/// https://claude.ai/artifact/TREkFu1hk9jK3qfEE9vrdu
///
/// Saf: kayıtlı [PortfoyYorumu]'ndan hangi ölçümün manşet, hangisinin
/// gösterge, hangisinin kıyas çubuğu olacağına YALNIZ burası karar verir;
/// açılır sayfa ve PDF aynı sonucu çizer, iki yüzey ayrışmaz.
///
/// **Yeni sayı yok.** Her gösterim ölçümün telefonda yazılmış hâlidir
/// (`YorumOlcumu.gosterim`). Kıyas çubuğunun UZUNLUĞU için gösterim
/// okunur ([yuzdeDegeri]); okunamazsa çubuk çizilmez (fiyat kaynağı
/// sözleşmesi madde 3: bilinmiyorsa uydurma yok).
///
/// Ölçüm adları Türkçe (modele giden ad; kanıt çipleri de Türkçe). Not da
/// Türkçe yazılır: yorum metni Türkçe olduğu için PDF'in tamamı Türkçe.
class YorumNotu {
  const YorumNotu({
    required this.yorum,
    required this.kapsam,
    required this.varlikAdi,
    required this.donemAdi,
    required this.manset,
    required this.mansetAlt,
    required this.gostergeler,
    required this.kiyaslar,
    required this.farklar,
    required this.digerleri,
  });

  final PortfoyYorumu yorum;
  final YorumKapsami kapsam;

  /// Varlık kapsamında ekranda görünen ad; portföyde `null`.
  final String? varlikAdi;

  /// "Son 3 ay", "Geçen hafta" …
  final String donemAdi;

  /// Dönem getirisi (portföy) ya da fiyat değişimi (varlık).
  final YorumOlcumu? manset;

  /// Manşetin altındaki tek satır (reel getiri, yoksa pozisyon getirisi).
  final YorumOlcumu? mansetAlt;

  /// PDF'teki dört gösterge (manşet dahil), sırası sabit.
  final List<YorumOlcumu> gostergeler;

  /// Kıyas çubukları: kendisi önce, sonra büyükten küçüğe.
  final List<KiyasCubugu> kiyaslar;

  /// `…_fark` ölçümleri (puan).
  final List<YorumOlcumu> farklar;

  /// Açılır sayfadaki gruplu satırlar: manşet dışındaki tüm ölçümler.
  final List<YorumOlcumu> digerleri;

  static const _gostergeSirasi = [
    'getiri',
    'degisim',
    'reel_getiri',
    'en_derin_dusus',
    'oynaklik',
    'yillik_getiri',
    'pozisyon_getirisi',
    'portfoy_payi',
  ];

  static YorumNotu kur(
    PortfoyYorumu y, {
    required YorumKapsami kapsam,
    required String donemAdi,
    String? varlikAdi,
  }) {
    YorumOlcumu? bul(String a) =>
        y.olcumler.where((o) => o.anahtar == a).firstOrNull;
    final manset = bul('getiri') ?? bul('degisim');
    final mansetAlt = bul('reel_getiri') ?? bul('pozisyon_getirisi');
    final gostergeler = [
      for (final a in _gostergeSirasi)
        if (bul(a) case final o?) o,
    ].take(4).toList();

    final kiyaslar = <KiyasCubugu>[];
    if (manset != null) {
      final d = yuzdeDegeri(manset.gosterim);
      if (d != null) {
        kiyaslar.add(KiyasCubugu(
            kapsam == YorumKapsami.varlik ? (varlikAdi ?? 'Varlık') : 'Portföy',
            d,
            manset.gosterim,
            kendisi: true));
      }
    }
    final digerKiyas = <KiyasCubugu>[];
    for (final o in y.olcumler) {
      final ad = _kiyasAdi(o.anahtar);
      if (ad == null) continue;
      final d = yuzdeDegeri(o.gosterim);
      if (d != null) digerKiyas.add(KiyasCubugu(ad, d, o.gosterim));
    }
    digerKiyas.sort((a, b) => b.deger.compareTo(a.deger));
    kiyaslar.addAll(digerKiyas);

    return YorumNotu(
      yorum: y,
      kapsam: kapsam,
      varlikAdi: varlikAdi,
      donemAdi: donemAdi,
      manset: manset,
      mansetAlt: mansetAlt,
      gostergeler: gostergeler,
      kiyaslar: kiyaslar.length > 1 ? kiyaslar : const [],
      farklar: [
        for (final o in y.olcumler)
          if (o.anahtar.endsWith('_fark')) o,
      ],
      digerleri: [
        for (final o in y.olcumler)
          if (!identical(o, manset)) o,
      ],
    );
  }

  /// Kıyas ölçümünün kısa adı; kıyas değilse `null`. TÜFE çubuğu dönemin
  /// enflasyonu (`tufe`), nominal/fark ölçümleri çubuk olmaz.
  static String? _kiyasAdi(String anahtar) {
    if (anahtar == 'tufe') return 'TÜFE';
    if (!anahtar.startsWith('kiyas_') || anahtar.endsWith('_fark')) return null;
    final k = KiyasVarligi.values
        .where((v) => 'kiyas_${v.name}' == anahtar)
        .firstOrNull;
    if (k == null) return null;
    final ad = kiyasVarligiAdi(k);
    return ad[0].toUpperCase() + ad.substring(1);
  }

  /// Satır ve gösterge etiketi: bilinen ölçümlerde kısa ad, değilse
  /// ölçümün kendi adı.
  static String kisaAd(YorumOlcumu o) {
    final k = _kisaAdlar[o.anahtar] ?? _kiyasAdi(o.anahtar);
    if (k != null) return k;
    if (o.anahtar.endsWith('_fark')) {
      final temel = _kiyasAdi(o.anahtar.substring(0, o.anahtar.length - 5));
      if (temel != null) return '$temel farkı';
    }
    return o.ad;
  }

  static const _kisaAdlar = {
    'getiri': 'Dönem getirisi',
    'degisim': 'Dönem değişimi',
    'reel_getiri': 'Reel getiri',
    'en_derin_dusus': 'En derin düşüş',
    'oynaklik': 'Oynaklık (yıllık)',
    'yillik_getiri': 'Yıllık getiri',
    'pozisyon_getirisi': 'Pozisyon getirisi',
    'portfoy_payi': 'Portföy payı',
    'elde_tutma': 'Elde tutma',
    'toparlanma': 'Toparlanma süresi',
    'zirveye_uzaklik': 'Zirveye uzaklık',
    'dibe_uzaklik': 'Dibe uzaklık',
    'ilk_uc_pay': 'En büyük 3 varlığın payı',
    'pozisyon_sayisi': 'Varlık sayısı',
  };

  /// Dönemin Türkçe adı (sunucudaki `DONEM_ADI` ile aynı sözler).
  static String donemAdiOf(YorumTuru tur, String? donemKodu) => switch (tur) {
        YorumTuru.haftalik => 'Geçen hafta',
        YorumTuru.aylik => 'Geçen ay',
        YorumTuru.secili => switch (donemKodu) {
            '1H' => 'Son 1 hafta',
            '1A' => 'Son 1 ay',
            '3A' => 'Son 3 ay',
            '6A' => 'Son 6 ay',
            '1Y' => 'Son 1 yıl',
            '5Y' => 'Son 5 yıl',
            _ => 'Seçili dönem',
          },
      };

  /// PDF ve paylaşım dosyasının adı; kalıp ve gerekçe `belgeDosyaAdi`
  /// (2026-10-31). Belge türü PDF başlığıyla aynı ("Portföy değerlendirme
  /// notu"), varlık notunda varlığın adı, dönem türüne göre:
  /// `sandık Portföy Değerlendirme Notu Haftalık 2026-10-20 (20-26 Ekim)`,
  /// `… Aylık 2026-09 (Eylül)`, `sandık Varlık Değerlendirme Notu THYAO
  /// Son 3 ay 2026-10-14`. Eskiden `sandik-yorum-2026-10-14`: hafta mı 3 ay
  /// mı, hangi varlık, addan okunmuyordu.
  String get dosyaAdi {
    final tur = kapsam == YorumKapsami.varlik
        ? 'Varlık Değerlendirme Notu'
        : 'Portföy Değerlendirme Notu';
    final donem = switch (yorum.tur) {
      YorumTuru.haftalik =>
        'Haftalık ${haftaDonemi(yorum.baslangic, yorum.bitis)}',
      YorumTuru.aylik => 'Aylık ${ayDonemi(yorum.baslangic)}',
      YorumTuru.secili => '$donemAdi ${gunDonemi(yorum.bitis)}',
    };
    return belgeDosyaAdi(tur, donem,
        varlik: kapsam == YorumKapsami.varlik ? varlikAdi : null);
  }
}

/// Bir kıyas çubuğu: [deger] yalnız uzunluk için, ekranda [gosterim] yazar.
class KiyasCubugu {
  const KiyasCubugu(this.ad, this.deger, this.gosterim, {this.kendisi = false});
  final String ad;
  final double deger;
  final String gosterim;
  final bool kendisi;
}

/// Türkçe büyük harf: `i` → `İ`, `ı` → `I` (Dart'ın `toUpperCase`'i
/// dilden bağımsızdır; "Para birimi" → "PARA BIRIMI" yazıyordu).
String trBuyuk(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// `+%11,4` / `−%4,6` / `%7,9` → 11.4 / -4.6 / 7.9; yüzde değilse `null`.
double? yuzdeDegeri(String gosterim) {
  final s = gosterim.trim();
  if (!s.contains('%')) return null;
  final negatif = s.startsWith('−') || s.startsWith('-');
  final v = parseTrNumber(s.replaceAll(RegExp(r'[+−\-%]'), ''));
  if (v == null || !v.isFinite) return null;
  return negatif ? -v : v;
}
