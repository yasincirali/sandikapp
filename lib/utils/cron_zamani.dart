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
/// ilk gün döner. Aralık (2026-10-05): TÜFE çekimi ve aylık özet `3-12`
/// (0110 — 3'ü/4'ü hafta sonuna denk gelince Eylül TÜFE'si hiç gelmedi);
/// aralığın ilk günü döner.
int? cronAyGunu(String schedule) {
  final alanlar = schedule.trim().split(RegExp(r'\s+'));
  if (alanlar.length < 5) return null;
  final gunler = <int?>[];
  for (final parca in alanlar[2].split(',')) {
    final uclar = parca.split('-');
    if (uclar.length > 2) return null;
    final bas = int.tryParse(uclar.first);
    final son = int.tryParse(uclar.last);
    if (bas == null || son == null || son < bas) return null;
    gunler.add(bas);
    gunler.add(son);
  }
  if (gunler.isEmpty || gunler.any((g) => g == null || g < 1 || g > 31)) {
    return null;
  }
  return gunler.reduce((a, b) => a! < b! ? a : b);
}
