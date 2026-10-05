import '../models/asset.dart';
import 'contribution_history_service.dart';

/// Aylık birikim serisi — art arda kaç ay portföye para eklendi.
///
/// ## Neden "giriş serisi" değil (RETENTION_STRATEJISI.md §5.D)
/// Uygulamayı her gün açtıran seri bir takip uygulamasında boş etkileşimdir
/// ve sık bakmak kullanıcının getirisine zarar verir (Barber & Odean).
/// Burada sayılan şey kullanıcının KENDİ lehine olan davranışı: o ay
/// portföye net para girdi mi. Açılış hiçbir şey saymaz.
///
/// ## Kurallar (yasin kararları, 2026-10-05)
/// * Ritim **aylık** — maaş ritmi; haftalık seçenek yok.
/// * Birikim ayı: ayın net katkısı ≥ ₺1. Akış kuralı tek yerden
///   ([ContributionHistoryService] → `PeriodSummaryService.netInflow`):
///   alım +, satış −, temettü sayılmaz. BES'in otomatik yazılan katkısı
///   da bir alım lotudur ve SAYILIR (kullanıcı kararı: gerçek birikim).
/// * **Mola:** son 12 ayda **1** boş ay seriyi bozmaz ama artırmaz da.
///   Net satış yapılan ay da boş ay gibi işlenir — "başarısızlık" değil.
///   Mola durumsuzdur: her hesapta defterden aynı sonuç çıkar, sunucuda
///   sayaç tutulmaz, cihaz değişince kaybolmaz.
/// * **Açık ay:** içinde bulunulan ay katkı gelene kadar seriyi bozmaz.
///   "Ay bitmeden ekle" baskısı kurulmaz.
/// * Mola hakkı satılmaz, Premium'a bağlanmaz (kaybetme korkusunu paraya
///   çevirmek §9 etik testinden geçmiyor).
///
/// Geriye dönük hesaplanır: düzenli alım giren kullanıcı özelliği açtığı
/// gün gerçek serisini görür. Geçmiş tarihli alım girmek seriyi düzeltir;
/// bu hile değil, defterin doğru olmasıdır.
///
/// Saf ve statik — ağa çıkmaz.
abstract final class BirikimSerisiService {
  /// Bir ayın "birikim ayı" sayılması için gereken en az net katkı (TRY).
  /// `ContributionBucket.bos` ile aynı eşik: ₺1'in altı yuvarlama gürültüsü.
  static const esikTRY = 1.0;

  /// Kayan pencerede izin verilen mola sayısı.
  static const molaHakki = 1;

  /// Molanın sayıldığı kayan pencere (ay, ayın kendisi dahil).
  static const molaPenceresiAy = 12;

  /// Kartın çizilmesi için ilk birikim ayından bugüne en az kaç ay
  /// (bugün dahil) geçmiş olmalı. Daha kısa geçmişte "art arda 1 ay"
  /// bir seri değil, ilk adımdır ve kart gürültü olur.
  static const enAzGecmisAy = 3;

  /// Şeritte gösterilen ay sayısı.
  static const seritAy = 12;

  /// [assets] defterinden seriyi hesaplar. Hiç birikim ayı yoksa `null`.
  static BirikimSerisi? hesapla(List<Asset> assets, {required DateTime now}) {
    if (assets.isEmpty) return null;

    // En eski lot ayından bugüne kadar aylık kovalar. Kova üretimi
    // `ContributionHistoryService`'te: ay pencereleri ve akış kuralı orada.
    var enEski = assets.first.addedDate;
    for (final a in assets) {
      if (a.addedDate.isBefore(enEski)) enEski = a.addedDate;
    }
    final aySayisi = _ayFarki(enEski, now) + 1;
    if (aySayisi <= 0) return null;
    final kovalar = ContributionHistoryService.buckets(
      assets,
      aralik: ContributionInterval.aylik,
      now: now,
      kovaSayisi: aySayisi,
    );
    return hesaplaKovalardan(kovalar);
  }

