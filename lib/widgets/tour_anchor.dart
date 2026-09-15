import 'package:flutter/widgets.dart';

/// Tanıtım turunun spot ışığı düşürdüğü gerçek ekran öğeleri.
///
/// Tur (bkz. `onboarding_screen.dart`) ekranların kopyasını ÇİZMEZ; gerçek
/// ekranın üstüne karartma düşürür ve buradaki hedeflerden birini oyukla
/// açıkta bırakır. Hangi widget'ın hedef olduğunu ekranın kendisi söyler:
/// ilgili widget [TourAnchor] ile sarılır.
enum TourTarget {
  /// Alt menünün tamamı.
  altMenu,
  sekmeAna,
  sekmePortfoy,

  /// Ortadaki + tuşu.
  sekmeEkle,
  sekmePerformans,
  sekmeProfil,

  /// Ana ekran: toplam net varlık kartı.
  heroKart,

  /// Ana ekran: tutarları gizle/göster (göz).
  gizleTusu,

  /// Ana ekran: fiyatları yenile.
  yenileTusu,

  /// Portföy: "Varlıklarım | Takip Listesi" seçicisi.
  govdeSekmeleri,

  /// Varlık ekle: Hızlı Giriş (mikrofon).
  hizliGiris,

  /// Varlık ekle: Toplu ekle.
  topluEkle,

  /// Performans: dönem seçici (GÜNLÜK · 1H · 1A …).
  donemSecici,

  /// Performans: kapsam çipi (kim · hangi tür · hangi mod).
  ///
  /// 2026-09-15'e kadar `modSecici` idi ve Gerçek/Simülasyon anahtarını
  /// gösteriyordu. O anahtar artık kapsam panelinin içinde; tur da paneli
  /// açan çipi işaret ediyor.
  kapsamSecici,

  /// Ana ekran: bildirim çanı (teknik sinyaller + fiyat alarmları).
  ///
  /// 1.2.0'da eklendi — tur, uygulamanın güncel hâlini anlatmalı. Yeni
  /// kullanıcı en yeni özelliği de öğrenmeli, yalnızca eski sürümde var
  /// olanları değil.
  bildirimCani,

  /// Profil: davet kodu bölümü.
  davetKodu,

  /// Profil: Ayarlar tuşu.
  ayarlar,
}

/// Hedef kaydı — hedef adından ekrandaki dikdörtgene.
///
/// ## Neden GlobalKey değil
/// Bazı ekranlar aynı anda iki kez ağaçta olabilir (`PortfolioPerformanceScreen`
/// tam ekran grafik rotasında ikinci kez kurulur). GlobalKey iki kez
/// kullanılınca Flutter çöker. Burada hedefi bir `BuildContext` temsil eder
/// ve İLK kaydolan kazanır; ikinci kopya sessizce yok sayılır, çöküş yok.
abstract final class TourTargets {
  static final Map<TourTarget, BuildContext> _kayit = {};

  /// Kaydolmuş ve hâlâ ağaçta olan hedefin bağlamı.
  static BuildContext? context(TourTarget t) {
    final c = _kayit[t];
    if (c == null || !c.mounted) return null;
    return c;
  }

  /// Hedef şu an ağaçta mı? (Örn. "Varlık Ekle" ekranı açıldı mı?)
  static bool mounted(TourTarget t) => context(t) != null;

  /// Hedefin EKRAN koordinatlarındaki dikdörtgeni; yerleşmemişse null.
  ///
  /// Yerleşmemiş (offstage, henüz layout almamış) kutuda `localToGlobal`
  /// assert verir; null dönmek çağıranın "bekle ya da atla" demesine
  /// izin verir.
  static Rect? rect(TourTarget t) {
    final c = context(t);
    if (c == null) return null;
    final ro = c.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    final sol = ro.localToGlobal(Offset.zero);
    return sol & ro.size;
  }

  static void _kaydet(TourTarget t, BuildContext c) {
    // İlk kaydolan kazanır; eski kayıt hâlâ canlıysa dokunma.
    final eski = _kayit[t];
    if (eski != null && eski.mounted && eski != c) return;
    _kayit[t] = c;
  }

  static void _sil(TourTarget t, BuildContext c) {
    if (_kayit[t] == c) _kayit.remove(t);
  }
}

/// Bir widget'ı tur hedefi olarak işaretler.
///
/// Yerleşimi değiştirmez, tek çocuğunu olduğu gibi çizer; yalnızca kendi
/// bağlamını [TourTargets]'a kaydeder. Kullanım:
/// ```dart
/// TourAnchor(target: TourTarget.gizleTusu, child: _BalanceToggleButton())
/// ```
class TourAnchor extends StatefulWidget {
  const TourAnchor({super.key, required this.target, required this.child});

  final TourTarget target;
  final Widget child;

  @override
  State<TourAnchor> createState() => _TourAnchorState();
}

class _TourAnchorState extends State<TourAnchor> {
  @override
  void initState() {
    super.initState();
    TourTargets._kaydet(widget.target, context);
  }

  @override
  void didUpdateWidget(covariant TourAnchor old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) {
      TourTargets._sil(old.target, context);
      TourTargets._kaydet(widget.target, context);
    }
  }

  @override
  void dispose() {
    TourTargets._sil(widget.target, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
