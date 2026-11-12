import '../utils/tr_format.dart';

// Hedefe tarih (Premium, yasin 2026-11-06): "Ne zamana kadar?" seçimi ve
// "ayda yaklaşık ₺X eklersen yetişirsin" hesabı.
//
// Hesap bilerek düz bölmedir: kalan ÷ kalan ay. Getiri varsayımı yok —
// varsayılan bir yüzde, piyasanın vermediği bir sayıyı vaat eder
// ("uydurma sayı yasak"). Ekran bunu cümlenin içinde "(getiri hariç)" diye
// söyler.

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
  final gun = dayKey(tarih);
  final bugunGun = dayKey(bugun);
  if (gun.isBefore(bugunGun)) return null;
  return (kalan / hedefeKalanAy(gun, bugunGun)).ceil();
}

/// Kayıtlı gün geçti mi (bugünden önce)? Bugün = geçmedi: "bu ay" demek,
/// aylık tutar hâlâ söylenir ([hedefeKalanAy] en az 1).
///
/// Neden ayrı durum (2026-11-12 hata): gün geçince kart ve sayfa tarihi
/// sessizce düşürüyordu; kullanıcı hedefinin gününün geçtiğini hiçbir yerde
/// görmüyordu. Hedefe ulaşılmadıysa ekran bunu ilerlemeyle birlikte söyler
/// ve yeni gün seçtirir; ulaşıldıysa "ulaştın" kazanır.
bool hedefGunuGecti(DateTime tarih, DateTime bugun) =>
    dayKey(tarih).isBefore(dayKey(bugun));

/// Tam sayının Türkçe yönelme eki ("%82'ye", "%50'ye", "%100'e").
/// [yilYonelmeEki] ile aynı kural: son okunan kelime belirler.
String sayiYonelmeEki(int sayi) => yilYonelmeEki(sayi.abs());

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
