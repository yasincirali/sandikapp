import 'package:flutter/material.dart';
import '../theme/sandik.dart';

/// Yatay kaydırılabilir içeriğin sağ kenarına soldan sağa
/// şeffaflaşan bir gradient + küçük ok ikonu ekler.
/// Kullanıcı içeriği kaydırdıkça ok ikonu kaybolur.
class HScrollWithFade extends StatefulWidget {
  final Widget child;
  final Color? fadeColor;
  final double fadeWidth;

  const HScrollWithFade({
    super.key,
    required this.child,
    this.fadeColor,
    this.fadeWidth = 40,
  });

  @override
  State<HScrollWithFade> createState() => _HScrollWithFadeState();
}

class _HScrollWithFadeState extends State<HScrollWithFade> {
  final _scrollCtrl = ScrollController();
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  void _onScroll() {
    final canScroll = _scrollCtrl.position.extentAfter > 1;
    if (canScroll != _canScrollRight) setState(() => _canScrollRight = canScroll);
  }

  void _checkOverflow() {
    if (!_scrollCtrl.hasClients) return;
    final canScroll = _scrollCtrl.position.maxScrollExtent > 1;
    if (canScroll != _canScrollRight) setState(() => _canScrollRight = canScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Zemin rengi TEMADAN gelir. Sabit `Sandik.background` (koyu yeşil)
    // kullanılıyordu; light mode'da açık zeminin üzerine koyu bir blok
    // basıyor ve "bir garip duran" kesik oluşuyordu. Çağıran özel bir zemin
    // (kart yüzeyi vb.) üzerindeyse `fadeColor` ile bildirir.
    final fadeColor = widget.fadeColor ?? context.c.background;

    return Stack(
      children: [
        SingleChildScrollView(
          controller: _scrollCtrl,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
        if (_canScrollRight)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: widget.fadeWidth,
            child: IgnorePointer(
              child: Row(
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            fadeColor.withValues(alpha: 0),
                            // 0.92 → 1.0: sert kenar bırakmaz. Kısmi opaklık,
                            // altından geçen çipin kenarını hayalet gibi
                            // sızdırıyordu.
                            fadeColor,
                          ],
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(color: fadeColor),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        // `text36` de sabit beyazdı — light zeminde görünmezdi.
                        color: context.c.text36,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
