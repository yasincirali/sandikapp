// Halka arz takvimi kaydı (F6, ADR-3).
//
// Veri elle derlenmiş statik JSON'dan gelir (`docs/data/halka_arz.json`,
// GitHub Pages; gömülü kopyası `assets/data/halka_arz.json`). Bu dosya yalnızca
// şemayı ve saf durum kuralını taşır — ağ, önbellek ve asset okuma
// `HalkaArzService`'te.
//
// **Uydurma sayı yasak** (fiyat kaynağı sözleşmesi, madde 3): doğrulanamayan
// alan JSON'da `null` durur ve burada da `null` kalır. Fiyatı bilinmeyen bir
// kayıt için 0 ya da tahmini değer ÜRETİLMEZ; ekranda "—" yazar.

import '../utils/tr_format.dart' show dayKey;

/// Bir kaydın bugüne göre nerede olduğu. Sıra ekrandaki grup sırasıdır:
/// kullanıcıyı en çok ilgilendiren (şu an katılınabilen) en üstte.
enum HalkaArzDurumu {
  talepToplaniyor,
  yaklasan,
  islemBekliyor,
  islemGoruyor,
  bilinmiyor,
}

/// Dağıtım yönteminin bilinen değerleri. JSON'da serbest metin ("eşit",
/// "oransal", …) durur; tanınmayan değer ekranda olduğu gibi yazılır.
enum HalkaArzDagitim { esit, oransal, diger }

class HalkaArz {
  const HalkaArz({
    required this.kod,
    required this.sirket,
    required this.kaynak,
    this.talepBaslangic,
    this.talepBitis,
    this.fiyat,
    this.dagitim,
    this.islemBaslangic,
    this.pazar,
    this.guncelleme,
  });

  /// BIST işlem kodu, `.IS` son eki OLMADAN ("NETGL").
  final String kod;
  final String sirket;

  /// Kaydın dayandığı sayfa. Zorunlu: kaynağı olmayan kayıt listeye girmez.
  final String kaynak;

  /// Tarihler yalnızca GÜN taşır (yerel gece yarısı).
  final DateTime? talepBaslangic;
  final DateTime? talepBitis;

  /// Pay başına halka arz fiyatı (TL). Bilinmiyorsa `null` — 0 değil.
  final double? fiyat;
  final String? dagitim;
  final DateTime? islemBaslangic;
  final String? pazar;
  final DateTime? guncelleme;

  /// Portföy kaydında kullanılan sembol. Uygulamadaki BIST sembolleri
  /// Yahoo biçiminde (`THYAO.IS`) saklanır; ekleme formu bu biçimi görünce
  /// hisse seçicisini doldurur (`AddAssetFormState.initial`).
  String get sembol => '$kod.IS';

  HalkaArzDagitim? get dagitimTuru {
    final d = dagitim?.trim().toLowerCase();
    if (d == null || d.isEmpty) return null;
    if (d.startsWith('eşit') || d.startsWith('esit')) return HalkaArzDagitim.esit;
    if (d.startsWith('oransal')) return HalkaArzDagitim.oransal;
    return HalkaArzDagitim.diger;
  }

  /// JSON kaydını okur. Zorunlu alanı (kod, şirket, kaynak) eksik ya da
  /// tarihi bozuk kayıt `null` döner — yarım kayıt listeye sızmaz. Bozuk
  /// tarih "bilinmiyor" (`null`) sayılmaz: yazım hatası sessizce yanlış
  /// grupta görünmesin diye kaydın tamamı düşer.
  static HalkaArz? fromJson(Map<String, dynamic> j) {
    String? metin(String k) {
      final v = j[k];
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    final kod = metin('kod');
    final sirket = metin('sirket');
    final kaynak = metin('kaynak');
    if (kod == null || sirket == null || kaynak == null) return null;

    var bozuk = false;
    DateTime? tarih(String k) {
      final v = j[k];
      if (v == null) return null;
      final t = v is String ? isoGun(v) : null;
      if (t == null) bozuk = true;
      return t;
    }

    final talepBaslangic = tarih('talep_baslangic');
    final talepBitis = tarih('talep_bitis');
    final islemBaslangic = tarih('islem_baslangic');
    final guncelleme = tarih('guncelleme');
    if (bozuk) return null;

    final f = j['fiyat'];
    final fiyat = f is num && f > 0 ? f.toDouble() : null;

    return HalkaArz(
      kod: kod.toUpperCase(),
      sirket: sirket,
      kaynak: kaynak,
      talepBaslangic: talepBaslangic,
      talepBitis: talepBitis,
      fiyat: fiyat,
      dagitim: metin('dagitim'),
      islemBaslangic: islemBaslangic,
      pazar: metin('pazar'),
      guncelleme: guncelleme,
    );
  }

  /// `YYYY-MM-DD` → yerel gece yarısı. Başka biçim (saat, saat dilimi,
  /// "2026-9-1") ya da takvimde olmayan gün (`2026-02-30`) `null`.
  static DateTime? isoGun(String s) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final a = int.parse(m.group(2)!);
    final g = int.parse(m.group(3)!);
    final t = DateTime(y, a, g);
    // DateTime taşmayı sessizce sonraki aya kaydırır (30 Şubat → 2 Mart).
    if (t.year != y || t.month != a || t.day != g) return null;
    return t;
  }
}

/// Liste + nereden geldiği. Ekran, ağdan gelmeyen listeyi "çevrimdışı"
/// notuyla gösterir; kullanıcı eski veriye baktığını bilmeli.
enum HalkaArzKaynagi { ag, onbellek, gomulu }

class HalkaArzListesi {
  const HalkaArzListesi({
    required this.kayitlar,
    required this.kaynak,
    this.guncelleme,
  });

