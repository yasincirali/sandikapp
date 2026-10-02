import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../models/asset_type.dart';
import '../../providers/bulk_cart_provider.dart';
import '../mevduat_hesabi.dart';
import 'ekstre_tablosu.dart';
import 'fon_adi.dart';
import 'mevduat_tablosu.dart';
import 'pdf_okuyucu.dart';
import 'tablo_anlama.dart';
import 'tablo_okuyucular.dart';

export 'ekstre_tablosu.dart' show EkstreOkumaHatasi;
export 'mevduat_tablosu.dart' show EkstreMevduati;
export 'tablo_anlama.dart' show EkstreAnlami, EkstreRol, EkstreRolAdi;

/// Evrensel ekstre içe aktarma — dosya baytlarından `CsvImportService`'e.
///
/// ```
///  bayt ──bicimiSez──► okuyucu (xlsx | html-xls | csv/txt | pdf)
///                         │  List<EkstreTablosu>  (satır × hücre)
///                         ├──────────────► vadeliMevduatlar (sözleşmeli)
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
///
/// Banka varlık ekstresi (2026-10-03, kullanıcı: "sadece yatırım ve vadeli
/// mevduatlar içeride olmalı"): fonlar ADLA yazılır (kod sonradan TEFAS
/// unvanından, [EkstreOkumaSonucu.adKodlari]), vadeli mevduat sözleşmesiyle
/// ayrı kalem olur ([EkstreOkumaSonucu.mevduatlar]), vadesiz hesap hiç
/// alınmaz.
class EkstreOkumaSonucu {
  const EkstreOkumaSonucu({
    required this.bicim,
    required this.anlamlar,
    this.mevduatlar = const [],
    this.notlar = const [],
    this.belgeTarihi,
    this.kurum,
    this.adKodlari = const {},
  });

  final EkstreBicimi bicim;

  /// En güçlüsü başta. Birden fazlası XLSX'in ayrı sayfaları ya da ayrı
  /// HTML/PDF tablolarıdır (ör. "Hisse" ve "Fon" sayfaları).
  final List<EkstreAnlami> anlamlar;

  /// Vadeli mevduat sözleşmeleri (yalnız TL, eksiksiz satırlar).
  final List<EkstreMevduati> mevduatlar;

  /// Alınmayan mevduat satırlarının nedenleri — önizlemede uyarı olur.
  final List<String> notlar;

  /// Belgenin "itibariyle" günü; tarih sütunu olmayan satırların tarihi.
  final DateTime? belgeTarihi;

  /// Belgedeki banka (mevduat sözleşmesinin kurumu).
  final String? kurum;

  /// `fonAdiAnahtari(ad)` → TEFAS kodu ([kodlarla] doldurur).
  final Map<String, String> adKodlari;

  /// Eşleme kartının gösterdiği tablo; yalnız mevduat varsa `null`.
  EkstreAnlami? get ana => anlamlar.firstOrNull;

  /// Kanonik çıktıya giren tablolar: ana her zaman (eşleme ekranı onu
  /// gösterir); diğerleri yalnız eşiği geçerse. Elle eşleme adayı (ana
  /// sembolsüz) hiçbir şey vermez: metin alanına yarım bir tablo basmak
  /// yerine boş kalır; kart "emin değiliz" der, kullanıcı sütunları seçer.
  List<EkstreAnlami> get _secilen {
    final a = ana;
    if (a == null || !a.roller.containsKey(EkstreRol.sembol)) return const [];
    return [
      a,
      for (final x in anlamlar.skip(1))
        if (!x.eminDegil) x,
    ];
  }

  /// Emin olunan tabloların birleşik kanonik metni.
  String kanonikMetin() {
    final secilen = _secilen;
    if (secilen.isEmpty) return '';
    final tarihEkle = belgeTarihi != null &&
        secilen.any((a) => !a.roller.containsKey(EkstreRol.tarih));
    final sutunlar = EkstreAnlami.kanonikSutunlar(
      secilen,
      tarihEkle: tarihEkle,
    );
    return [
      sutunlar.map((r) => r.kanonikBaslik).join('\t'),
      for (final a in secilen)
        ...a.kanonikSatirlar(
          sutunlar,
          adKodlari: adKodlari,
          varsayilanTarih: belgeTarihi,
        ),
    ].join('\n');
  }

  /// Koda çözülmesi gereken fon adları (tekil, belge sırasıyla).
  List<String> get cozulecekFonAdlari =>
      {for (final a in _secilen) ...a.fonAdlari}.toList();

  /// TEFAS'ta tek bir fona eşleşmeyen adlar — içe aktarılmadı.
  List<String> get cozulemeyenFonlar => [
        for (final ad in cozulecekFonAdlari)
          if (!adKodlari.containsKey(fonAdiAnahtari(ad))) ad,
      ];

  /// Fon listesiyle adları koda çevirir (saf; liste ağdan çağıranda gelir).
  EkstreOkumaSonucu kodlarla(Iterable<({String kod, String unvan})> fonlar) {
    final kodlar = <String, String>{};
    for (final ad in cozulecekFonAdlari) {
      final kod = fonKoduBul(ad, fonlar);
      if (kod != null) kodlar[fonAdiAnahtari(ad)] = kod;
    }
    return _kopya(adKodlari: kodlar);
  }

