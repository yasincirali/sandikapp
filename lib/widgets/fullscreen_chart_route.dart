import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/sandik.dart';

/// Grafiği tam ekran gösteren route — YALNIZCA grafik.
///
/// ## Neden değişti (kullanıcı bildirimi 2026-09-17)
/// "Büyütme butonu efektif çalışmıyor; yan çevirince izlenebilir olmuyor.
/// Sadece grafiği içersin; cihaz dike çevrildiğinde normal dik ekrana dönsün."
///
/// Eski davranış: yön yataya KİLİTLENİYOR ve `builder` ekranın TAMAMINI
/// (başlık, sekmeler, şeritler, kartlar) aşağı kaydırılmış olarak basıyordu.
/// 360pt yükseklikteki yatay ekranda bu bir kaydırma listesiydi, grafik
/// değil; telefon dikeye çevrilince de kilit yüzünden hiçbir şey olmuyordu.
///
/// Yeni davranış:
///   · Yön KİLİTLENMEZ; yatay (iki yön) + dikey (üst) serbest. Telefon
///     fiziksel olarak yan tutuluyorsa sistem yataya döner; dik tutuluyorsa
///     grafik dikeyde tam boy gösterilir (cihaz yönü karar verir).
///   · Yatay bir kez görüldükten sonra telefon dikeye çevrilirse route
///     KENDİNİ KAPATIR — "normal dik ekran" geri gelir. Yatay hiç
///     görülmediyse kapatma yalnızca X ile (yoksa dik açılan sayfa hemen
///     kapanırdı).
///   · Çağıran taraf `sadeceGrafik: true` ile YALNIZCA dönem seçici +
///     grafik kurar (`AssetDetailScreen.sadeceGrafik`,
///     `PortfolioPerformanceScreen.sadeceGrafik`).
///
/// `flutter-adaptive-ui` "yönü hiç kilitleme" der; uygulama geneli dikey
/// kilitli (tasarım kararı, CLAUDE.md kazanır) — bu route yönü serbest
/// bırakan tek yerdir ve çıkışta kilidi geri kurar.
class FullscreenChartRoute extends StatefulWidget {
  final WidgetBuilder builder;
  final String? title;

  const FullscreenChartRoute({
    super.key,
    required this.builder,
    this.title,
  });

  static Future<void> open(BuildContext context,
      {required WidgetBuilder builder, String? title}) {
    return Navigator.of(context, rootNavigator: true).push(
      adaptiveRoute(
        fullscreenDialog: true,
        builder: (_) => FullscreenChartRoute(builder: builder, title: title),
      ),
    );
  }

  @override
  State<FullscreenChartRoute> createState() => _FullscreenChartRouteState();
}

class _FullscreenChartRouteState extends State<FullscreenChartRoute> {
  bool _yatayGoruldu = false;
  bool _kapaniyor = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  void dispose() {
    // Uygulama geneli dikey kilitli — çıkışta geri kur.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yatay = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (yatay) {
      _yatayGoruldu = true;
    } else if (_yatayGoruldu && !_kapaniyor) {
      // Yatay → dikey: kullanıcı "normal ekrana dön" dedi. Build içinde
      // pop yapılmaz; kare bitince.
      _kapaniyor = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    return Scaffold(
      backgroundColor: context.c.background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(SandikSpace.sm),
                child: widget.builder(context),
              ),
            ),
            // Kapat — yatayda dikey alan değerli; başlık satırı yerine
            // köşede tek düğme. Başlık zaten bir alttaki ekranda.
            Positioned(
              top: 0,
              right: 0,
              child: Semantics(
                button: true,
                label: widget.title,
                child: SizedBox(
                  width: SandikTouch.min,
                  height: SandikTouch.min,
                  child: IconButton(
                    icon: Icon(Icons.close_rounded, color: context.c.text58),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
