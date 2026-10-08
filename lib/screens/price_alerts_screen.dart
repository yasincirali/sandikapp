import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../models/price_alert.dart';
import '../providers/portfolio_provider.dart';
import '../providers/price_alert_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/analytics_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../widgets/kapanan_satir.dart';
import '../widgets/alarm_kur_sheet.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_skeleton.dart';
import '../utils/tr_format.dart';
import '../widgets/sandik_error_view.dart';
import '../l10n/l10n.dart';

/// Fiyat alarmları — tüm alarmların LİSTESİ.
///
/// **Neden bu ekran değerli:** alarm, kullanıcının KENDİSİNİN istediği tek
/// bildirimdir. Alaka garantili, opt-out riski yok, ve alarm kuran kullanıcı
/// uygulamayı kurulu bırakmak için bir sebep edinir.
///
/// 2026-09-14: asıl kurma yeri varlık ekranındaki zil oldu (alarm varlığa
/// aittir; üç ekran uzaktaki bir listeden kurulmaz). Burası Bildirimler
/// altında yaşayan genel liste; buradan da kurulabilir (sembol seçtirir).
/// Liste durumu `priceAlertsProvider`'da — varlık ekranı ve Portföy
/// kartındaki zil rozeti aynı kaynağı okur.
///
/// **Sembol seçimi arama değil, kendi varlıklarından.** Kullanıcı sahip
/// olduğu ya da izlediği şeye alarm kurar; boş bir arama kutusu hem fazladan
/// bir adım hem de kaynağın tanımadığı bir sembol girme riski demekti.
class PriceAlertsScreen extends ConsumerStatefulWidget {
  const PriceAlertsScreen({super.key});

  @override
  ConsumerState<PriceAlertsScreen> createState() => _PriceAlertsScreenState();
}

