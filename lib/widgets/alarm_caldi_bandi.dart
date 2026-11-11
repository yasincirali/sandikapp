import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/gelen_alarm.dart';
import '../models/price_alert.dart';
import '../providers/price_alert_provider.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'alarm_kur_sheet.dart';
import 'sandik_skeleton.dart';

/// Alarmdan açılan varlık sayfasının başındaki "Alarmın çaldı" bandı
/// (2026-11-11, ücretsiz).
///
/// **Neden:** fiyat alarmı bildirimine dokunmak varlık sayfasını açıyordu
/// ama sayfa NEDEN açıldığını söylemiyordu; kişi hangi eşiğin çaldığını
/// şeritteki çipler arasında arıyordu. Bant tek cümleyle söyler
/// ("Alarmın çaldı: 245,00 ₺ üstü · 14:32") ve bir sonraki adımı ("Yeniden
/// kur") aynı yere koyar.
///
/// - Yalnız [alarmId] verilip alarm listede bulunduğunda çizilir
///   ([gelenAlarmiBul]); bulunamazsa hiç yer kaplamaz.
/// - Kart değil, ince bant: sayfanın içeriği değil, sayfaya geliş nedeni.
/// - Anlam renkte değil: zil ikonu + cümle. Amber ton yalnız vurgu.
/// - Kapatınca bu sayfa oturumu için kalkar (durum widget'ta; kalıcı değil,
///   bildirimden yeniden gelinirse yine görünür — yeni bir çalma anlatır).
/// - Belirme/kalkma [SandikBelirme] üzerinden: hareketi azalt açıkken
///   animasyonsuz.
class AlarmCaldiBandi extends ConsumerStatefulWidget {
  /// Bildirimin `alert_id`'si.
  final String alarmId;

  /// "Yeniden kur" sayfasının adayı — varlık ekranının zilindeki adayla
  /// aynı (sembol, ad, güncel fiyat, maliyet, 52 hafta).
  final AlarmAdayi aday;

  const AlarmCaldiBandi({
    super.key,
    required this.alarmId,
    required this.aday,
  });

  @override
  ConsumerState<AlarmCaldiBandi> createState() => _AlarmCaldiBandiState();
}

class _AlarmCaldiBandiState extends ConsumerState<AlarmCaldiBandi> {
  bool _kapali = false;

  void _kapat() {
    SandikHaptic.selection.perform();
    setState(() => _kapali = true);
  }

  /// Ön dolu kurma sayfası: güncelin %5 ötesi ([yenidenKurHedefi]). Yeni
  /// alarm kurulursa çalıp susmuş tek atış alarm silinir (liste ikilenmesin;
  /// `alarmiYenidenKur` ile aynı karar) ve bant işini bitirmiş olur.
  /// Tekrarlı alarm nöbette kalır: yeni alarm onun yanına eklenen ikinci
  /// eşiktir, eskisini silmek kişinin kurduğunu elinden almak olurdu.
  Future<void> _yenidenKur(PriceAlert alarm) async {
    final aday = widget.aday;
    try {
      final yeni = await alarmKurAkisi(
        context,
        ref,
        sabit: aday,
        baslangicHedef: yenidenKurHedefi(alarm, aday.guncelFiyat),
        bilinmeyenFiyattaYon: alarm.direction,
      );
      if (yeni == null) return;
      if (alarm.sondu) {
        await ref.read(priceAlertsProvider.notifier).delete(alarm.id);
      }
      if (mounted) setState(() => _kapali = true);
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => SandikBelirme(child: _govde(context));

  Widget _govde(BuildContext context) {
    if (_kapali) return const SizedBox.shrink();
    final alarm = gelenAlarmiBul(
        ref.watch(priceAlertsProvider).valueOrNull ?? const <PriceAlert>[],
        widget.alarmId);
    if (alarm == null) return const SizedBox.shrink();

    final c = context.c;
    final t = context.t;
    final l10n = context.l10n;
    final hedef = alarmFiyatMetni(alarm.targetPrice, alarm.symbol);
    final kosul = alarm.isAbove
        ? l10n.alarmCaldiBandiUst(hedef)
        : l10n.alarmCaldiBandiAlt(hedef);
    final zaman = alarmCalmaZamaniMetni(alarm, DateTime.now());
    final metin = zaman == null ? kosul : '$kosul · $zaman';
    // Büyük yazıda (1,5× üstü) eylemler cümlenin altına iner: dar satırda
    // cümleyi tek kelimeye, düğmeleri birbirine sıkıştırmasın (Dynamic Type;
    // Alarmlarım satırıyla aynı eşik).
    final buyukYazi = MediaQuery.textScalerOf(context).scale(1) > 1.5;

    final cumle = Text(
      metin,
      style:
          t.bodyMedium?.copyWith(color: c.text90, fontWeight: FontWeight.w600),
    );
    final ikon = Padding(
      padding: const EdgeInsets.only(right: SandikSpace.sm),
      child: Icon(Icons.notifications_active_rounded,
          size: 18, color: c.amberText),
    );
    final yenidenKur = TextButton(
      onPressed: () => _yenidenKur(alarm),
      style: TextButton.styleFrom(
        minimumSize: SandikTouch.minSize,
        padding: const EdgeInsets.symmetric(horizontal: SandikSpace.sm),
        foregroundColor: c.amberText,
      ),
      child: Text(l10n.recreateAlert),
    );
    final kapat = IconButton(
      tooltip: l10n.close,
      icon: Icon(Icons.close_rounded, size: 18, color: c.text58),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
          minWidth: SandikTouch.min, minHeight: SandikTouch.min),
      onPressed: _kapat,
    );

    final Widget icerik = buyukYazi
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                    top: SandikSpace.sm, right: SandikSpace.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [ikon, Expanded(child: cumle)],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [Flexible(child: yenidenKur), kapat],
              ),
            ],
          )
        : Row(
            children: [
              ikon,
              Expanded(child: cumle),
              yenidenKur,
              kapat,
            ],
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.md),
      child: Semantics(
        container: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.amberText.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(SandikRadius.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: SandikSpace.md),
            child: icerik,
          ),
        ),
      ),
    );
  }
}
