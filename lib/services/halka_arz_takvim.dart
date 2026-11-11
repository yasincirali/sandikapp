// Halka arz detayındaki "Takvime ekle" (2026-11-08).
//
// Takvim izni ya da yeni eklenti İSTEMEDEN: bir `.ics` dosyası üretilir ve
// sistem paylaşım sayfasıyla verilir; iOS/Android takvim uygulaması dosyayı
// tanıyıp "etkinlik ekle" der. Böylece kişisel veri cihazdan çıkmaz, yeni
// izin/yasal metin gerekmez.
//
// Metin üretimi saf fonksiyondur ([halkaArzIcs]); 2026-11-11'den beri RFC
// 5545 kısmı genel `takvim_ics.dart`'ta (mevduat/Eurobond/temettü de
// kullanır), burada yalnız halka arzın iki etkinliği kurulur. **Uydurma
// tarih yok**: bilinmeyen tarih için etkinlik yazılmaz; iki tarih de yoksa
// düğme hiç çizilmez.
import 'dart:ui' show Rect;

import '../models/halka_arz.dart';
import 'takvim_ics.dart';

// Eski çağıranlar (testler) kaçış/katlamayı buradan alıyordu.
export 'takvim_ics.dart' show icsKacis, icsKatla;

/// En az bir tarih biliniyorsa takvime eklenecek bir şey vardır.
bool halkaArzTakvimeEklenebilir(HalkaArz arz) =>
    arz.talepBitis != null || arz.islemBaslangic != null;

/// [arz] için en fazla iki tüm gün etkinliği taşıyan VCALENDAR metni.
///
/// [talepSonBaslik] / [islemBaslik] ekranın diline göre hazır başlıklar.
/// [simdi] DTSTAMP içindir (test deterministik kalsın diye dışarıdan).
/// Hiç tarih yoksa `null` — boş takvim dosyası paylaşılmaz.
String? halkaArzIcs({
  required HalkaArz arz,
  required String talepSonBaslik,
  required String islemBaslik,
  required DateTime simdi,
}) {
  // Açıklama: şirket adı + kaynak sayfa. Kaynak modelde zorunlu (kaynağı
  // olmayan kayıt listeye girmez); kullanıcı takvimden doğrulayabilsin.
  final aciklama = '${arz.sirket}\n${arz.kaynak}';
  TakvimEtkinligi olay(String tur, DateTime gun, String baslik) =>
      TakvimEtkinligi(
        uid: '${arz.kod}-$tur-${takvimGunu(gun)}',
        gun: gun,
        baslik: baslik,
        aciklama: aciklama,
        url: arz.kaynak,
      );
  // PRODID eski çıktıyla birebir: daha önce paylaşılmış dosyalarla aynı
  // üretici kimliği kalsın (2026-11-11 genel üreticiye ayrılırken).
  return takvimIcs(
    etkinlikler: [
      if (arz.talepBitis != null)
        olay('talep-son', arz.talepBitis!, talepSonBaslik),
      if (arz.islemBaslangic != null)
        olay('islem-baslangic', arz.islemBaslangic!, islemBaslik),
    ],
    simdi: simdi,
    prodId: '-//sandik//halka arz takvimi//TR',
  );
}

/// `.ics` dosyasını geçici klasöre yazıp paylaşım sayfasını açar.
/// Hata çağırana fırlar; ekran kullanıcıya dostça gösterir.
Future<void> halkaArzTakvimPaylas({
  required String ics,
  required String kod,
  required String konu,
  Rect? origin,
}) =>
    // Dosya adı eskisiyle aynı: `sandik-halka-arz-<kod>.ics`.
    takvimPaylas(
      ics: ics,
      dosyaAdi:
          'sandik-halka-arz-${kod.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}',
      konu: konu,
      origin: origin,
    );
