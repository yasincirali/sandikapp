/// "Seni ilgilendiren günler": ana sayfada önümüzdeki iki günün tek olayı
/// (yasin onayı; müşteri gözüyle rapor 2026-10-20 21:15).
///
/// ## Karar kuralları
/// - **Ana sayfada aynı anda tek dürtü.** Sıra: "bilgi eksik" satırı >
///   takvim olayı > özellik önerisi ([anaSayfaDurtusu]). Eksik veri
///   düzeltmek her şeyden önce gelir; yaklaşan gün kaçarsa anlamını yitirir,
///   öneri ise bekleyebilir.
/// - **Yalnız iki gün içindeki olay satıra çıkar** ([satirPenceresiGun]).
///   Daha uzak olay ana sayfada yer kaplamaz; satıra dokununca açılan
///   sayfada 14 güne kadar liste görünür ([listePenceresiGun]).
/// - **Sonuç tahmini yok.** "Faiz kararı açıklanacak" denir, "indirim
///   bekleniyor" denmez; bilmediğimiz şeyi söylemeyiz.
/// - **Kapatılan olay bir daha gelmez** (kimliği tarihli; gelecek yılın
///   aynı olayı yeni kimlikle yine gelir).
///
/// ## Uydurma tarih yasak (fiyat kaynağı sözleşmesi madde 3'ün ruhu)
/// Makro takvim yalnız RESMÎ olarak yayımlanmış günleri taşır; emin
/// olunmayan gün yazılmaz. Liste bitince satır makro olay göstermez —
/// yeni takvim yayımlanınca buraya eklenir.
///
/// Temettü günü kullanıcının KENDİ bugünkü BIST hissesinin geçen yılki
/// gerçekleşmiş hak gününün yıl dönümüdür (`temettu_tahmini.dart`, aynı
/// kural: "geçen yıl ne olduysa"). Şirketin bu yılki kararı bilinmez; metin
/// bunu söyler ("geçen yıl bu gün"), tutar yazılmaz.
///
/// Saf: ağ, Flutter, saat yok. Sağlayıcı `gunler_provider.dart`.
library;

import 'package:flutter/foundation.dart';

enum GunOlayiTuru { tcmb, fomc, temettu }

@immutable
class GunOlayi {
  const GunOlayi({required this.gun, required this.tur, this.kod});

  /// TR takvim günü, saatsiz (`DateTime.utc(y, m, d)`; `trGunu` ile aynı).
  final DateTime gun;
  final GunOlayiTuru tur;

  /// Temettüde BIST kodu (`THYAO`, `.IS` eki olmadan); makroda `null`.
  final String? kod;

  /// Kapatma kaydı anahtarı; biçimi değiştirilmez (kapatılanlar bununla
  /// tutulur). Tarih içerir: gelecek yılın aynı olayı yeni bir olaydır.
  String get kimlik {
    final g = '${gun.year}-${_iki(gun.month)}-${_iki(gun.day)}';
    return kod == null ? '${tur.name}_$g' : '${tur.name}_${kod}_$g';
  }

  static String _iki(int n) => n.toString().padLeft(2, '0');

  @override
  bool operator ==(Object other) =>
      other is GunOlayi &&
      other.gun == gun &&
      other.tur == tur &&
      other.kod == kod;

  @override
  int get hashCode => Object.hash(gun, tur, kod);
}

/// Satırın baktığı pencere: bugün, yarın, öbür gün.
const satirPenceresiGun = 2;

/// Sayfadaki liste penceresi.
const listePenceresiGun = 14;

