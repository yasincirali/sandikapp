/// Kayıtta yazım hatalı e-posta için öneri (yasin 2026-11-14: "hatalı mail
/// girdiğini nasıl anlar").
///
/// Neden: biçim denetimi (`AuthService.eMailGecerliMi`) `ahmet@gmial.com`'u
/// geçerli sayar; kod o adrese gider, hiç gelmez ve kullanıcı sorunun nerede
/// olduğunu kendisi bulmak zorunda kalır. Burada yalnız ÖNERİ üretilir —
/// kayıt engellenmez, çünkü az bilinen ama gerçek bir alan adını "yanlış"
/// saymak yanlış pozitifin bedelini kullanıcıya ödetir.
///
/// Kural: alan adı bilinen bir sağlayıcıya 1 düzeltme (harf ekle/sil/değiştir
/// ya da yan yana iki harfi takas) uzaklıktaysa o önerilir; uzun alan
/// adında (≥ 8 karakter) 2 düzeltmeye kadar. Gerçek ama benzer sağlayıcılar
/// (ymail, mail.com, gmx…) [_gecerliBilinen] listesinde: onlara öneri çıkmaz.
/// Sağlayıcı tanınmasa da son ek açık bir `.com` yazım hatasıysa (`.con`,
/// `.cmo`…) yalnız son ek düzeltilir. `.co` / `.om` gerçek ülke uzantısı
/// olduğundan kendi başına düzeltilmez.
library;

import '../services/auth_service.dart';

/// Önerilebilen hedefler: Türkiye'de en çok görülen sağlayıcılar.
const _hedefler = <String>[
  'gmail.com',
  'hotmail.com',
  'hotmail.com.tr',
  'outlook.com',
  'outlook.com.tr',
  'live.com',
  'yahoo.com',
  'icloud.com',
  'yandex.com',
  'yandex.com.tr',
  'mynet.com',
  'msn.com',
  'protonmail.com',
];

/// Gerçek alan adları: hedeflerden birine yakın olsalar da öneri çıkmaz.
const _gecerliBilinen = <String>{
  'ymail.com', 'mail.com', 'email.com', 'gmx.com', 'gmx.de', 'gmx.net',
  'aol.com', 'mail.ru', 'me.com', 'mac.com', 'googlemail.com', 'proton.me',
  'pm.me', 'yandex.ru', 'ya.ru', 'windowslive.com', 'yahoo.com.tr',
  'yahoo.co.uk', 'hotmail.co.uk', 'hotmail.de', 'hotmail.fr', 'hotmail.it',
  'outlook.de', 'outlook.fr', 'live.co.uk', 'live.de', 'live.fr',
  'superonline.com', 'ttmail.com', 'turk.net', 'yahoo.de', 'yahoo.fr',
  'rocketmail.com', 'zoho.com', 'tutanota.com', 'hey.com', 'fastmail.com',
};

/// Son ekin açık yazım hataları → doğrusu.
const _sonEkDuzeltme = <String, String>{
  'con': 'com',
  'cmo': 'com',
  'cpm': 'com',
  'vom': 'com',
  'xom': 'com',
  'cim': 'com',
  'comm': 'com',
  'coom': 'com',
  'ocm': 'com',
  'comtr': 'com.tr',
};

/// [eposta] için düzeltilmiş adres önerisi; öneri yoksa null.
/// Yerel kısım (@ öncesi) olduğu gibi korunur; alan adı küçük harfe iner.
String? ePostaYazimOnerisi(String eposta) {
  final v = eposta.trim();
  final at = v.lastIndexOf('@');
  if (at <= 0 || at == v.length - 1) return null;
  final yerel = v.substring(0, at);
  final alan = v.substring(at + 1).toLowerCase();
  if (_hedefler.contains(alan) || _gecerliBilinen.contains(alan)) return null;

  // Önce son ek: "gmial.con" gibi çift hatada sağlayıcı eşleşmesi son ek
  // düzeldikten sonra daha kısa mesafede bulunur.
  final nokta = alan.lastIndexOf('.');
  var aday = alan;
  if (nokta > 0) {
    final ek = alan.substring(nokta + 1);
    final dogru = _sonEkDuzeltme[ek];
    if (dogru != null) aday = '${alan.substring(0, nokta)}.$dogru';
  }
  if (_hedefler.contains(aday) || _gecerliBilinen.contains(aday)) {
    return aday == alan ? null : '$yerel@$aday';
  }

  String? enIyi;
  var enKisa = 1 << 30;
  for (final h in _hedefler) {
    final d = _osaMesafe(aday, h);
    if (d < enKisa) {
      enKisa = d;
      enIyi = h;
    }
  }
  final sinir = aday.length >= 8 ? 2 : 1;
  if (enIyi != null && enKisa >= 1 && enKisa <= sinir) {
    return '$yerel@$enIyi';
  }
  // Sağlayıcı tanınmadı ama son ek düzeldiyse (ör. "sirket.con").
  return aday == alan ? null : '$yerel@$aday';
}