  final List<HalkaArz> kayitlar;
  final HalkaArzKaynagi kaynak;

  /// Dosya düzeyindeki derleme tarihi.
  final DateTime? guncelleme;

  /// Desteklenen şema sürümü. Daha yenisi gelirse (alan anlamı değişmiş
  /// olabilir) liste reddedilir ve bir önceki kaynak kullanılır.
  static const desteklenenSurum = 1;

  /// Dosyanın tamamını okur. Şema uymazsa `null`; tek tek bozuk kayıtlar
  /// atlanır (bir yazım hatası bütün takvimi karartmasın).
  static HalkaArzListesi? fromJson(Object? j, HalkaArzKaynagi kaynak) {
    if (j is! Map<String, dynamic>) return null;
    if (j['surum'] != desteklenenSurum) return null;
    final ham = j['kayitlar'];
    if (ham is! List) return null;
    final kayitlar = <HalkaArz?>[
      for (final e in ham)
        if (e is Map<String, dynamic>) HalkaArz.fromJson(e),
    ].whereType<HalkaArz>().toList();
    final g = j['guncelleme'];
    return HalkaArzListesi(
      kayitlar: kayitlar,
      kaynak: kaynak,
      guncelleme: g is String ? HalkaArz.isoGun(g) : null,
    );
  }
}

/// Kaydın [simdi]'ye göre durumu. Saf fonksiyon: saat değil GÜN karşılaştırılır
/// (talep son günü akşamı hâlâ "talep toplanıyor" sayılır; aracı kurumların
/// kapanış saati kurumdan kuruma değişir, onu bilmiyoruz).
///
/// Kural — yalnızca BİLİNEN tarihlerden çıkarım, boşluk tahminle doldurulmaz:
///   · işlem başlangıcı geldiyse → işlem görüyor
///   · talep başlangıcından önce → yaklaşan
///   · talep aralığının içinde → talep toplanıyor (aralığın iki ucu da
///     bilinmeli; yalnız başlangıç biliniyorsa sadece o GÜN kesin)
///   · talep bitti, işlem başlamadı / tarihi yok → işlem görmeyi bekliyor
///   · geri kalan her şey → bilinmiyor
HalkaArzDurumu halkaArzDurumu(HalkaArz a, DateTime simdi) {
  final bugun = dayKey(simdi);
  final bas = a.talepBaslangic;
  final bit = a.talepBitis;
  final islem = a.islemBaslangic;

  if (islem != null && !bugun.isBefore(islem)) {
    return HalkaArzDurumu.islemGoruyor;
  }
  if (bas != null && bugun.isBefore(bas)) return HalkaArzDurumu.yaklasan;
  if (bas != null && bit != null && !bugun.isAfter(bit)) {
    return HalkaArzDurumu.talepToplaniyor;
  }
  if (bas != null && bit == null && bugun == bas) {
    return HalkaArzDurumu.talepToplaniyor;
  }
  if (bit != null && bugun.isAfter(bit)) return HalkaArzDurumu.islemBekliyor;
  return HalkaArzDurumu.bilinmiyor;
}

/// "Katıldım" kaydı ancak dağıtım sonuçları açıklandıktan sonra anlamlı:
/// talep toplanırken ya da öncesinde kaç lot düşeceği bilinmez. Tarihi
/// belirsiz kayıtta da katılım olup olmadığı bilinmez.
bool halkaArzKatilimKaydedilebilir(HalkaArzDurumu d) =>
    d == HalkaArzDurumu.islemBekliyor || d == HalkaArzDurumu.islemGoruyor;

/// Katılım lot'unun alış tarihi (ekleme formuna ön dolu gider).
///
/// İşlem başlangıcı biliniyor ve geldiyse O GÜN: fiyat serisi o günden
/// başlar; daha eski bir tarih, grafikte kotasyonu olmayan günler üretirdi.
/// İlk gün kapanışı ile halka arz fiyatı arasındaki fark böylece kâr/zarar
/// olarak görünür. İşlem henüz başlamadıysa (ya da tarih yoksa) bugün —
/// form ileri tarih kabul etmez ve tahmini tarih yazılmaz.
DateTime halkaArzAlisTarihi(HalkaArz a, DateTime simdi) {
  final bugun = dayKey(simdi);
  final islem = a.islemBaslangic;
  if (islem != null && !islem.isAfter(bugun)) return islem;
  return bugun;
}

/// Kayıtları durum gruplarına ayırır; boş grup dönmez. Grup içi sıra:
/// talep/yaklaşan en yakın tarih önce, işlem görenler en yeni önce.
Map<HalkaArzDurumu, List<HalkaArz>> halkaArzGruplari(
  List<HalkaArz> kayitlar,
  DateTime simdi,
) {
  final gruplar = <HalkaArzDurumu, List<HalkaArz>>{};
  for (final a in kayitlar) {
    (gruplar[halkaArzDurumu(a, simdi)] ??= []).add(a);
  }
  int artan(DateTime? x, DateTime? y) {
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  }

  for (final e in gruplar.entries) {
    switch (e.key) {
      case HalkaArzDurumu.talepToplaniyor:
      case HalkaArzDurumu.yaklasan:
        e.value.sort((x, y) => artan(x.talepBaslangic, y.talepBaslangic));
      case HalkaArzDurumu.islemGoruyor:
        e.value.sort((x, y) => artan(y.islemBaslangic, x.islemBaslangic));
      case HalkaArzDurumu.islemBekliyor:
      case HalkaArzDurumu.bilinmiyor:
        e.value.sort((x, y) => artan(y.talepBitis, x.talepBitis));
    }
  }
  return {
    for (final d in HalkaArzDurumu.values)
      if (gruplar[d] != null) d: gruplar[d]!,
  };
}
