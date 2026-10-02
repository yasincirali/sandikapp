import 'dart:async';

import 'package:flutter/material.dart';

import '../config/surum_notlari.dart';
import '../services/analytics_service.dart';
import '../services/surum_notu_service.dart';
import '../theme/sandik.dart';

/// "Yenilikler" — güncelleme sonrası neyin değiştiğini anlatan sheet.
///
/// **Ton kuralı** (`MilestoneSheet` ile aynı): fintech tonunda kalınır.
/// Kutlama dili, emoji seli, "🎉 Harika haber!" yok. Kullanıcı ne
/// değiştiğini öğrenmeye geliyor; metin kısa ve somut olmalı.
///
/// **Gösterim politikası** `SurumNotuService`'te (bkz. `yeniNotlar`): ilk
/// kurulumda açılmaz, aynı sürüm ikinci kez açılmaz, yalnızca `onemli`
/// sürümler kendiliğinden açılır. Bu widget o kararı VERMEZ, yalnızca
/// sunar — karar mantığı saf ve test edilebilir kalsın diye.
class YeniliklerSheet extends StatefulWidget {
  const YeniliklerSheet({super.key, required this.notlar});

  final List<SurumNotu> notlar;

  /// Kendiliğinden açılan sayfada görünen madde sayısı; gerisi "Tüm
  /// değişiklikler" altında katlı durur.
  ///
  /// **Neden (2026-10-02 müşteri testi):** 1.1.6 notu 44 madde; App
  /// Store'daki 1.0.5'ten güncelleyen herkese otomatik açılıyor ve altı ekran
  /// kaydırma sürüyordu — kullanıcı büyük ihtimalle okumadan "Anladım"a
  /// basar. Liste zaten en önemli önce yazılır; ilk altısı sürümün asıl
  /// hikâyesi.
  static const oneCikanSayisi = 6;

  /// Sheet'i açar ve kapanışta "görüldü" işaretini yazar.
  ///
  /// İşaret KAPANIŞTA yazılır, açılışta değil: kullanıcı sheet'i görmeden
  /// uygulama çökerse ya da öldürülürse not bir daha gösterilmezdi.
  static Future<void> goster(
    BuildContext context,
    List<SurumNotu> notlar,
  ) async {
    if (notlar.isEmpty) return;
    // Beklenmiyor: analitik yazımı sheet'in açılmasını geciktirmemeli.
    unawaited(AnalyticsService.instance.logWhatsNewShown(
      surum: notlar.first.surum,
      adet: notlar.length,
    ));
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => YeniliklerSheet(notlar: notlar),
    );
    await SurumNotuService.instance.goruldu();
  }

  @override
  State<YeniliklerSheet> createState() => _YeniliklerSheetState();
}

class _YeniliklerSheetState extends State<YeniliklerSheet> {
  bool _tumu = false;

  List<SurumNotu> get notlar => widget.notlar;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final toplam = notlar.fold<int>(0, (n, s) => n + s.yenilikler.length);
    final katli = !_tumu && toplam > YeniliklerSheet.oneCikanSayisi;
    // Sürümler arası sıra korunur; sayaç tüm sürümlerin maddelerini sayar.
    var gosterilen = 0;
    // Uzun liste ekranı taşırmasın: tek sürümde dört madde rahat sığar ama
    // atlanan sürümler biriktiğinde (1.0 → 1.3) liste uzar.
    final maxH = MediaQuery.of(context).size.height * 0.75;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SandikRadius.lg),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        SandikSpace.lg,
        SandikSpace.md,
        SandikSpace.lg,
        SandikSpace.lg + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: const SandikTutamac(),
          ),
          const SizedBox(height: SandikSpace.lg),
          Text(
            'Yenilikler',
            style: context.t.headlineMedium?.copyWith(color: c.text90),
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            _altBaslik(),
            style: context.t.bodyMedium?.copyWith(color: c.text58),
          ),
          const SizedBox(height: SandikSpace.lg),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < notlar.length; i++) ...[
                    // Tek sürüm gösteriliyorsa sürüm başlığı gereksiz —
                    // üstteki alt başlık zaten onu söylüyor.
                    if (notlar.length > 1) ...[
                      if (i > 0) const SizedBox(height: SandikSpace.md),
                      Text(
                        'Sürüm ${notlar[i].surum} · ${notlar[i].tarih}',
                        style: context.t.labelMedium?.copyWith(color: c.text36),
                      ),
                      const SizedBox(height: SandikSpace.sm),
                    ],
                    for (final y in notlar[i].yenilikler)
                      if (!katli ||
                          gosterilen++ < YeniliklerSheet.oneCikanSayisi) ...[
                        _YenilikSatiri(yenilik: y),
                        const SizedBox(height: SandikSpace.md),
                      ],
                  ],
                  if (katli)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _tumu = true),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text('Tüm değişiklikler '
                            '(${toplam - YeniliklerSheet.oneCikanSayisi} madde daha)'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.amberFill,
              foregroundColor: c.onAmber,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Anladım'),
          ),
        ],
      ),
    );
  }

  String _altBaslik() {
    if (notlar.length == 1) {
      final n = notlar.first;
      return n.baslik ?? 'Sürüm ${n.surum} · ${n.tarih}';
    }
    return 'Son ${notlar.length} sürümde eklenenler';
  }
}

class _YenilikSatiri extends StatelessWidget {
  const _YenilikSatiri({required this.yenilik});

  final Yenilik yenilik;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Sabit `switch` — tree-shake'in ikonları eleyebilmesi için ikonlar
    // burada DOĞRUDAN yazılmalı (bkz. `YenilikIkonu`).
    final ikon = switch (yenilik.ikon) {
      YenilikIkonu.bildirim => Icons.notifications_active_rounded,
      YenilikIkonu.grafik => Icons.trending_up_rounded,
      YenilikIkonu.para => Icons.savings_rounded,
      YenilikIkonu.liste => Icons.inbox_rounded,
      YenilikIkonu.ayar => Icons.tune_rounded,
      YenilikIkonu.guvenlik => Icons.lock_rounded,
      YenilikIkonu.genel => Icons.auto_awesome_rounded,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.amberFill.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(SandikRadius.md),
          ),
          child: Icon(ikon, size: 18, color: c.amberText),
        ),
        const SizedBox(width: SandikSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                yenilik.baslik,
                style: context.t.titleMedium?.copyWith(
                  color: c.text90,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                yenilik.aciklama,
                style: context.t.bodyMedium?.copyWith(color: c.text58),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
