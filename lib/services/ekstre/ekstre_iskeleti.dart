import '../bist_hisse_katalogu.dart';
import 'ekstre_ice_aktarma.dart';
import 'tablo_anlama.dart';

/// Tanılama iskeleti — motorun okuyamadığı ekstrenin ANONİM yapısı.
///
/// ## Neden (kullanıcı, 2026-10-05)
/// "Hangi banka olduğu önemli değil, tüm banka ve aracı kurumları
/// kapsamalıyız." Motor kurum başına kod içermiyor ama her kurumun düzenini
/// önceden göremiyoruz; tanınmayan bir dosyayı düzeltmenin tek yolu
/// yapısını görmek. Belgenin kendisi kişisel ve finansal veridir (KVKK:
/// cihazdan çıkmaz, bkz. docs/EKSTRE_MOTORU.md "Belge nerede işlenir").
/// İskelet tablo düzenini korur, içeriği maskeler: kullanıcı onu kendisi
/// kopyalayıp gönderir, teşhis belge olmadan yapılır.
///
/// ## Ne kalır, ne maskelenir
/// - Kalır: tablo/satır/sütun düzeni (PDF geometrisinin nasıl böldüğü asıl
///   ipucu), başlık sözlüğündeki kelimeler, genel finans kelimeleri
///   ([_genel]), bilinen BIST kodları, döviz kodları, motorun kararı (başlık
///   satırı, roller, güven).
/// - Maskelenir: geri kalan her kelime — harf `A`/`a`, rakam `9`; noktalama
///   ve uzunluk korunur ("1.739,18" → "9.999,99", "Yasin" → "Aaaaa"). Ad,
///   TC, IBAN, adres, tutar böylece okunmaz; biçimleri (sayı stili, tarih
///   düzeni) görünür kalır.
///
/// Saf fonksiyon; ağ yok, kayıt yok. Ekranda bayrak `ekstre_tanilama`.
///
/// ## Uzunluk sınırı (2026-10-10)
/// İskelet `ekstre-esle`ye de gider ve sunucu [iskeletAzamiUzunluk]'tan
/// uzununu 400 `uzun` ile reddeder (`_shared/ekstre_esleme.ts`
/// `AZAMI_UZUNLUK`). Çok sayfalı PDF'te her sayfa ayrı tablo olduğundan
/// 60 satırlık kesim 12 sayfada ~51.000 karaktere çıkıyordu; kullanıcı
/// yalnız "şu an yapılamadı" görüyordu (TestFlight). Sığana kadar tablo
/// başına satır azaltılır — sütun tanımak için başlık + birkaç satır
/// yeter. O da yetmezse sondaki tablolar düşer; numaralar değişmez, çünkü
/// model yanıtı tablo NUMARASIYLA döner (`aiEslemesiyle`).
String ekstreIskeleti(
  EkstreOkumaSonucu sonuc, {
  int tabloBasinaSatir = 60,
  int azamiUzunluk = iskeletAzamiUzunluk,
}) {
  return _sigdir(sonuc, tabloBasinaSatir, azamiUzunluk, _iskeletIlkSatir,
      (s) => s.map(iskeletHucresi).toList());
}

/// Metin yolu (2026-10-13, bayrak `ekstre_metin_yolu`, sunucu 0147) —
/// [ekstreIskeleti] ile aynı düzen, farklı maske.
///
/// ## Neden
/// yasin'in DenizBank ekstresinde AI eşleme "0 tablo" döndü (Tokyo kaydı
/// 2026-10-13 09:05): iskelette sözlük dışı her kelime A/a olduğundan
/// model "Nominal Miktar" gibi başlıkları ve fon adlarını göremiyordu.
/// yasin: "eklenen pdf in içeriğini metin olarak apide ayıklatabilir
/// miyiz" → görsel değil METİN (görsel 5–10 kat pahalı), Haiku 5.5.
///
/// ## Ne gider
/// - Açık: kelimeler (başlıklar, varlık adları, kurum adı).
/// - Maskeli (9): TÜM rakamlar — tutar, adet, fiyat, IBAN, TCKN, hesap ve
///   müşteri no, telefon. Model sayı üretmez, değerler cihazda belgeden
///   okunur; sunucu maskesiz rakamı 400 ile reddeder.
/// - Maskeli (A/a): e-posta ve etiketli kişisel alanlar — "Sayın …",
///   "Ad Soyad: …", "Adres …" ([_kisiselEtiketler]). Etiketsiz yazılmış bir
///   ad maskelenmeyebilir; bu yüzden metin yolu yalnız açık rızayla
///   kullanılır. İlk plan Açık Rıza güncellemesi + herkese yeniden onaydı;
///   yasin (2026-10-13) rızanın işlemi isteyenden ilk kullanımda alınmasını
///   seçti (`ekstre_ai_rizalari`). Gizlilik/KVKK 1.11 (0149) bunu yazar.
String ekstreMetni(
  EkstreOkumaSonucu sonuc, {
  int tabloBasinaSatir = 60,
  int azamiUzunluk = iskeletAzamiUzunluk,
}) =>
    _sigdir(sonuc, tabloBasinaSatir, azamiUzunluk, ekstreMetniIlkSatir,
        metinSatiri);