/// Resmî olarak yayımlanmış faiz kararı günleri (TR takvimi).
///
/// Kaynaklar (2026-10-21'de doğrulandı):
/// - **TCMB PPK**: TCMB "2026 Yılı Para ve Kur Politikası" ile birlikte
///   yayımlanan 2026 ve 2027 ilk yarısı toplantı takvimi (Aralık 2025;
///   tcmb.gov.tr, Bloomberg HT / CNBC-e haberleri aynı tarihleri verir).
///   Karar 14:00'te açıklanır. 2027 ikinci yarısı henüz yayımlanmadı
///   (2027 Para Politikası Metni 18 Aralık 2026'da bekleniyor) → yok.
/// - **Fed FOMC**: federalreserve.gov "Meeting calendars" — 2026 takvimi
///   ve 2027 takvimi (5 Eylül 2025 basın bülteni, "tentative"). İki günlük
///   toplantının İKİNCİ günü yazılır: karar o gün 14:00 ET'de (TR 21:00
///   ya da 22:00, aynı takvim günü). Fed takvimi her toplantıda bir
///   sonrakini teyit eder; değişirse burası güncellenir.
///
/// Geçmiş günler eklenmedi: liste yazıldığı günden (2026-10-21) başlar.
final List<GunOlayi> makroTakvim = List.unmodifiable([
  // TCMB PPK — 2026 kalanı
  for (final (y, m, d) in const [
    (2026, 10, 22),
    (2026, 12, 10),
    // TCMB PPK — 2027 ilk yarısı
    (2027, 1, 21),
    (2027, 3, 18),
    (2027, 4, 22),
    (2027, 6, 10),
  ])
    GunOlayi(gun: DateTime.utc(y, m, d), tur: GunOlayiTuru.tcmb),
  // Fed FOMC karar günleri — 2026 kalanı ve 2027
  for (final (y, m, d) in const [
    (2026, 10, 28),
    (2026, 12, 9),
    (2027, 1, 27),
    (2027, 3, 17),
    (2027, 4, 28),
    (2027, 6, 9),
    (2027, 7, 28),
    (2027, 9, 15),
    (2027, 10, 27),
    (2027, 12, 8),
  ])
    GunOlayi(gun: DateTime.utc(y, m, d), tur: GunOlayiTuru.fomc),
]);

/// Geçen yılın hak günlerinden bu yılın yıl dönümleri.
///
/// [hakGunleri]: sembol (Yahoo, `THYAO.IS`) → son 12 ayın gerçekleşmiş hak
/// günleri (`TahminSatiri.hakGunleri`). 29 Şubat → 28 Şubat (Dart'ın
/// 1 Mart'a taşmasını önler). [bugun]'den önceki yıl dönümü atılır.
List<GunOlayi> temettuGunleri(
  Map<String, List<DateTime>> hakGunleri, {
  required DateTime bugun,
}) {
  final out = <GunOlayi>{};
  for (final e in hakGunleri.entries) {
    final kod = e.key.endsWith('.IS')
        ? e.key.substring(0, e.key.length - 3)
        : e.key;
    for (final h in e.value) {
      final y = h.year + 1;
      final gun = h.month == 2 && h.day == 29
          ? DateTime.utc(y, 2, 28)
          : DateTime.utc(y, h.month, h.day);
      if (gun.isBefore(bugun)) continue;
      out.add(GunOlayi(gun: gun, tur: GunOlayiTuru.temettu, kod: kod));
    }
  }
  return out.toList();
}

/// [bugun] (TR takvim günü, saatsiz) ile [bugun] + [gun] arasındaki,
/// kapatılmamış olaylar; tarihe göre, aynı günde makro önce (herkesi
/// ilgilendirir), sonra koda göre.
List<GunOlayi> yaklasanOlaylar(
  Iterable<GunOlayi> olaylar, {
  required DateTime bugun,
  required Set<String> kapatilanlar,
  int gun = listePenceresiGun,
}) {
  final son = bugun.add(Duration(days: gun));
  final out = [
    for (final o in olaylar)
      if (!o.gun.isBefore(bugun) &&
          !o.gun.isAfter(son) &&
          !kapatilanlar.contains(o.kimlik))
        o
  ]..sort((a, b) {
      final g = a.gun.compareTo(b.gun);
      if (g != 0) return g;
      final t = a.tur.index.compareTo(b.tur.index);
      if (t != 0) return t;
      return (a.kod ?? '').compareTo(b.kod ?? '');
    });
  return out;
}

/// Satırda gösterilecek olay: iki gün içindeki ilk olay ya da null.
GunOlayi? satirOlayi(
  Iterable<GunOlayi> olaylar, {
  required DateTime bugun,
  required Set<String> kapatilanlar,
}) {
  final l = yaklasanOlaylar(olaylar,
      bugun: bugun, kapatilanlar: kapatilanlar, gun: satirPenceresiGun);
  return l.isEmpty ? null : l.first;
}

/// Ana sayfanın tek dürtü yuvası.
enum AnaSayfaDurtusu { bilgiEksik, takvim, oneri }

/// Sıra: bilgi eksik > takvim olayı > özellik önerisi. Hiçbiri yoksa null.
AnaSayfaDurtusu? anaSayfaDurtusu({
  required bool bilgiEksikGorunur,
  required GunOlayi? takvimOlayi,
  required bool oneriVar,
}) {
  if (bilgiEksikGorunur) return AnaSayfaDurtusu.bilgiEksik;
  if (takvimOlayi != null) return AnaSayfaDurtusu.takvim;
  if (oneriVar) return AnaSayfaDurtusu.oneri;
  return null;
}
