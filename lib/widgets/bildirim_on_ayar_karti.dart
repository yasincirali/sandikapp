import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/bildirim_on_ayar_provider.dart';
import '../providers/preferences_provider.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'sandik_segment.dart';

/// Ayarlar › Bildirimler'in başındaki tek soru: "Bildirimler ne sıklıkta
/// gelsin?" — Az · Dengeli · Çok.
///
/// Sinyal Ayarları'ndaki ön ayar kartının (`_OnAyarKarti`) bütün push'lara
/// genişlemiş hâli; davranış aynı: seçim kayıtlı değerlerden türetilir
/// ([bildirimOnAyarProvider]), hiçbir ön ayara uymayan kullanıcı "Özel"
/// etiketini görür ve hiçbir şey değişmez. Özel bir segment değildir —
/// dokununca neye döneceği belirsiz kalırdı.
///
/// Yazma sürerken ikinci dokunuş yok sayılır (çift yazma, iki ön ayarın
/// karışmasıyla "Özel" bırakırdı). Ayrı bir yükleniyor göstergesi yok:
/// segment iyimser kayar, yazma arka planda biter
/// (`yukleniyor_tek_davranis_test` — elle çizilmiş meşgul hâl yasak).
class BildirimOnAyarKarti extends ConsumerStatefulWidget {
  const BildirimOnAyarKarti({super.key, required this.onPaywall});

  /// Seçilen ön ayarın sinyal sıklığı ücretsiz günlük sınırı aşıyorsa
  /// çağrılır; o durumda hiçbir şey yazılmaz.
  final VoidCallback onPaywall;

  @override
  ConsumerState<BildirimOnAyarKarti> createState() =>
      _BildirimOnAyarKartiState();
}

class _BildirimOnAyarKartiState extends ConsumerState<BildirimOnAyarKarti> {
  bool _yaziliyor = false;

  /// Yazma sürerken segmentin göstereceği seçim (iyimser).
  BildirimOnAyar? _hedef;

  Future<void> _sec(BildirimOnAyar a) async {
    if (_yaziliyor) return;
    if (bildirimOnAyariPremiumIster(a, ref.read(sinyalSlotSiniriProvider))) {
      widget.onPaywall();
      return;
    }
    setState(() {
      _yaziliyor = true;
      _hedef = a;
    });
    try {
      await bildirimOnAyariUygula(ref, a);
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _yaziliyor = false;
          _hedef = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final durum = ref.watch(bildirimOnAyarProvider);
    final yuklendi = durum.hasValue;
    final secili = _hedef ?? durum.valueOrNull;
    final etiketler = [l10n.s5OnAyarAz, l10n.s5OnAyarDengeli, l10n.s5OnAyarCok];
    final aciklama = !yuklendi
        ? ''
        : switch (secili) {
            BildirimOnAyar.az => l10n.bildirimOnAyarAzAciklama,
            BildirimOnAyar.dengeli => l10n.bildirimOnAyarDengeliAciklama,
            BildirimOnAyar.cok => l10n.bildirimOnAyarCokAciklama,
            null => l10n.bildirimOnAyarOzelAciklama,
          };
    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.bildirimOnAyarSoru,
                  style: context.t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600, color: context.c.text90),
                ),
              ),
              if (yuklendi && secili == null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.sm, vertical: SandikSpace.xxs),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                    border: Border.all(
                        color: context.c.amberFill.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    l10n.s5OnAyarOzel,
                    style: context.t.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.c.amberText,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: SandikSpace.smd),
          SandikSegment(
            adet: etiketler.length,
            // Yüklenirken ve Özel'de aralık dışı → zemin çizilmez.
            secili: yuklendi ? (secili?.index ?? -1) : -1,
            onSec: (i) {
              if (!yuklendi) return;
              _sec(BildirimOnAyar.values[i]);
            },
            oge: (context, i, _) => Text(etiketler[i]),
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(
            aciklama,
            style: context.t.bodySmall
                ?.copyWith(color: context.c.text58, height: 1.4),
          ),
        ],
      ),
    );
  }
}
