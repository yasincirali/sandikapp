// Halka arz detayındaki "Takvime ekle" (2026-11-08).
//
// Takvim izni ya da yeni eklenti İSTEMEDEN: bir `.ics` dosyası üretilir ve
// sistem paylaşım sayfasıyla verilir; iOS/Android takvim uygulaması dosyayı
// tanıyıp "etkinlik ekle" der. Böylece kişisel veri cihazdan çıkmaz, yeni
// izin/yasal metin gerekmez.
//
// Metin üretimi saf fonksiyondur ([halkaArzIcs]) ki RFC 5545 kuralları
// (CRLF, satır katlama, kaçış) widget'sız test edilsin; ekran yalnızca
// başlıkları l10n'dan verir. **Uydurma tarih yok**: bilinmeyen tarih için
// etkinlik yazılmaz; iki tarih de yoksa düğme hiç çizilmez.
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path_provider/path_provider.dart';

import '../models/halka_arz.dart';
import 'share_card_service.dart';

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
  final olaylar = <(String, DateTime, String)>[
    if (arz.talepBitis != null) ('talep-son', arz.talepBitis!, talepSonBaslik),
    if (arz.islemBaslangic != null)
      ('islem-baslangic', arz.islemBaslangic!, islemBaslik),
  ];
  if (olaylar.isEmpty) return null;

  final damga = _utcDamga(simdi);
  // Açıklama: şirket adı + kaynak sayfa. Kaynak modelde zorunlu (kaynağı
  // olmayan kayıt listeye girmez); kullanıcı takvimden doğrulayabilsin.
  final aciklama = '${arz.sirket}\n${arz.kaynak}';
  final satirlar = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//sandik//halka arz takvimi//TR',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    for (final (tur, gun, baslik) in olaylar) ...[
      'BEGIN:VEVENT',
      // Kararlı UID: aynı dosya iki kez açılırsa takvim uygulaması aynı
      // etkinliği günceller, kopya üretmez.
      'UID:${arz.kod}-$tur-${_gun(gun)}@sandik',
      'DTSTAMP:$damga',
      'DTSTART;VALUE=DATE:${_gun(gun)}',
      // Tüm gün etkinliğinde DTEND hariçtir: ertesi gün.
      'DTEND;VALUE=DATE:${_gun(DateTime(gun.year, gun.month, gun.day + 1))}',
      'SUMMARY:${icsKacis(baslik)}',
      'DESCRIPTION:${icsKacis(aciklama)}',
      if (Uri.tryParse(arz.kaynak)?.hasScheme ?? false) 'URL:${arz.kaynak}',
      'TRANSP:TRANSPARENT',
      'END:VEVENT',
    ],
    'END:VCALENDAR',
  ];
  return '${satirlar.map(icsKatla).join('\r\n')}\r\n';
}

/// RFC 5545 §3.3.11 TEXT kaçışı: ters bölü, `;`, `,` ve satır sonu.
String icsKacis(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\r\n', '\\n')
    .replaceAll('\n', '\\n')
    .replaceAll('\r', '\\n');

/// RFC 5545 §3.1 satır katlama: 75 OKTETİ aşan satır CRLF + boşlukla
/// bölünür. Türkçe harfler UTF-8'de iki oktet olduğundan karakter değil
/// oktet sayılır ve çok oktetli karakter ortadan bölünmez.
String icsKatla(String satir) {
  if (utf8.encode(satir).length <= 75) return satir;
  final sb = StringBuffer();
  var oktet = 0;
  var sinir = 75; // devam satırının baştaki boşluğu da sayılır → 74
  for (final r in satir.runes) {
    final ch = String.fromCharCode(r);
    final n = utf8.encode(ch).length;
    if (oktet + n > sinir) {
      sb.write('\r\n ');
      oktet = 0;
      sinir = 74;
    }
    sb.write(ch);
    oktet += n;
  }
  return sb.toString();
}

String _iki(int n) => n.toString().padLeft(2, '0');

String _gun(DateTime d) => '${d.year.toString().padLeft(4, '0')}'
    '${_iki(d.month)}${_iki(d.day)}';

String _utcDamga(DateTime t) {
  final u = t.toUtc();
  return '${_gun(u)}T${_iki(u.hour)}${_iki(u.minute)}${_iki(u.second)}Z';
}

/// `.ics` dosyasını geçici klasöre yazıp paylaşım sayfasını açar.
/// Hata çağırana fırlar; ekran kullanıcıya dostça gösterir.
Future<void> halkaArzTakvimPaylas({
  required String ics,
  required String kod,
  required String konu,
  Rect? origin,
}) async {
  final dir = await getTemporaryDirectory();
  final ad = kod.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final file = File('${dir.path}/sandik-halka-arz-$ad.ics');
  await file.writeAsString(ics, flush: true);
  // Dosya bilerek silinmez: Android'de alıcı takvim uygulaması dosyayı
  // paylaşım sayfası kapandıktan SONRA okuyabilir. İçerik kişisel veri
  // değil (kamuya açık halka arz tarihleri); geçici klasörü OS temizler.
  await ShareCardService.shareFile(
    file.path,
    mimeType: 'text/calendar',
    subject: konu,
    origin: origin,
  );
}