/// Sunucudaki `METIN_ILK_SATIR` ile aynı (`ekstre_iskeleti_test`).
const ekstreMetniIlkSatir = 'sandık ekstre metni v2';
const _iskeletIlkSatir = 'sandık ekstre iskeleti v1';

String _sigdir(
  EkstreOkumaSonucu sonuc,
  int tabloBasinaSatir,
  int azamiUzunluk,
  String ilkSatir,
  List<String> Function(List<String>) maske,
) {
  String kur(int satir, int tablo) =>
      _iskeletKur(sonuc, satir, tablo, ilkSatir, maske);
  for (final satir in [tabloBasinaSatir, 40, 25, 15, 10, 6, 3]) {
    if (satir > tabloBasinaSatir) continue;
    final s = kur(satir, sonuc.tablolar.length);
    if (s.length <= azamiUzunluk) return s;
  }
  var tablo = sonuc.tablolar.length;
  var s = kur(3, tablo);
  while (s.length > azamiUzunluk && tablo > 1) {
    s = kur(3, --tablo);
  }
  return s;
}

/// Metin yolunda bir satırın maskeli hâli: rakamlar 9, e-posta ve
/// etiketli kişisel alanlar A/a.
List<String> metinSatiri(List<String> satir) {
  final hucreler = [
    for (final h in satir) h.replaceAll(RegExp(r'[\t\r\n]+'), ' '),
  ];
  final dolu = hucreler.where((h) => h.trim().isNotEmpty).length;
  final out = <String>[];
  var sonrakiniMaskele = false;
  for (final h in hucreler) {
    if (sonrakiniMaskele && h.trim().isNotEmpty) {
      sonrakiniMaskele = false;
      // Dar bir tablonun başlığı ("Adı" | "Adet" | "Tutar") künye sanılmasın:
      // yandaki hücre sütun adıysa açık kalır.
      if (!_sutunAdiMi(h)) {
        out.add(_tumunuMaskele(h));
        continue;
      }
    }
    final (hucre, etiketTek) = _etiketliHucre(h);
    out.add(hucre);
    // "Müşteri Adı" | "AHMET YILMAZ" künye satırı: değer yandaki hücrede.
    // Geniş satırda (tablo başlığı: "Fon Unvanı" | "Adet" …) uygulanmaz.
    if (etiketTek && dolu <= 4) sonrakiniMaskele = true;
  }
  return out;
}

/// Hücrenin maskeli hâli ve hücrenin yalnız bir etiketten ibaret olup
/// olmadığı.
(String, bool) _etiketliHucre(String h) {
  final kelimeler = h.split(' ');
  final norm = [for (final k in kelimeler) ekstreNormal(k)];
  for (var n = 3; n >= 1; n--) {
    if (norm.length < n) continue;
    final bas = norm.take(n).where((k) => k.isNotEmpty).join(' ');
    if (!_kisiselEtiketler.contains(bas)) continue;
    final kalan = kelimeler.skip(n).join(' ');
    if (kalan.replaceAll(RegExp(r'[\s:.\-]'), '').isEmpty) {
      return (_rakamMaskele(h), true);
    }
    // Değer aynı hücredeyse ayraç şart ("Müşteri Adı: …", "Sayın …"):
    // "Müşteri No 123" bir etiket + nitelemedir, ad değil.
    final ayracli = kelimeler[n - 1].endsWith(':') ||
        kalan.trimLeft().startsWith(':') ||
        bas == 'sayin';
    if (!ayracli) break;
    return (
      '${kelimeler.take(n).join(' ')} ${_tumunuMaskele(kalan)}',
      false,
    );
  }
  return (
    kelimeler
        .map((k) => k.contains('@') ? _tumunuMaskele(k) : _rakamMaskele(k))
        .join(' '),
    false,
  );
}

