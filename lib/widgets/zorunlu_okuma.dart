import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import 'sigan_metin.dart';

/// Zorunlu okuma — onay istenen her metin TAM gösterilir ve sonuna kadar
/// okunmadan onaylanamaz (bayrak `zorunlu_okuma`, kullanıcı kararı
/// 2026-10-04).
///
/// ## Karar
/// *"Özeti değil hepsini okutmalıyız. Zorunlu okutup en sonda onaylatarak
/// ilerleyelim."* Kapsam: TÜM onay metinleri (Koşullar, Gizlilik, KVKK
/// Aydınlatma, Açık Rıza Metni, yatırım uyarısı, Zirve açık rızası). Onay
/// düğmesi metnin EN SONUNDA durur ve kullanıcı sona ulaşınca açılır.
///
/// ## "Sona ulaştı" neden kaydırma konumundan okunur
/// Tek kaynak `ScrollMetrics.extentAfter`: kaydırılabilir alanın altında
/// kalan içerik [OkumaOlcumu.tolerans]'tan azsa metin okunmuş sayılır.
/// Bunun üç yolu var ve üçü de aynı konumu değiştirir — ayrı bir "erişilebilir
/// yol" yazmaya gerek kalmaz, dolayısıyla kilitlenme de olmaz:
/// - parmakla kaydırma (`ScrollUpdateNotification`);
/// - TalkBack/VoiceOver kaydırma eylemi (`SemanticsAction.scrollUp` vb.
///   sürüklemeyi taklit eder, konum değişir);
/// - TalkBack/VoiceOver ile öğe öğe ilerleme: odak alan öğe ekrana getirilir
///   (`showOnScreen`), son öğe onay düğmesidir — ona gelindiğinde liste sona
///   kaymış olur.
/// Metin ekrana sığıyorsa ilk ölçümde `extentAfter == 0` → düğme baştan açık
/// (`ScrollMetricsNotification` ilk yerleşimde de gelir). Ulaşıldı bilgisi
/// YAPIŞKANDIR: yukarı geri kaydırmak ya da yazı boyutunu değiştirmek onu
/// geri almaz.
///
/// Tolerans 48 pt: listenin alt boşluğu ve güvenli alan payı (en çok
/// ~34 pt) `extentAfter`'a girer; bunlar okunacak metin değildir. Daha
/// büyük bir pay son paragrafın okunmadan geçilmesine izin verirdi.
abstract final class OkumaOlcumu {
  static const double tolerans = SandikSpace.xxl;

  /// Metnin sonuna gelindi mi (ya da metin zaten sığıyor mu)? Saf.
  ///
  /// [sonPay]: onay düğmesinden SONRA gelen, metin olmayan boşluk (liste alt
  /// boşluğu + güvenli alan). Erişilebilirlik odağı düğmeyi ekrana
  /// getirdiğinde (`showOnScreen`) düğmenin altı tam hizalanır, bu pay
  /// görünmez kalabilir; payı saymamak düğmeyi kilitli bırakırdı.
  static bool sonaUlasti(ScrollMetrics m, {double sonPay = 0}) =>
      m.hasContentDimensions &&
      m.hasPixels &&
      m.extentAfter <= tolerans + sonPay;

  /// 0..1 okuma ilerlemesi (ipucu çubuğu). Sığan metin 1.
  static double ilerleme(ScrollMetrics m) {
    if (!m.hasContentDimensions || !m.hasPixels) return 0;
    final toplam = m.maxScrollExtent - m.minScrollExtent;
    if (toplam <= tolerans) return 1;
    return ((m.pixels - m.minScrollExtent) / toplam).clamp(0.0, 1.0);
  }
}

/// Zorunlu okuma ekranının dönüşü — çağıran onay kaydına (`degiskenler`)
/// `sonuna_kadar_okundu` işaretini buradan yazar.
@immutable
class ZorunluOkumaSonucu {
  const ZorunluOkumaSonucu({
    required this.onaylandi,
    required this.sonunaKadarOkundu,
  });

  /// "Okudum ve onaylıyorum"a basıldı.
  final bool onaylandi;

  /// Onay anında metnin sonuna ulaşılmıştı. Bugün düğme ancak sona
  /// ulaşınca açıldığı için onaylanan her sonuçta `true`; ayrı alan, çünkü
  /// kayıt "hangi kanıt var" sorusuna ayrı ayrı cevap verir.
  final bool sonunaKadarOkundu;
}

