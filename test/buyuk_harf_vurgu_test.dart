import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Metinde büyük harfle vurgu yok (Ar-Ge 11 Kas 17:04 #5).
///
/// Kural kaynağı: CLAUDE.md "yeni metni .arb'a büyük harfle yazma" ve
/// `store_listing/preview_video/ANLATIM_KURALLARI.md` "vurgu cümlenin
/// kuruluşuyla". Büyük harfle yazılan kelime bağırır, ekran okuyucu da onu
/// kimi zaman harf harf okur. Vurgu gerekiyorsa cümle öyle kurulur: hesap
/// silmede "Bu işlem geri alınamaz." ilk cümle olarak durur.
///
/// Ratchet: sayı yalnız azalabilir. Bugün 0; yeni bir büyük harfli kelime
/// gerçekten kısaltma ya da sembolse [_kisaltmalar]'a gerekçesiyle eklenir,
/// vurgu ise cümle yeniden kurulur.
///
/// Sayılan: `{yer tutucu}` dışında kalan, en az 4 harfli, tamamı büyük harf
/// kelime (Türkçe harfler dahil). 3 harf ve altı (TL, USD, AL/SAT, BES, KAP)
/// zaten sayılmaz; kısaltmalar çoğunlukla bu boydadır.
const _tavan = 0;

/// Gerçekten arb'larda geçen 4+ harfli kısaltma ve semboller. Listeye
/// "belki lazım olur" diye ekleme yapılmaz: her satır bugün bir metinde
/// geçiyor.
const _kisaltmalar = <String>{
  // Kurum ve sistem adları: büyük harf yazımın kendisi.
  'BIST', // Borsa İstanbul
  'TEFAS', // Türkiye Elektronik Fon Alım Satım Platformu
  'TÜFE', // Tüketici fiyat endeksi
  'TÜİK', // Türkiye İstatistik Kurumu
  'TCMB', // Merkez Bankası (TR)
  'CBRT', // Merkez Bankası (EN karşılığı)
  'KVKK', // Kişisel Verilerin Korunması Kanunu
  'ISIN', // menkul kıymet kimlik numarası
  // Ölçü ve teknik terim kısaltmaları.
  'XIRR', // yıllık getiri yöntemi; ekranda kısaltmayla anılıyor
  'MACD', // teknik gösterge adı
  'JSON', // dışa aktarım biçimi
  // Örnek semboller ve kodlar: kullanıcının yazacağı biçimin aynısı.
  'AAPL', 'GARAN', 'THYAO', // hisse kodları
  'USDT', 'USDTRY', 'EURTRY', 'GBPTRY', 'XAUTRY', // kur/kripto sembolleri
  'KRHNJ', // ortak kodu örneği (KRHNJ-8P2SW)
};

final _kelime = RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]+');
final _kucuk = RegExp(r'[a-zçğıöşü]');
final _yerTutucu = RegExp(r'\{[^}]*\}');

List<String> _vurgular(String arbYolu) {
  final arb = jsonDecode(File(arbYolu).readAsStringSync()) as Map;
  final bulunan = <String>[];
  arb.forEach((anahtar, deger) {
    if ((anahtar as String).startsWith('@') || deger is! String) return;
    for (final m in _kelime.allMatches(deger.replaceAll(_yerTutucu, ' '))) {
      final w = m.group(0)!;
      if (w.length < 4 || _kucuk.hasMatch(w)) continue;
      if (_kisaltmalar.contains(w)) continue;
      bulunan.add('$anahtar: $w');
    }
  });
  return bulunan;
}

void main() {
  for (final yol in ['lib/l10n/app_tr.arb', 'lib/l10n/app_en.arb']) {
    test('$yol: büyük harfle vurgulanan kelime yok (yalnız azalabilir)', () {
      final bulunan = _vurgular(yol);
      expect(
        bulunan.length,
        lessThanOrEqualTo(_tavan),
        reason: 'Büyük harfle vurgu: ${bulunan.join(', ')}. Vurguyu cümlenin '
            'kuruluşuyla ver ("Bu işlem geri alınamaz." ilk cümle gibi). '
            'Kısaltma ya da sembolse _kisaltmalar\'a gerekçesiyle ekle.',
      );
    });
  }

  test('sayaç gerçekten büyük harfi yakalıyor (Türkçe harfler dahil)', () {
    // Düzenli ifade Türkçe büyük harfleri kaçırırsa test sessizce yeşil
    // kalırdı; eski dört metnin kelimeleri burada yakalanmalı.
    for (final w in ['KALICI', 'GERİ', 'TARİHLER', 'ETKİLEMEZ', 'ŞÜPHE']) {
      final m = _kelime.firstMatch(w)!.group(0)!;
      expect(m, w, reason: '$w tek kelime olarak eşleşmeli');
      expect(_kucuk.hasMatch(m), isFalse);
    }
  });

  test('Play "Yenilikler" metni YENİ/NEW önekiyle başlamaz', () {
    // "Yeni rozeti yok" kararı (yasin 2026-11-05): madde başında "YENİ:"
    // ilan dilidir, mağaza notu zaten yeni olanı anlatır.
    final onek = RegExp(r'^\W*(yeni|new)\b', caseSensitive: false);
    for (final yol in [
      'store_listing/tr-TR/whats_new.txt',
      'store_listing/en-US/whats_new.txt',
    ]) {
      for (final satir in File(yol).readAsLinesSync()) {
        expect(onek.hasMatch(satir), isFalse,
            reason: '$yol satırı önekle başlıyor: "$satir"');
      }
    }
  });
}
