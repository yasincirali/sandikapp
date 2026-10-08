import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/eurobond.dart';
import '../providers/eurobond_provider.dart';
import '../services/eurobond_ozeti.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Varlık ekranının "Tahvil bilgileri" kartı — yalnız eurobond lotunda
/// (2026-10-08, yasin: "her varlık türü için detaycı olmalıyız").
///
/// Sözleşme + son fiyat [eurobondProvider]'dan; sayılar [eurobondOzeti]'nde
/// (kart hesaplamaz). Yüklenirken ya da katalogda yoksa kart HİÇ yer
/// kaplamaz: eurobond bayrağı kapalıyken bu tür eklenemez, kayıtlı lot da
/// katalogsuz kalırsa boş kart göstermenin anlamı yok.
class EurobondBilgiKarti extends ConsumerWidget {
  const EurobondBilgiKarti({
    super.key,
    required this.ticker,
    required this.nominal,
    this.dis = const EdgeInsets.only(top: SandikSpace.lg),
  });

  /// `EUROBOND:<ISIN>`.
  final String ticker;

  /// Açık nominal (pozisyon miktarı) — kupon ve bankaya satış tutarı için.
  final double nominal;
  final EdgeInsets dis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isin = eurobondIsin(ticker);
    if (isin == null) return const SizedBox.shrink();
    final veri = ref.watch(eurobondProvider(isin)).valueOrNull;
    if (veri == null) return const SizedBox.shrink();
    return Padding(
      padding: dis,
      child: EurobondKarti(
        ozet: eurobondOzeti(
          sozlesme: veri.$1,
          fiyat: veri.$2,
          nominal: nominal,
          simdi: DateTime.now(),
        ),
      ),
    );
  }
}

/// Kartın kendisi — saf, test edilebilir (sahte sözleşme + fiyatla).
class EurobondKarti extends StatelessWidget {
  const EurobondKarti({super.key, required this.ozet});

  final EurobondOzeti ozet;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final o = ozet;
    final s = o.sozlesme;
    final para = s.paraBirimi;
    // Fiyatlar 100 nominal başına puandır (nominalin yüzdesi); bankalar
    // üç haneyle kote eder. Getiri/kupon/stopaj oran olduğundan `fmtPct`.
    String puan(double v) => fmtNum(v, digits: 3);
    String tutar(double v) => '${fmtNum(v)} $para';
    String tarih(DateTime d) => fmtTarihSaat(dayKey(d));

    final ihracci = s.ihracci == EurobondIhracci.hazine
        ? l.bondIssuerTreasury
        : l.bondIssuerCorporate;
    final stopaj = l.bondWithholding(
        fmtPct(s.kuponStopajOrani * 100, digits: 0));

    final satirlar = <(String, String)>[
      if (o.temizFiyat != null) (l.bondCleanPrice, puan(o.temizFiyat!)),
      (l.bondAccrued, fmtPct(o.islemisFaiz, digits: 3)),
      if (o.kirliFiyat != null) (l.bondDirtyPrice, puan(o.kirliFiyat!)),
      if (o.vadeyeGetiri != null)
        (l.bondYtm, fmtPct(o.vadeyeGetiri! * 100)),
      (
        l.bondCoupon,
        l.bondCouponValue(
            fmtPct(s.kuponOrani * 100, digits: 3), '${s.yillikKuponSayisi}'),
      ),
      if (o.sonrakiKupon != null)
        (
          l.bondNextCoupon,
          o.sonrakiKuponTutari != null
              ? '${l.bondNextCouponValue(tarih(o.sonrakiKupon!), tutar(o.sonrakiKuponTutari!))} · $stopaj'
              : '${tarih(o.sonrakiKupon!)} · $stopaj',
        ),
      (
        l.bondMaturity,
        o.kalanGun != null
            ? l.bondMaturityValue(tarih(s.vade), '${o.kalanGun}')
            : tarih(s.vade),
      ),
      (l.bondIssuer, ihracci),
    ];

    final banka = <(String, String)>[
      if (o.bankaAlis != null) (l.bondBankBid, puan(o.bankaAlis!)),
      if (o.bankaSatis != null) (l.bondBankAsk, puan(o.bankaSatis!)),
      if (o.bankaMakasi != null) (l.bondBankSpread, puan(o.bankaMakasi!)),
      if (o.bankayaSatisTutari != null)
        (l.bondBankProceeds, tutar(o.bankayaSatisTutari!)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SandikSectionHeader(title: l.bondInfoUpper),
        const SizedBox(height: SandikSpace.sm),
        SandikCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.ad,
                  style: context.t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: context.c.text90)),
              const SizedBox(height: SandikSpace.xxs),
              Text('${s.isin} · ${l.bondPerNominalNote}',
                  style:
                      context.t.bodySmall?.copyWith(color: context.c.text58)),
              const SizedBox(height: SandikSpace.sm),
              ..._satirlar(context, satirlar),
            ],
          ),
        ),
        if (o.bankaVar && banka.isNotEmpty) ...[
          const SizedBox(height: SandikSpace.lg),
          SandikSectionHeader(title: l.bondBankSellUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.bondBankUpdated(
                      l.bondBankZiraat, fmtTarihSaat(o.bankaGuncellendi!)),
                  style: context.t.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600, color: context.c.text58),
                ),
                const SizedBox(height: SandikSpace.sm),
                ..._satirlar(context, banka),
                const SizedBox(height: SandikSpace.sm),
                Text(l.bondBankNote,
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text36)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _satirlar(BuildContext context, List<(String, String)> s) => [
        for (var i = 0; i < s.length; i++) ...[
          if (i > 0) Divider(height: 1, color: context.c.hairline),
          _Satir(etiket: s[i].$1, deger: s[i].$2),
        ],
      ];
}

/// "etiket · değer" satırı. Değer sağa yaslı ve esnek: uzun kupon satırı
/// ("15 Oca 2027 · 493,75 USD · Stopaj %0") dar ekranda alta kırılır,
/// taşmaz.
class _Satir extends StatelessWidget {
  const _Satir({required this.etiket, required this.deger});

  final String etiket;
  final String deger;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(etiket,
                  style: context.t.bodyMedium
                      ?.copyWith(color: context.c.text58)),
            ),
            const SizedBox(width: SandikSpace.smd),
            Flexible(
              flex: 2,
              child: Text(
                deger,
                textAlign: TextAlign.end,
                style: context.t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600, color: context.c.text90),
              ),
            ),
          ],
        ),
      );
}