/// Optimal string alignment mesafesi: ekle/sil/değiştir + yan yana takas
/// (gmial → gmail = 1). Levenshtein takası 2 sayar ve "hotmial"i kaçırırdı.
int _osaMesafe(String a, String b) {
  final n = a.length, m = b.length;
  final d = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final maliyet = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = [
        d[i - 1][j] + 1,
        d[i][j - 1] + 1,
        d[i - 1][j - 1] + maliyet,
      ].reduce((x, y) => x < y ? x : y);
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1]) {
        final t = d[i - 2][j - 2] + 1;
        if (t < v) v = t;
      }
      d[i][j] = v;
    }
  }
  return d[n][m];
}

/// Yalnız biçimce geçerli adreste öneri: yarım yazılmış adres ("ahmet@gm")
/// öneri üretmez, ekran tek çağrıyla karar verir.
String? ePostaYazimOnerisiGecerliyse(String eposta) =>
    AuthService.eMailGecerliMi(eposta) ? ePostaYazimOnerisi(eposta) : null;

/// Sunucu kapısının (0185 `hook_before_user_created`) reddettiği alan
/// adları — birebir aynı liste (`eposta_sunucu_kapisi_parite_test` kilitli).
/// Bunlar "belki" değil kesin hata: kayıt ekranı alanı kırmızı yapar ve
/// sunucuya gitmeden durur (yasin 2026-11-14: "ilerlediğinde direkt inline
/// textfield'ı kızartsak"). Benzerlik tahmini ([ePostaYazimOnerisi]) yalnız
/// öneri olarak kalır; gerçek ama az bilinen alan adını engellemesin.
const kesinYazimHatalari = <String, String>{
  'gmial.com': 'gmail.com',
  'gmai.com': 'gmail.com',
  'gmal.com': 'gmail.com',
  'gamil.com': 'gmail.com',
  'gnail.com': 'gmail.com',
  'gmaill.com': 'gmail.com',
  'gmali.com': 'gmail.com',
  'gmil.com': 'gmail.com',
  'gmail.co': 'gmail.com',
  'gmail.cm': 'gmail.com',
  'gmail.om': 'gmail.com',
  'hotmial.com': 'hotmail.com',
  'hotmai.com': 'hotmail.com',
  'hotmal.com': 'hotmail.com',
  'hotamil.com': 'hotmail.com',
  'hotmil.com': 'hotmail.com',
  'hotmail.co': 'hotmail.com',
  'hotmail.cm': 'hotmail.com',
  'hotmail.com.t': 'hotmail.com.tr',
  'hotmial.com.tr': 'hotmail.com.tr',
  'outlok.com': 'outlook.com',
  'outllok.com': 'outlook.com',
  'otlook.com': 'outlook.com',
  'outlook.co': 'outlook.com',
  'yahooo.com': 'yahoo.com',
  'yaho.com': 'yahoo.com',
  'iclod.com': 'icloud.com',
  'icoud.com': 'icloud.com',
  'icloud.co': 'icloud.com',
  'icloud.cm': 'icloud.com',
};

/// Sunucunun reddettiği son ekler (`.con` …) — 0185 ile aynı.
const kesinHataliSonEkler = <String>{
  'con', 'cmo', 'cpm', 'vom', 'xom', 'cim', 'comm', 'coom', 'ocm',
};

/// Adres sunucu kapısına takılacaksa düzeltilmiş adres; değilse null.
/// 0185'teki karar sırasının aynısı: önce harita, sonra son ek (son ek
/// düzelince haritaya bir daha bakılır: gmial.con → gmail.com).
String? ePostaKesinYazimHatasi(String eposta) {
  final v = eposta.trim();
  final at = v.lastIndexOf('@');
  if (at <= 0 || at == v.length - 1) return null;
  final yerel = v.substring(0, at);
  final alan = v.substring(at + 1).toLowerCase();
  var dogru = kesinYazimHatalari[alan];
  final nokta = alan.lastIndexOf('.');
  if (dogru == null && nokta > 0) {
    final ek = alan.substring(nokta + 1);
    if (kesinHataliSonEkler.contains(ek)) {
      final d = '${alan.substring(0, nokta)}.com';
      dogru = kesinYazimHatalari[d] ?? d;
    } else if (ek == 'comtr') {
      dogru = '${alan.substring(0, nokta)}.com.tr';
    }
  }
  return dogru == null ? null : '$yerel@$dogru';
}
