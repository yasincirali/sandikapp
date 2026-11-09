/// Türkçe-güvenli arama/eşleştirme katlaması: küçük harf + ASCII'ye indirgeme.
///
/// Neden ortak (2026-09-28, arama): "turk hava" yazan kullanıcı "Türk Hava
/// Yolları"nı, "altin" yazan "Gram Altın"ı bulamıyordu — arama
/// `toUpperCase().contains` ile yapılıyordu ve klavyesi İngilizce olan ya da
/// aceleyle yazan kullanıcı için ü/ı/ş duvar oluyordu. Aynı katlama CSV
/// başlık eşleştirmesinde zaten vardı (2026-09-23 U08); iki kopya zamanla
/// ayrışırdı, tek yer burası.
///
/// Dart'ın `toLowerCase()`'i dilden bağımsızdır; "İ"yi "i̇" (i + U+0307)
/// yapar. Tek başına İ→i / I→ı eşlemesi de yetmez: İngilizce "PRICE"
/// "prıce" olurdu. Bu yüzden iki taraf da ASCII'ye katlanır; "ALIŞ" / "alis"
/// / "Alış" aynı anahtara düşer.
String trKatla(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(_harita[ch] ?? ch);
  }
  return b.toString().toLowerCase();
}

const _harita = {
  'İ': 'i', 'I': 'i', 'ı': 'i', '̇': '',
  'Ğ': 'g', 'ğ': 'g', 'Ü': 'u', 'ü': 'u', 'Ş': 's', 'ş': 's',
  'Ö': 'o', 'ö': 'o', 'Ç': 'c', 'ç': 'c',
  'Â': 'a', 'â': 'a', 'Î': 'i', 'î': 'i', 'Û': 'u', 'û': 'u',
};

/// Dile göre büyük harf — bölüm başlıkları için.
///
/// Dart'ın `toUpperCase()`'i dilden bağımsızdır: "Hisse" → "HISSE",
/// "Döviz" → "DÖVIZ" olur; Türkçe okurda göze batar. Türkçede i→İ, ı→I
/// önce elle çevrilir; İngilizcede ("Stocks") dokunulmaz.
String buyukHarf(String s, {required bool turkce}) => turkce
    ? s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase()
    : s.toUpperCase();

/// Türkçe alfabe sırasıyla karşılaştırma — "Ada göre (A–Z)" sıralaması için.
///
/// Neden [trKatla] değil (2026-11-07, portföy ada göre sıralama): katlama
/// arama içindir, Ş'yi S'ye eşitler; sıralamada "Şişecam" "Sasa"yla
/// karışır. Neden `compareTo` değil: kod noktası sırası Ç/Ğ/İ/Ö/Ş/Ü'yü
/// Z'nin ARKASINA atar ve büyük/küçük harfi ayırır. Burada harf Türkçe
/// küçültülür (I→ı, İ→i) ve "a b c ç d e f g ğ h ı i j … ö p r s ş t u ü v
/// y z" sırasına konur; q/w/x komşusunun ardına, şapkalı harf şapkasızın
/// ardına. Rakam ve boşluk harften önce (kod noktası), başka alfabe en
/// sonda. Eşitlikte (yalnız büyük/küçük harf farkı) ham `compareTo` — sıra
/// her açılışta aynı kalsın. Dil İngilizce olsa da aynı sıra: varlık adları
/// Türkçe (THYAO, Gram Altın), İngilizce adlarda zaten fark doğmaz.
int trKarsilastir(String a, String b) {
  final ka = _siraAnahtari(a), kb = _siraAnahtari(b);
  final n = ka.length < kb.length ? ka.length : kb.length;
  for (var i = 0; i < n; i++) {
    final d = ka[i] - kb[i];
    if (d != 0) return d;
  }
  if (ka.length != kb.length) return ka.length - kb.length;
  return a.compareTo(b);
}

const _trAlfabe = 'abcçdefgğhıijklmnoöprsştuüvyz';
const _ekHarf = {'q': 'p', 'w': 'v', 'x': 'v', 'â': 'a', 'î': 'i', 'û': 'u'};

List<int> _siraAnahtari(String s) {
  final out = <int>[];
  for (final r in s.runes) {
    var ch = String.fromCharCode(r);
    if (ch == '̇') continue; // "i̇" birleşik nokta — İ'nin artığı
    ch = ch == 'I' ? 'ı' : (ch == 'İ' ? 'i' : ch.toLowerCase());
    final sira = _trAlfabe.indexOf(ch);
    if (sira >= 0) {
      out.add(1000 + sira * 10);
      continue;
    }
    final komsu = _ekHarf[ch];
    if (komsu != null) {
      // x, w'nin ardına: ikisi de v'den sonra, x bir adım daha geride.
      out.add(1000 + _trAlfabe.indexOf(komsu) * 10 + (ch == 'x' ? 6 : 3));
      continue;
    }
    out.add(r < 128 ? r : 100000 + r);
  }
  return out;
}
