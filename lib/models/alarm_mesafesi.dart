import 'hedef_tarihi.dart' show sayiYonelmeEki;

/// Alarmlarım satırındaki "%3,2 kaldı" (müşteri raporu 31 Eki 21:15, yasin
/// "yap").
///
/// Alarm kuran kişinin tek sorusu "ne kadar kaldı"; haftalarca çalmayan
/// alarmda mesafe aynı zamanda alarmın canlı olduğunun kanıtı. Satır eskiden
/// yalnız hedefi yazıyordu.
///
/// Kurallar:
/// - Fiyat bilinmiyorsa (0, negatif, NaN) mesafe YOK: takip listesi adayı
///   fiyatsızken 0 taşır, "%100 kaldı" uydurma sayı olurdu.
/// - Hedef aşılmışsa (yukarı alarmda fiyat ≥ hedef) mesafe YOK: tek atışlık
///   alarm bir sonraki kontrolde çalar, tekrarlı alarm geri dönüşü bekler;
///   "%0 kaldı" ya da eksi mesafe yanlış okunurdu.
/// - İlerleme çubuğu bilerek yok: başlangıç (kurulduğu günkü) fiyat
///   saklanmıyor, "yolun yüzde kaçı" uydurulurdu. Sayı tek başına dürüst.
///
/// [yukari] `null` → iki yönlü (çizginin iki yanı): uzaklığın mutlak değeri.
/// Dönüş güncel fiyata göre yüzde (5 → %5).
double? alarmMesafesi({
  required double fiyat,
  required double hedef,
  required bool? yukari,
}) {
  if (!fiyat.isFinite || fiyat <= 0 || !hedef.isFinite || hedef <= 0) {
    return null;
  }
  final fark = (hedef - fiyat) / fiyat * 100;
  return switch (yukari) {
    true => fark > 0 ? fark : null,
    false => fark < 0 ? -fark : null,
    null => fark == 0 ? null : fark.abs(),
  };
}

/// Mesafe kaç haneyle yazılsın: %1'in altında iki hane ("%0,45"), üstünde
/// bir ("%3,2"). Yakın alarmda "%0,0 kaldı" yazmasın.
int alarmMesafesiHanesi(double mesafe) => mesafe < 1 ? 2 : 1;

/// Biçimli fiyatın ("₺180,00", "₺41,62", "$1.240,50") Türkçe yönelme eki:
/// "₺180,00'e çıktı", "₺41,62'ye indi" (Ar-Ge 14 Kas 02:03 #2, çalmış satır
/// tek cümle).
///
/// Ek son OKUNAN kelimeye uyar: kuruş sıfırsa ("180,00" → "yüz seksen")
/// tam kısım, değilse kuruş kısmı ("41,62" → "… altmış iki") belirler.
/// Kural [sayiYonelmeEki]'nin kendisi (yıl ve yüzde ekiyle aynı); burada
/// yalnız biçimli metinden okunan sayı seçilir. Rakam yoksa ek boş.
String bicimliFiyatYonelmeEki(String bicimli) {
  final temiz = bicimli.replaceAll(RegExp(r'[^0-9,]'), '');
  final parca = temiz.split(',');
  final kurus = parca.length > 1 ? int.tryParse(parca.last) : null;
  if (kurus != null && kurus != 0) return sayiYonelmeEki(kurus);
  final tam = int.tryParse(parca.first);
  if (tam == null) return '';
  return sayiYonelmeEki(tam);
}
