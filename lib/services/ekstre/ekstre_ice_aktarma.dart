import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../models/asset_type.dart';
import '../bist_hisse_katalogu.dart';
import '../../providers/bulk_cart_provider.dart';
import '../mevduat_hesabi.dart';
import 'ekstre_tablosu.dart';
import 'fon_adi.dart';
import 'hareket_tablosu.dart';
import 'mevduat_tablosu.dart';
import 'pdf_okuyucu.dart';
import 'tablo_anlama.dart';
import 'tablo_okuyucular.dart';
import 'tutar_tablosu.dart';

export 'ekstre_tablosu.dart' show EkstreAiHatasi, EkstreOkumaHatasi;
export 'mevduat_tablosu.dart' show EkstreMevduati;
export 'ekstre_iskeleti.dart' show ekstreIskeleti, ekstreMetni;
export 'hareket_tablosu.dart' show EkstreHareketi;
export 'tablo_anlama.dart' show EkstreAnlami, EkstreRol, EkstreRolAdi;
export 'tutar_tablosu.dart'
    show EkstreTutarKalemi, EkstreTutarTuru, gunFiyati, kurSembolu;

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
    this.fonListesi = const [],
    this.tablolar = const [],
    this.hareketler = const [],
    this.aiOnerisi = false,
    this.tutarKalemleri = const [],
    this.tutarFiyatlari = const {},
  });

  final EkstreBicimi bicim;

  /// Okuyucunun ürettiği ham tablolar (anlamadan önce). Yalnız tanılama
  /// iskeleti okur (`ekstreIskeleti`): "PDF'te sütunlar doğru bölündü mü"
  /// sorusu anlama katmanından değil buradan yanıtlanır.
  final List<EkstreTablosu> tablolar;

  /// Hesap hareketlerindeki alım/satımlar (`hareket_tablosu.dart`). Yalnız
  /// `kanonikMetin(hareketlerle: true)` kullanır (bayrak `ekstre_hareketleri`).
  final List<EkstreHareketi> hareketler;

  /// Eşleme yapay zekâ önerisinden geldi ([aiEslemesiyle]); kart
  /// "kontrol et" der.
  final bool aiOnerisi;

  /// Yalnız tutar yazan varlık satırları ("Varlık Geçmişi Formu",
  /// `tutar_tablosu.dart`). Yalnız sembollü varlık tablosu yokken ve belge
  /// tarihi biliniyorken dolar; adet belge günündeki fiyattan bulunur.
  final List<EkstreTutarKalemi> tutarKalemleri;

  /// Fiyat sembolü (`TEFAS:YAY`, `AKBNK.IS`, `ALTIN_GRAM24`, `USDTRY=X`…)
  /// → belge günündeki kapanış ([fiyatlarla] doldurur; ağdan çağıran
  /// getirir). Kurlar da buradadır. Fiyatı olmayan kalem kanonik metne
  /// girmez.
  final Map<String, double> tutarFiyatlari;

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

  /// [kodlarla]'ya verilen TEFAS listesi. Hareketlerde geçen ama varlık
  /// tablosunda olmayan kodun gerçek bir fon olup olmadığını söyler
  /// ([hareketKodlari]); boşsa öyle kodlar alınmaz.
  final List<({String kod, String unvan})> fonListesi;

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
  ///
  /// [hareketlerle]: dönem içindeki alım ve satımlar hesap hareketindeki
  /// gerçek tarih ve fiyatla ayrı satır olur ([hareketlerleIncelt]).
  /// Kapalıyken (bayrak `ekstre_hareketleri` kapalı) çıktı birebir eski.
  String kanonikMetin({bool hareketlerle = false}) {
    final ({List<EkstreRol> sutunlar, List<String> satirlar})? k =
        _secilen.isEmpty && tutarKalemleri.isNotEmpty
            ? _tutarKanonik()
            : hareketlerle
                ? _hareketli()
                : _kanonik();
    // Hareketli yolda varlık tablosu olmayabilir; satır yoksa metin de yok.
    if (k == null || (hareketlerle && k.satirlar.isEmpty)) return '';
    return [k.sutunlar.map((r) => r.kanonikBaslik).join('\t'), ...k.satirlar]
        .join('\n');
  }

  /// Hareketlerle satırı değişen ya da hareketten eklenen varlık sayısı
  /// (önizleme notu için).
  int hareketleIncelenen() =>
      hareketler.isEmpty ? 0 : (_hareketlerle()?.incelen ?? 0);

  /// Hareketlerde geçen ama varlık tablosunda olmayan kodlardan gerçek
  /// varlık olanlar → `tur` hücresi. Fon: TEFAS listesinde (ve çözülemeyen
  /// bir fon adının adayı DEĞİL — o fonun bugünkü adedi bilinmiyor; satışını
  /// eklemek elde duran fonu kapanmış gösterirdi). Hisse: BIST kataloğunda.
  Map<String, String> get hareketKodlari {
    final fonKodlari = {for (final f in fonListesi) f.kod.trim().toUpperCase()};
    final belirsiz = {
      for (final ad in cozulemeyenFonlar) ...fonAdaylari(ad, fonListesi),
    };
    final out = <String, String>{};
    for (final h in hareketler) {
      final kod = h.kod.toUpperCase();
      if (fonKodlari.contains(kod)) {
        if (!belirsiz.contains(kod)) out[kod] = 'Fon';
      } else if (BistHisseKatalogu.instance.kodMu(kod)) {
        out[kod] = 'Hisse';
      }
    }
    return out;
  }

  /// Kanonik çıktı + hareketler. Sütunlar hareket satırının ihtiyacıyla
  /// genişler (fiyat, tutar, tarih, yön, tür); varlık satırında yeni sütun
  /// boş kalır ve `CsvImportService` onu eskisi gibi yorumlar (boş tür →
  /// sembolden çıkarım, boş fiyat → tutardan).
  ({List<EkstreRol> sutunlar, List<String> satirlar})? _hareketli() =>
      _hareketlerle()?.kanonik;

  ({
    ({List<EkstreRol> sutunlar, List<String> satirlar}) kanonik,
    int incelen
  })? _hareketlerle() {
    final k = _kanonik();
    if (hareketler.isEmpty) return k == null ? null : (kanonik: k, incelen: 0);
    const gerekli = {
      EkstreRol.sembol, EkstreRol.adet, EkstreRol.fiyat, EkstreRol.tutar,
      EkstreRol.tarih, EkstreRol.yon, EkstreRol.tur,
    };
    final eski = k?.sutunlar ?? const <EkstreRol>[];
    final sutunlar = [
      for (final r in EkstreRol.values)
        if (gerekli.contains(r) || eski.contains(r)) r,
    ];
    final satirlar = [
      for (final satir in k?.satirlar ?? const <String>[])
        () {
          final h = satir.split('\t');
          return [
            for (final r in sutunlar)
              if (eski.indexOf(r) case final i when i >= 0 && i < h.length)
                h[i]
              else
                '',
          ].join('\t');
        }(),
    ];
    final r = hareketlerleIncelt(
      satirlar,
      sutunlar,
      hareketler,
      bilinenKodlar: hareketKodlari,
      varlikTablosuVar: k != null,
    );
    return (
      kanonik: (sutunlar: sutunlar, satirlar: r.satirlar),
      incelen: r.incelen,
    );
  }

  ({List<EkstreRol> sutunlar, List<String> satirlar})? _kanonik() {
    final secilen = _secilen;
    if (secilen.isEmpty) return null;
    final tarihEkle = belgeTarihi != null &&
        secilen.any((a) => !a.roller.containsKey(EkstreRol.tarih));
    final sutunlar = EkstreAnlami.kanonikSutunlar(
      secilen,
      tarihEkle: tarihEkle,
    );
    return (
      sutunlar: sutunlar,
      satirlar: [
        for (final a in secilen)
          ...a.kanonikSatirlar(
            sutunlar,
            adKodlari: adKodlari,
            varsayilanTarih: belgeTarihi,
          ),
      ],
    );
  }

  /// Yalnız-tutarlı kalemler: adet = tutar ÷ belge günündeki fiyat. Kodu,
  /// fiyatı ya da gereken kuru olmayan satır atlanır (tahmin yok).
  ({List<EkstreRol> sutunlar, List<String> satirlar})? _tutarKanonik() {
    final gun = belgeTarihi;
    if (gun == null) return null;
    final tarih = '${gun.day.toString().padLeft(2, '0')}.'
        '${gun.month.toString().padLeft(2, '0')}.${gun.year}';
    const sutunlar = [
      EkstreRol.sembol, EkstreRol.adet, EkstreRol.fiyat, EkstreRol.tarih,
      EkstreRol.tur, EkstreRol.paraBirimi, EkstreRol.isim,
    ];
    final satirlar = <String>[];
    for (final k in tutarKalemleri) {
      final d = _tutarDegeri(k);
      if (d == null) continue;
      final fon = k.tur == EkstreTutarTuru.fon;
      satirlar.add([
        fon ? adKodlari[fonAdiAnahtari(k.ad)]! : k.sembol!,
        sayiMetni(d.adet),
        sayiMetni(d.fiyat),
        tarih,
        k.turMetni,
        k.fiyatPara,
        // Fon adı belgedekinden; diğerleri uygulamanın adıyla (boş hücre
        // → `normalizeTicker` adı): "Altın Hesabı" bir varlık adı değil.
        if (fon)
          k.ad.split('---').first.replaceAll(RegExp(r'\s+'), ' ').trim()
        else
          '',
      ].join('\t'));
    }
    if (satirlar.isEmpty) return null;
    return (sutunlar: sutunlar, satirlar: satirlar);
  }

  /// Kalemin fiyat sembolü; fonun kodu henüz çözülmediyse `null`.
  String? _fiyatSembolu(EkstreTutarKalemi k) {
    if (k.tur != EkstreTutarTuru.fon) return k.fiyatSembolu;
    final kod = adKodlari[fonAdiAnahtari(k.ad)];
    return kod == null ? null : '$tefasOneki$kod';
  }

  /// Adet ve birim fiyat (fiyatın kendi parasında). Tutarın parası fiyatın
  /// parasından farklıysa belge gününün kurlarıyla çevrilir (TL tutarlı
  /// ABD hissesi, dolar tutarlı altın). Eksik fiyat ya da kur → `null`.
  ({double adet, double fiyat})? _tutarDegeri(EkstreTutarKalemi k) {
    final fs = _fiyatSembolu(k);
    final fiyat = fs == null ? null : tutarFiyatlari[fs];
    if (fiyat == null || fiyat <= 0) return null;
    // Döviz hesabı kendi parasıyla yazılmışsa adet tutarın kendisidir.
    if (k.tur == EkstreTutarTuru.doviz && k.para == k.sembol) {
      return (adet: k.tutar, fiyat: fiyat);
    }
    if (k.para == k.fiyatPara) {
      return (adet: tutardanAdet(k.tutar, fiyat), fiyat: fiyat);
    }
    double? kur(String para) {
      final s = kurSembolu(para);
      return s == null ? 1.0 : tutarFiyatlari[s];
    }
    final tutarKuru = kur(k.para), fiyatKuru = kur(k.fiyatPara);
    if (tutarKuru == null || fiyatKuru == null) return null;
    final tutar = k.tutar * tutarKuru / fiyatKuru;
    return (adet: tutardanAdet(tutar, fiyat), fiyat: fiyat);
  }

  /// Belge gününün fiyatı istenecek semboller (kurlar dahil, tekil).
  List<String> get istenecekFiyatlar => {
        for (final k in tutarKalemleri)
          if (_fiyatSembolu(k) case final String s) ...[
            s,
            if (k.para != k.fiyatPara &&
                !(k.tur == EkstreTutarTuru.doviz && k.para == k.sembol)) ...[
              if (kurSembolu(k.para) case final String x) x,
              if (kurSembolu(k.fiyatPara) case final String x) x,
            ],
          ],
      }.toList();

  /// Tanınmış (fonsa kodu bulunmuş) ama belge gününün fiyatı ya da kuru
  /// alınamamış kalemlerin adları.
  List<String> get fiyatiAlinamayanlar => [
        for (final k in tutarKalemleri)
          if (_fiyatSembolu(k) != null && _tutarDegeri(k) == null)
            k.ad.split('---').first.trim(),
      ];

  /// Belge günündeki fiyatlarla kopya (saf; fiyatlar ağdan çağıranda gelir).
  EkstreOkumaSonucu fiyatlarla(Map<String, double> fiyatlar) =>
      _kopya(tutarFiyatlari: fiyatlar);

  /// Koda çözülmesi gereken fon adları (tekil, belge sırasıyla).
  List<String> get cozulecekFonAdlari => {
        for (final a in _secilen) ...a.fonAdlari,
        for (final k in tutarKalemleri)
          if (k.tur == EkstreTutarTuru.fon) k.ad,
      }.toList();

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
    return _kopya(adKodlari: kodlar, fonListesi: fonlar.toList());
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

  /// AI sütun eşlemesini uygular (`ekstre-esle` yanıtı). Tablo numarası
  /// iskeletteki gibi 1'den; satır/sütun numaraları ham tablonun.
  /// İçerik kapısını geçemeyen eşleme düşer ([tabloyuRollerleAnla]); hiçbiri
  /// geçmezse `null` — ekran eski eşlemeyle kalır.
  ///
  /// [sablondan] (metin yolu, 0147): eşleme modelden değil sunucunun banka
  /// şablonu hafızasından geldi. Banka aynı başlıkla düzeni değiştirmiş
  /// olabilir (yasin 2026-10-13: "banka şablonları da değişebilir"), bu
  /// yüzden daha sıkı: tek bir tablo bile kapıdan ya da adet × fiyat ≈ tutar
  /// sağlamasından ([eslemeSaglamasi]) geçmezse `null` — ekran şablonsuz
  /// yeniden sorar, sunucu şablonun hata sayacını artırır.
  EkstreOkumaSonucu? aiEslemesiyle(
    List<Map<String, dynamic>> yanit, {
    bool sablondan = false,
  }) {
    final yeni = <EkstreAnlami>[];
    for (final x in yanit) {
      final t = x['tablo'], b = x['baslik_satiri'], r = x['roller'];
      if (t is! int || t < 1 || t > tablolar.length || r is! Map) {
        if (sablondan) return null;
        continue;
      }
      final roller = <EkstreRol, int>{
        for (final rol in EkstreRol.values)
          if (r[rol.aiAdi] case final int c) rol: c,
      };
      final a = tabloyuRollerleAnla(
          tablolar[t - 1], b is int ? b : -1, roller);
      if (sablondan && (a == null || !eslemeSaglamasi(a))) return null;
      if (a != null) yeni.add(a);
    }
    if (yeni.isEmpty) return null;
    yeni.sort((a, b) => b.veri.length.compareTo(a.veri.length));
    return _kopya(anlamlar: yeni, aiOnerisi: true);
  }

  EkstreOkumaSonucu _kopya({
    List<EkstreAnlami>? anlamlar,
    Map<String, String>? adKodlari,
    List<({String kod, String unvan})>? fonListesi,
    bool? aiOnerisi,
    Map<String, double>? tutarFiyatlari,
  }) =>
      EkstreOkumaSonucu(
        bicim: bicim,
        anlamlar: anlamlar ?? this.anlamlar,
        mevduatlar: mevduatlar,
        notlar: notlar,
        belgeTarihi: belgeTarihi,
        kurum: kurum,
        adKodlari: adKodlari ?? this.adKodlari,
        fonListesi: fonListesi ?? this.fonListesi,
        tablolar: tablolar,
        hareketler: hareketler,
        aiOnerisi: aiOnerisi ?? this.aiOnerisi,
        tutarKalemleri: tutarKalemleri,
        tutarFiyatlari: tutarFiyatlari ?? this.tutarFiyatlari,
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
  final belgeTarihi = belgeTarihiBul(metin);
  // Sembollü varlık tablosu yok ama varlıklar adla ve yalnız tutarla
  // yazılmış ("Varlık Geçmişi Formu", 2026-10-15): elle eşleme adayı
  // gösterilmez — orada seçilecek adet sütunu yok, kart "Adet ← Sütun 2"
  // diye yanıltıyordu.
  final tutarKalemleri = belgeTarihi != null &&
          !anlamlar.any((a) =>
              a.roller.containsKey(EkstreRol.sembol) &&
              a.roller.containsKey(EkstreRol.adet))
      ? tutarliKalemler(tablolar)
      : const <EkstreTutarKalemi>[];
  if (tutarKalemleri.isNotEmpty) anlamlar = const [];
  if (anlamlar.isEmpty &&
      mevduat.mevduatlar.isEmpty &&
      tutarKalemleri.isEmpty) {
    // Sembol sütunu tanınmadı ama ortada bir tablo var: çıkmaz sokak yerine
    // en büyük tabloyu güven 0 ile ver — ekran "emin değiliz" der ve
    // "Sütunları düzelt" ile kullanıcı sembolü kendisi gösterir. Motor
    // uydurmaz (roller boş kalır); yalnızca elle eşlemenin yolu açık kalır.
    // Tanınmayan kurum çıktısında ilk sürüm doğrudan hata veriyordu ve
    // kullanıcının dosyayla yapabileceği hiçbir şey kalmıyordu (2026-10-02).
    anlamlar = _elleEslemeAdayi(tablolar);
  }
  if (anlamlar.isEmpty &&
      mevduat.mevduatlar.isEmpty &&
      tutarKalemleri.isEmpty) {
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
    belgeTarihi: belgeTarihi,
    kurum: bankaAdiBul(metin),
    tablolar: tablolar,
    hareketler: hareketleriBul(tablolar),
    tutarKalemleri: tutarKalemleri,
  );
}

