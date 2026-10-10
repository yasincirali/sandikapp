import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/hesap_gecisi.dart';
import '../services/notification_service.dart';
import '../theme/sandik.dart';

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
/// Bayrak kapalıyken [HesapGecisi.nesil] hiç değişmez: ağaç birebir
/// `ProviderScope(child: SandikApp())`.
class UygulamaKabugu extends StatefulWidget {
  const UygulamaKabugu({super.key, required this.uygulama, this.tema});

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
    _gecis.perde.addListener(_yenile);
  }

  @override
  void dispose() {
    _gecis.nesil.removeListener(_nesilDegisti);
    _gecis.perde.removeListener(_yenile);
    super.dispose();
  }

  void _yenile() {
    if (mounted) setState(() {});
  }

  void _nesilDegisti() {
    if (!mounted) return;
    setState(() => _bosKare = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _bosKare = false;
        _kurulanNesil = _gecis.nesil.value;
      });
      // Yeni kapsam ilk karesini çizdi; açılış kendi yükleme ekranını
      // gösterir. Perde kısa bir an daha kalır ki geçiş tek hareket
      // gibi okunsun (sert bir boş kare görünmesin).
      Future<void>.delayed(SandikMotion.modal, () {
        _gecis.perdeyiKaldir();
        final bildirim = _gecis.bekleyenBildirim;
        if (bildirim == null) return;
        _gecis.bekleyenBildirim = null;
        // Soğuk açılış yolu: navigator hazır olana dek bekler.
        NotificationService.instance
            .handleRemoteMessageData(bildirim, fromColdStart: true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final perde = _gecis.perde.value;
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
                child: HesapGecisPerdesiGorunumu(
                    perde: perde, tema: widget.tema)),
        ],
      ),
    );
  }
}

/// Geçiş perdesi — uygulamanın temasının DIŞINDA çizilir (kapsam o an
/// yeniden kuruluyor), bu yüzden kendi temasını cihaz parlaklığından kurar.
class HesapGecisPerdesiGorunumu extends StatelessWidget {
  const HesapGecisPerdesiGorunumu({super.key, required this.perde, this.tema});

  final HesapGecisPerdesi? perde;
  final ThemeData Function(Brightness)? tema;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.fromView(
      view: View.of(context),
      child: Builder(builder: (context) {
        final parlaklik = MediaQuery.platformBrightnessOf(context);
        final kur = tema;
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
            final p = perde;
            return Semantics(
              liveRegion: true,
              label: p == null ? 'Yükleniyor' : '${p.ad} ${p.alt}',
              child: ColoredBox(
                color: context.c.background,
                child: Center(
                  child: p == null
                      ? const CupertinoActivityIndicator()
                      : Padding(
                          padding: const EdgeInsets.all(SandikSpace.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              HesapAvatari(harf: p.basHarf, cap: 64),
                              const SizedBox(height: SandikSpace.md),
                              Text(
                                p.ad,
                                textAlign: TextAlign.center,
                                style: context.t.titleLarge
                                    ?.copyWith(color: context.c.text90),
                              ),
                              const SizedBox(height: SandikSpace.xs),
                              Text(
                                p.alt,
                                textAlign: TextAlign.center,
                                style: context.t.bodyMedium
                                    ?.copyWith(color: context.c.text58),
                              ),
                              const SizedBox(height: SandikSpace.lg),
                              const CupertinoActivityIndicator(),
                            ],
                          ),
                        ),
                ),
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
            style: context.t.titleMedium?.copyWith(
              color: ton % 3 == 0 ? c.onAmber : c.onStatus,
              fontWeight: FontWeight.w700,
            ).apply(fontSizeFactor: cap / 40),
          ),
        ),
      ),
    );
  }
}
