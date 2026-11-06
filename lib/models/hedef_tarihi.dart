// Hedefe tarih (Premium, yasin 2026-11-06): "Ne zamana kadar?" seçimi ve
// "ayda yaklaşık ₺X eklersen yetişirsin" hesabı.
//
// Hesap bilerek düz bölmedir: kalan ÷ kalan ay. Getiri varsayımı yok —
// varsayılan bir yüzde, piyasanın vermediği bir sayıyı vaat eder
// ("uydurma sayı yasak"). Ekran bunu "getiri hariç" notuyla söyler.

/// "Ne zamana kadar?" seçenekleri. [ozel] = takvimden seçilen gün.
enum HedefTarihSecenegi { yok, birYil, yilSonu, ozel }

/// Seçeneğin bugüne göre günü. [yok] ve [ozel] için null (özel gün
/// takvimden gelir).
DateTime? hedefTarihiSecenekten(HedefTarihSecenegi s, DateTime bugun) =>
    switch (s) {
      HedefTarihSecenegi.birYil =>
        DateTime(bugun.year + 1, bugun.month, bugun.day),
      HedefTarihSecenegi.yilSonu => DateTime(bugun.year, 12, 31),
      HedefTarihSecenegi.yok || HedefTarihSecenegi.ozel => null,
    };

/// Kayıtlı günün hangi seçeneğe karşılık geldiği (çip seçimi için).
/// Hazır seçeneğe denk gelmeyen gün [HedefTarihSecenegi.ozel].
HedefTarihSecenegi hedefTarihSecenegi(DateTime? tarih, DateTime bugun) {
  if (tarih == null) return HedefTarihSecenegi.yok;
  bool ayni(DateTime? a) =>
      a != null &&
      a.year == tarih.year &&
      a.month == tarih.month &&
      a.day == tarih.day;
  if (ayni(hedefTarihiSecenekten(HedefTarihSecenegi.birYil, bugun))) {
    return HedefTarihSecenegi.birYil;
  }
  if (ayni(hedefTarihiSecenekten(HedefTarihSecenegi.yilSonu, bugun))) {
    return HedefTarihSecenegi.yilSonu;
  }
  return HedefTarihSecenegi.ozel;
}

/// Bugünden [tarih]'e kalan TAM ay; en az 1.
///
/// Kısmi ay aşağı yuvarlanır (6 Kas → 31 Ara = 1 ay): az ay = büyük aylık
/// tutar, yani söylenen tutar yetişmeye yeter. Aynı gün ya da bir aydan az
/// kala 1 ay sayılır (sıfıra bölme yok, "bu ay" demektir).
int hedefeKalanAy(DateTime tarih, DateTime bugun) {
  var ay = (tarih.year - bugun.year) * 12 + (tarih.month - bugun.month);
  if (tarih.day < bugun.day) ay -= 1;
  return ay < 1 ? 1 : ay;
}

/// Ayda eklenmesi gereken tutar (TRY, yukarı yuvarlanmış tam sayı) ya da
/// söylenecek bir şey yoksa null: kalan ≤ 0 (hedefe ulaşıldı — ekranda
/// "ulaştın" durumu kazanır) ya da gün geçmiş (bugünden önce).
int? hedefAylikTutar({
  required double kalan,
  required DateTime tarih,
  required DateTime bugun,
}) {
  if (kalan <= 0) return null;
  final gun = DateTime(tarih.year, tarih.month, tarih.day);
  final bugunGun = DateTime(bugun.year, bugun.month, bugun.day);
  if (gun.isBefore(bugunGun)) return null;
  return (kalan / hedefeKalanAy(gun, bugunGun)).ceil();
}

/// Türkçe yönelme eki, yılın okunuşuna göre ("2027'ye", "2026'ya",
/// "2030'a", "2028'e"). Sayının son okunan kelimesi belirler: birler,
/// yoksa onlar, yoksa yüz/bin.
String yilYonelmeEki(int yil) {
  const birler = ['', 'e', 'ye', 'e', 'e', 'e', 'ya', 'ye', 'e', 'a'];
  const onlar = ['', 'a', 'ye', 'a', 'a', 'ye', 'a', 'e', 'e', 'a'];
  final b = yil % 10;
  if (b != 0) return birler[b];
  final o = (yil ~/ 10) % 10;
  if (o != 0) return onlar[o];
  return 'e'; // yüz / bin
}
