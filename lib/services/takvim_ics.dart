// Genel "Takvime ekle" üreticisi (2026-11-11).
//
// Halka arzdaki `.ics` yolu (2026-11-08) mevduat vadesi, Eurobond kuponu ve
// beklenen temettüye de açıldığı için saf kısmı buraya ayrıldı. İlke aynı:
// takvim izni ya da yeni eklenti İSTEMEDEN bir `.ics` dosyası üretilir ve
// sistem paylaşım sayfasıyla verilir; kişisel veri cihazdan çıkmaz, yeni
// izin/yasal metin gerekmez.
//
// Metin üretimi saf fonksiyondur ([takvimIcs]) ki RFC 5545 kuralları (CRLF,
// satır katlama, kaçış) widget'sız test edilsin. **Uydurma tarih yok**:
// etkinlik listesi boşsa dosya üretilmez; çağıran tarih bilinmiyorsa
// etkinliği listeye koymaz, düğmeyi de çizmez.
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path_provider/path_provider.dart';

import 'share_card_service.dart';

/// Tek bir tüm gün etkinliği. Saat bilgisi bilerek yok: vade, kupon ve
/// temettü günleri gün düzeyinde bilinir; saat yazmak uydurma olurdu.
class TakvimEtkinligi {
  const TakvimEtkinligi({
    required this.uid,
    required this.gun,
    required this.baslik,
    this.aciklama,
    this.url,
  });

  /// Kararlı kimlik (`@sandik` sonek olarak eklenir): aynı dosya iki kez
  /// açılırsa takvim uygulaması aynı etkinliği günceller, kopya üretmez.
  final String uid;
  final DateTime gun;
  final String baslik;
  final String? aciklama;

  /// Yalnız şemalı (http/https…) adres yazılır; şemasızı takvim uygulaması
  /// bağlantı sanıp bozuk açar.
  final String? url;
}

/// [etkinlikler] için VCALENDAR metni; liste boşsa `null` (boş takvim
/// dosyası paylaşılmaz). [simdi] DTSTAMP içindir (test deterministik kalsın
/// diye dışarıdan). [prodId] halka arzın eski çıktısı birebir kalsın diye
/// parametre.
String? takvimIcs({
  required List<TakvimEtkinligi> etkinlikler,
  required DateTime simdi,
  String prodId = '-//sandik//takvim//TR',
}) {
  if (etkinlikler.isEmpty) return null;
  final damga = _utcDamga(simdi);
  final satirlar = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:$prodId',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    for (final e in etkinlikler) ...[
      'BEGIN:VEVENT',
      'UID:${e.uid}@sandik',
      'DTSTAMP:$damga',
      'DTSTART;VALUE=DATE:${takvimGunu(e.gun)}',
      // Tüm gün etkinliğinde DTEND hariçtir: ertesi gün.
      'DTEND;VALUE=DATE:'
          '${takvimGunu(DateTime(e.gun.year, e.gun.month, e.gun.day + 1))}',
      'SUMMARY:${icsKacis(e.baslik)}',
      if (e.aciklama != null) 'DESCRIPTION:${icsKacis(e.aciklama!)}',
      if (e.url != null && (Uri.tryParse(e.url!)?.hasScheme ?? false))
        'URL:${e.url}',
      // Tüm gün hatırlatıcısı kullanıcının gününü "meşgul" göstermesin.
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

/// `YYYYAAGG` — DATE değeri ve UID'lerde kullanılır.
String takvimGunu(DateTime d) => '${d.year.toString().padLeft(4, '0')}'
    '${_iki(d.month)}${_iki(d.day)}';

String _utcDamga(DateTime t) {
  final u = t.toUtc();
  return '${takvimGunu(u)}T${_iki(u.hour)}${_iki(u.minute)}${_iki(u.second)}Z';
}

/// `.ics` dosyasını geçici klasöre yazıp paylaşım sayfasını açar.
/// [dosyaAdi] uzantısız; harf/rakam dışı karakterler atılır.
/// Hata çağırana fırlar; ekran kullanıcıya dostça gösterir.
Future<void> takvimPaylas({
  required String ics,
  required String dosyaAdi,
  required String konu,
  Rect? origin,
}) async {
  final dir = await getTemporaryDirectory();
  final ad = dosyaAdi.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '');
  final file = File('${dir.path}/$ad.ics');
  await file.writeAsString(ics, flush: true);
  // Dosya bilerek silinmez: Android'de alıcı takvim uygulaması dosyayı
  // paylaşım sayfası kapandıktan SONRA okuyabilir. Geçici klasörü OS
  // temizler.
  await ShareCardService.shareFile(
    file.path,
    mimeType: 'text/calendar',
    subject: konu,
    origin: origin,
  );
}
