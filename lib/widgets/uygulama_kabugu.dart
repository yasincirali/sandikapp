import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/hesap_gecisi.dart';
import '../services/notification_service.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import 'custom_loading_indicator.dart';

/// Kök sağlayıcı kapsamı + hesap geçiş perdesi.
///
/// ## Neden kapsam baştan kurulur
/// Hesap değişince önceki hesabın HİÇBİR sağlayıcı durumu yeni hesaba
/// ulaşmamalı (gerekçe `HesapGecisi`). `ProviderScope` anahtarı
/// [HesapGecisi.nesil]'dir; artınca kapsam ve altındaki bütün ağaç
/// (MaterialApp, Navigator, `_AuthGate`) yeniden doğar.
///
/// ## Neden İKİ adımda
/// `appNavigatorKey` bir `GlobalKey`. Eski ve yeni ağaç aynı karede
/// kurulursa Flutter eski Navigator'ı (rotalarıyla) yeni ağaca TAŞIR —
/// önceki hesabın açık ekranları yeni hesapta yaşamaya devam ederdi. Önce
/// bir kare yalnız perde çizilir (eski ağaç tamamen söner), sonraki karede
/// yeni kapsam kurulur.
///
/// ## Perde ne zaman kalkar — tek yükleme
/// [hazirBekle] açıkken (uygulama) perde, yeni kapsamın ilk gerçek ekranı
/// çizilene dek kalır ([HesapGecisi.yeniEkranHazir]); açılış GIF'i perdenin
/// ARKASINDA kalır ve görünmez. Eskiden perde sabit [SandikMotion.modal]
/// sonra kalkıyor, ardından GIF veri beklerken ikinci kez yükleme
/// gösteriyordu (yasin, 2026-10-10). [_emniyet] GIF'in 10 sn'lik veri
/// supabından uzun: ağ yoksa kullanıcı perdede takılı kalmaz, ana ekran kendi
/// hata durumunu gösterir.
///
/// Bayrak kapalıyken [HesapGecisi.nesil] hiç değişmez: ağaç birebir
/// `ProviderScope(child: SandikApp())`.
class UygulamaKabugu extends StatefulWidget {
  const UygulamaKabugu({
    super.key,
    required this.uygulama,
    this.tema,
    this.hazirBekle = false,
  });

  /// Perde yeni kapsamın "hazırım" demesini bekler mi. Bunu söyleyen
  /// `_AuthGate`; onu kurmayan kök (test) için sabit kısa süre.
  final bool hazirBekle;

  static const _emniyet = Duration(seconds: 12);

  /// Kapsamın içindeki uygulama (`SandikApp`). Test başka kök verir.
  final Widget uygulama;

  /// Perdenin teması (uygulamanın gerçek teması, `SandikApp.buildTheme`).
  /// Verilmezse yalnız palet uzantısı kurulur.
  final ThemeData Function(Brightness)? tema;

  @override
  State<UygulamaKabugu> createState() => _UygulamaKabuguState();
}

class _UygulamaKabuguState extends State<UygulamaKabugu> {
  final _gecis = HesapGecisi.instance;
  late int _kurulanNesil = _gecis.nesil.value;
  bool _bosKare = false;

  @override
  void initState() {
    super.initState();
    _gecis.nesil.addListener(_nesilDegisti);
    _gecis.perde.addListener(_perdeDegisti);
    _gecis.yeniEkranHazir.addListener(_ekranHazirDegisti);
  }

  @override
  void dispose() {
    _gecis.nesil.removeListener(_nesilDegisti);
    _gecis.perde.removeListener(_perdeDegisti);
    _gecis.yeniEkranHazir.removeListener(_ekranHazirDegisti);
    _emniyetSayaci?.cancel();
    super.dispose();
  }

  Timer? _emniyetSayaci;

