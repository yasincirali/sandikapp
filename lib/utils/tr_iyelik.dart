/// Türkçe ilgi (iyelik) eki — "Ayşe" → "Ayşe'nin", "Ahmet" → "Ahmet'in".
///
/// Neden var (2026-09-21): Bugün kartı ortak görünümünde "Ayşe'nin bugünü"
/// diye başlar. Ek, adın SON ÜNLÜSÜNE göre dört biçim alır (ın/in/un/ün) ve
/// ad ünlüyle bitiyorsa araya "n" girer; tek bir şablon ("{ad}'nin")
/// adların çoğunda yanlış çıkar ("Ahmet'nin"). Kural küçüktür ve
/// tahmin edilebilirdir; özel adlar kesme işaretiyle ayrılır (TDK).
///
/// Kapsam bilinçli olarak dar: yalnızca ilgi eki, yalnızca özel ad. Yumuşama
/// (k→ğ) özel adda kesmeyle olmadığı için yok. Son ünlüsü bulunamayan ad
/// (ünsüz kısaltma, boş) ince-düz ek alır ("XYZ'in").
/// Türkçe büyük harf: `toUpperCase` i→I ve ı→I yapar ("Ayşe'nin" →
/// "AYŞE'NIN"). Noktalı i önce İ'ye çevrilir; ı zaten I'ya gider.
String trBuyukHarf(String s) => s.replaceAll('i', 'İ').toUpperCase();

String trIyelik(String ad) {
  final t = ad.trim();
  if (t.isEmpty) return t;
  // Dart'ın `toLowerCase`'i I→i, İ→i eşler; Türkçe I→ı olmalı, yoksa
  // "IŞIK" ince sanılır ("IŞIK'in" yerine "IŞIK'ın").
  final kucuk = t.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

  const unluler = 'aeıioöuü';
  String? sonUnlu;
  for (var i = kucuk.length - 1; i >= 0; i--) {
    if (unluler.contains(kucuk[i])) {
      sonUnlu = kucuk[i];
      break;
    }
  }
  final kalin = sonUnlu != null && 'aıou'.contains(sonUnlu);
  final yuvarlak = sonUnlu != null && 'ouöü'.contains(sonUnlu);
  final ek = kalin ? (yuvarlak ? 'un' : 'ın') : (yuvarlak ? 'ün' : 'in');
  final unluyleBitiyor = unluler.contains(kucuk[kucuk.length - 1]);
  return "$t'${unluyleBitiyor ? 'n' : ''}$ek";
}

/// Sayının iyelik + ayrılma eki, kesmesiz: 30 → "undan" ("%30'undan"),
/// 20 → "sinden", 3 → "ünden", 100 → "ünden".
///
/// Neden var (2026-10-08, web ekran görüntüleri): yüzdelik şeridi ve
/// paylaşım kartı sabit "'inden" yazıyordu; ek sayının OKUNUŞUNUN son
/// sözcüğüne göre değişir ("yüzde otuzundan", "yüzde yirmisinden"),
/// sabit ek 10/30/40/60/90 gibi değerlerde yanlış çıkıyordu. Yalnızca son
/// sözcük gerekir: birler basamağı, yoksa onlar, yoksa yüz/bin.
String trSayiAyrilmaEki(int n) {
  const birler = [
    '', 'bir', 'iki', 'üç', 'dört', 'beş', 'altı', 'yedi', 'sekiz', 'dokuz',
  ];
  const onlar = [
    '', 'on', 'yirmi', 'otuz', 'kırk', 'elli', 'altmış', 'yetmiş', 'seksen',
    'doksan',
  ];
  final m = n.abs();
  final String soz;
  if (m == 0) {
    soz = 'sıfır';
  } else if (m % 10 != 0) {
    soz = birler[m % 10];
  } else if (m % 100 != 0) {
    soz = onlar[(m % 100) ~/ 10];
  } else if (m % 1000 != 0) {
    soz = 'yüz';
  } else {
    soz = 'bin';
  }
  const unluler = 'aeıioöuü';
  var sonUnlu = 'e';
  for (var i = soz.length - 1; i >= 0; i--) {
    if (unluler.contains(soz[i])) {
      sonUnlu = soz[i];
      break;
    }
  }
  final kalin = 'aıou'.contains(sonUnlu);
  final iyelik = switch (sonUnlu) {
    'a' || 'ı' => 'ı',
    'e' || 'i' => 'i',
    'o' || 'u' => 'u',
    _ => 'ü',
  };
  final unluyleBitiyor = unluler.contains(soz[soz.length - 1]);
  return '${unluyleBitiyor ? 's' : ''}$iyelik${kalin ? 'ndan' : 'nden'}';
}
