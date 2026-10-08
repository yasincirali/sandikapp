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

  /// Ana ekran, boş portföy: "Canlı fiyat vitrini" (bayrak `ilk_varlik_kolay`,
  /// 2026-10-04). Ortak yokken ₺0 kartının yerini alır; tur bu durumda
  /// `heroKart` yerine bunu anlatır.
  ilkVarlikVitrini,

  /// Ana ekran: piyasa şeridi (dolar/euro/altın/BIST 100).
  piyasaSeridi,

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

  /// Varlık ekle: tür çipleri (Hisse · Fon · … · Kripto). 2026-09-25'te
  /// kripto türüyle eklendi.
  turSecici,

  /// Performans: dönem seçici (GÜNLÜK · 1H · 1A …).
  donemSecici,

  /// Performans: kapsam çipi (kim · hangi tür · hangi mod).
  ///
  /// 2026-09-15'e kadar `modSecici` idi ve Gerçek/Simülasyon anahtarını
  /// gösteriyordu. O anahtar artık kapsam panelinin içinde; tur da paneli
  /// açan çipi işaret ediyor.
  kapsamSecici,

  /// Performans: "Zirvedeki Portföyler" kartı (tür dökümünün altında).
  /// Yarış ekranından buraya taşındı (2026-09-29); dokununca cetvel
  /// ekranı açılır. Küresel bayrak kapalıyken çizilmez; tur hedefi
  /// bulamazsa adımı atlar.
  zirveKarti,

  /// Ana ekran: "Portföy hareketleri" kabı. Satıra dokununca işlem notu
  /// sayfası açılır (2026-09-29) — dokunulabilirliği satırda görünmediği
  /// için tur anlatır. Portföy boşken kap çizilmez; adım `kosul` ile atlar.
  hareketler,

  /// Ana ekran: "Bugün" kartı (günün hareketi, hedef, yaklaşan tarihler).
  /// Portföy boşken çizilmez; tur hedefi bulamazsa adımı atlar.
  bugunKarti,

  /// Ana ekran: radar şeridi ("N varlığında bu hafta olağandışı hareket
  /// var", Balina S7-A 2026-10-05). Yalnız bayrak açık ve söylenecek hareket
  /// varken çizilir; tur hedefi bulamazsa adımı atlar.
  radarSeridi,

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
/// ve İLK kaydolan kazanır; ikinci kopya beklemede durur, çöküş yok.
///
/// ## Neden sıra (2026-10-03, Zirve adımı kartı göstermiyordu)
/// Kayıt tek yuvaydı: ikinci kopya "ilk hâlâ canlı" diye REDDEDİLİYOR, sonra
/// ilk kopya sökülünce `_sil` yuvayı boşaltıyordu. Tembel listede yeniden
/// kurulan ya da rota/yüzey geçişinde bir kare üst üste yaşayan hedef böylece
/// ağaçta olduğu hâlde "yok" görünüyor, tur metni boşluğun üstünde kalıyordu.
/// Şimdi kayıtlar sırayla tutulur: kural aynı (ilk canlı kazanır), ama ilk
/// gidince sıradaki devralır.
abstract final class TourTargets {
  static final Map<TourTarget, List<BuildContext>> _kayit = {};

  /// Kaydolmuş ve hâlâ ağaçta olan İLK hedefin bağlamı.
  static BuildContext? context(TourTarget t) {
    final liste = _kayit[t];
    if (liste == null) return null;
    for (final c in liste) {
      if (c.mounted) return c;
    }
    return null;
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
    final liste = _kayit.putIfAbsent(t, () => <BuildContext>[]);
    liste.removeWhere((e) => !e.mounted);
    if (!liste.contains(c)) liste.add(c);
  }

  static void _sil(TourTarget t, BuildContext c) {
    final liste = _kayit[t];
    if (liste == null) return;
    liste.remove(c);
    if (liste.isEmpty) _kayit.remove(t);
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
