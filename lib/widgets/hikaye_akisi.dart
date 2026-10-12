import 'package:flutter/material.dart';

import '../theme/sandik.dart';
import 'sandik_cam.dart';

/// Kart kart ilerleyen hikâye kabuğu: üstte ilerleme çubukları, ortada
/// kaydırılan sayfalar, altta tek düğme ("Devam" → son sayfada [sonEylem]).
///
/// ## Neden (göz alıcılık D, 2026-10-09)
/// Yıllık "sandık Özeti" (`RecapScreen`) hikâye biçimindeydi ve işliyordu:
/// her rakam kendi anını alıyor. Aylık rapor ise tek uzun listeydi; ayın
/// en çok ne söylediği listenin içinde kayboluyordu. Aylık hikâye bu
/// kabukla açılır. Yıllık özet de (2026-10-09) aynı kabuğa taşındı: iki
/// hikâye tek davranış, çubuk/düğme bir yerde düzelince ikisinde düzelir.
///
/// ## Kurallar
/// - Çubuklar parmakla dolar (`PageController.page` kesirli değeri):
///   sürüklerken çubuk da sürüklenir (animasyon denetimi 2026-10-01).
/// - Sayfa değişince hafif seçim titreşimi: hikâyede bir adım.
/// - Geçiş yüzey hareketidir (`surfaceOf`): "hareketi azalt"ta anında.
/// - [onAtla] → sağ üstte "Atla"; hikâye zorla izletilmez. Kendi üst
///   eylemi olan çağıran (yıllık özetin kapat düğmesi) [ustEylem] verir.
///
/// ## Story akışı (bayrak `goz_alici`, 2026-10-12)
/// yasin: "yıl özeti story gibi akmıyor". Kabuk story gibi görünüyordu ama
/// story gibi davranmıyordu: ilerlemek için "Devam"a basmak ya da kaydırmak
/// gerekiyordu. Bayrak açıkken:
/// - sayfa [HikayeAkisi.sayfaSuresi] sonra kendiliğinden geçer, çubuk zamanla dolar;
/// - ekranın sol üçte birine dokunmak geri, kalanı ileri; geçiş story'deki
///   gibi KESME (`jumpToPage`) ve içerik yumuşakça girer. Kaydırma hâlâ
///   kaydırır, onda giriş animasyonu yok (içerik zaten görünüyordu);
/// - basılı tutmak durdurur, bırakınca kaldığı yerden sürer;
/// - son sayfada durur (paylaş / rapor düğmesi kullanıcının);
/// - VoiceOver/TalkBack ya da "hareketi azalt" açıkken otomatik geçiş YOK
///   (HIG: kendiliğinden değişen içerik okumayı keser); dokunarak geçiş
///   kalır.
class HikayeAkisi extends StatefulWidget {
  const HikayeAkisi({
    super.key,
    required this.sayfalar,
    required this.devamMetni,
    required this.sonEylemMetni,
    required this.onBitti,
    this.atlaMetni,
    this.onAtla,
    this.ustEylem,
  });

  final List<Widget> sayfalar;
  final String devamMetni;
  final String sonEylemMetni;

  /// Son sayfadaki düğme.
  final VoidCallback onBitti;
  final String? atlaMetni;
  final VoidCallback? onAtla;

  /// Sağ üstte "Atla" yerine çizilir.
  final Widget? ustEylem;

  /// Story açıkken bir sayfanın ekranda kaldığı süre. Tek büyük sayı ve
  /// bir cümle için yeterli; acele eden dokunur, okuyamayan basılı tutar.
  static const Duration sayfaSuresi = Duration(seconds: 6);

  @override
  State<HikayeAkisi> createState() => _HikayeAkisiState();
}

