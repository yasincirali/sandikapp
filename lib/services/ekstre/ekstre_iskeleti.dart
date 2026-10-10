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
  for (final satir in [tabloBasinaSatir, 40, 25, 15, 10, 6, 3]) {
    if (satir > tabloBasinaSatir) continue;
    final s = _iskeletKur(sonuc, satir, sonuc.tablolar.length);
    if (s.length <= azamiUzunluk) return s;
  }
  var tablo = sonuc.tablolar.length;
  var s = _iskeletKur(sonuc, 3, tablo);
  while (s.length > azamiUzunluk && tablo > 1) {
    s = _iskeletKur(sonuc, 3, --tablo);
  }
  return s;
}

/// `ekstre-esle`nin kabul ettiği en uzun iskelet. Sunucudaki
/// `AZAMI_UZUNLUK` ile aynı olmalı (`ekstre_iskeleti_test` iki dosyayı
/// karşılaştırır).
const iskeletAzamiUzunluk = 40000;

String _iskeletKur(
  EkstreOkumaSonucu sonuc,
  int tabloBasinaSatir,
  int tabloSayisi,
) {
  final b = StringBuffer()
    ..writeln('sandık ekstre iskeleti v1')
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
      b.writeln('$j\t${s.map(iskeletHucresi).join('\t')}');
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
