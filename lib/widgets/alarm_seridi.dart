import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/price_alert.dart';
import '../providers/price_alert_provider.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/tr_format.dart';
import 'alarm_kur_sheet.dart';
import '../l10n/l10n.dart';

/// Varlık ekranındaki alarm şeridi — bu sembolün KURULU alarmları.
///
/// Alarm varlığa aittir; kullanıcı "THY 320'yi geçince" derken varlığın
/// ekranındadır, Ayarlar'da değil. Sembolü olmayan (manuel fiyatlı) varlıkta
/// hiç çizilmez: sunucu onun fiyatını izleyemez.
///
/// ## Boşken çizilmez (2026-09-18)
/// Eskiden şerit boşken de tek bir "Alarm kur" çipi gösteriyordu — "özellik
/// keşfedilebilir olsun" diye. O karar app bar'a zil eklenmeden (2026-09-14)
/// önce verilmişti; zil geldikten sonra aynı eylem ekranda İKİ kez duruyordu
/// (sağ üstte ikon, sinyal kartının altında yalnız bir sarı buton) ve
/// kullanıcı bunu "estetikten uzak" diye bildirdi. Giriş noktası artık tek:
/// app bar'daki zil. Şerit yalnızca kurulu alarm varken görünür; sonuna
/// küçük bir "+" çipi eklenir ki ikinci alarm mevcut olanların yanından
/// kurulabilsin.
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
    if (alarmlar.isEmpty) return const SizedBox.shrink();

    // Alt boşluk şeridin KENDİ sorumluluğu: üst ekran "şerit + SizedBox"
    // dizerse boş durumda boşluk tek başına kalır ve sinyal kartıyla periyot
    // seçici arasında açıklanamayan bir delik açılırdı.
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.smd),
      child: Semantics(
        container: true,
        label: context.l10n
            .nActiveAlerts(alarmlar.where((a) => a.isActive).length),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final a in alarmlar) ...[
                if (a != alarmlar.first)
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
                      title: context.l10n.deleteAlertTitle,
                      message: a.isAbove
                          ? context.l10n.deleteAlertAbove(
                              fmtTRY(a.targetPrice, digits: 2))
                          : context.l10n.deleteAlertBelow(
                              fmtTRY(a.targetPrice, digits: 2)),
                      confirmLabel: 'Sil',
                      destructive: true,
                    );
                    if (ok) await n.delete(a.id);
                  },
                ),
              ],
              const SizedBox(width: SandikSpace.xs2),
              // "+" — yalnızca ikon: metin app bar'daki zilin tooltip'inde
              // zaten var, burada tekrar edilse şerit yine ikinci bir "Alarm
              // kur" butonuna dönerdi.
              _Cip(
                onTap: () => alarmKurAkisi(context, ref,
                    sabit: AlarmAdayi(sembol, ad, guncelFiyat)),
                renk: c.amberText,
                zemin: c.amberFill.withValues(alpha: 0.12),
                semanticLabel: context.l10n.setPriceAlert,
                child: Icon(Icons.add_rounded, size: 18, color: c.amberText),
              ),
            ],
          ),
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
          ? context.l10n.triggeredAlertSemantics(fiyat)
          : (alarm.isAbove
              ? context.l10n.alertAboveSemantics(fiyat)
              : context.l10n.alertBelowSemantics(fiyat)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(alarm.isAbove ? '▲' : '▼',
              style: context.t.labelLarge
                  ?.copyWith(color: renk, fontWeight: FontWeight.w700)),
          const SizedBox(width: SandikSpace.xs),
          Text(
            tetiklendi ? context.l10n.alertTriggered(fiyat) : fiyat,
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