  /// Kullanıcı ana tablonun eşlemesini düzeltti.
  EkstreOkumaSonucu anaDuzeltildi(Map<EkstreRol, int> roller) =>
      _kopya(anlamlar: [ana!.yeniRollerle(roller), ...anlamlar.skip(1)]);

  /// Vadeli mevduatlar sepet kalemi olarak. Stopaj açılış gününün tarihli
  /// tablosundan ÖNERİDİR (`onerilenStopaj`); ekstre stopaj oranı yazmaz.
  List<BulkCartItem> mevduatKalemleri({Uuid uuid = const Uuid()}) => [
        for (final m in mevduatlar)
          BulkCartItem(
            id: uuid.v4(),
            type: AssetType.mevduat,
            name: '${kurum ?? 'Banka'} vadeli',
            // Sembolü sözleşme kimliğinden `mevduatAc` kurar.
            ticker: '',
            quantity: m.anapara,
            price: 1.0,
            currency: 'TRY',
            addedDate: m.baslangic,
            mevduat: (
              kurum: kurum ?? 'Banka',
              yillikFaiz: m.yillikFaiz,
              stopaj: onerilenStopaj(m.baslangic, m.vadeGun),
              vadeGun: m.vadeGun,
            ),
          ),
      ];

  EkstreOkumaSonucu _kopya({
    List<EkstreAnlami>? anlamlar,
    Map<String, String>? adKodlari,
  }) =>
      EkstreOkumaSonucu(
        bicim: bicim,
        anlamlar: anlamlar ?? this.anlamlar,
        mevduatlar: mevduatlar,
        notlar: notlar,
        belgeTarihi: belgeTarihi,
        kurum: kurum,
        adKodlari: adKodlari ?? this.adKodlari,
      );
}

/// Dosyayı okur ve anlar. Okunamaz ya da içinde ne portföy tablosu ne
/// vadeli mevduat varsa kullanıcıya gösterilecek mesajla
/// [EkstreOkumaHatasi] fırlatır.
Future<EkstreOkumaSonucu> ekstreyiOku(Uint8List bytes) async {
  if (bytes.isEmpty) throw const EkstreOkumaHatasi('Dosya boş.');
  final bicim = bicimiSez(bytes);
  final List<EkstreTablosu> tablolar;
  final String metin;
  if (bicim == EkstreBicimi.pdf) {
    final pdf = await pdfOku(bytes);
    tablolar = pdf.tablolar;
    metin = pdf.metin;
  } else {
    tablolar = tablolariOku(bytes);
    metin = [
      for (final t in tablolar)
        for (final s in t.satirlar) s.join(' '),
    ].join('\n');
  }
  return ekstreyiAnla(bicim, tablolar, metin);
}

/// Okunmuş tablolardan sonuç — saf (PDF eklentisine dokunmaz; testler
/// gerçek PDFium kutularından kurulan tablolarla buradan girer).
EkstreOkumaSonucu ekstreyiAnla(
  EkstreBicimi bicim,
  List<EkstreTablosu> tablolar,
  String metin,
) {
  var anlamlar = tablolariAnla(tablolar);
  final mevduat = vadeliMevduatlar(tablolar);
  if (anlamlar.isEmpty && mevduat.mevduatlar.isEmpty) {
    // Sembol sütunu tanınmadı ama ortada bir tablo var: çıkmaz sokak yerine
    // en büyük tabloyu güven 0 ile ver — ekran "emin değiliz" der ve
    // "Sütunları düzelt" ile kullanıcı sembolü kendisi gösterir. Motor
    // uydurmaz (roller boş kalır); yalnızca elle eşlemenin yolu açık kalır.
    // Tanınmayan kurum çıktısında ilk sürüm doğrudan hata veriyordu ve
    // kullanıcının dosyayla yapabileceği hiçbir şey kalmıyordu (2026-10-02).
    anlamlar = _elleEslemeAdayi(tablolar);
  }
  if (anlamlar.isEmpty && mevduat.mevduatlar.isEmpty) {
    throw const EkstreOkumaHatasi(
      'Dosyada sembol içeren bir tablo bulunamadı. Portföy dökümü ya da '
      'işlem ekstresi olduğundan emin ol; olmuyorsa tabloyu kopyalayıp '
      'aşağıya yapıştır.',
    );
  }
  return EkstreOkumaSonucu(
    bicim: bicim,
    anlamlar: anlamlar,
    mevduatlar: mevduat.mevduatlar,
    notlar: mevduat.notlar,
    belgeTarihi: belgeTarihiBul(metin),
    kurum: bankaAdiBul(metin),
  );
}

/// Sembolsüz anlaşılan tablolardan elle eşlemeye en uygun olanı: en az iki
/// veri satırı ve üç sütun; en çok satırlı önce.
List<EkstreAnlami> _elleEslemeAdayi(List<EkstreTablosu> tablolar) {
  final adaylar = <EkstreAnlami>[
    for (final t in tablolar)
      if (tabloyuAnla(t) case final a?)
        if (a.veri.length >= 2 && a.basliklar.length >= 3) a,
  ]..sort((a, b) => b.veri.length.compareTo(a.veri.length));
  return adaylar.take(1).toList();
}
