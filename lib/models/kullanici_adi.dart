/// Kullanıcı adı kuralları — istemci tarafı (2026-09-28).
///
/// KARAR SUNUCUDADIR (`supabase/migrations/0079_kullanici_adi.sql`,
/// `kullanici_adi_denetle`): uygunsuz söz filtresi, ayrılmış adlar ve
/// benzersizlik orada. Burada yalnızca BİÇİM tekrar edilir — kullanıcı
/// yazarken ağ beklemeden "boşluk olmaz" diyebilmek için. İki regex
/// aynı kalmalı (`kullanici_adi_test` sunucu dosyasıyla karşılaştırır).
enum KullaniciAdiSonuc {
  uygun,
  bicim,
  uygunsuz,
  ayrilmis,
  alinmis,
  bilinmiyor,
}

class KullaniciAdi {
  KullaniciAdi._();

  static const enKisa = 3;
  static const enUzun = 20;

  static final _bicim =
      RegExp(r'^[A-Za-zÇĞİÖŞÜçğıöşü][A-Za-z0-9ÇĞİÖŞÜçğıöşü._]{2,19}$');
  static final _ciftAyrac = RegExp(r'[._]{2}');
  static final _ayracSonu = RegExp(r'[._]$');

  /// Biçim uygunsa `null`, değilse [KullaniciAdiSonuc.bicim].
  static KullaniciAdiSonuc? bicimDenetle(String ad) {
    final a = ad.trim();
    if (!_bicim.hasMatch(a) ||
        _ciftAyrac.hasMatch(a) ||
        _ayracSonu.hasMatch(a)) {
      return KullaniciAdiSonuc.bicim;
    }
    return null;
  }

  /// Sunucu RPC'sinin döndürdüğü kodu çözer. Tanınmayan kod (ör.
  /// `profil_yok`) "bilinmiyor"dur — kullanıcıya genel hata gösterilir.
  static KullaniciAdiSonuc sonucCoz(Object? kod) => switch (kod) {
        'ok' => KullaniciAdiSonuc.uygun,
        'bicim' => KullaniciAdiSonuc.bicim,
        'uygunsuz' => KullaniciAdiSonuc.uygunsuz,
        'ayrilmis' => KullaniciAdiSonuc.ayrilmis,
        'alinmis' => KullaniciAdiSonuc.alinmis,
        _ => KullaniciAdiSonuc.bilinmiyor,
      };

  /// Mevcut görünen addan başlangıç önerisi: "Yasin Dirali" → "Yasin.Dirali".
  /// Biçime uymayan karakterler atılır; sonuç biçime uymazsa boş döner
  /// (Apple'ın gizli e-posta öneki gibi anlamsız bir şeyi önermek yerine).
  static String oneri(String kaynak) {
    var s = kaynak.trim().replaceAll(RegExp(r'\s+'), '.');
    s = s.replaceAll(RegExp(r'[^A-Za-z0-9ÇĞİÖŞÜçğıöşü._]'), '');
    s = s.replaceAllMapped(RegExp(r'[._]{2,}'), (m) => m[0]![0]);
    s = s.replaceFirst(RegExp(r'^[^A-Za-zÇĞİÖŞÜçğıöşü]+'), '');
    if (s.length > enUzun) s = s.substring(0, enUzun);
    s = s.replaceFirst(RegExp(r'[._]+$'), '');
    return bicimDenetle(s) == null ? s : '';
  }
}
