import '../models/asset.dart';
import '../utils/tr_format.dart';
import 'contribution_history_service.dart';

/// "Plandasın" satırı (Premium hedefe tarih, 2026-11-12).
///
/// ## Neden
/// Hedef sayfası "ayda yaklaşık ₺X eklersen yetişirsin" diyordu ama
/// kullanıcının gerçekten bu hızda ekleyip eklemediği hiçbir yerde
/// yazmıyordu. Bu satır defterden ölçülen hızı gerekenle yan yana koyar:
/// olan biteni bildirir, tavsiye değildir.
///
/// ## Kurallar
/// * Hız = son 3 TAM takvim ayının net eklemesinin aylık ortalaması. İçinde
///   bulunulan ay girmez: yarısı geçmiş ayı tam aylarla ortalamak hızı
///   düşük gösterirdi (`ContributionBucket.kismi` ile aynı gerekçe).
/// * Net ekleme kuralı Özet'teki "Net katkın" / birikim disiplini kartıyla
///   AYNI: `ContributionHistoryService.buckets` → `PeriodSummaryService
///   .netInflow` (alım +, satışta ele geçen tutar −, temettü sayılmaz).
///   İkinci bir akış tanımı yazılmaz.
/// * Defter pencereden kısaysa (ilk işlem pencerenin ilk gününden önce
///   değilse) söylenecek bir şey yok: portföyün ilk girişi "eklenen para"
///   sayılır ve hızı şişirirdi. Satır çizilmez (`null`) — uydurma sayı yok.
/// * Kıyas ekrandaki yuvarlanmış tutarla yapılır: "₺8.334 ekledin · ayda
///   ₺1 daha gerek" gibi kendi içinde çelişen cümle çıkmasın.
///
/// Saf ve statik — ağa çıkmaz.
abstract final class HedefRitmiService {
  /// Ortalamanın alındığı tam ay sayısı.
  static const pencereAy = 3;

  /// [defter]'den son [pencereAy] tam ayın aylık net ekleme ortalaması
  /// (TRY) ya da defter kısaysa `null`. Ortalama negatif olabilir (net
  /// satış); yorumu [HedefRitmi]'nin.
  static double? sonUcAyOrtalamasi(List<Asset> defter,
      {required DateTime now}) {
    DateTime? ilk;
    for (final a in defter) {
      if (!a.isActive) continue;
      if (ilk == null || a.addedDate.isBefore(ilk)) ilk = a.addedDate;
    }
    if (ilk == null) return null;
    final kovalar = ContributionHistoryService.buckets(
      defter,
      aralik: ContributionInterval.aylik,
      now: now,
      kovaSayisi: pencereAy + 1,
    ).where((k) => !k.kismi).toList();
    if (kovalar.length != pencereAy) return null;
    if (!dayKey(ilk).isBefore(kovalar.first.start)) return null;
    final toplam = kovalar.fold<double>(0, (t, k) => t + k.netTRY);
    return toplam / pencereAy;
  }
}

/// Ölçülen hız ile gereken aylık tutarın kıyası.
class HedefRitmi {
  const HedefRitmi._({required this.ortalama, required this.gereken});

  /// Son üç ayın aylık ortalaması, tam liraya yuvarlanmış (ekrandaki sayı).
  final int ortalama;

  /// Ayda gereken tutar (`hedefAylikTutar`, ≥ 1).
  final int gereken;

  /// [ortalama] ya da [gereken] yoksa `null`: satır çizilmez. [gereken]
  /// gün geçmişken ve hedefe ulaşılmışken zaten `null` gelir.
  static HedefRitmi? kur({double? ortalama, int? gereken}) {
    if (ortalama == null || gereken == null || gereken <= 0) return null;
    return HedefRitmi._(ortalama: ortalama.round(), gereken: gereken);
  }

  /// Son üç ayda net ekleme olmadı (sıfır ya da net satış). "Ayda −₺5.000
  /// ekledin" yazılmaz; satır "net ekleme olmadı" der.
  bool get eklemeYok => ortalama <= 0;

  bool get plandasin => ortalama >= gereken;

  /// Gerekene ulaşmak için ayda eklenmesi gereken ek tutar. Net ekleme
  /// yokken gereken tutarın kendisi (geçmişteki satış ileriye borç
  /// olarak taşınmaz: gereken zaten bugünkü değerden hesaplandı).
  int get eksik => plandasin ? 0 : gereken - (eklemeYok ? 0 : ortalama);
}
