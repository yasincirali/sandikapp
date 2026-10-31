import 'package:intl/intl.dart';

/// Üretilen belgelerin (PDF ve aynı belgenin Excel'i) dosya adı. TEK yer.
///
/// ## Neden (yasin 2026-10-31)
/// "Üretilen tüm pdflerin isimlerini zamanına ve kategorisine göre geçmişe
/// dönüp bakılacak şekilde anlamlı ver; indirdiği ya da paylaştığı yerde
/// kolay anlaşılsın." Eski adlar `sandik-2026-10-aylik-rapor`,
/// `sandik-yorum-2026-10-14` gibiydi: Dosyalar'da, WhatsApp'ta, e-postada
/// ne olduğu ilk bakışta okunmuyordu, yorum notunun dönemi (hafta mı, 3 ay
/// mı) ve varlığı addan anlaşılmıyordu, aynı gün alınan iki döküm aynı adı
/// taşıyordu.
///
/// ## Kalıp
/// `sandık <Belge türü> [<Varlık>] <Dönem>` ; dönem önce sayıyla
/// (`2026-10`, `2026-10-31`), gerekiyorsa ardından ay adıyla.
///   - Belge türü önde: bir klasörde aynı tür belgeler yan yana dizilir.
///   - Sayısal dönem `yıl-ay-gün`: aynı türün içinde ad sırası = zaman
///     sırası, geçmişe dönüp bakmak bu demek.
///   - Ay adı parantezde: "2026-10" okuyana "Ekim" demek kolaylık; sıralamayı
///     bozmaz (sayıdan sonra gelir).
///   - Anlık belgede (portföy dökümü) saat de var: aynı gün iki döküm üst
///     üste yazılmaz, hangisinin sonra olduğu belli.
///
/// Türkçe harfler ve boşluk kalır (iOS/Android paylaşım sayfası, Dosyalar,
/// e-posta ve mesajlaşma bunları taşır); dosya sisteminde sorun çıkaran
/// karakterler (`/ \ : * ? " < > |`) tireye çevrilir.
/// Uzantıyı çağıran ekler (`.pdf`, `.xlsx`).
String belgeDosyaAdi(String tur, String donem, {String? varlik}) => _temizle([
      'sandık',
      tur,
      if (varlik != null && varlik.trim().isNotEmpty) varlik,
      donem
    ].join(' '));

/// `2026-10 (Ekim)`
String ayDonemi(DateTime ay) =>
    '${DateFormat('yyyy-MM').format(ay)} (${DateFormat('MMMM', 'tr_TR').format(ay)})';

/// `2026-10-31`
String gunDonemi(DateTime gun) => DateFormat('yyyy-MM-dd').format(gun);

/// `2026-10-31 14.30` (iki nokta dosya adında yasak; saat noktayla).
String anDonemi(DateTime an) => DateFormat('yyyy-MM-dd HH.mm').format(an);

/// `2026-10-20 (20-26 Ekim)`; ay taşan haftada `2026-09-29 (29 Eylül-5 Ekim)`.
String haftaDonemi(DateTime bas, DateTime bit) {
  final ay = DateFormat('MMMM', 'tr_TR');
  final aralik = bas.month == bit.month
      ? '${bas.day}-${bit.day} ${ay.format(bit)}'
      : '${bas.day} ${ay.format(bas)}-${bit.day} ${ay.format(bit)}';
  return '${gunDonemi(bas)} ($aralik)';
}

String _temizle(String s) => s
    .replaceAll(RegExp(r'[/\\:*?"<>|]'), '-')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