  void _nesilDegisti() {
    if (!mounted) return;
    // Yeni kapsam kurulmadan ÖNCE: kapı ilk build'inde bunu okur.
    if (widget.hazirBekle) _gecis.yeniEkranHazir.value = false;
    setState(() => _bosKare = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _bosKare = false;
        _kurulanNesil = _gecis.nesil.value;
      });
      if (!widget.hazirBekle) {
        _perdeyiKaldirSonra();
        return;
      }
      _emniyetSayaci?.cancel();
      _emniyetSayaci = Timer(UygulamaKabugu._emniyet, () {
        _gecis.yeniEkranHazir.value = true;
      });
    });
  }

  void _ekranHazirDegisti() {
    if (!_gecis.yeniEkranHazir.value) return;
    _emniyetSayaci?.cancel();
    _emniyetSayaci = null;
    if (_gecis.perde.value != null) _perdeyiKaldirSonra();
  }

  /// Perde kısa bir an daha kalır: kapının splash → ekran geçişi
  /// (`AnimatedSwitcher`) perdenin arkasında biter, kullanıcı GIF'in
  /// sönüşünü görmez; geçiş tek hareket gibi okunur.
  void _perdeyiKaldirSonra() {
    Future<void>.delayed(SandikMotion.modal, () {
      _gecis.perdeyiKaldir();
      final bildirim = _gecis.bekleyenBildirim;
      if (bildirim == null) return;
      _gecis.bekleyenBildirim = null;
      // Soğuk açılış yolu: navigator hazır olana dek bekler.
      NotificationService.instance
          .handleRemoteMessageData(bildirim, fromColdStart: true);
    });
  }

  /// Ekranda tutulan perde. [HesapGecisi.perde] boşalınca da kapanış
  /// hareketi bitene dek burada kalır ([_kapaniyor]).
  late HesapGecisPerdesi? _gosterilen = _gecis.perde.value;
  bool _kapaniyor = false;

  /// Geçiş hareketi (`goz_alici`, 2026-10-10). Kapalıyken perde eskisi
  /// gibi sert girer/çıkar — bayrak kapalı = bugünkü davranış birebir.
  bool get _hareketli => RemoteConfigService.instance.gozAlici;

  void _perdeDegisti() {
    if (!mounted) return;
    final yeni = _gecis.perde.value;
    setState(() {
      if (yeni == null && _gosterilen != null && _hareketli) {
        _kapaniyor = true;
      } else {
        _gosterilen = yeni;
        _kapaniyor = false;
      }
    });
  }

  void _kapandi() {
    if (!mounted || _gecis.perde.value != null) return;
    setState(() {
      _gosterilen = null;
      _kapaniyor = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final perde = _gosterilen;
    final hareketli = _hareketli;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          if (!_bosKare)
            ProviderScope(
              key: ValueKey(_kurulanNesil),
              child: widget.uygulama,
            ),
          if (perde != null || _bosKare)
            Positioned.fill(
              key: const ValueKey('hesap-perdesi'),
              child: HesapGecisPerdesiGorunumu(
                perde: perde,
                tema: widget.tema,
                hareketli: hareketli,
                kapaniyor: _kapaniyor,
                onKapandi: _kapandi,
              ),
            ),
        ],
      ),
    );
  }
}

/// Geçiş perdesi — uygulamanın temasının DIŞINDA çizilir (kapsam o an
/// yeniden kuruluyor), bu yüzden kendi temasını cihaz parlaklığından kurar.
///
/// ## Hareket ([hareketli], bayrak `goz_alici`; yasin 2026-10-10: "geçiş
/// animasyonu üstüne biraz düşünülmesi gerek")
/// Amaç SÜS değil, "hangi hesaba gidiyorum" sorusunu cevaplamak (mekânsal
/// süreklilik): dokunulan avatar seçicideki yerinden kalkıp ortaya taşınır,
/// rengi aynı kalır; ad onun altında belirir. Instagram'ın hesap geçişiyle
/// aynı okuma.
/// - Giriş [SandikMotion.modal] (320 ms): zemin ilk %60'ta [SandikMotion.enter]
///   ile solar; avatar [SandikMotion.cekmece] (iOS sheet eğrisi) ile taşınır;
///   ad ve alt satır %40'tan sonra 8 pt aşağıdan gelir (küçük kademe, hepsi
///   aynı anda girmesin).
/// - Gösterge [_gostergeGecikmesi] (~640 ms) sonra belirir: hızlı geçişte hiç
///   görünmez, yükleme yanıp sönmez. Yavaşsa "bekliyorum" der.
/// - Çıkış [SandikMotion.surface] (240 ms): perde solar, avatar %4 büyüyerek
///   "içine girilen" hissini verir; altında yeni hesabın dolu ekranı durur.
///   Altındaki uygulamayı ayrıca ölçeklemek bilerek yok: bütün ağacı saran
///   bir dönüşüm, kapsam kimliğine dokunmadan eklenemiyordu ve kazancı
///   perdenin solmasının yanında küçük kalıyordu.
/// - Hareketi azalt: süreler sıfır, avatar yerinde; anlık değişim.
/// Bayrak kapalıyken hiçbir hareket yok: eski sert giriş/çıkış birebir.
class HesapGecisPerdesiGorunumu extends StatefulWidget {
  const HesapGecisPerdesiGorunumu({
    super.key,
    required this.perde,
    this.tema,
    this.hareketli = false,
    this.kapaniyor = false,
    this.onKapandi,
  });

