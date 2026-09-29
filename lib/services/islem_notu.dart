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

/// Tüm Hareketler araması için — küçük harfe çevrilmiş [q] görünen notta
/// geçiyor mu. Gizlenen kopya aramada da bulunmaz (görünmeyen bir şeyle
/// eşleşen satır kullanıcıya "neden bu çıktı?" dedirtirdi).
bool islemNotuEslesir(Asset a, Iterable<Asset> defter, String q) {
  final not = islemNotu(a, defter);
  return not != null && not.toLowerCase().contains(q);
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
