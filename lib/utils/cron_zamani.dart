/// Cron ifadesinden "aylık iş mi?" okuması — Push Teşhisi için.
///
/// **Neden gerekli (2026-09-21).** Teşhis ekranı "kurulu ama hiç koşmamış"
/// job'u kırmızı basıyordu; `0054`'ün arızası tam buydu (gövde koşmamış).
/// Ama ayın 1'i / 3'ü koşan işler (aylık özet, TÜFE, takvim dürtmesi) ilk
/// slotlarından ÖNCE kurulduysa Ekim'e kadar "hiç çalışmamış" görünür ve
/// beş kırmızı satır gerçek bir arızayı gölgeler. `cron.job` kurulum zamanı
/// tutmaz; ayırt edici tek şey ifadenin kendisi: gün-ay alanı `*` değilse
/// iş aylıktır ve "ilk slotu henüz gelmedi" olağan bir durumdur.
///
/// Kapsam dar: standart 5 alanlı ifade; gün tek sayı ya da sayı LİSTESİ.
/// Liste (2026-10-01): aylık özet `3,4` (TÜFE günü + gecikme turu, 0093);
/// ilk gün döner. Aralık (`1-5`) aylık kabul edilmez — bu projede yok.
int? cronAyGunu(String schedule) {
  final alanlar = schedule.trim().split(RegExp(r'\s+'));
  if (alanlar.length < 5) return null;
  final gunler = alanlar[2].split(',').map(int.tryParse).toList();
  if (gunler.isEmpty || gunler.any((g) => g == null || g < 1 || g > 31)) {
    return null;
  }
  return gunler.reduce((a, b) => a! < b! ? a : b);
}
