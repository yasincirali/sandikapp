import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/kullanici_adi.dart';

/// Kullanıcı adı alanının anlık denetimi — kayıt formu ve ad ekranı ortak.
///
/// Neden ayrı bir sınıf (2026-09-28): benzersizlik denetimi yalnız
/// `KullaniciAdiScreen` içindeydi; kayıt formu biçime bakıp adı OTP
/// sonrasına bırakıyordu. Ad alınmışsa kullanıcı bunu kayıttan SONRA,
/// giriş kapısında öğreniyordu — "adımı verdim, neden tekrar soruyor?"
/// (kullanıcı kararı: ad veren kullanıcıya kapı gösterilmez, benzersizlik
/// formda denetlenir). Aynı gecikme/eskime mantığını iki ekrana kopyalamak
/// yerine burada toplandı; ekranlar yalnızca [durum] ve [kaydedilebilir]
/// okur.
///
/// Kurallar:
/// - Biçim anında (`KullaniciAdi.bicimDenetle`), ağ beklenmez.
/// - Biçim uygunsa sunucuya [bekleme] sonra sorulur; her tuş sayacı sıfırlar.
/// - Sunucu yanıtı yalnız O ANKİ metne aitse geçerlidir (eski yanıt yeni
///   metnin üstüne yazılmaz).
/// - [mevcutAd] (değiştirme ekranında zaten sahip olunan ad) sorulmaz ve
///   kaydedilemez: değişiklik yok.
/// - Ağ hatası sessizdir: kayıt yine sunucuya sorar, son sözü o söyler.
class KullaniciAdiDenetimi extends ChangeNotifier {
  KullaniciAdiDenetimi({
    required this.sor,
    this.mevcutAd,
    this.bekleme = const Duration(milliseconds: 450),
  });

  /// Sunucu sorusu — ekran hangi RPC'yi (oturumlu / kayıt) kullanacağını
  /// verir; test sahte fonksiyon geçer.
  final Future<KullaniciAdiSonuc> Function(String ad) sor;

  /// Zaten sahip olunan ad; boşsa yeni ad seçiliyor demektir.
  final String? mevcutAd;

  final Duration bekleme;

  Timer? _sayac;
  String _metin = '';
  KullaniciAdiSonuc? _sonuc;
  String? _sonucMetni;
  bool _soruluyor = false;

  String get metin => _metin;
  bool get soruluyor => _soruluyor;

  bool get _mevcut => mevcutAd != null && mevcutAd == _metin;

  /// Alan değişti. Boş/biçimsiz/mevcut ad için sunucuya gidilmez.
  /// [hemen]: gecikmesiz sor (açılıştaki öneri; kullanıcı yazmadı ki
  /// beklensin).
  void metinDegisti(String yeni, {bool hemen = false}) {
    _sayac?.cancel();
    _metin = yeni.trim();
    notifyListeners();
    if (_metin.isEmpty ||
        KullaniciAdi.bicimDenetle(_metin) != null ||
        _mevcut) {
      return;
    }
    // Aynı metin için yanıt zaten varsa tekrar sorma (geri silip aynı
    // adı yazınca).
    if (_sonucMetni == _metin && _sonuc != null) return;
    if (hemen) {
      hemenSor(_metin);
    } else {
      _sayac = Timer(bekleme, () => hemenSor(_metin));
    }
  }

  /// Sunucuya hemen sor (ilk açılıştaki öneri için; gecikme anlamsız).
  Future<void> hemenSor(String ad) async {
    final m = ad.trim();
    if (m.isEmpty || KullaniciAdi.bicimDenetle(m) != null) return;
    _soruluyor = true;
    notifyListeners();
    try {
      final s = await sor(m);
      if (_ayrildi || m != _metin) return;
      _sonuc = s;
      _sonucMetni = m;
    } catch (_) {
      // Anlık kontrol ağda kaldıysa sessiz: kayıt yine sunucuya sorar.
    } finally {
      if (!_ayrildi) {
        _soruluyor = false;
        notifyListeners();
      }
    }
  }

  /// Kayıt denemesinden dönen ret — sunucu son sözü söyledi, alana yazılır.
  void sonucYaz(String ad, KullaniciAdiSonuc s) {
    _sonuc = s;
    _sonucMetni = ad.trim();
    notifyListeners();
  }

  /// Alanın altındaki satırın kaynağı:
  /// - `null` → bilgi yok, kural metni gösterilir (boş alan, mevcut ad,
  ///   yanıt beklenirken);
  /// - [KullaniciAdiSonuc.bicim] → biçim hatası (anında);
  /// - [KullaniciAdiSonuc.uygun] → sunucu onayladı;
  /// - diğerleri → sunucu reddetti.
  KullaniciAdiSonuc? get durum {
    if (_metin.isEmpty) return null;
    if (KullaniciAdi.bicimDenetle(_metin) != null) {
      return KullaniciAdiSonuc.bicim;
    }
    if (_mevcut || _sonucMetni != _metin) return null;
    return _sonuc;
  }

  /// Kaydet/Devam düğmesi: biçim uygun, mevcut ad değil ve sunucu bu
  /// metne "hayır" dememiş. Yanıt henüz gelmediyse de kaydedilebilir —
  /// kayıt sunucuya sorar; formu ağ gecikmesine kilitlemek yanlış olurdu.
  bool get kaydedilebilir {
    if (_metin.isEmpty ||
        KullaniciAdi.bicimDenetle(_metin) != null ||
        _mevcut) {
      return false;
    }
    final d = durum;
    return d == null || d == KullaniciAdiSonuc.uygun;
  }

  bool _ayrildi = false;

  @override
  void dispose() {
    _ayrildi = true;
    _sayac?.cancel();
    super.dispose();
  }
}
