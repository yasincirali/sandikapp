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
