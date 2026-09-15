import 'price_alert_notification.dart';
import 'signal_alert.dart';

/// Çan sayfasındaki tek bir satır — teknik sinyal ya da fiyat alarmı.
///
/// **Neden sealed bir sarmalayıcı:** iki bildirim türünün veri modeli ayrı
/// (bkz. `PriceAlertNotification` sınıf notu) ama kullanıcı için ikisi de
/// "bildirim". Ayrılık veri katmanında, birlik sunum katmanında: liste tek
/// bir zaman akışı gösterir, tür farkı yalnızca satırın nasıl çizildiğini
/// belirler.
///
/// Ortak alanlar (`zaman`, `dismissEdilmis`) burada tanımlı ki sıralama ve
/// aktif/geçmiş ayrımı türü bilmeden yapılabilsin.
sealed class BildirimOgesi {
  const BildirimOgesi();

  /// Sıralama anahtarı — iki tür tek akışta harmanlanır.
  DateTime get zaman;

  /// Listeden düşürülmüş mü (GEÇMİŞ bölümüne ait mi).
  bool get dismissEdilmis;

  /// Satır kimliği — tür içinde benzersiz, türler arası çakışabilir
  /// (iki ayrı tablo, iki ayrı uuid uzayı). Bu yüzden silme/dismiss
  /// çağrıları türe göre AYRI notifier'a gider.
  String get kimlik;
}

/// Teknik sinyal satırı.
class SinyalOgesi extends BildirimOgesi {
  const SinyalOgesi(this.alert);
  final SignalAlert alert;

  @override
  DateTime get zaman => alert.detectedAt;

  @override
  bool get dismissEdilmis => alert.isDismissed;

  @override
  String get kimlik => alert.id ?? '';
}

/// Fiyat alarmı satırı.
class FiyatAlarmiOgesi extends BildirimOgesi {
  const FiyatAlarmiOgesi(this.bildirim);
  final PriceAlertNotification bildirim;

  @override
  DateTime get zaman => bildirim.sentAt;

  @override
  bool get dismissEdilmis => bildirim.isDismissed;

  @override
  String get kimlik => bildirim.id;
}

/// İki bildirim türünü TEK zaman akışında birleştirir — en yeni önce.
///
/// Saf fonksiyon: provider'a, context'e, servise dokunmaz. Sıralama kuralı
/// istemci olmadan test edilir (`test/bildirim_akisi_test.dart`).
///
/// **Neden istemcide birleştiriliyor:** iki ayrı tablo tek sorguda
/// okunamaz (UNION için view gerekirdi ve o view'ın RLS'i iki tablonun
/// politikalarını tekrar etmek zorunda kalırdı — sızıntı riski, bakım
/// maliyeti). Liste zaten 100 satırla sınırlı; birleştirme O(n log n) ve
/// tamamen bellekte.
List<BildirimOgesi> bildirimAkisi(
  List<SignalAlert> sinyaller,
  List<PriceAlertNotification> alarmlar,
) {
  final hepsi = <BildirimOgesi>[
    // Kimliksiz sinyal satırı dismiss/delete edilemez (id'siz kayıt yerel
    // bir artık olabilir) — listeye alınmaz, aksi halde dokunulunca hiçbir
    // şey olmayan bir satır çizerdik.
    for (final s in sinyaller)
      if ((s.id ?? '').isNotEmpty) SinyalOgesi(s),
    for (final a in alarmlar) FiyatAlarmiOgesi(a),
  ];
  // En yeni önce. Eşit zamanda sıra belirsiz kalmasın diye kimliğe düşülür:
  // aynı saniyede yazılmış iki bildirimin her build'de yer değiştirmesi
  // listeyi titretirdi.
  hepsi.sort((a, b) {
    final c = b.zaman.compareTo(a.zaman);
    return c != 0 ? c : a.kimlik.compareTo(b.kimlik);
  });
  return hepsi;
}
