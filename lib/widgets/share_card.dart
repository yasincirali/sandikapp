import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/analytics_service.dart';
import '../services/recap_service.dart' show PortfolioCharacter;
import '../services/share_card_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../l10n/l10n.dart';

/// Paylaşım kartının içeriği — TUTAR YOK.
///
/// Kural (`_PaylasButonu` notu): tutarlı kart paylaşılmaz, tutarsız kart
/// paylaşılır. Yüzde, karakter, enflasyon farkı ve dilim yeter; para
/// miktarı bir kez dışarı çıktı mı geri alınamaz. `share_card_test` bu
/// dosyada para biçimleyici ve lira simgesi bulunmadığını kilitler.
@immutable
class ShareCardData {
  const ShareCardData({
    required this.baslik,
    this.degisimPct,
    this.degisimEtiketi = 'Portföy değişimi',
    this.karakter,
    this.enflasyonPuan,
    this.takipGunu,
    this.percentile,
  });

  /// "Son 1 yıl", "2026 Özetim".
  final String baslik;
  final double? degisimPct;
  final String degisimEtiketi;
  final PortfolioCharacter? karakter;
  final double? enflasyonPuan;
  final int? takipGunu;

  /// 1 = en üst. "Yatırımcıların %X'inden iyi" satırı için.
  final int? percentile;

  bool get bos =>
      degisimPct == null &&
      karakter == null &&
      enflasyonPuan == null &&
      (takipGunu ?? 0) <= 0 &&
      percentile == null;
}