class _PriceAlertsScreenState extends ConsumerState<PriceAlertsScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView(screenName: 'price_alerts');
  }

  /// Alarm kurulabilecek semboller: portföydeki aktif alımlar + takip listesi.
  List<AlarmAdayi> _adaylar() {
    final out = <String, AlarmAdayi>{};

    // `aktifLotlar`: tamamen satılmış pozisyonlar elenir. Ham `isActive`
    // filtresi yetmiyordu — satılan hissenin alım lot'u defterde durduğu
    // için kullanıcı artık tutmadığı bir sembol için alarm kurabiliyordu.
    final assets = aktifLotlar(
        ref.read(portfolioProvider).valueOrNull?.assets ?? const []);
    for (final a in assets) {
      if (!a.isBuy) continue;
      final sembol = alarmSembolu(a.ticker, a.subCategory);
      if (sembol == null) continue;
      out[sembol] = AlarmAdayi(sembol, a.name, a.currentPrice);
    }

    final watch = ref.read(watchlistProvider).valueOrNull ?? const [];
    for (final w in watch) {
      final sembol = alarmSembolu(w.ticker, w.subCategory);
      if (sembol == null) continue;
      out.putIfAbsent(
        sembol,
        () => AlarmAdayi(sembol, w.name, w.currentPrice ?? 0),
      );
    }

    final liste = out.values.toList()
      ..sort((a, b) => a.ad.toLowerCase().compareTo(b.ad.toLowerCase()));
    return liste;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final alarmlar = ref.watch(priceAlertsProvider);
    return Scaffold(
      backgroundColor: c.background,
      appBar: SandikAppBar(
        title: context.l10n.priceAlertsTitle,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.amberFill,
        foregroundColor: c.onAmber,
        // Tema FAB'ı `CircleBorder` yapıyor (main.dart); uzatılmış FAB'a da
        // uygulanınca simge ve yazı dairenin dışına taşıyordu (kullanıcı
        // ekran görüntüsü, 2026-09-21). Uzatılmış biçim stadyum ister.
        shape: const StadiumBorder(),
        extendedPadding: const EdgeInsets.symmetric(horizontal: SandikSpace.lgs),
        onPressed: () => alarmKurAkisi(context, ref, adaylar: _adaylar()),
        icon: const Icon(Icons.add_alert_rounded),
        label: Text(context.l10n.createAlert),
      ),
      body: alarmlar.when(
        error: (e, _) => SandikErrorView(
          error: e,
          onRetry: () => ref.read(priceAlertsProvider.notifier).refresh(),
        ),
        loading: () => const SandikSkeletonList(rows: 5),
        data: (liste) {
          if (liste.isEmpty) return _bosDurum(c);
          return RefreshIndicator.adaptive(
            color: c.amberText,
            onRefresh: () => ref.read(priceAlertsProvider.notifier).refresh(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 8, SandikSpace.screenH(context), 96),
              itemCount: liste.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              // Silinen satır önce kapanır, altındakiler yukarı kayar; sunucu
              // reddederse geri açılır ve sebep söylenir (animasyon denetimi
              // 2026-10-01 — eskiden satır tek karede yok oluyor, hata da
              // yakalanmıyordu).
              itemBuilder: (_, i) => KapananSatir(
                key: ValueKey(liste[i].id),
                child: Builder(
                  builder: (satirCtx) => _AlarmSatiri(
                    alarm: liste[i],
                    onDelete: () async {
                      final id = liste[i].id;
                      SandikHaptic.medium.perform();
                      try {
                        await KapananSatir.kapatVeYap(
                            satirCtx,
                            () => ref
                                .read(priceAlertsProvider.notifier)
                                .delete(id));
                      } catch (e) {
                        if (context.mounted) showAppError(context, e);
                      }
                    },
                    onRearm: () => ref
                        .read(priceAlertsProvider.notifier)
                        .rearm(liste[i].id),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _bosDurum(SandikPalette c) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none_rounded, size: 44, color: c.text36),
              const SizedBox(height: 14),
              Text(
                context.l10n.noAlertsYet,
                style: context.t.headlineSmall?.copyWith(color: c.text90),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.noAlertsBody,
                textAlign: TextAlign.center,
                style: context.t.bodyLarge?.copyWith(color: c.text58),
              ),
            ],
          ),
        ),
      );
}

// ── Alarm satırı ─────────────────────────────────────────────────────────────

class _AlarmSatiri extends StatelessWidget {
  final PriceAlert alarm;
  final VoidCallback onDelete;
  final VoidCallback onRearm;

  const _AlarmSatiri({
    required this.alarm,
    required this.onDelete,
    required this.onRearm,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tetiklendi = alarm.triggeredAt != null;
    // Düz kart: kenar `text20 %22` idi, kartlar arası tek kenar dili
    // saç teli olsun diye `SandikCard`'a geçti (SandikCard 2. tur, 2026-10-08).
    return SandikCard(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.md2, vertical: SandikSpace.smd),
      child: Row(
        children: [
          // Yön RENKLE anlatılmaz — ok her zaman var.
          Text(
            alarm.isAbove ? '▲' : '▼',
            style: context.t.titleMedium?.copyWith(
              color: tetiklendi ? c.text36 : (alarm.isAbove ? c.gain : c.loss),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alarm.label,
                  style: context.t.titleMedium?.copyWith(color: c.text90),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  tetiklendi
                      ? 'Çalıştı · ${fmtTRYFiyat(alarm.targetPrice)}'
                      : '${alarm.isAbove ? "Üstüne çıkınca" : "Altına inince"}'
                          ' · ${fmtTRYFiyat(alarm.targetPrice)}',
                  style: context.t.bodyMedium?.copyWith(color: c.text58),
                ),
              ],
            ),
          ),
          if (tetiklendi)
            TextButton(onPressed: onRearm, child: Text(context.l10n.recreateAlert)),
          IconButton(
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline_rounded, color: c.text36),
            tooltip: 'Sil',
          ),
        ],
      ),
    );
  }
}