class _HikayeAkisiState extends State<HikayeAkisi>
    with SingleTickerProviderStateMixin {
  final _controller = PageController();
  int _index = 0;

  /// Bayrak açıkken sayfanın süresi; kapalıyken hiç ilerlemez.
  late final AnimationController _sure =
      AnimationController(vsync: this, duration: HikayeAkisi.sayfaSuresi)
        ..addStatusListener(_sureBitti);

  /// Dokunma/zamanla gelinen sayfa giriş animasyonu oynatır; kaydırmayla
  /// gelinen oynatmaz. Sayaç anahtar olur, her girişte animasyon baştan.
  int _giris = 0;
  bool _kesmeGecisi = false;

  bool get _story => SandikCam.acik;

  bool _otomatik(BuildContext context) =>
      _story &&
      !MediaQuery.disableAnimationsOf(context) &&
      !MediaQuery.accessibleNavigationOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Erişilebilirlik ayarı açılış sırasında da değişebilir: kapandıysa
    // sayaç durur, açıldıysa baştan başlar.
    if (_otomatik(context)) {
      if (!_sure.isAnimating && _sure.value == 0) _sure.forward();
    } else {
      _sure.stop();
    }
  }

  @override
  void dispose() {
    _sure.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _sureBitti(AnimationStatus durum) {
    if (durum == AnimationStatus.completed &&
        _index < widget.sayfalar.length - 1) {
      _git(_index + 1);
    }
  }

  /// Story kesmesi: sayfa kaymaz, yerinde değişir; içerik girer.
  void _git(int i) {
    if (i < 0 || i >= widget.sayfalar.length) return;
    if (i == _index) {
      // İlk sayfada geri: sayfayı baştan oynat (story davranışı).
      setState(() => _giris++);
      _sureyiBaslat();
      return;
    }
    _kesmeGecisi = true;
    _controller.jumpToPage(i);
  }

  void _sureyiBaslat() {
    if (!mounted) return;
    if (_otomatik(context)) {
      _sure.forward(from: 0);
    } else {
      _sure.value = 0;
    }
  }

  void _dokundu(TapUpDetails d, double genislik) {
    final geri = d.localPosition.dx < genislik / 3;
    // RTL'de yön ters: sağ üçte bir geri.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _git((geri != rtl) ? _index - 1 : _index + 1);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final sayfalar = widget.sayfalar;
    final sonSayfa = _index >= sayfalar.length - 1;
    final atlaMetni = widget.atlaMetni;
    final onAtla = widget.onAtla;
    final story = _story;
    Widget sayfaGorunumu = PageView.builder(
      controller: _controller,
      itemCount: sayfalar.length,
      onPageChanged: (i) {
        SandikHaptic.selection.perform();
        setState(() {
          _index = i;
          if (_kesmeGecisi) _giris++;
        });
        _kesmeGecisi = false;
        if (story) _sureyiBaslat();
      },
      itemBuilder: (_, i) => story && i == _index && _giris > 0
          ? _Giris(key: ValueKey(_giris), child: sayfalar[i])
          : sayfalar[i],
    );
    if (story) {
      // Kapanış yeniden atanan değişkeni değil, sabit kopyayı yakalamalı;
      // yoksa LayoutBuilder kendini çocuk olarak kurar (sonsuz özyineleme).
      final sayfalarGorunumu = sayfaGorunumu;
      sayfaGorunumu = LayoutBuilder(
        builder: (context, kutu) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (d) => _dokundu(d, kutu.maxWidth),
          onLongPressStart: (_) => _sure.stop(),
          onLongPressEnd: (_) {
            if (_otomatik(context) && _sure.value < 1) _sure.forward();
          },
          child: sayfalarGorunumu,
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              SandikSpace.md, SandikSpace.smd, SandikSpace.md, SandikSpace.xs),
          child: AnimatedBuilder(
            animation: Listenable.merge([_controller, _sure]),
            builder: (context, _) {
              final sayfa =
                  _controller.hasClients && _controller.position.haveDimensions
                      ? (_controller.page ?? _index.toDouble())
                      : _index.toDouble();
              // Parmak sürüklerken çubuk parmağı izler; sayfa oturunca
              // (story açıkken) içinde bulunulan çubuk zamanla dolar.
              final oturdu = (sayfa - _index).abs() < 0.001;
              double dolu(int i) {
                if (story && oturdu) {
                  if (i < _index) return 1;
                  if (i > _index) return 0;
                  return _sure.value;
                }
                return (sayfa - i + 1).clamp(0.0, 1.0);
              }

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
                          widthFactor: dolu(i),
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
        if (widget.ustEylem case final ustEylem?)
          Align(alignment: AlignmentDirectional.centerEnd, child: ustEylem)
        else if (atlaMetni != null && onAtla != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
              onPressed: onAtla,
              child: Text(atlaMetni,
                  style: context.t.labelLarge?.copyWith(color: c.text58)),
            ),
          ),
        Expanded(child: sayfaGorunumu),
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
                  padding: const EdgeInsets.symmetric(vertical: SandikSpace.md2),
                ),
                onPressed: sonSayfa
                    ? widget.onBitti
                    : story
                        ? () => _git(_index + 1)
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

/// Story sayfasının girişi: hafifçe yükselip belirir. "Hareketi azalt"ta
/// süre sıfır (`flowOf`), içerik doğrudan yerinde.
class _Giris extends StatelessWidget {
  const _Giris({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: SandikMotion.flowOf(context),
        curve: SandikMotion.enter,
        child: child,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * SandikSpace.md),
            child: child,
          ),
        ),
      );
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