  /// Kova dizisinden seri (eskiden yeniye; sonuncusu içinde bulunulan ay).
  /// Testler ve [hesapla] buradan geçer.
  static BirikimSerisi? hesaplaKovalardan(List<ContributionBucket> kovalar) {
    final ilk = kovalar.indexWhere((k) => k.netTRY >= esikTRY);
    if (ilk < 0) return null;

    final durumlar = List<SeriAyDurumu>.filled(
        kovalar.length, SeriAyDurumu.oncesi);
    final molaAylari = <int>[];
    var guncel = 0;
    var enUzun = 0;
    final son = kovalar.length - 1;

    for (var i = ilk; i <= son; i++) {
      final katki = kovalar[i].netTRY >= esikTRY;
      if (katki) {
        guncel++;
        durumlar[i] = SeriAyDurumu.birikim;
      } else if (i == son) {
        // İçinde bulunulan ay: henüz kapanmadı, seriyi bozmaz.
        durumlar[i] = SeriAyDurumu.acik;
      } else if (guncel == 0) {
        // Korunacak seri yok — mola harcanmaz.
        durumlar[i] = SeriAyDurumu.ara;
      } else if (_pencerdekiMola(molaAylari, i) < molaHakki) {
        molaAylari.add(i);
        durumlar[i] = SeriAyDurumu.mola;
      } else {
        guncel = 0;
        durumlar[i] = SeriAyDurumu.ara;
      }
      if (guncel > enUzun) enUzun = guncel;
    }

    // Kalan hak: içinde bulunulan ay boş kapanırsa kullanabileceği hak —
    // penceresi bu ay dahil geriye 12 ay.
    final kullanilan = _pencerdekiMola(molaAylari, son);
    final kalan = (molaHakki - kullanilan).clamp(0, molaHakki);
    DateTime? molaAcilis;
    if (kalan == 0 && molaAylari.isNotEmpty) {
      // En eski pencere-içi molanın pencereden çıktığı ay.
      final enEskiMola = molaAylari
          .where((m) => m > son - molaPenceresiAy)
          .reduce((a, b) => a < b ? a : b);
      final ay = kovalar[enEskiMola].start;
      molaAcilis = DateTime(ay.year, ay.month + molaPenceresiAy, 1);
    }

    final seritBas = (kovalar.length - seritAy).clamp(0, kovalar.length);
    return BirikimSerisi(
      guncel: guncel,
      enUzun: enUzun,
      kalanMola: kalan,
      molaAcilisAyi: molaAcilis,
      buAyKatkiVar: durumlar[son] == SeriAyDurumu.birikim,
      gecmisAy: kovalar.length - ilk,
      serit: [
        for (var i = seritBas; i <= son; i++)
          SeriAyi(ay: kovalar[i].start, durum: durumlar[i]),
      ],
    );
  }

  static int _pencerdekiMola(List<int> molaAylari, int ay) =>
      molaAylari.where((m) => m > ay - molaPenceresiAy && m <= ay).length;

  static int _ayFarki(DateTime a, DateTime b) =>
      (b.year - a.year) * 12 + (b.month - a.month);
}

/// Bir ayın serideki durumu.
enum SeriAyDurumu {
  /// İlk birikim ayından önce — seri henüz başlamamış.
  oncesi,

  /// Net katkı yapılan ay; seriyi bir artırır.
  birikim,

  /// Boş geçen ama mola hakkıyla seriyi bozmayan ay.
  mola,

  /// Seri sıfırlandı (ya da korunacak seri yoktu).
  ara,

  /// İçinde bulunulan, henüz katkı gelmemiş ay.
  acik,
}

class SeriAyi {
  const SeriAyi({required this.ay, required this.durum});

  /// Ayın 1'i.
  final DateTime ay;
  final SeriAyDurumu durum;
}

class BirikimSerisi {
  const BirikimSerisi({
    required this.guncel,
    required this.enUzun,
    required this.kalanMola,
    required this.buAyKatkiVar,
    required this.gecmisAy,
    required this.serit,
    this.molaAcilisAyi,
  });

  /// Şu anki seri (birikim ayı sayısı; molalar sayılmaz).
  final int guncel;

  /// Defterdeki en uzun seri — seri sıfırlansa da görünür kalır.
  final int enUzun;

  /// Kullanılabilir mola hakkı (0 ya da 1).
  final int kalanMola;

  /// [kalanMola] 0 ise hakkın yeniden açılacağı ayın 1'i.
  final DateTime? molaAcilisAyi;

  /// İçinde bulunulan ayda katkı var mı?
  final bool buAyKatkiVar;

  /// İlk birikim ayından bugüne kaç ay (bugün dahil).
  final int gecmisAy;

  /// Son [BirikimSerisiService.seritAy] ay, eskiden yeniye.
  final List<SeriAyi> serit;

  /// Kart çizilmeli mi? Kısa geçmişte seri ilk adımdır, gösterilmez.
  bool get gosterilir =>
      gecmisAy >= BirikimSerisiService.enAzGecmisAy && enUzun >= 1;

  /// Seri sıfırlanmış mı (önceden seri vardı, şimdi yok)?
  bool get yenidenBasladi => guncel == 0 && enUzun > 0;
}
