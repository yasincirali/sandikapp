import 'package:flutter/material.dart';

import '../theme/sandik.dart';

/// Kart kart ilerleyen hikâye kabuğu: üstte ilerleme çubukları, ortada
/// kaydırılan sayfalar, altta tek düğme ("Devam" → son sayfada [sonEylem]).
///
/// ## Neden (göz alıcılık D, 2026-10-09)
/// Yıllık "sandık Özeti" (`RecapScreen`) hikâye biçimindeydi ve işliyordu:
/// her rakam kendi anını alıyor. Aylık rapor ise tek uzun listeydi; ayın
/// en çok ne söylediği listenin içinde kayboluyordu. Aylık hikâye bu
/// kabukla açılır. `RecapScreen` kendi kopyasını taşımaya devam ediyor
/// (yılda 16 gün görünür, şimdi doğrulanamaz; taşıma `TECHNICAL_DEBT.md`).
///
/// ## Kurallar
/// - Çubuklar parmakla dolar (`PageController.page` kesirli değeri):
///   sürüklerken çubuk da sürüklenir (animasyon denetimi 2026-10-01).
/// - Sayfa değişince hafif seçim titreşimi: hikâyede bir adım.
/// - Geçiş yüzey hareketidir (`surfaceOf`): "hareketi azalt"ta anında.
/// - [onAtla] → sağ üstte "Atla"; hikâye zorla izletilmez.
class HikayeAkisi extends StatefulWidget {
  const HikayeAkisi({
    super.key,
    required this.sayfalar,
    required this.devamMetni,
    required this.sonEylemMetni,
    required this.onBitti,
    this.atlaMetni,
    this.onAtla,
  });

  final List<Widget> sayfalar;
  final String devamMetni;
  final String sonEylemMetni;

  /// Son sayfadaki düğme.
  final VoidCallback onBitti;
  final String? atlaMetni;
  final VoidCallback? onAtla;

  @override
  State<HikayeAkisi> createState() => _HikayeAkisiState();
}

class _HikayeAkisiState extends State<HikayeAkisi> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final sayfalar = widget.sayfalar;
    final sonSayfa = _index >= sayfalar.length - 1;
    final atlaMetni = widget.atlaMetni;
    final onAtla = widget.onAtla;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              SandikSpace.md, SandikSpace.smd, SandikSpace.md, SandikSpace.xs),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final sayfa =
                  _controller.hasClients && _controller.position.haveDimensions
                      ? (_controller.page ?? _index.toDouble())
                      : _index.toDouble();
              return Row(
                children: [
                  for (var i = 0; i < sayfalar.length; i++)
                    Expanded(
                      child: Container(
                        height: SandikSpace.xxs + 1,
                        margin: const EdgeInsets.symmetric(
                            horizontal: SandikSpace.xxs),
                        decoration: BoxDecoration(
                          color: c.text20,
                          borderRadius: BorderRadius.circular(SandikSpace.xxs),
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (sayfa - i + 1).clamp(0.0, 1.0),
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.amberFill,
                              borderRadius:
                                  BorderRadius.circular(SandikSpace.xxs),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (atlaMetni != null && onAtla != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
              onPressed: onAtla,
              child: Text(atlaMetni,
                  style: context.t.labelLarge?.copyWith(color: c.text58)),
            ),
          ),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: sayfalar.length,
            onPageChanged: (i) {
              SandikHaptic.selection.perform();
              setState(() => _index = i);
            },
            itemBuilder: (_, i) => sayfalar[i],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                SandikSpace.lg, SandikSpace.sm, SandikSpace.lg, SandikSpace.lg),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.amberFill,
                  foregroundColor: c.onAmber,
                  minimumSize: SandikTouch.minSize,
                ),
                onPressed: sonSayfa
                    ? widget.onBitti
                    : () => _controller.nextPage(
                          duration: SandikMotion.surfaceOf(context),
                          curve: SandikMotion.enter,
                        ),
                child:
                    Text(sonSayfa ? widget.sonEylemMetni : widget.devamMetni),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Hikâyenin tek sayfası: [bas] (çizim ya da çip), küçük üst satır, tek
/// büyük başlık (sayı ya da ad), açıklama.
///
/// Sayfa başına TEK büyük öğe: ikinci bir büyük sayı ilkinin anını çalar.
/// Başlık uzunsa küçülür değil sarar; yazı ×2'de taşmasın diye sayfa
/// kaydırılabilir.
class HikayeSayfasi extends StatelessWidget {
  const HikayeSayfasi({
    super.key,
    required this.ust,
    required this.baslik,
    required this.alt,
    required this.renk,
    this.bas,
  });

  final String ust;
  final String baslik;
  final String alt;
  final Color renk;
  final Widget? bas;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bas = this.bas;
    return LayoutBuilder(
      builder: (context, kutu) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kutu.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bas != null) ...[
                bas,
                const SizedBox(height: SandikSpace.lg),
              ],
              Text(ust,
                  style: context.t.titleMedium?.copyWith(color: c.text58)),
              const SizedBox(height: SandikSpace.xs2),
              Text(
                baslik,
                style: context.t.displaySmall?.copyWith(
                  color: renk,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: SandikSpace.smd),
              Text(
                alt,
                style:
                    context.t.bodyLarge?.copyWith(color: c.text58, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
