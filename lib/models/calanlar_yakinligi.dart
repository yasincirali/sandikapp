/// Alarmlarım'daki "Çalanlar" bölümünün açılış kararı (Ar-Ge 7 Kas 13:40 #2).
///
/// **Neden:** bölüm her zaman kapalı ve listenin altındaydı. Bildirimden
/// ekranı açan kişi ne çaldığını görmek için aşağı inip grubu açıyordu.
/// Kapalı açılma kararı ("liste neyi bekliyorum'u cevaplar") eski çalmalar
/// için doğru; yeni çalma ise kişinin o an baktığı şey. Sınır 24 saat: bir
/// gün içinde çalan alarm "haber", daha eskisi arşiv.
///
/// Saf fonksiyon: saat dışarıdan gelir ([simdi]); ekran `alarmSaatProvider`
/// üzerinden verir, test sabit saatle çağırır. `build()` içinde hesap yok,
/// karar burada.
library;

/// "Yeni çalma" sınırı.
const calanlarYakinlikSiniri = Duration(hours: 24);

/// En yeni çalma [calanlarYakinlikSiniri]'ndan yeniyse `true`: Çalanlar
/// açık ve listenin en üstünde. Hiç çalma yoksa ([enYeniCalma] null) ya da
/// daha eskiyse `false` (kapalı, altta).
///
/// Saati ileride görünen çalma (cihaz saati geride) yeni sayılır: fark
/// negatif, sınırın altında.
bool calanlarOneCiksin(DateTime? enYeniCalma, DateTime simdi) {
  if (enYeniCalma == null) return false;
  return simdi.difference(enYeniCalma) < calanlarYakinlikSiniri;
}
