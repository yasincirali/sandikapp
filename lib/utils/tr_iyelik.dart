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