/// Adet × fiyat ≈ tutar sağlaması (şablon eşlemesi için, 0147). Üç rol
/// birden yoksa ya da hiçbir satırda üçü de okunmuyorsa denetlenecek bir
/// şey yoktur: içerik kapısı ([tabloyuRollerleAnla]) yeterli sayılır. Varsa
/// satırların en az yarısı %2 içinde tutmalı — sütunu kaymış bir şablon
/// (adet ↔ fiyat yer değiştirmiş, araya sütun girmiş) burada düşer.
bool eslemeSaglamasi(EkstreAnlami a) {
  final ad = a.roller[EkstreRol.adet],
      fi = a.roller[EkstreRol.fiyat],
      tu = a.roller[EkstreRol.tutar];
  if (ad == null || fi == null || tu == null) return true;
  var denenen = 0, tutan = 0;
  for (final s in a.veri) {
    // Sayı stili satırdan bilinmez ("285.40" TR'de 28540): iki stilden
    // biri tutarsa satır tutar.
    var okundu = false, tuttu = false;
    for (final turkce in [true, false]) {
      final x = sayiCoz(s[ad], turkce: turkce),
          y = sayiCoz(s[fi], turkce: turkce),
          z = sayiCoz(s[tu], turkce: turkce);
      if (x == null || y == null || z == null || z == 0) continue;
      okundu = true;
      if (((x * y - z).abs() / z.abs()) <= 0.02) tuttu = true;
    }
    if (okundu) denenen++;
    if (tuttu) tutan++;
  }
  return denenen == 0 || tutan * 2 >= denenen;
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
