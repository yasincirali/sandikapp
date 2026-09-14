import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/price_alert.dart';
import '../providers/price_alert_provider.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/tr_format.dart';
import 'alarm_kur_sheet.dart';

/// Varlık ekranındaki alarm şeridi — bu sembolün alarmları + "Alarm kur".
///
/// Alarm varlığa aittir; kullanıcı "THY 320'yi geçince" derken varlığın
/// ekranındadır, Ayarlar'da değil. Şerit boşken de görünür (tek bir "Alarm
/// kur" çipi) — özellik keşfedilebilir olsun. Sembolü olmayan (manuel
/// fiyatlı) varlıkta hiç çizilmez: sunucu onun fiyatını izleyemez.
class AlarmSeridi extends ConsumerWidget {
  final String sembol;
  final String ad;
  final double guncelFiyat;
  const AlarmSeridi({
    super.key,
    required this.sembol,
    required this.ad,
    required this.guncelFiyat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final alarmlar = ref.watch(symbolAlertsProvider(sembol));
    final n = ref.read(priceAlertsProvider.notifier);

    return Semantics(
      container: true,
      label: alarmlar.isEmpty
          ? 'Fiyat alarmı yok'
          : '${alarmlar.where((a) => a.isActive).length} aktif fiyat alarmı',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _Cip(
              onTap: () => alarmKurAkisi(context, ref,
                  sabit: AlarmAdayi(sembol, ad, guncelFiyat)),
              renk: c.amberText,
              zemin: c.amberFill.withValues(alpha: 0.12),
              semanticLabel: 'Fiyat alarmı kur',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_alert_outlined, size: 16, color: c.amberText),
                  const SizedBox(width: SandikSpace.xs),
                  Text('Alarm kur',
                      style: context.t.labelLarge?.copyWith(
                          color: c.amberText, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            for (final a in alarmlar) ...[
              const SizedBox(width: SandikSpace.xs2),
              _AlarmCipi(
                alarm: a,
                // Tetiklenmiş alarm dokununca yeniden kurulur; aktif alarm
                // dokununca silme sorulur. İki durumun tek dokunuşu vardır,
                // ikinci bir ikon şeridi sıkıştırırdı.
                onTap: () async {
                  if (a.triggeredAt != null) {
                    await n.rearm(a.id);
                    return;
                  }
                  final ok = await showSandikConfirm(
                    context: context,
                    title: 'Alarmı sil',
                    message: '${fmtTRY(a.targetPrice, digits: 2)} '
                        '${a.isAbove ? 'üstüne çıkınca' : 'altına inince'} '
                        'alarmı silinsin mi?',
                    confirmLabel: 'Sil',
                    destructive: true,
                  );
                  if (ok) await n.delete(a.id);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AlarmCipi extends StatelessWidget {
  final PriceAlert alarm;
  final VoidCallback onTap;
  const _AlarmCipi({required this.alarm, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tetiklendi = alarm.triggeredAt != null;
    final renk = tetiklendi ? c.text58 : (alarm.isAbove ? c.gain : c.loss);
    final fiyat = fmtTRY(alarm.targetPrice, digits: 2);
    return _Cip(
      onTap: onTap,
      renk: renk,
      zemin: renk.withValues(alpha: tetiklendi ? 0.06 : 0.12),
      semanticLabel: tetiklendi
          ? 'Çalışmış alarm $fiyat, yeniden kurmak için dokun'
          : '${alarm.isAbove ? 'Üstüne çıkınca' : 'Altına inince'} $fiyat, '
              'silmek için dokun',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(alarm.isAbove ? '▲' : '▼',
              style: context.t.labelLarge
                  ?.copyWith(color: renk, fontWeight: FontWeight.w700)),
          const SizedBox(width: SandikSpace.xs),
          Text(
            tetiklendi ? '$fiyat · çalıştı' : fiyat,
            style: context.t.labelLarge?.copyWith(
              color: tetiklendi ? c.text58 : c.text90,
              fontWeight: FontWeight.w600,
              decoration: tetiklendi ? TextDecoration.lineThrough : null,
            ),
          ),
          if (tetiklendi) ...[
            const SizedBox(width: SandikSpace.xs),
            Icon(Icons.refresh_rounded, size: 14, color: c.text58),
          ],
        ],
      ),
    );
  }
}

class _Cip extends StatelessWidget {
  final VoidCallback onTap;
  final Color renk;
  final Color zemin;
  final String semanticLabel;
  final Widget child;
  const _Cip({
    required this.onTap,
    required this.renk,
    required this.zemin,
    required this.semanticLabel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SandikTappable(
      semanticLabel: semanticLabel,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
        decoration: BoxDecoration(
          color: zemin,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: renk.withValues(alpha: 0.35)),
        ),
        child: child,
      ),
    );
  }
}
