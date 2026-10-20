import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/fon_xray_provider.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../services/fon_dagilimi.dart' show XrayKova;
import '../services/zirve_icerik.dart';
import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import 'fon_dagilimi_karti.dart';
import 'premium_kilit_karti.dart';
import 'sandik_skeleton.dart';

/// Zirve portföy ayrıntısında "Fonların içi açılınca" (yasin 2026-10-20):
/// fonlar ve BES TEFAS dağılımıyla açılmış hâliyle portföyün gerçekte
/// hangi varlık sınıflarında durduğu. Hesap `zirve_icerik.dart`'ta (saf).
///
/// Fon X-Ray'in parçası, onunla aynı kapı (yeni özellik Premium; yasin
/// kuralı): Premium özellikleri görünmüyorsa (paywall kapalı, admin değil)
/// HİÇ çizilmez; paywall açık ve Premium değilse kilit kartı (veri
/// okunmaz, RLS de vermez). Portföyde fon/BES yoksa çizilmez: doğrudan
/// varlıklar zaten "Varlıklar" listesinde.
///
/// Her sınıf satırının altında kaynakları: "Doğrudan %30 · AFT %12 · …" —
/// "hisse %48" sayısının ne kadarının fonun içinden geldiğini söyler.
/// Döviz satırında doğrudan pay para birimine ayrılır: "USD %2 · EUR %1".
class ZirveIcerikKarti extends ConsumerWidget {
  const ZirveIcerikKarti({
    super.key,
    required this.pay,
    required this.fonDetay,
    required this.varlikDetay,
    this.dis = const EdgeInsets.only(top: SandikSpace.md),
  });

  final Map<String, double> pay;
  final Map<String, double> fonDetay;
  final Map<String, Map<String, double>> varlikDetay;

  /// Çizildiğinde çevresindeki boşluk; çizilmezse boşluk da yok.
  final EdgeInsetsGeometry dis;

  /// Satır altında en çok kaç kaynak adı (gerisi "+n").
  static const kaynakSayisi = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SandikBelirme(child: _govde(context, ref));

  Widget _govde(BuildContext context, WidgetRef ref) {
    if (!ref.watch(fonXrayGorunurProvider)) return const SizedBox.shrink();
    if ((pay['fon'] ?? 0) + (pay['bes'] ?? 0) <= 0) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    if (ref.watch(premiumKilitliProvider)) {
      return Padding(
        padding: dis,
        child: PremiumKilitKarti(
          ikon: Icons.donut_large_rounded,
          baslik: l.ziKilitBaslik,
          govde: l.ziKilitGovde,
          kilitMetni: l.ziKilitSatir,
          kaynak: 'zirve_xray',
        ),
      );
    }
    final kodlar = zirveFonKodlari(fonDetay, varlikDetay).join(',');
    final dagilimlar =
        ref.watch(zirveFonDagilimlariProvider(kodlar)).valueOrNull;
    // Yüklenirken yer kaplamaz; gelince akarak belirir (SandikBelirme).
    if (dagilimlar == null) return const SizedBox.shrink();
    final x = zirveIcerigi(
      pay: pay,
      fonDetay: fonDetay,
      varlikDetay: varlikDetay,
      dagilimlar: dagilimlar,
    );
    // Hiçbir fon açılamadıysa söylenecek bir şey yok: hepsi "bilinmeyen".
    if (!x.acildi) return const SizedBox.shrink();

    final c = context.c;
    final dil = Localizations.localeOf(context).toString();
    final sirali = x.sirali;
    final h = x.hisse();
    final gorunenHisse = h.toplam - h.fonlardan;
    return Padding(
      padding: dis,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l.ziBaslikUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.ziAciklama,
                  style: context.t.bodySmall?.copyWith(color: c.text58),
                ),
                const SizedBox(height: SandikSpace.smd),
                if (h.fonlardan >= 1) ...[
                  Text(
                    l.ziOzetHisse(
                        ZirveKiyas.pay(gorunenHisse), ZirveKiyas.pay(h.toplam)),
                    style: context.t.bodyMedium?.copyWith(
                        color: c.text90, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: SandikSpace.smd),
                ],
                XrayCubugu(
                  paylar: [for (final e in sirali) (e.key, e.value)],
                  disi: x.bilinmeyen,
                ),
                const SizedBox(height: SandikSpace.smd),
                for (final e in sirali) _satir(context, x, e.key, e.value),
                if (x.bilinmeyen >= 0.05)
                  _satir(context, x, null, x.bilinmeyen),
                const SizedBox(height: SandikSpace.sm),
                Text(
                  l.ziKaynak(DateFormat('d MMMM y', dil).format(x.tarih!)),
                  style: context.t.bodySmall?.copyWith(color: c.text36),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sınıf satırı + altında kaynakları. [k] null → içeriği bilinmeyen.
  Widget _satir(BuildContext context, ZirveIcerik x, XrayKova? k, double v) {
    final l = context.l10n;
    final c = context.c;
    final ad = k == null ? l.ziBilinmeyen : zirveGrupAdi(l, k);
    final String alt;
    if (k == null) {
      alt = l.ziBilinmeyenAlt;
    } else {
      final kaynaklar = x.kaynaklariSirali(k);
      final ilk = [
        for (final e in kaynaklar.take(kaynakSayisi))
          '${e.key == zirveDogrudan ? l.ziDogrudan : zirveKurKodu(e.key) ?? e.key} '
              '${ZirveKiyas.pay(e.value)}',
      ];
      final kalan = kaynaklar.length - ilk.length;
      alt = [...ilk, if (kalan > 0) '+$kalan'].join(' · ');
    }
    final yuzde = ZirveKiyas.pay(v);
    return Semantics(
      label: l.ziSatirEtiket(ad, yuzde, alt),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: SandikSpace.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            XrayKovaSatiri(
              kova: k,
              ad: ad,
              renk: k == null ? c.text20.withValues(alpha: 0.5) : null,
              deger: yuzde,
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                  start: SandikSpace.sm + SandikSpace.sm),
              child: Text(
                alt,
                style: context.t.bodySmall?.copyWith(color: c.text58),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sade grup adı (Zirve; `zirveSadeKova` sonrası). Fon X-Ray'in teknik
/// sınıf adları ("Para piyasası / repo", "Kıymetli maden") yerine gündelik
/// dil: kullanıcı başkasının portföyünü bir bakışta anlamalı.
String zirveGrupAdi(AppLocalizations l, XrayKova k) => switch (k) {
      XrayKova.bistHisse => l.ziGrupBistHisse,
      XrayKova.yabanciHisse => l.ziGrupYabanciHisse,
      XrayKova.devletBorclanma || XrayKova.ozelBorclanma => l.ziGrupTahvil,
      XrayKova.dovizBorclanma => l.ziGrupDovizTahvil,
      XrayKova.paraPiyasasi || XrayKova.mevduat => l.ziGrupNakit,
      XrayKova.kiymetliMaden => l.ziGrupAltin,
      XrayKova.fon => l.ziGrupFon,
      XrayKova.gayrimenkulGirisim => l.ziGrupGayrimenkul,
      XrayKova.diger || XrayKova.etiketsiz => l.ziGrupDiger,
      XrayKova.doviz => l.ziGrupDoviz,
      XrayKova.kripto => l.ziGrupKripto,
      XrayKova.emtia => l.ziGrupEmtia,
    };