  final HesapGecisPerdesi? perde;
  final ThemeData Function(Brightness)? tema;
  final bool hareketli;
  final bool kapaniyor;
  final VoidCallback? onKapandi;

  static const double avatarCapi = 64;
  // İki modal süresi: giriş hareketi bitip bir o kadar daha beklenir.
  static final _gostergeGecikmesi = SandikMotion.modal * 2;

  @override
  State<HesapGecisPerdesiGorunumu> createState() =>
      _HesapGecisPerdesiGorunumuState();
}

class _HesapGecisPerdesiGorunumuState extends State<HesapGecisPerdesiGorunumu>
    with TickerProviderStateMixin {
  late final AnimationController _giris =
      AnimationController(vsync: this, duration: SandikMotion.modal);
  late final AnimationController _cikis =
      AnimationController(vsync: this, duration: SandikMotion.surface);
  final _avatarAnahtari = GlobalKey();

  /// Avatarın hedef yerinden kaynağa uzaklığı ve ölçeği (ölçülünce dolar).
  Offset _fark = Offset.zero;
  double _olcek = 1;
  bool _olculdu = false;
  bool _gosterge = false;
  Timer? _gostergeSayaci;

  @override
  void initState() {
    super.initState();
    if (!widget.hareketli) {
      _giris.value = 1;
      _olculdu = true;
      _gosterge = true;
      return;
    }
    _gostergeSayaci = Timer(HesapGecisPerdesiGorunumu._gostergeGecikmesi,
        () => mounted ? setState(() => _gosterge = true) : null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _baslat());
  }

  void _baslat() {
    if (!mounted) return;
    final azalt = _azalt;
    final kaynak = widget.perde?.kaynak;
    final kutu = _avatarAnahtari.currentContext?.findRenderObject();
    if (!azalt && kaynak != null && kutu is RenderBox && kutu.hasSize) {
      final hedef = kutu.localToGlobal(Offset.zero) & kutu.size;
      _fark = kaynak.center - hedef.center;
      _olcek = kaynak.width / hedef.width;
    }
    setState(() => _olculdu = true);
    if (azalt) {
      _giris.value = 1;
    } else {
      _giris.forward();
    }
  }

  @override
  void didUpdateWidget(HesapGecisPerdesiGorunumu eski) {
    super.didUpdateWidget(eski);
    if (widget.kapaniyor && !eski.kapaniyor) {
      final azalt = _azalt;
      if (azalt) {
        // didUpdateWidget build içinde: ebeveyn kare sonunda güncellenir.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => widget.onKapandi?.call());
      } else {
        _cikis.forward(from: 0).whenComplete(() => widget.onKapandi?.call());
      }
    } else if (!widget.kapaniyor && eski.kapaniyor) {
      // Kapanırken yeni bir geçiş başladı: perde geri gelir.
      _cikis.value = 0;
    }
  }

  @override
  void dispose() {
    _gostergeSayaci?.cancel();
    _giris.dispose();
    _cikis.dispose();
    super.dispose();
  }

  /// Perde uygulamanın MediaQuery'sinin ÜSTÜNDE yaşar; ayar görünümden okunur.
  bool get _azalt =>
      MediaQueryData.fromView(View.of(context)).disableAnimations;

  static double _aralik(double t, double bas, double son, Curve egri) =>
      egri.transform(((t - bas) / (son - bas)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return MediaQuery.fromView(
      view: View.of(context),
      child: Builder(builder: (context) {
        final parlaklik = MediaQuery.platformBrightnessOf(context);
        final kur = widget.tema;
        final data = kur != null
            ? kur(parlaklik)
            : ThemeData(brightness: parlaklik, extensions: [
                parlaklik == Brightness.dark
                    ? SandikPalette.dark
                    : SandikPalette.light,
              ]);
        return Theme(
          data: data,
          child: Builder(builder: (context) {
            final p = widget.perde;
            final gosterge = AnimatedOpacity(
              opacity: _gosterge ? 1 : 0,
              duration: SandikMotion.stateOf(context),
              curve: SandikMotion.enter,
              child: const CustomLoadingIndicator(
                  size: CustomLoadingIndicator.small),
            );
            return Semantics(
              liveRegion: true,
              label: p == null ? 'Yükleniyor' : '${p.ad} ${p.alt}',
              child: AnimatedBuilder(
                animation: Listenable.merge([_giris, _cikis]),
                builder: (context, _) {
                  final t = _giris.value;
                  final c = SandikMotion.enter.transform(_cikis.value);
                  final zemin = _aralik(t, 0, 0.6, SandikMotion.enter);
                  final tasi = _aralik(t, 0, 1, SandikMotion.cekmece);
                  final yazi = _aralik(t, 0.4, 1, SandikMotion.enter);
                  final kaynakYok = widget.perde?.kaynak == null;
                  // Zemin solarak gelir; avatar SOLMAZ (seçicideki yerinden
                  // "kalkar"). Çıkışta hepsi birlikte solar.
                  return Opacity(
                    opacity: 1 - c,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Opacity(
                          opacity: zemin,
                          child: ColoredBox(color: context.c.background),
                        ),
                        Center(
                          // Perde yokken (boş kare) yalnız gösterge.
                          child: p == null
                              ? gosterge
                              : Padding(
                                  padding: const EdgeInsets.all(SandikSpace.xl),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Opacity(
                                        opacity: !_olculdu
                                            ? 0
                                            : kaynakYok
                                                ? zemin
                                                : 1,
                                        child: Transform.translate(
                                          offset: _fark * (1 - tasi),
                                          child: Transform.scale(
                                            scale:
                                                (_olcek + (1 - _olcek) * tasi) *
                                                    (kaynakYok
                                                        ? 0.92 + 0.08 * tasi
                                                        : 1) *
                                                    (1 + 0.04 * c),
                                            child: HesapAvatari(
                                                key: _avatarAnahtari,
                                                harf: p.basHarf,
                                                ton: p.ton,
                                                cap: HesapGecisPerdesiGorunumu
                                                    .avatarCapi),
                                          ),
                                        ),
                                      ),
                                      Opacity(
                                        opacity: yazi,
                                        child: Transform.translate(
                                          offset: Offset(
                                              0, SandikSpace.sm * (1 - yazi)),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SizedBox(
                                                  height: SandikSpace.md),
                                              Text(
                                                p.ad,
                                                textAlign: TextAlign.center,
                                                style: context.t.titleLarge
                                                    ?.copyWith(
                                                        color:
                                                            context.c.text90),
                                              ),
                                              const SizedBox(
                                                  height: SandikSpace.xs),
                                              Text(
                                                p.alt,
                                                textAlign: TextAlign.center,
                                                style: context.t.bodyMedium
                                                    ?.copyWith(
                                                        color:
                                                            context.c.text58),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: SandikSpace.lg),
                                      gosterge,
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          }),
        );
      }),
    );
  }
}

/// Hesabın baş harfli yuvarlak avatarı. Renk hesap kimliğinden değil
/// sıradan gelir ki aynı listede iki hesap aynı tonda olmasın; perde ve
/// seçici aynı bileşeni kullanır.
class HesapAvatari extends StatelessWidget {
  const HesapAvatari({
    super.key,
    required this.harf,
    this.cap = 40,
    this.ton = 0,
    this.soluk = false,
  });

  final String harf;
  final double cap;
  final int ton;
  final bool soluk;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final zemin = switch (ton % 3) {
      0 => c.amberFill,
      1 => c.gain,
      _ => c.info,
    };
    return ExcludeSemantics(
      child: Opacity(
        opacity: soluk ? 0.5 : 1,
        child: Container(
          width: cap,
          height: cap,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: zemin, shape: BoxShape.circle),
          child: Text(
            harf,
            style: context.t.titleMedium
                ?.copyWith(
                  color: ton % 3 == 0 ? c.onAmber : c.onStatus,
                  fontWeight: FontWeight.w700,
                )
                .apply(fontSizeFactor: cap / 40),
          ),
        ),
      ),
    );
  }
}
