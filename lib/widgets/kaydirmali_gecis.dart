// Kaydırmalı geçiş — toplam kartında Ben / ortak / Birlikte arasında.
//
// 2026-09-21: kaydırma hareketi işe yarıyordu ama görünmezdi — kart yerinde
// durup içerik bir anda değişince "ne oldu?" sorusu doğuyordu (kullanıcı).
// İkinci tur (aynı gün): "kaydırırken diğer kartın başlangıcını göreyim" —
// kenar rozeti yerine KOMŞU KARTIN KENDİSİ görünür (carousel):
//   1. Sürüklerken mevcut kart parmağı 1:1 izler; komşu görünümün kartı
//      (Ayşe'nin toplamı, kendi çipiyle) aynı hizada yandan kayar. Kartın
//      kutusu kırpılır: pencere sabit, içerik kayar — ekran kenarındaki
//      boşluğa taşmaz.
//   2. Eşiği geçip bırakınca kayma kart genişliğini tamamlar, sonra
//      görünüm değişir ve yeni kart sıfır konumuna oturur (zıplama yok:
//      tamamlanan kayma ile yeni içerik aynı karede yer değiştirir).
//   3. Eşiği geçmeden bırakınca kart yerine yaylanır — iptal.
// "Hareketi azalt" açıkken bırakma animasyonları sıfır sürelidir; parmak
// sürüklemesi kullanıcı hareketidir, olduğu gibi kalır (HIG).
//
// ## Pürüzsüzlük (üçüncü tur, 2026-09-21)
// Kullanıcı: "kartın slide'ı pürüzsüz kaymalı, kalite algısı için kritik."
// İlk sürümde her sürükleme karesi `setState` ile bu State'in tamamını
// yeniden kuruyordu: [komsu] her karede yeniden ÇAĞRILIYOR (ana ekran orada
// komşu görünümün toplamını baştan hesaplıyor), kart ve komşu her karede
// yeniden BOYANIYORDU. Şimdi:
//   · kayma bir `ValueNotifier`'da; yalnızca kart penceresi ve sayfa
//     noktaları yeniden kurulur, State'in `build`'i çalışmaz;
//   · komşu kart yön başına BİR KEZ kurulup önbelleğe alınır (üst widget
//     güncellenince düşer);
//   · kart ve komşu `RepaintBoundary` içindedir — `Transform.translate`
//     kompozitörde yalnızca katmanı öteler, piksel yeniden çizilmez.
//
// Bu widget görünümün NE olduğunu bilmez: [onGecis] ile yön bildirir,
// [komsu] ile "o yöndeki kart"ı ister. Böylece ana ekranın kimlik
// sözleşmesine ('' / id / null) bağlanmaz ve tek başına test edilir.
import 'package:flutter/material.dart';

import '../theme/sandik.dart';

class KaydirmaliGecis extends StatefulWidget {
  const KaydirmaliGecis({
    super.key,
    required this.etkin,
    required this.onGecis,
    required this.komsu,
    required this.child,
    this.altBilgi,
    this.ipucu = false,
    this.onIpucuGosterildi,
  });

  /// Kartın altına çizilen satır (sayfa noktaları); [ilerleme] sürükleme
  /// oranıdır (−1..1). Yalnızca bu sarmalayıcı yeniden kurulur — her
  /// sürükleme karesinde ana ekranın tamamı build edilmez.
  final Widget Function(BuildContext context, double ilerleme)? altBilgi;

  /// Ortak yoksa hareket kapalı: kart sürüklenmez, jest tüketilmez.
  final bool etkin;

  /// `ileri`: sola kaydırma (sıradakine), değilse sağa (öncekine).
  final ValueChanged<bool> onGecis;

  /// O yöndeki görünümün kartı — sürüklerken yanda görünür. Etkileşimsiz
  /// çizilir (`IgnorePointer`); geçiş tamamlanınca gerçek kart gelir.
  /// Sürükleme boyunca yön başına BİR KEZ çağrılır (önbellek).
  final Widget Function(bool ileri) komsu;

  final Widget child;

