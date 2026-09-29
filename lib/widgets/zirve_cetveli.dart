import 'package:flutter/material.dart';

import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Getiri cetveli — herkes aynı çizgide.
///
/// Zirvedeki portföyler ve kullanıcı TEK getiri ekseninde işaretlenir;
/// sıfır çizgisi görünür, uçlarda eksen değerleri. Konum (kaçıncı), mesafe
/// (kaç puan) ve yön (artıda mı) aynı anda okunur; ikinci bir grafik
/// gerekmez (kullanıcı seçimi 2026-09-29, "A · Cetvel önde").
///
/// ## Neden katlar
/// 2. (−%3,30) ve 3. (−%3,32) aynı noktaya düşer. Katsız çizimde biri
/// ötekini örter ve dokunulamaz. Yakın işaretler bir üst kata çıkar, ince
/// bir sapla eksene bağlanır (`ZirveKiyas.katlar`).
///
/// ## Etkileşim
/// İşarete dokunmak onu seçer ([onSec]); ekran alttaki bloğu o portföye
/// çevirir. Dönem değişince işaretler yeni yerine KAYAR — hareket bilgi
/// taşır ("bu hafta önümdeydi, bu ay gerimde"); "hareketi azalt" açıkken
/// anında.
class ZirveCetveli extends StatelessWidget {
  const ZirveCetveli({
    super.key,
    required this.isaretler,
    required this.secili,
    required this.onSec,
  });

  final List<ZirveIsaret> isaretler;

  /// Seçili işaretin anahtarı.
  final String? secili;
  final ValueChanged<String> onSec;

  /// Widget'ın toplam yüksekliği; en üst kat + etiket buna sığar.
  static const double yukseklik = 128;

  static const double _isaretCap = 24;
  static const double _katAdimi = 26;
  static const double _etiketYuksekligi = 16;

  /// Eksenin üstten uzaklığı: iki kat + etiket + dokunma kutusunun yarısı.
  static const double _eksenY = 96;

  /// Uçtaki işaretin dokunma kutusu dışarı taşmasın diye kenar payı.
  static const double _kenar = SandikTouch.min / 2;

  static String _ucEtiketi(double v) =>
      '${v < 0 ? '−' : '+'}%${fmtNum(v.abs(), digits: 0)}';

