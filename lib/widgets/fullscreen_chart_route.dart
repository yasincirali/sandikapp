import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/sandik.dart';

/// Grafik container'ını yatay tam ekran gösteren route. Kullanıcı sağ üstteki
/// "genişlet" butonuna basınca push edilir; geri dönünce portrait'e döner.
///
/// `builder` çağrıldığında yeni bir grafik widget'ı üretir. Grafik state'i
/// (viewport controller, veri) parent'ta paylaşılıyorsa canlı sync korunur —
/// fullscreen'de zoom yapmak portrait grafiğe de yansır.
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
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Portrait'e geri dön. UI hâlâ portrait-only olduğu için uygulama geri
    // döner dönmez normal moda oturur.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: context.c.text58),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  if (widget.title != null)
                    Expanded(
                      child: Text(
                        widget.title!,
                        style: TextStyle(
                          color: context.c.text90,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(child: widget.builder(context)),
            ],
          ),
        ),
      ),
    );
  }
}