bool _sutunAdiMi(String h) {
  final kelimeler = ekstreNormal(h).split(' ').where((k) => k.isNotEmpty);
  return kelimeler.isNotEmpty &&
      kelimeler.every(
          (k) => ekstreSozlukKelimeleri.contains(k) || _genel.contains(k));
}

String _rakamMaskele(String k) =>
    k.replaceAll(RegExp(r'\p{N}', unicode: true), '9');

String _tumunuMaskele(String k) => k
    .replaceAll(RegExp(r'\p{Lu}', unicode: true), 'A')
    .replaceAll(RegExp(r'\p{Ll}', unicode: true), 'a')
    .replaceAll(RegExp(r'\p{N}', unicode: true), '9');

/// Değeri kişisel olan künye etiketleri (katlanmış, `ekstreNormal`).
/// "unvan" yok: "Fon Unvanı" varlık sütunudur.
const _kisiselEtiketler = {
  'sayin', 'ad soyad', 'adi soyadi', 'ad soyadi', 'adi', 'ad',
  'musteri adi', 'musteri adi soyadi', 'musteri unvani', 'musteri',
  'hesap sahibi', 'hesap sahibinin', 'isim', 'isim soyisim', 'soyad',
  'soyadi', 'adres', 'adresi', 'musteri adresi', 'yazisma adresi',
  'e posta', 'eposta', 'email', 'e mail',
};

/// `ekstre-esle`nin kabul ettiği en uzun iskelet. Sunucudaki
/// `AZAMI_UZUNLUK` ile aynı olmalı (`ekstre_iskeleti_test` iki dosyayı
/// karşılaştırır).
const iskeletAzamiUzunluk = 40000;

String _iskeletKur(
  EkstreOkumaSonucu sonuc,
  int tabloBasinaSatir,
  int tabloSayisi,
  String ilkSatir,
  List<String> Function(List<String>) maske,
) {
  final b = StringBuffer()
    ..writeln(ilkSatir)
    ..writeln('biçim: ${sonuc.bicim.name}')
    ..writeln('belge tarihi: ${sonuc.belgeTarihi != null ? 'var' : 'yok'}'
        ' · kurum adı: ${sonuc.kurum != null ? 'bulundu' : 'yok'}'
        ' · vadeli mevduat: ${sonuc.mevduatlar.length}');
  // Anlam satırları da tablo sayısıyla sınırlı: yüzlerce tabloda yalnız
  // bunlar sınırı aşıyordu (test "sondaki tablolar düşer").
  final anlamlar = sonuc.anlamlar.take(tabloSayisi).toList();
  if (anlamlar.length < sonuc.anlamlar.length) {
    b.writeln('sığmayan anlam: ${sonuc.anlamlar.length - anlamlar.length}');
  }
  for (final (i, a) in anlamlar.indexed) {
    final roller = [
      for (final r in EkstreRol.values)
        if (a.roller[r] case final s?) '${r.name}=$s',
    ].join(' ');
    b.writeln('anlam ${i + 1}: başlık satırı ${a.baslikSatiri}'
        ' · güven ${a.guven.toStringAsFixed(2)}'
        ' · adla ${a.adlaTanimli ? 'evet' : 'hayır'}'
        ' · veri ${a.veri.length} · atlanan ${a.atlanan}'
        ' · roller [$roller]');
  }
  if (sonuc.cozulemeyenFonlar.isNotEmpty) {
    b.writeln('tanınmayan fon: ${sonuc.cozulemeyenFonlar.length}');
  }
  if (tabloSayisi < sonuc.tablolar.length) {
    b.writeln('sığmayan tablo: ${sonuc.tablolar.length - tabloSayisi}');
  }
  for (final (i, t) in sonuc.tablolar.take(tabloSayisi).indexed) {
    final sutun = t.satirlar.fold<int>(0, (m, s) => s.length > m ? s.length : m);
    b
      ..writeln()
      ..writeln('## tablo ${i + 1} (${t.kaynak}) · '
          '${t.satirlar.length} satır × $sutun sütun');
    for (final (j, s) in t.satirlar.take(tabloBasinaSatir).indexed) {
      b.writeln('$j\t${maske(s).join('\t')}');
    }
    if (t.satirlar.length > tabloBasinaSatir) {
      b.writeln('… ${t.satirlar.length - tabloBasinaSatir} satır daha');
    }
  }
  return b.toString().trimRight();
}

