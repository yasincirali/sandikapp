import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../services/crash_reporter.dart';
import '../../providers/preferences_provider.dart'
    show yatayGrafikAcildiProvider;
import '../../theme/sandik.dart';

/// Telefon dikten yana dönünce [ac]'ı bir kez çağırır.
///
/// ## Neden yalnız geçişte
/// Tam ekran grafiğin tek girişi yan çevirmek (dik ekrandaki çip
/// 2026-09-17'de kullanıcı kararıyla kalktı). Sayfa zaten yatayken
/// açıldıysa ya da kullanıcı tam ekranı kapat düğmesiyle kapatıp yatay
/// kaldıysa grafik yeniden itilmez: aksi hâlde kapatmak imkânsız olurdu.
/// Yeni bir açılış için telefon önce dik dönmelidir.
///
/// ## Neden tablette yok
/// En kısa kenarı 600 dp ve üstü olan cihazda yatay ekran zaten geniş;
/// dik/yatay geçiş bir niyet bildirmez (iPad'de klavye kılıfıyla yatay
/// çalışmak olağan). Widget testlerinin varsayılan 800×600 yüzeyi de bu
/// yüzden tetiklemez.
///
/// ## Neden yalnız en üstteki sayfada
/// Bir sheet ya da başka sayfa üstteyken yan çevirmek o sayfanın işidir;
/// `ModalRoute.isCurrent` değilse hiçbir şey yapılmaz.
///
/// ## Tek seferlik ipucu (yasin 2026-10-29)
/// *"Detaylı varlık detayı ekranında yan çevirmeyle ilgili bir bilgi
/// içermeli mi?"* — giriş tek jest olunca kimse bilmiyordu. Çip geri
/// gelmez (2026-09-17 kararı); grafiğin altında DÜĞME OLMAYAN küçük bir
/// satır: dönüş simgesi + "Detaylı grafik için telefonu yan çevir".
/// Yalnız tam ekranın sunulduğu varlıkta, telefonda ve dik ekranda.
/// Kullanıcı yatay ekranı bir kez açınca ([yatayGrafikAcildiProvider],
/// cihaz tercihi) bir daha görünmez: öğrenilmiş jesti hatırlatmak gürültü.
/// İpucu ve görünürlük kuralı tek yerde ([YanCevirIpucu]); varsayılan
/// olarak bu sarmalayıcı onu grafiğin altına koyar (varlık sayfası).
/// Grafiği SABİT yükseklikte bir kartın içinde olan konak (varlık detayı:
/// `GrafikStili.kartYuksekligi`, yükleme/hata da o yükseklikte — yerleşim
/// zıplamasın) [ipucu]'yu kapatır ve aynı widget'ı kartın altına koyar;
/// kartın içine eklenen satır taşıyordu.
class YanCevirinceTamEkran extends ConsumerStatefulWidget {
  const YanCevirinceTamEkran({
    super.key,
    required this.etkin,
    required this.ac,
    required this.child,
    this.ipucu = true,
  });

  /// Bu yüzeyde tam ekran grafik var mı (mum kaynağı olan varlık).
  final bool etkin;
  final Future<void> Function(BuildContext context) ac;
  final Widget child;

  /// Tek seferlik ipucu çocuğun altına konsun mu (bkz. sınıf notu).
  final bool ipucu;

  @override
  ConsumerState<YanCevirinceTamEkran> createState() =>
      _YanCevirinceTamEkranState();
}

class _YanCevirinceTamEkranState extends ConsumerState<YanCevirinceTamEkran> {
  Orientation? _onceki;
  bool _acik = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final boyut = MediaQuery.sizeOf(context);
    final yon = boyut.width > boyut.height
        ? Orientation.landscape
        : Orientation.portrait;
    final onceki = _onceki;
    _onceki = yon;
    if (onceki != Orientation.portrait || yon != Orientation.landscape) return;
    if (!widget.etkin || _acik || boyut.shortestSide >= 600) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _acik = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _acik = false;
        return;
      }
      // Açılış = jest öğrenildi; ipucu bir daha çıkmaz. Kare sonrasında:
      // build sırasında sağlayıcı değiştirmek yasak.
      CrashReporter.arkaPlan(
          ref.read(yatayGrafikAcildiProvider.notifier).set(true),
          reason: 'YanCevirinceTamEkran.ipucuGoruldu');
      try {
        await widget.ac(context);
      } finally {
        _acik = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.ipucu || !YanCevirIpucu.gorunur(context, ref, widget.etkin)) {
      return widget.child;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [widget.child, YanCevirIpucu(etkin: widget.etkin)],
    );
  }
}

/// "Detaylı grafik için telefonu yan çevir" — bilgi satırı, düğme değil
/// (dokunma hedefi yok; ekran okuyucu düz metin okur, simge süs).
/// Renk text58: grafiğin eksen yazılarıyla aynı ağırlıkta, dikkat çalmaz.
/// Görünmüyorsa yer kaplamaz.
class YanCevirIpucu extends ConsumerWidget {
  const YanCevirIpucu({super.key, required this.etkin});

  /// [YanCevirinceTamEkran.etkin] ile aynı: bu varlıkta tam ekran var mı.
  final bool etkin;

  /// Telefonda (en kısa kenar < 600, [YanCevirinceTamEkran]'ın açtığı
  /// cihazlar), dik ekranda ve yatay hiç açılmamışsa.
  static bool gorunur(BuildContext context, WidgetRef ref, bool etkin) {
    if (!etkin) return false;
    final boyut = MediaQuery.sizeOf(context);
    return boyut.shortestSide < 600 &&
        boyut.height >= boyut.width &&
        !ref.watch(yatayGrafikAcildiProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!gorunur(context, ref, etkin)) return const SizedBox.shrink();
    final c = context.c;
    return Padding(
      key: const ValueKey('yanCevirIpucu'),
      padding: const EdgeInsets.only(top: SandikSpace.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.screen_rotation_rounded,
                size: 16, color: c.text58),
          ),
          const SizedBox(width: SandikSpace.xs2),
          Flexible(
            child: Text(
              context.l10n.tegYanCevirIpucu,
              style: context.t.labelSmall?.copyWith(color: c.text58),
            ),
          ),
        ],
      ),
    );
  }
}
