import '../../utils/tr_katla.dart';

/// Fon ADINDAN TEFAS kodu — SAF, ağ yok.
///
/// ## Neden (2026-10-03, DenizBank Varlık Ekstresi)
/// Banka ekstreleri fonu kodla değil adla yazar: "İŞ PORTFÖY YARI İLETKEN
/// TEKNOLOJİLERİ DEĞİŞKEN FON", "YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ
/// SEKTÖRÜ HİSSE" (TEFAS unvanının KESİK hâli; tam unvan "… HİSSE SENEDİ
/// FONU (HİSSE SENEDİ YOĞUN FON)"). Bazı formlar sona ISIN ekler
/// ("…---TRMYK9WWWWW2").
///
/// ## Kural: tahmin yok
/// Ad, unvanın kelime kelime ÖNEKİ olmalı (her kelime unvandaki karşılığının
/// başı: "FON" ↔ "FONU"). Tek aday → kod; birden çok aday ya da hiç aday →
/// `null` ve satır içe aktarılmaz, kullanıcıya "tanınmadı" denir. Yanlış
/// fonu eklemek (yanlış fiyat, yanlış getiri) hiç eklememekten kötüdür —
/// "GARANTİ PORTFÖY ALTIN KATILIM FONU" adla eşleşmeseydi tür çıkarımı onu
/// gram altın sanardı.
String fonAdiAnahtari(String ad) {
  var s = ad;
  final isin = s.indexOf('---');
  if (isin > 0) s = s.substring(0, isin);
  return trKatla(s)
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// [ad] için [fonlar] (kod, unvan) içinden TEK eşleşen fonun kodu.
String? fonKoduBul(String ad, Iterable<({String kod, String unvan})> fonlar) {
  final anahtar = fonAdiAnahtari(ad);
  if (anahtar.isEmpty) return null;
  final kelimeler = anahtar.split(' ');
  final adaylar = <String>{};
  for (final f in fonlar) {
    final u = fonAdiAnahtari(f.unvan);
    // Birebir aynı unvan her zaman kazanır (kısa unvan, uzun unvanın
    // öneki de olabilir: "X FONU" ve "X FONU SERBEST").
    if (u == anahtar) return f.kod.trim().toUpperCase();
    final uk = u.split(' ');
    if (uk.length < kelimeler.length) continue;
    var tutar = true;
    for (var i = 0; i < kelimeler.length; i++) {
      if (!uk[i].startsWith(kelimeler[i])) {
        tutar = false;
        break;
      }
    }
    if (tutar) adaylar.add(f.kod.trim().toUpperCase());
  }
  return adaylar.length == 1 ? adaylar.single : null;
}
