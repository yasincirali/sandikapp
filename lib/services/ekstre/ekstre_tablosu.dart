import '../../utils/friendly_error.dart';

/// Evrensel ekstre motorunun ortak ara biçimi: bir belgeden çıkan TABLO.
///
/// ## Neden tek ara biçim
/// Kurumlar ekstreyi PDF, `.xlsx`, `.xls` (çoğu aslında HTML tablo), CSV
/// ya da düz metin olarak veriyor ve her kurumun sütun düzeni farklı
/// (bkz. docs/EKSTRE_MOTORU.md). Biçimi çözmek (okuyucular) ile tabloyu
/// ANLAMAK (hangi sütun sembol, hangisi adet — `TabloAnlama`) ayrı işlerdir:
/// her okuyucu yalnızca "satır × hücre" üretir, anlama katmanı biçimden
/// habersizdir. Yeni bir biçim yalnızca okuyucu ekler; yeni bir kurum çoğu
/// zaman hiç kod gerektirmez.
///
/// Hücreler HAM metindir; tek istisna XLSX'in sayı ve tarih hücreleridir —
/// orada tip bilindiği için okuyucu belirsizliği baştan kaldırır (sayı
/// "1234,56", tarih "gg.aa.yyyy").
class EkstreTablosu {
  const EkstreTablosu({required this.kaynak, required this.satirlar});

  /// İnsan için kaynak adı: "Sayfa1", "PDF", "CSV"…
  final String kaynak;

  /// Satırlar; her satır hücre metinleri. Satırlar farklı uzunlukta olabilir.
  final List<List<String>> satirlar;

  bool get bos => satirlar.every((s) => s.every((h) => h.trim().isEmpty));
}

/// Okuma sırasında kullanıcıya söylenecek, tabloyu okunamaz kılan durum.
///
/// `KullaniciMesajli`: mesaj bizim cümlemizdir (ham teknik metin değil);
/// `friendlyError` onu olduğu gibi gösterir.
class EkstreOkumaHatasi implements KullaniciMesajli {
  const EkstreOkumaHatasi(this.mesaj);
  final String mesaj;

  @override
  String get message => mesaj;

  @override
  String toString() => mesaj;
}

/// AI sütun eşleme (`ekstre-esle`) başarısız. [kota]: günlük hak ya da
/// aylık maliyet tavanı doldu (429) — kullanıcıya "yarın yeniden dene"
/// denir. [premium]: sunucunun Premium kapısı reddetti (403; istemci
/// hakkı henüz bilmiyordu) — paywall açılır. Diğer her durumda genel
/// mesaj. Ham sunucu yanıtı gösterilmez.
class EkstreAiHatasi implements Exception {
  const EkstreAiHatasi({this.kota = false, this.premium = false});
  final bool kota;
  final bool premium;
}
