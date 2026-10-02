import 'dart:async';

/// Anahtarlı, sınırlı, tazelik damgalı sonuç belleği + uçuşan istek
/// paylaşımı.
///
/// Performans › Özet'in seri ve yan veri belleği bunu kullanır
/// (`_OzetBellek`, titreme bulgusu 2026-10-02): aynı anahtar ikinci kez
/// açıldığında sonuç EŞZAMANLI okunur ([oku]) ve ekran iskelete düşmez;
/// arkadaki ısıtma ile ekranın kendi isteği aynı anahtara düşerse tek
/// istek atılır ([yukle]).
///
/// Saf Dart — widget'tan bağımsız test edilir (`test/sonuc_bellegi_test.dart`).
class SonucBellegi<T> {
  SonucBellegi({
    required this.tazelik,
    required this.azami,
    this.saklanir,
    DateTime Function()? saat,
  }) : _saat = saat ?? DateTime.now;

  /// Bundan eski girdi [oku] ile yine okunur ama [taze] false döner —
  /// çağıran gösterip arkada tazeler.
  final Duration tazelik;

  /// Azami girdi; üstü en az yakın zamanda YAZILANDAN atılır.
  final int azami;

  /// Sonuç saklanmaya değer mi. `false` dönen sonuç (ör. ağ yokken BOŞ
  /// seri) yine döndürülür ama belleğe yazılmaz — sonraki açılış yeniden
  /// dener, boş sonuç "veri" sayılmaz.
  final bool Function(T)? saklanir;

  final DateTime Function() _saat;
  final _girdiler = <String, ({DateTime at, T deger})>{};
  final _istekler = <String, Future<T>>{};

  T? oku(String k) => _girdiler[k]?.deger;

  bool taze(String k) {
    final at = _girdiler[k]?.at;
    return at != null && _saat().difference(at) < tazelik;
  }

  /// Aynı anahtar için uçuşan istek varsa onu döndürür, yoksa [cek]'i
  /// çağırır. Sonuç [saklanir]'dan geçerse yazılır.
  Future<T> yukle(String k, Future<T> Function() cek) {
    final ucusan = _istekler[k];
    if (ucusan != null) return ucusan;
    final f = _cek(k, cek);
    _istekler[k] = f;
    // Kayıt, istek nasıl biterse bitsin düşer. `ignore`: hata çağırana
    // [f] üzerinden ulaşır; bu yan zincir ikinci bir yakalanmamış hata
    // üretmesin.
    f.whenComplete(() {
      if (identical(_istekler[k], f)) _istekler.remove(k);
    }).ignore();
    return f;
  }

  Future<T> _cek(String k, Future<T> Function() cek) async {
    final v = await cek();
    if (saklanir?.call(v) ?? true) yaz(k, v);
    return v;
  }

  void yaz(String k, T v) {
    // Yeniden ekle: `Map` ekleme sırasını korur; silmeden yazılırsa sık
    // kullanılan girdi en eski sayılıp atılabilir
    // (`HistoryService._fetchTickerAtTier` ile aynı disiplin).
    _girdiler.remove(k);
    _girdiler[k] = (at: _saat(), deger: v);
    while (_girdiler.length > azami) {
      _girdiler.remove(_girdiler.keys.first);
    }
  }

  void sil(String k) => _girdiler.remove(k);

  void temizle() => _girdiler.clear();

  int get uzunluk => _girdiler.length;
}