  @override
  Widget build(BuildContext context) {
    final eksen = ZirveKiyas.eksen(isaretler.map((i) => i.roi));
    return LayoutBuilder(
      builder: (context, c) {
        final genislik = c.maxWidth;
        final kullanilabilir = genislik - 2 * _kenar;
        double oran(double v) => (v - eksen.lo) / (eksen.hi - eksen.lo);
        double x(double v) => _kenar + oran(v) * kullanilabilir;
        final katlar =
            ZirveKiyas.katlar([for (final i in isaretler) oran(i.roi)]);
        final ucStili = context.t.labelSmall?.copyWith(
          color: context.c.text36,
          letterSpacing: 0,
        );

        return SizedBox(
          height: yukseklik,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Eksen.
              Positioned(
                left: _kenar,
                right: _kenar,
                top: _eksenY - 1,
                child: Container(height: 2, color: context.c.hairline),
              ),
              // Sıfır çizgisi: kim artıda kim ekside, renge gerek kalmadan.
              AnimatedPositioned(
                duration: SandikMotion.surfaceOf(context),
                curve: SandikMotion.move,
                left: x(0) - 0.5,
                top: _eksenY - 9,
                child: Container(width: 1, height: 18, color: context.c.text36),
              ),
              AnimatedPositioned(
                duration: SandikMotion.surfaceOf(context),
                curve: SandikMotion.move,
                left: x(0) - 20,
                top: _eksenY + 12,
                child: SizedBox(
                  width: 40,
                  child: Text('0', textAlign: TextAlign.center, style: ucStili),
                ),
              ),
              Positioned(
                left: 0,
                top: _eksenY + 12,
                child: Text(_ucEtiketi(eksen.lo), style: ucStili),
              ),
              Positioned(
                right: 0,
                top: _eksenY + 12,
                child: Text(_ucEtiketi(eksen.hi), style: ucStili),
              ),
              // Saplar önce (işaretlerin altında kalsın).
              for (var i = 0; i < isaretler.length; i++)
                if (katlar[i] > 0)
                  AnimatedPositioned(
                    duration: SandikMotion.surfaceOf(context),
                    curve: SandikMotion.move,
                    left: x(isaretler[i].roi) - 0.5,
                    top: _eksenY - katlar[i] * _katAdimi,
                    child: Container(
                      width: 1,
                      height: katlar[i] * _katAdimi,
                      color: context.c.text36,
                    ),
                  ),
              // Üst kattakiler SONRA çizilir: alttakinin dokunma kutusunun
              // üstüne binen etiket/kutu, alttakini örtmesin (ölçüldü:
              // 2. üst katta, 3.'nün etiketi 2.'nin kutusunu kapatıyordu).
              for (final i in List<int>.generate(isaretler.length, (i) => i)
                ..sort((a, b) => katlar[a].compareTo(katlar[b])))
                _isaret(context, isaretler[i], x(isaretler[i].roi), katlar[i]),
            ],
          ),
        );
      },
    );
  }

  Widget _isaret(BuildContext context, ZirveIsaret i, double x, int kat) {
    final merkezY = _eksenY - kat * _katAdimi;
    final seciliMi = i.anahtar == secili;
    final birinci = i.sira == 1;
    final kenarRengi = i.sen
        ? context.c.amberFill
        : birinci
            ? context.c.gold
            : context.c.text58;
    final yaziRengi = i.sen
        ? context.c.onAmber
        : birinci
            ? context.c.gold
            : context.c.text90;
    return AnimatedPositioned(
      key: ValueKey('zirve-isaret-${i.anahtar}'),
      duration: SandikMotion.surfaceOf(context),
      curve: SandikMotion.move,
      left: x - SandikTouch.min / 2,
      top: merkezY - SandikTouch.min / 2 - _etiketYuksekligi,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Etiket dokunuşu yutmasın: altındaki işaretin kutusuna gidebilir.
          IgnorePointer(
            child: SizedBox(
              width: SandikTouch.min,
              height: _etiketYuksekligi,
              child: Text(
                i.etiket,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: context.t.labelSmall?.copyWith(
                  letterSpacing: 0,
                  fontWeight: seciliMi ? FontWeight.w800 : FontWeight.w600,
                  color: seciliMi ? context.c.text90 : context.c.text58,
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            selected: seciliMi,
            label: i.sen
                ? 'Sen, ${ZirveKiyas.getiriParcasi(i.roi)}'
                : '${i.sira}. portföy, ${ZirveKiyas.getiriParcasi(i.roi)}',
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSec(i.anahtar),
                child: SizedBox(
                  key: ValueKey('zirve-dokun-${i.anahtar}'),
                  width: SandikTouch.min,
                  height: SandikTouch.min,
                  child: Center(
                    child: AnimatedContainer(
                      duration: SandikMotion.stateOf(context),
                      curve: SandikMotion.enter,
                      width: _isaretCap,
                      height: _isaretCap,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i.sen ? context.c.amberFill : context.c.surface1,
                        border: Border.all(color: kenarRengi, width: 2),
                        boxShadow: [
                          if (seciliMi)
                            BoxShadow(
                              color: context.c.amberFill.withValues(alpha: 0.35),
                              spreadRadius: 4,
                            )
                          else if (birinci)
                            BoxShadow(
                              color: context.c.gold.withValues(alpha: 0.35),
                              blurRadius: 12,
                            ),
                        ],
                      ),
                      child: Text(
                        i.sen ? 'S' : '${i.sira}',
                        style: context.t.numSmall.copyWith(
                          fontWeight: FontWeight.w900,
                          color: yaziRengi,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
