/// Ana ekranda "bunu denedin mi?" kartı: kullanıcının henüz kullanmadığı bir
/// özelliğe tek dokunuşla götürür (yasin isteği 2026-10-20: alarm kur,
/// takibe al, ortak ekle, zirvedeki portföyler; "örnek olarak verdim").
///
/// ## Karar kuralları (müşteri gözüyle rapor 2026-10-20 21:15)
/// - **Bir anda tek kart.** Dört öneri alt alta reklam panosu olur; kullanıcı
///   hepsini kapatıp bir daha bakmaz.
/// - **Yalnız gerçekten kullanılmayan özellik.** Alarmı olan alarm, takip
///   listesi dolu olan takip önerisi görmez. Veri yüklenmemişse (null)
///   öneri yok: yanlış "henüz kurmadın" demektense susmak.
/// - **Varlık yoksa susar.** Boş portföyde iş ilk varlığı eklemek; o akış
///   ayrı (ilk varlık vitrini).
/// - **Kapatılan ya da dokunulan bir daha gelmez.** Dokunan kullanıcı
///   özelliği görmüştür; vazgeçse de aynı kartla dürtülmez.
/// - **Arada nefes.** Bir kart kapatıldıktan/dokunulduktan sonra sıradaki
///   [bekleme] boyunca gelmez; her açılışta yeni öneri ısrar olur.
/// - Sıra kullanım değerine göre: elindeki varlığa alarm (en somut fayda),
///   takip listesi, ortak, Zirve (merak; yeni katılım Premium).
library;

enum OzellikOnerisi {
  alarm('alarm'),
  takip('takip'),
  ortak('ortak'),
  zirve('zirve');

  const OzellikOnerisi(this.anahtar);

  /// Kalıcı kayıt ve analitik anahtarı; yeniden adlandırılmaz (kapatılan
  /// kayıtlar bununla tutulur).
  final String anahtar;
}

/// Bir kart kapatıldıktan sonra sıradakinin gelmesi için geçecek süre.
const bekleme = Duration(days: 3);

/// Saf karar: gösterilecek öneri ya da null.
///
/// Sayılar null ise o kaynak henüz yüklenmemiştir; o öneri atlanır ve
/// SIRADAKİNE geçilmez (sıra kayıp yüklemeyle değişmesin diye tümüyle
/// susulur).
OzellikOnerisi? siradakiOneri({
  required int varlikSayisi,
  required int? alarmSayisi,
  required int? takipSayisi,
  required int? ortakSayisi,
  required bool zirveAcik,
  required bool? zirveRizasi,
  required Set<String> kapatilanlar,
  required DateTime? sonKapatma,
  required DateTime simdi,
}) {
  if (varlikSayisi <= 0) return null;
  if (sonKapatma != null && simdi.difference(sonKapatma) < bekleme) {
    return null;
  }
  for (final o in OzellikOnerisi.values) {
    if (kapatilanlar.contains(o.anahtar)) continue;
    final kullanilmiyor = switch (o) {
      OzellikOnerisi.alarm => alarmSayisi == null ? null : alarmSayisi == 0,
      OzellikOnerisi.takip => takipSayisi == null ? null : takipSayisi == 0,
      OzellikOnerisi.ortak => ortakSayisi == null ? null : ortakSayisi == 0,
      // Bayrak kapalıysa Zirve yok; rıza bilinmiyorsa (ağ hatası) öneri yok.
      OzellikOnerisi.zirve =>
        !zirveAcik ? false : (zirveRizasi == null ? null : !zirveRizasi),
    };
    if (kullanilmiyor == null) return null;
    if (kullanilmiyor) return o;
  }
  return null;
}
