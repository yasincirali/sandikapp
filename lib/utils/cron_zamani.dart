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
/// Kapsam dar: yalnızca standart 5 alanlı ifade ve tek sayı gün. Liste
/// (`1,15`) ya da aralık (`1-5`) aylık kabul edilmez — bu projede yok.
int? cronAyGunu(String schedule) {
  final alanlar = schedule.trim().split(RegExp(r'\s+'));
  if (alanlar.length < 5) return null;
  final gun = int.tryParse(alanlar[2]);
  if (gun == null || gun < 1 || gun > 31) return null;
  return gun;
}