  /// Tek seferlik "göz kırpma": ilk açılışta kart hafifçe sola kayıp geri
  /// gelir, o an komşu kartın kenarı görünür. Jestin var olduğunu kart
  /// kendisi söyler; tur metni ve alt sayfa notu okunup unutuluyordu.
  /// Gösterildiğini [onIpucuGosterildi] ile işaretler (tercih).
  final bool ipucu;
  final VoidCallback? onIpucuGosterildi;

  /// Göz kırpma mesafesi (pt) — komşu kartın kenarı okunacak kadar.
  static const double ipucuKayma = 28;

  /// Geçiş eşiği: kart genişliğinin bu oranı kadar sürüklenmiş ya da
  /// [esikHiz]'den hızlı fırlatılmış.
  static const double esikOran = 0.3;
  static const double esikHiz = 400;

  /// İki kart arasındaki boşluk (pt).
  static const double aralik = SandikSpace.smd;

  @override
  State<KaydirmaliGecis> createState() => _KaydirmaliGecisState();
}

class _KaydirmaliGecisState extends State<KaydirmaliGecis>
    with SingleTickerProviderStateMixin {
  // `late final` ile tembel kurulmaz: hiç sürüklenmeden dispose edilirse
  // ilk erişim dispose içinde olur ve Ticker, ayrılmış ağaçta ata arar
  // ("Looking up a deactivated widget's ancestor") — taşma testinde yaşandı.
  late final AnimationController _yay;

  /// Kayma (pt). Notifier olması pürüzsüzlüğün özü: her sürükleme karesinde
  /// yalnızca dinleyen iki sarmalayıcı (kart penceresi, sayfa noktaları)
  /// yeniden kurulur; bu State'in `build`'i ve [KaydirmaliGecis.komsu]
  /// çalışmaz.
  final _dx = ValueNotifier<double>(0);

  /// Son ölçülen kart genişliği — bırakma anında eşik ve tam kayma için.
  double _genislik = 0;

  /// Komşu kart önbelleği — yön başına bir kez kurulur. Üst widget
  /// güncellenince (fiyat tazeleme, görünüm değişimi) düşer; sürükleme
  /// sırasında yön değişirse yeniden kurulur.
  Widget? _komsuWidget;
  bool? _komsuYon;

  @override
  void initState() {
    super.initState();
    _yay = AnimationController(vsync: this);
    if (widget.ipucu && widget.etkin) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _gozKirp());
    }
  }

  @override
  void didUpdateWidget(KaydirmaliGecis oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Üst widget yeniden kuruldu: komşu kartın verisi değişmiş olabilir.
    _komsuWidget = null;
    _komsuYon = null;
  }

  @override
  void dispose() {
    _yay.dispose();
    _dx.dispose();
    super.dispose();
  }

  /// [bas] → [son] arası kaymayı [sure] boyunca oynatır; süre sıfırsa
  /// (hareketi azalt) doğrudan [son]a atlar.
  Future<void> _kaydir(
      double bas, double son, Duration sure, Curve egriTuru) async {
    if (sure == Duration.zero) {
      if (mounted) _dx.value = son;
      return;
    }
    _yay
      ..duration = sure
      ..reset();
    final egri = CurvedAnimation(parent: _yay, curve: egriTuru);
    void tik() => _dx.value = bas + (son - bas) * egri.value;
    egri.addListener(tik);
    await _yay.forward();
    egri.removeListener(tik);
    egri.dispose();
    if (mounted) _dx.value = son;
  }

  /// Tek seferlik ipucu: ekran otursun, sola kay, komşu okunsun, geri gel.
  /// Kullanıcı bu sırada dokunursa `_surukle` denetleyiciyi durdurur ve
  /// hareket parmağa geçer. Hareketi azalt açıkken hiç oynamaz; tercih
  /// yine işaretlenir ki her açılışta denenmesin.
  Future<void> _gozKirp() async {
    if (!mounted) return;
    widget.onIpucuGosterildi?.call();
    final sure = SandikMotion.surfaceOf(context);
    if (sure == Duration.zero) return;
    await Future<void>.delayed(sure * 3);
    if (!mounted || _dx.value != 0 || _yay.isAnimating) return;
    await _kaydir(0, -KaydirmaliGecis.ipucuKayma, sure, SandikMotion.enter);
    await Future<void>.delayed(sure * 2);
    if (!mounted || _dx.value != -KaydirmaliGecis.ipucuKayma) return;
    await _kaydir(-KaydirmaliGecis.ipucuKayma, 0, sure, SandikMotion.move);
  }

  void _surukle(DragUpdateDetails d) {
    if (_yay.isAnimating) _yay.stop();
    final sinir = _genislik + KaydirmaliGecis.aralik;
    _dx.value = (_dx.value + d.delta.dx).clamp(-sinir, sinir);
  }

  Future<void> _birak(DragEndDetails d) async {
    final hiz = d.primaryVelocity ?? 0;
    final dx = _dx.value;
    final ileri = dx < 0 || (dx == 0 && hiz < 0);
    final tam = _genislik + KaydirmaliGecis.aralik;
    final gecis = dx != 0 &&
        (dx.abs() >= _genislik * KaydirmaliGecis.esikOran ||
            hiz.abs() >= KaydirmaliGecis.esikHiz);
    if (gecis) {
      // Kaymayı tamamla: komşu kart pencereye tam oturur. Sonra görünüm
      // değişir ve kayma sıfırlanır — yeni gerçek kart, komşunun durduğu
      // yerde belirir; göz fark etmez.
      SandikHaptic.selection.perform();
      await _kaydir(dx, ileri ? -tam : tam, SandikMotion.surfaceOf(context),
          SandikMotion.enter);
      if (!mounted) return;
      _dx.value = 0;
      widget.onGecis(ileri);
      return;
    }
    // İptal: yerine yaylan.
    await _kaydir(dx, 0, SandikMotion.stateOf(context), SandikMotion.enter);
  }

  /// O yöndeki komşu kart — önbellekten; yoksa bir kez kurulur.
  Widget _komsu(bool ileri) {
    if (_komsuWidget == null || _komsuYon != ileri) {
      _komsuYon = ileri;
      _komsuWidget = RepaintBoundary(
        child: IgnorePointer(
          child: ExcludeSemantics(child: widget.komsu(ileri)),
        ),
      );
    }
    return _komsuWidget!;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.etkin) return widget.child;

    // Kart bir kez kurulur ve kendi katmanında yaşar; sürüklerken
    // yalnızca ötelenir.
    final kart = RepaintBoundary(child: widget.child);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _surukle,
      onHorizontalDragEnd: _birak,
      onHorizontalDragCancel: () => _dx.value = 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _kartPenceresi(kart),
          if (widget.altBilgi != null)
            Padding(
              padding: const EdgeInsets.only(top: SandikSpace.sm),
              child: Center(
                child: ValueListenableBuilder<double>(
                  valueListenable: _dx,
                  builder: (ctx, dx, _) {
                    final tam = _genislik + KaydirmaliGecis.aralik;
                    final ilerleme =
                        _genislik <= 0 ? 0.0 : (dx / tam).clamp(-1.0, 1.0);
                    return widget.altBilgi!(ctx, ilerleme);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kartPenceresi(Widget kart) => LayoutBuilder(
        builder: (context, k) {
          _genislik = k.maxWidth;
          return ValueListenableBuilder<double>(
            valueListenable: _dx,
            builder: (context, dx, _) {
              final ileri = dx < 0;
              final komsuX = ileri
                  ? dx + _genislik + KaydirmaliGecis.aralik
                  : dx - _genislik - KaydirmaliGecis.aralik;
              // Stack varsayılan olarak kırpar (Clip.hardEdge): pencere
              // kartın kutusudur, komşu yalnızca o kutunun içinde görünür.
              return Stack(
                children: [
                  Transform.translate(
                    offset: Offset(dx, 0),
                    child: kart,
                  ),
                  if (dx != 0)
                    Positioned(
                      left: komsuX,
                      top: 0,
                      width: _genislik,
                      child: _komsu(ileri),
                    ),
                ],
              );
            },
          );
        },
      );
}