/// Tek hücrenin maskeli hâli; kelime kelime karar verilir.
String iskeletHucresi(String hucre) => hucre
    .replaceAll(RegExp(r'[\t\r\n]+'), ' ')
    .split(' ')
    .map(_kelime)
    .join(' ');

String _kelime(String k) {
  if (k.isEmpty) return k;
  final cekirdek = k.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  if (cekirdek.isEmpty) return k; // yalnız noktalama: "-", "%", "/"
  if (_korunur(cekirdek)) return k;
  return k
      .replaceAll(RegExp(r'\p{Lu}', unicode: true), 'A')
      .replaceAll(RegExp(r'\p{Ll}', unicode: true), 'a')
      .replaceAll(RegExp(r'\p{N}', unicode: true), '9');
}

bool _korunur(String cekirdek) {
  // Kod yalnız büyük harfle yazılmışsa kod sayılır: "Cad." (cadde) CAD
  // (Kanada doları) değildir.
  final u = cekirdek;
  if (RegExp(r'^[A-Z]{3,6}$').hasMatch(u) &&
      (BistHisseKatalogu.instance.kodMu(u) || _dovizKodlari.contains(u))) {
    return true;
  }
  final n = ekstreNormal(cekirdek);
  return n.isNotEmpty &&
      !n.contains(RegExp(r'[0-9]')) &&
      (ekstreSozlukKelimeleri.contains(n) ||
          _genel.contains(n));
}

const _dovizKodlari = {
  'TRY', 'TL', 'USD', 'EUR', 'GBP', 'CHF', 'JPY', 'CAD', 'AUD', 'SAR', 'RUB',
  'CNY', 'NOK', 'SEK', 'DKK', 'XAU', 'XAG',
};

/// Sözlük dışında kalan ama tablo yapısını anlatan, kişisel olmayan
/// kelimeler (katlanmış). Belge türü, bölüm başlıkları, yön, birim.
const _genel = {
  'varlik', 'ekstre', 'ekstresi', 'portfoy', 'dokum', 'dokumu', 'ozet',
  'ozeti', 'hesap', 'hesabi', 'hesaplar', 'hesaplari', 'vadeli', 'vadesiz', 'mevduat',
  'yatirim', 'yatirimlar', 'fonu', 'fonlari', 'fonlar', 'hisse', 'senedi',
  'senetleri', 'tahvil', 'bono', 'eurobond', 'repo', 'altin', 'gumus', 'gram',
  'ons', 'doviz', 'kripto', 'emtia', 'varant', 'viop', 'bes', 'alis', 'satis',
  'alim', 'satim', 'al', 'sat', 'temettu', 'virman', 'kar', 'zarar', 'getiri',
  'faiz', 'oran', 'orani', 'vade', 'vadesi', 'baslangic', 'bitis', 'sonu',
  'acilis', 'kapanis', 'donem', 'itibariyle', 'itibari', 'ile', 've', 'tl',
  'try', 'toplam', 'genel', 'ara', 'net', 'brut', 'birim', 'pay', 'nominal',
  'deger', 'degeri', 'guncel', 'piyasa', 'son', 'ortalama', 'ort', 'maliyet',
  'adet', 'tutar', 'fiyat', 'tarih', 'kur', 'kuru', 'cinsi', 'tur', 'turu',
  'tipi', 'no', 'sayfa', 'musteri', 'sube', 'kodu', 'kod', 'isin', 'fon',
  'menkul', 'kiymet', 'kiymetler', 'sermaye', 'piyasasi', 'araci', 'kurum',
  'kurumu', 'banka', 'bankasi', 'tefas', 'mkk', 'bist', 'bakiye', 'bakiyesi',
  'kullanilabilir', 'bloke', 'serbest', 'degisken', 'karma', 'katilim',
  'endeks', 'yabanci', 'sektoru', 'teknoloji', 'para', 'kisa', 'borclanma',
  'araclari', 'ozel', 'sirket', 'kamu', 'dis', 'ic', 'yogun', 'sabit',
  'getirili', 'stopaj', 'komisyon', 'bsmv', 'vergi', 'masraf', 'aciklama',
  'islem', 'islemler', 'hareket', 'hareketleri', 'borc', 'alacak', 'bilgi',
};
