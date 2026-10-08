import '../../models/asset_categories.dart';
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
String ekstreIskeleti(
  EkstreOkumaSonucu sonuc, {
  int tabloBasinaSatir = 60,
}) {
  final b = StringBuffer()
    ..writeln('sandık ekstre iskeleti v1')
    ..writeln('biçim: ${sonuc.bicim.name}')
    ..writeln('belge tarihi: ${sonuc.belgeTarihi != null ? 'var' : 'yok'}'
        ' · kurum adı: ${sonuc.kurum != null ? 'bulundu' : 'yok'}'
        ' · vadeli mevduat: ${sonuc.mevduatlar.length}');
  for (final (i, a) in sonuc.anlamlar.indexed) {
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
  for (final (i, t) in sonuc.tablolar.indexed) {
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
      (bist100StocksMap.containsKey('$u.IS') || _dovizKodlari.contains(u))) {
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