/// Paylaşılan görsel. Boyut SABİT (4:5 — Instagram/WhatsApp kartı) ve renk
/// paleti KOYU: alıcı uygulamanın temasını bilmez, marka dark-first.
/// `context.c` burada bilerek kullanılmıyor — light temadaki kullanıcı da
/// aynı koyu kartı paylaşır; tipografi yine `context.t`'den (DM Sans).
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.data, this.tarih});

  final ShareCardData data;

  /// Kartın altındaki tarih; test için enjekte edilir.
  final DateTime? tarih;

  static const width = 320.0;
  static const height = 400.0;

  @override
  Widget build(BuildContext context) {
    const p = SandikPalette.dark;
    final d = data;
    final pct = d.degisimPct;
    final pozitif = (pct ?? 0) >= 0;
    final tarih = this.tarih ?? DateTime.now();

    // Kart bir DIŞA AKTARIMDIR (sabit 320×400): sistemin metin ölçeği
    // burada yok sayılmaz (HIG — `touch_target_size_test` bunu kilitler)
    // ama SINIRLANIR: 1,3× üstü sabit kutuda taşar ve alıcı görseli zaten
    // kendi ekranında kendi ölçeğiyle görür. Önizleme sayfasının başlığı ve
    // düğmeleri tam ölçeğe uyar; yalnızca kart sınırlıdır.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(SandikSpace.xl),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [p.background, p.surface1],
          ),
          borderRadius: BorderRadius.circular(SandikRadius.lg),
        ),
        child: DefaultTextStyle(
          style: context.t.bodyMedium!.copyWith(color: p.text90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wordmark + dönem — tek satır, sabit.
              Row(
                children: [
                  Text(
                    'sandık',
                    style: context.t.titleLarge?.copyWith(
                      color: p.gold,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: SandikSpace.md),
                  Expanded(
                    child: Text(
                      d.baslik,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: context.t.labelLarge?.copyWith(
                        color: p.text58,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
              // Orta bölüm ölçeğe dayanıklı: içerik sabit kutuya sığmazsa
              // (büyük metin ölçeği, dört satır + iki satırlık tagline) bütün
              // olarak küçülür; sığıyorsa doğal boyutunda, dikeyde ortalı.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, kutu) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: kutu.maxWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (pct != null) ...[
                            Text(
                              d.degisimEtiketi.toUpperCase(),
                              style: context.t.labelLarge?.copyWith(
                                color: p.text58,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: SandikSpace.xs),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${pozitif ? '+' : '−'}%'
                                '${fmtNum(pct.abs(), digits: 2)}',
                                style: context.t.numLarge.copyWith(
                                  fontSize: 56,
                                  height: 1,
                                  color: pozitif ? p.gain : p.loss,
                                  letterSpacing: -1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: SandikSpace.lg),
                          ],
                          if (d.karakter != null) ...[
                            _Satir(
                              ikon: Icons.auto_awesome_rounded,
                              renk: p.amberText,
                              metin:
                                  '${d.karakter!.label} — ${d.karakter!.tagline}',
                            ),
                            const SizedBox(height: SandikSpace.sm),
                          ],
                          if (d.enflasyonPuan != null) ...[
                            _Satir(
                              ikon: Icons.trending_up_rounded,
                              renk: d.enflasyonPuan! >= 0 ? p.gain : p.loss,
                              metin: d.enflasyonPuan! >= 0
                                  ? context.l10n.aheadOfInflationPts(
                                      fmtNum(d.enflasyonPuan!, digits: 1))
                                  : context.l10n.behindInflationPts(
                                      fmtNum(d.enflasyonPuan!.abs(), digits: 1)),
                            ),
                            const SizedBox(height: SandikSpace.sm),
                          ],
                          if (d.percentile != null) ...[
                            _Satir(
                              ikon: Icons.groups_rounded,
                              renk: p.info,
                              metin: context.l10n.betterThanPctInvestors(100 - d.percentile!),
                            ),
                            const SizedBox(height: SandikSpace.sm),
                          ],
                          if ((d.takipGunu ?? 0) > 0)
                            _Satir(
                              ikon: Icons.calendar_month_rounded,
                              renk: p.text58,
                              metin: context.l10n.nDaysTracked(d.takipGunu!),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Divider(color: p.hairline, height: 1),
              const SizedBox(height: SandikSpace.smd),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.trackingWithSandik,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall?.copyWith(color: p.text58),
                    ),
                  ),
                  const SizedBox(width: SandikSpace.sm),
                  Text(
                    DateFormat('d MMM yyyy', 'tr_TR').format(tarih),
                    maxLines: 1,
                    style: context.t.bodySmall?.copyWith(color: p.text36),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({required this.ikon, required this.renk, required this.metin});
  final IconData ikon;
  final Color renk;
  final String metin;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 16, color: renk),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: Text(
              metin,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodyMedium?.copyWith(
                color: SandikPalette.dark.text90,
                height: 1.3,
              ),
            ),
          ),
        ],
      );
}

/// Önizleme + iki paylaşım yolu.
///
/// Eskiden "Özetini paylaş" doğrudan dört satırlık metni sistem sayfasına
/// veriyordu — kullanıcı ne paylaştığını görmüyordu ve sonuç "arkası boş"
/// hissi veriyordu (2026-09-14 geri bildirimi). Şimdi kart önce gösterilir;
/// görsel varsayılan yol, metin yedek (görsel almayan hedefler için).
Future<void> showShareSheet(
  BuildContext context, {
  required ShareCardData data,
  required String metin,
  required String subject,
  required String analyticsPeriod,
}) {
  final key = GlobalKey();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.c.surface1,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => _ShareSheet(
      boundaryKey: key,
      data: data,
      metin: metin,
      subject: subject,
      analyticsPeriod: analyticsPeriod,
    ),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.boundaryKey,
    required this.data,
    required this.metin,
    required this.subject,
    required this.analyticsPeriod,
  });

  final GlobalKey boundaryKey;
  final ShareCardData data;
  final String metin;
  final String subject;
  final String analyticsPeriod;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _mesgul = false;

  Future<void> _gorsel() async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    try {
      final png = await ShareCardService.renderPng(widget.boundaryKey);
      await AnalyticsService.instance
          .logRecapShared(period: widget.analyticsPeriod, channel: 'image');
      await ShareCardService.shareImage(
        png,
        text: widget.metin,
        subject: widget.subject,
      );
    } catch (e) {
      if (mounted) {
        sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _metin() async {
    await AnalyticsService.instance
        .logRecapShared(period: widget.analyticsPeriod, channel: 'text');
    await ShareCardService.shareText(widget.metin, subject: widget.subject);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.lg, SandikSpace.smd, SandikSpace.lg, SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.text20,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: SandikSpace.md),
            Text(
              'Özetini paylaş',
              style: context.t.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: c.text90,
              ),
            ),
            const SizedBox(height: SandikSpace.xs),
            Text(
              context.l10n.shareCardNoAmounts,
              style: context.t.bodySmall?.copyWith(color: c.text58),
            ),
            const SizedBox(height: SandikSpace.md),
            // Kart gerçek boyutunda çizilir (PNG bu ağaçtan alınır), dar
            // ekranda yalnızca önizleme küçültülür — piksel boyutu değişmez.
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RepaintBoundary(
                  key: widget.boundaryKey,
                  child: ShareCard(data: widget.data),
                ),
              ),
            ),
            const SizedBox(height: SandikSpace.lg),
            FilledButton.icon(
              onPressed: _mesgul ? null : _gorsel,
              icon: const Icon(Icons.image_rounded, size: 18),
              label: Text(_mesgul ? context.l10n.preparingEllipsis : context.l10n.shareAsImage),
            ),
            const SizedBox(height: SandikSpace.sm),
            TextButton.icon(
              onPressed: _mesgul ? null : _metin,
              icon: const Icon(Icons.notes_rounded, size: 18),
              label: Text(context.l10n.shareAsText),
            ),
          ],
        ),
      ),
    );
  }
}
