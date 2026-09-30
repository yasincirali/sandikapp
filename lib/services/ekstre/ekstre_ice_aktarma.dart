import 'dart:typed_data';

import 'ekstre_tablosu.dart';
import 'pdf_okuyucu.dart';
import 'tablo_anlama.dart';
import 'tablo_okuyucular.dart';

export 'ekstre_tablosu.dart' show EkstreOkumaHatasi;
export 'tablo_anlama.dart' show EkstreAnlami, EkstreRol, EkstreRolAdi;

/// Evrensel ekstre içe aktarma — dosya baytlarından `CsvImportService`'e.
///
/// ```
///  bayt ──bicimiSez──► okuyucu (xlsx | html-xls | csv/txt | pdf)
///                         │  List<EkstreTablosu>  (satır × hücre)
///                         ▼
///                   tablolariAnla  (başlık bul, sütun rolü: başlık + içerik
///                         │         + adet×fiyat≈tutar; güven skoru)
///                         ▼
///                  kanonik sekmeli metin ──► CsvImportService.parse
/// ```
/// Kullanıcı (2026-10-01): "öyle bir algoritma çözmeliyiz ki tüm
/// formattakiler .pdf, .xlsx, .csv hepsini çözüp uygulamaya dahil
/// edebilmeli, farklı kolon yapıları olmasına rağmen." Kurum başına kod
/// YOK; ayrıntı ve sınırlar: docs/EKSTRE_MOTORU.md.
class EkstreOkumaSonucu {
  const EkstreOkumaSonucu({required this.bicim, required this.anlamlar});

  final EkstreBicimi bicim;

  /// En güçlüsü başta. Birden fazlası XLSX'in ayrı sayfaları ya da ayrı
  /// HTML tablolarıdır (ör. "Hisse" ve "Fon" sayfaları).
  final List<EkstreAnlami> anlamlar;

  EkstreAnlami get ana => anlamlar.first;

  /// Emin olunan tabloların birleşik kanonik metni. Ana tablo her zaman
  /// girer (eşleme ekranı onu gösterir); diğerleri yalnız eşiği geçerse.
  String kanonikMetin() {
    final secilen = [
      ana,
      for (final a in anlamlar.skip(1))
        if (!a.eminDegil) a,
    ];
    final sutunlar = EkstreAnlami.kanonikSutunlar(secilen);
    return [
      sutunlar.map((r) => r.kanonikBaslik).join('\t'),
      for (final a in secilen) ...a.kanonikSatirlar(sutunlar),
    ].join('\n');
  }

  /// Kullanıcı ana tablonun eşlemesini düzeltti.
  EkstreOkumaSonucu anaDuzeltildi(Map<EkstreRol, int> roller) => EkstreOkumaSonucu(
        bicim: bicim,
        anlamlar: [ana.yeniRollerle(roller), ...anlamlar.skip(1)],
      );
}

/// Dosyayı okur ve anlar. Okunamaz ya da içinde portföy tablosu yoksa
/// kullanıcıya gösterilecek mesajla [EkstreOkumaHatasi] fırlatır.
Future<EkstreOkumaSonucu> ekstreyiOku(Uint8List bytes) async {
  if (bytes.isEmpty) throw const EkstreOkumaHatasi('Dosya boş.');
  final bicim = bicimiSez(bytes);
  final tablolar =
      bicim == EkstreBicimi.pdf ? await pdfTablolari(bytes) : tablolariOku(bytes);
  final anlamlar = tablolariAnla(tablolar);
  if (anlamlar.isEmpty) {
    throw const EkstreOkumaHatasi(
        'Dosyada sembol içeren bir tablo bulunamadı. Portföy dökümü ya da '
        'işlem ekstresi olduğundan emin ol; olmuyorsa tabloyu kopyalayıp '
        'aşağıya yapıştır.');
  }
  return EkstreOkumaSonucu(bicim: bicim, anlamlar: anlamlar);
}