/// Bir kaydırılabilir alanın "sona ulaştı" durumunu ve ilerlemesini
/// bildirir. Yalnız DOĞRUDAN altındaki kaydırılabiliri dinler (`depth == 0`):
/// metnin içinde yatay bir tablo kaydırması onu bozmasın.
class SonaKadarOkumaIzleyici extends StatefulWidget {
  const SonaKadarOkumaIzleyici({
    super.key,
    required this.child,
    required this.onSonaUlasti,
    this.onIlerleme,
    this.sonPay = 0,
  });

  final Widget child;

  /// Bkz. [OkumaOlcumu.sonaUlasti].
  final double sonPay;

  /// Bir kez çağrılır (yapışkan).
  final VoidCallback onSonaUlasti;
  final ValueChanged<double>? onIlerleme;

  @override
  State<SonaKadarOkumaIzleyici> createState() => _SonaKadarOkumaIzleyiciState();
}

class _SonaKadarOkumaIzleyiciState extends State<SonaKadarOkumaIzleyici> {
  bool _ulasti = false;
  double _ilerleme = -1;

  void _olc(ScrollMetrics m) {
    final ulasti = !_ulasti && OkumaOlcumu.sonaUlasti(m, sonPay: widget.sonPay);
    // Sona ulaşıldıktan sonra çubuk dolu kalır (yapışkan, bkz. sınıf notu).
    final ilerleme = _ulasti || ulasti ? 1.0 : OkumaOlcumu.ilerleme(m);
    if (ulasti) _ulasti = true;
    final degisti = (ilerleme - _ilerleme).abs() >= 0.01;
    if (degisti) _ilerleme = ilerleme;
    if (!ulasti && !degisti) return;
    void bildir() {
      if (!mounted) return;
      if (degisti) widget.onIlerleme?.call(ilerleme);
      if (ulasti) widget.onSonaUlasti();
    }

    // Ölçüm yerleşim sırasında gelebilir; çağıran setState yapar.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => bildir());
    } else {
      bildir();
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        if (n.depth == 0) _olc(n.metrics);
        return false;
      },
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) {
          if (n.depth == 0) _olc(n.metrics);
          return false;
        },
        child: widget.child,
      ),
    );
  }
}

/// Sona ulaşılana kadar ekranın altında duran ipucu: ince ilerleme çubuğu
/// + "Onaylamak için metni sona kadar oku". Onay düğmesi metnin sonunda
/// olduğu için kullanıcı okurken onu görmez; neyin beklendiğini bu söyler.
class OkumaIpucu extends StatelessWidget {
  const OkumaIpucu({super.key, required this.ilerleme});

  final double ilerleme;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: context.c.surface2,
          border:
              Border(top: BorderSide(color: context.c.hairline, width: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: ilerleme.clamp(0.0, 1.0),
              minHeight: 3,
              color: context.c.amberFill,
              backgroundColor: context.c.overlay,
              semanticsLabel: l.zorunluOkumaIlerleme,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: SandikSpace.md, vertical: SandikSpace.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 16, color: context.c.text58),
                  const SizedBox(width: SandikSpace.xs),
                  Flexible(
                    child: SiganMetin(
                      [l.zorunluOkumaIpucu, l.zorunluOkumaIpucuKisa],
                      textAlign: TextAlign.center,
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Okunacak metinler listesinin bir satırı: ad (sığan yazım), sürüm ve
/// durum (okundu / onaylandı) — dokununca metin açılır.
///
/// Yeniden onay kapısındaki satırdan taşındı (2026-10-04): kayıt ekranı
/// zorunlu okumada aynı listeyi gösterir, iki ayrı görünüş olmasın.
class YasalBelgeSatiri extends StatelessWidget {
  const YasalBelgeSatiri({
    super.key,
    required this.adaylar,
    required this.surum,
    required this.tamam,
    required this.tamamEtiketi,
    required this.onTap,
  });

  final List<String> adaylar;
  final String surum;

  /// Kapıda (bayrak kapalı) "açıldı"; zorunlu okumada "onaylandı".
  final bool tamam;
  final String tamamEtiketi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: SandikBasma(
        onTap: onTap,
        olcek: 0.98,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: SandikSpace.md, vertical: SandikSpace.smd),
            child: Row(
              children: [
                Icon(Icons.description_outlined,
                    size: 20, color: context.c.amberText),
                const SizedBox(width: SandikSpace.smd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SiganMetin(
                        adaylar,
                        style: context.t.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.c.text90,
                        ),
                      ),
                      const SizedBox(height: SandikSpace.xxs),
                      Text(
                        tamam ? '$surum · $tamamEtiketi' : surum,
                        style: context.t.bodySmall
                            ?.copyWith(color: context.c.text36),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Icon(
                  tamam
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  size: 20,
                  color: tamam ? context.c.gain : context.c.text36,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
