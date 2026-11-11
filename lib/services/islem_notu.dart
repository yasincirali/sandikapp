import '../models/asset.dart';

/// İşlem notu — hangi notun kullanıcıya GÖRÜNECEĞİ ve kimin düzenleyebileceği.
///
/// ## Neden ayrı bir karar noktası
/// Not, ekleme formundaki "Not ekle" alanından `assets.notes` sütununa
/// yazılıyordu ama hiçbir ekran onu okumuyordu (kullanıcı bildirimi
/// 2026-09-29: "not kayboluyor"). Artık hareket satırı (ikon), not sayfası
/// ve Tüm Hareketler araması okuyor; üçü de notu BURADAN alır ki bir
/// yüzeyde görünen not ötekinde gizli kalmasın.
///
/// ## Eski kopyalar
/// 2026-09-29'a kadar not, türetilmiş kayıtlara kopyalanıyordu: satış ve
/// silme kaydı alış lot'unun notunu, hızlı "Al" önceki lot'un notunu
/// alıyordu. Yazma yolu düzeltildi (`notes: ''`) ama sunucudaki eski
/// satırlar duruyor. Veri göçü yerine burada ayıklanır:
///   · silme kaydı (mezar taşı) hiçbir zaman not göstermez — kullanıcı
///     ona not yazamaz, taşıdığı her not kopyadır;
///   · satış, aynı varlığın bir ALIŞ notuyla birebir aynıysa kopyadır.
///     Satışa not yalnızca not sayfasından yazılabilir; kullanıcı orada
///     alışınkinden farklı bir şey yazar.
/// Hızlı "Al" kopyaları ayırt edilemez (ikisi de alış, ikisi de aynı not);
/// iki alışta aynı not görünür — yanlış bilgi değil, yalnızca tekrar.
///
/// Sunucudaki kopyaları temizleyen bir göç iki sunucuya birden gitmek
/// zorunda (CLAUDE.md "İki sunucu birebir") ve kullanıcının bilerek aynı
/// yazdığı notu da silebilirdi; ayıklama okuma tarafında kalır.
String? islemNotu(Asset a, Iterable<Asset> defter) {
  final not = a.notes.trim();
  if (not.isEmpty) return null;
  if (a.isDeleteLog) return null;
  if (a.isSell) {
    final kopya = defter.any((b) =>
        b.isBuy &&
        b.ticker == a.ticker &&
        b.type == a.type &&
        b.notes.trim() == not);
    if (kopya) return null;
  }
  return not;
}

/// Notu kim düzenleyebilir: yalnızca kaydın SAHİBİ (ortak kaydına RLS
/// yazmayı zaten reddeder; düğmeyi göstermek boş bir hata üretirdi),
/// silinmemiş ve mezar taşı olmayan kayıtta.
bool islemNotuDuzenlenebilir(Asset a, {required String? benimId}) =>
    benimId != null &&
    a.userId == benimId &&
    !a.isDeleteLog &&
    !a.isDeleted;

/// Tüm Hareketler araması için — [q] görünen notta geçiyor mu (büyük/küçük
/// harf ve Türkçe i/ı duyarsız, bkz. [notAramaKatla]). Gizlenen kopya
/// aramada da bulunmaz (görünmeyen bir şeyle eşleşen satır kullanıcıya
/// "neden bu çıktı?" dedirtirdi).
bool islemNotuEslesir(Asset a, Iterable<Asset> defter, String q) {
  final not = islemNotu(a, defter);
  return not != null && notAramaKatla(not).contains(notAramaKatla(q));
}

/// Not aramasının karşılaştırma biçimi: küçük harf, ve `I`/`ı`/`İ`/`i`
/// tek harf sayılır.
///
/// Neden (2026-11-11): düz `toLowerCase` Türkçe değil — "I" → "i" verir;
/// notunda "IŞIK" yazan işlem "ışık" aramasında çıkmıyordu. Türkçe kural
/// ("I" → "ı") da tek başına yetmez: İngilizce notta "INFO" "info"
/// aramasında kaybolurdu. Dört harfi bir saymak ikisini de bulur; arama
/// için fazladan eşleşme, kaçan eşleşmeden iyidir.
///
/// Harf harf çevrilir ve uzunluk korunur: [islemNotuParcasi] eşleşmenin
/// yerini katlanmış metinden asıl metne aynı indeksle taşır.
String notAramaKatla(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == 'I' || c == 'ı' || c == 'İ') {
      b.write('i');
      continue;
    }
    final k = c.toLowerCase();
    b.write(k.length == 1 ? k : c);
  }
  return b.toString();
}

/// Aramada yalnız notu yüzünden çıkan satırın altındaki not parçası:
/// eşleşen yerin çevresi ("… maaştan ayırdım …").
///
/// Neden (2026-11-11): not satırda yalnız ikonla durur (bkz.
/// `TransactionRow.not`); "maaş" arayan kullanıcı adında maaş geçmeyen
/// THYAO satırını görünce neden çıktığını anlamıyordu. Parça yalnız
/// arama sürerken ve eşleşme notta olduğunda yazılır; liste ritmi aramasız
/// hâlde değişmez.
///
/// Tek satıra sığsın diye eşleşmenin önünde en çok [onBaglam], arkasında
/// en çok [sonBaglam] karakter kalır; kesim kelime sınırına çekilir, kesilen
/// uçta `basKesik`/`sonKesik` doğrudur (çizen "…" koyar). Satır sonları tek
/// boşluğa iner. [q] boşsa ya da notta yoksa `null`.
({String once, String eslesen, String sonra, bool basKesik, bool sonKesik})?
    islemNotuParcasi(String not, String q,
        {int onBaglam = 18, int sonBaglam = 48}) {
  final n = not.replaceAll(RegExp(r'\s+'), ' ').trim();
  final kq = notAramaKatla(q.trim());
  if (kq.isEmpty) return null;
  final bas = notAramaKatla(n).indexOf(kq);
  if (bas < 0) return null;
  final son = bas + kq.length;

  var p = bas - onBaglam;
  if (p <= 0) {
    p = 0;
  } else {
    // Kelimenin ortasından başlama: kesimden sonraki ilk boşluğa ilerle.
    final bosluk = n.indexOf(' ', p);
    if (bosluk >= 0 && bosluk < bas) p = bosluk + 1;
  }
  var r = son + sonBaglam;
  if (r >= n.length) {
    r = n.length;
  } else {
    final bosluk = n.lastIndexOf(' ', r);
    if (bosluk > son) r = bosluk;
  }
  return (
    once: n.substring(p, bas),
    eslesen: n.substring(bas, son),
    sonra: n.substring(son, r).trimRight(),
    basKesik: p > 0,
    sonKesik: r < n.length,
  );
}

/// Bir pozisyonun notlu işlemleri, en yeni önce — Portföy kartının açılır
/// panelindeki "NOTLAR" bölümü için (kullanıcı isteği 2026-09-29).
///
/// [lotlar] pozisyonun ham lot'ları (alış + satış + temettü); eski kopya
/// ayıklaması için aynı liste defter olarak yeter — kopya ancak aynı
/// varlığın alışından gelebilir.
List<({Asset islem, String not})> notluIslemler(Iterable<Asset> lotlar) {
  final out = <({Asset islem, String not})>[];
  for (final l in lotlar) {
    final not = islemNotu(l, lotlar);
    if (not != null) out.add((islem: l, not: not));
  }
  out.sort((a, b) => b.islem.addedDate.compareTo(a.islem.addedDate));
  return out;
}
