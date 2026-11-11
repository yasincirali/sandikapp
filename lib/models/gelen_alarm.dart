import '../utils/tr_format.dart';
import 'price_alert.dart';

/// Alarmdan açılan varlık sayfasının "Alarmın çaldı" bandının saf kararları
/// (2026-11-11). Ekran yalnız çizer; hangi alarmın, hangi saatin ve "Yeniden
/// kur"un hangi hedefle açılacağı burada, testli
/// (`test/gelen_alarm_test.dart`).

/// Bildirimin taşıdığı `alert_id`'nin alarmı. Kimlik yoksa ya da alarm artık
/// listede yoksa (silinmiş, başka hesap) `null` → bant hiç çıkmaz: olmayan
/// bir alarm için "çaldı" demek yanıltıcı olur.
PriceAlert? gelenAlarmiBul(Iterable<PriceAlert> alarmlar, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final a in alarmlar) {
    if (a.id == id) return a;
  }
  return null;
}

/// "Yeniden kur" sayfasının ön dolu hedefi: güncel fiyattan alarmın yönünde
/// %5 öte (üstü ×1,05, altı ×0,95).
///
/// **Neden güncel fiyattan, eski hedeften değil:** alarm çaldıysa fiyat
/// eşiği geçmiştir; aynı eşikle kurulan alarm ilk kontrolde yeniden çalar
/// (`alarmHemenCalarMi`). Güncel fiyatın %5 ötesi, sayfanın yönü güncel
/// fiyattan türetmesiyle ([PriceAlert.suggestDirection]) aynı yönü verir.
///
/// Güncel fiyat bilinmiyorsa (≤ 0) eski hedef: uydurma sayı yazılmaz.
double yenidenKurHedefi(PriceAlert alarm, double guncelFiyat) {
  if (guncelFiyat <= 0) return alarm.targetPrice;
  return guncelFiyat * (alarm.isAbove ? 1.05 : 0.95);
}

/// Bantta yazılacak çalma anı metni: aynı gün yalnız saat ("14:32"), başka
/// gün gün + saat ("10 Kas · 14:32"). Çalma anı bilinmiyorsa (`null`)
/// saat hiç yazılmaz — uydurma "şimdi" yok.
///
/// Kaynak [PriceAlert.sonCalis]: tek atış alarmda `triggered_at`, tekrarlı
/// alarmda nöbete dönüşte silinmeyen `son_tetik_at` (0171).
String? alarmCalmaZamaniMetni(PriceAlert alarm, DateTime simdi) {
  final t = alarm.sonCalis?.toLocal();
  if (t == null) return null;
  final s = simdi.toLocal();
  if (t.year == s.year && t.month == s.month && t.day == s.day) {
    String iki(int n) => n.toString().padLeft(2, '0');
    return '${iki(t.hour)}:${iki(t.minute)}';
  }
  return fmtTarihSaat(t, yilsiz: true);
}
