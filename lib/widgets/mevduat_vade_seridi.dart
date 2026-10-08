import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../providers/sozlesme_provider.dart';
import '../services/mevduat_hesabi.dart';
import '../theme/sandik.dart';
import '../utils/money_format.dart';
import '../utils/tr_format.dart';

/// Portföy kartının açılır panelinde mevduatın grafik yerine geçen şeridi.
///
/// ## Neden grafik değil (kullanıcı isteği, 2026-10-02)
/// *"Vadeli mevduatta portföy varlık kartı açılır detayında grafik alanını
/// boş bırakıyor. Orası uygun bir dizaynda olmalı."* Panel her türe "son 1
/// ay" fiyat eğrisi çiziyordu; vadeli mevduatın değeri vade içinde düz
/// (faiz vade sonunda eklenir), eğri ya boş ya da düz bir çizgiydi ve bir
/// şey söylemiyordu. Mevduatın asıl sorusu "vadeye ne kaldı, sonunda ne
/// eklenecek"; şerit onu yanıtlar: açılış → vade ilerlemesi, kalan gün ve
/// vade sonunda eklenecek net faiz. Günlük faizli hesapta vade yoktur;
/// oran ve günlük net faiz yazılır.
///
/// Sayılar `MevduatHesabi.ozet`ten gelir; şerit hesap yapmaz. Tutarlar
/// [baz]'dan geçer: bakiye gizliyken maskelenir, baz para birimine çevrilir.
class MevduatVadeSeridi extends ConsumerWidget {
  const MevduatVadeSeridi({
    super.key,
    required this.temsilci,
    required this.pay,
    required this.baz,
  });

  /// Pozisyonun temsilci lotu (`MEVDUAT:<sözleşme>` sembolü).
  final Asset temsilci;

  /// Pozisyondaki net pay adedi.
  final double pay;

  final BazPara baz;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = temsilci.sozlesmeId ?? mevduatSozlesmeId(temsilci.ticker);
    if (id == null) return const SizedBox.shrink();
    final donemler =
        ref.watch(sozlesmeProvider).valueOrNull?.donemleri(id) ?? const [];
    final o = MevduatHesabi.ozet(donemler, pay, DateTime.now());
    if (o == null) return const SizedBox.shrink();

    final l10n = context.l10n;
    final renk = AssetType.mevduat.color;
    final tarih = DateFormat('d MMM', l10n.localeName);
    final ikincil = context.t.bodySmall?.copyWith(color: context.c.text58);
    final soluk = context.t.bodySmall?.copyWith(color: context.c.text36);
    final vade = o.vade;
    final oran = fmtNumFlex(o.yillikFaiz, maxDigits: 2);

    final (String sagUst, String altEtiket, double? altTutar) = vade == null
        ? (
            l10n.depositKindDaily,
            l10n.depositDailyNet,
            o.gunlukNet,
          )
        : (
            o.doldu
                ? l10n.depositMatured
                : l10n.depositDaysLeft(o.kalanGun ?? 0),
            o.doldu
                ? l10n.depositInterestAdded
                : l10n.depositInterestAtMaturity,
            o.vadeSonuNet,
          );

    return Container(
      padding: const EdgeInsets.all(SandikSpace.smd),
      // Açık temada tint %5: %8'de koyu zemin üstünde `gain` tutarı
      // 4,49:1'e iniyordu (AA 4,5 — açık tema denetimi 2026-10-08).
      decoration: BoxDecoration(
        color: renk.withValues(alpha: context.isLight ? 0.05 : 0.08),
        borderRadius: SandikRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: SandikSpace.sm,
            runSpacing: SandikSpace.xs,
            children: [
              // İkon metnin içinde: büyük ölçekte metinle birlikte sarar
              // (ayrı Row'da metin taşıyordu).
              Text.rich(
                TextSpan(children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: SandikSpace.xs2),
                      child:
                          // İkon `onSurface`: ham çelik mavisi açık temada
                          // 2,2:1 (açık tema denetimi 2026-10-08).
                          Icon(AssetType.mevduat.icon,
                              size: 16,
                              color: AssetType.mevduat.onSurface(context)),
                    ),
                  ),
                  TextSpan(text: l10n.depositStripRate(oran)),
                ]),
                style: context.t.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700, color: context.c.text90),
              ),
              Text(sagUst,
                  style: ikincil?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          if (vade != null) ...[
            const SizedBox(height: SandikSpace.sm),
            ClipRRect(
              borderRadius: SandikRadius.smAll,
              child: LinearProgressIndicator(
                value: o.ilerleme ?? 1,
                minHeight: 6,
                backgroundColor: context.c.overlay,
                color: renk,
              ),
            ),
            const SizedBox(height: SandikSpace.xs),
            // Wrap: büyük metin ölçeğinde iki tarih alt alta iner, taşmaz.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: SandikSpace.sm,
              children: [
                Text(tarih.format(o.baslangic), style: soluk),
                Text(tarih.format(vade), style: soluk),
              ],
            ),
          ],
          const SizedBox(height: SandikSpace.sm),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: SandikSpace.sm,
            children: [
              Text(altEtiket, style: ikincil),
              if (altTutar != null)
                Text(
                  '+${baz.fmt(altTutar, digits: 2)}',
                  style: context.t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800, color: context.c.gain),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
