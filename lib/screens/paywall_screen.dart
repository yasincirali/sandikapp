import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/preferences_provider.dart';
import '../services/analytics_service.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import '../widgets/custom_loading_indicator.dart';

/// Premium'a geçiş için paywall. Faz 1'de RevenueCat'e bağlanacak;
/// şu an dummy — [_completePurchase] direkt [premiumUnlockedProvider]'ı
/// açar (test amaçlı). Fiyatlar Remote Config'ten dinamik gelir.
///
/// Kullanım:
///   PaywallScreen.show(context, source: 'asset_limit_dialog');
class PaywallScreen extends ConsumerStatefulWidget {
  final String source;
  const PaywallScreen({super.key, required this.source});

  static Future<bool?> show(BuildContext context,
      {required String source}) {
    // Güvenlik ağı: master switch kapalıyken paywall açılmasın. UI trigger'lar
    // zaten gate'leniyor ama merkezi bir noktada da tut.
    if (!RemoteConfigService.instance.paywallEnabled) {
      return Future.value(null);
    }
    AnalyticsService.instance
        .logPremiumUpgradeStarted(source: source);
    return Navigator.of(context).push<bool>(
      adaptiveRoute(
        fullscreenDialog: true,
        builder: (_) => PaywallScreen(source: source),
      ),
    );
  }

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

enum _Plan { monthly, yearly }

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  _Plan _selected = _Plan.yearly;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final rc = RemoteConfigService.instance;
    final priceMonthly = rc.premiumPriceMonthly;
    final priceYearly = rc.premiumPriceYearly;

    return Scaffold(
      backgroundColor: Sandik.background,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 220),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  const _Header(),
                  const SizedBox(height: 28),
                  _HeroCard(),
                  const SizedBox(height: 24),
                  const _FeatureList(),
                  const SizedBox(height: 24),
                  _PlanCard(
                    plan: _Plan.yearly,
                    title: 'Yıllık',
                    price: priceYearly,
                    subtitle: '7 gün ücretsiz dene, sonra otomatik yenilenir',
                    badgeText: '%40 tasarruf',
                    selected: _selected == _Plan.yearly,
                    onTap: () => setState(() => _selected = _Plan.yearly),
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    plan: _Plan.monthly,
                    title: 'Aylık',
                    price: priceMonthly,
                    subtitle: 'İstediğin zaman iptal edebilirsin',
                    badgeText: null,
                    selected: _selected == _Plan.monthly,
                    onTap: () => setState(() => _selected = _Plan.monthly),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Abonelik App Store hesabına yansır. Otomatik yenilenir, '
                    'iptal için Ayarlar → Apple ID → Abonelikler menüsünden '
                    'yönetebilirsin. Yıllık abonelikte ilk 7 gün ücretsiz denemedir; '
                    'iptal etmezsen deneme sonunda ücret tahsil edilir.',
                    style: context.t.bodySmall?.copyWith(
                      color: Sandik.text36,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomBar(
                busy: _busy,
                selectedPlan: _selected,
                onSubscribe: _completePurchase,
                onRestore: _restorePurchases,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _completePurchase() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // FAZ 1 TODO: RevenueCat.purchasePackage() burada çağrılacak.
      // Şu an dummy — direkt premium'u aç ki UI akışını test edebilelim.
      await Future.delayed(const Duration(milliseconds: 600));
      await ref
          .read(premiumUnlockedProvider.notifier)
          .set(true);
      AnalyticsService.instance.logPremiumUpgradeCompleted(
        plan: _selected == _Plan.yearly ? 'yearly' : 'monthly',
      );
      if (!mounted) return;
      await _showSuccessSheet();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restorePurchases() async {
    // FAZ 1 TODO: RevenueCat.restorePurchases()
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Geri yükleme yakında (RevenueCat entegrasyonu ile)',
          style: context.t.bodyLarge,
        ),
        backgroundColor: Sandik.surface2,
      ),
    );
  }

  Future<void> _showSuccessSheet() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Sandik.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Sandik.text36,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Sandik.amber.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Sandik.amber.withValues(alpha: 0.45), width: 2),
                ),
                child: const Icon(Icons.check_rounded,
                    color: Sandik.amber, size: 40),
              ),
              const SizedBox(height: 16),
              Text('Premium açıldı 🎉',
                  style: context.t.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 8),
              Text(
                'Sınırsız varlık, günde 2 sinyal analizi, premium göstergeler ve '
                'daha fazlası açıldı.',
                textAlign: TextAlign.center,
                style: context.t.bodyMedium?.copyWith(
                    color: Sandik.text58, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: Sandik.amber,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(SandikRadius.md)),
                  ),
                  child: Text('Harika',
                      style: context.t.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        const Spacer(),
      ],
    );
  }
}

// ── Hero kart ─────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Sandik.amber.withValues(alpha: 0.18),
            Sandik.gold.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(SandikRadius.lg),
        border: Border.all(color: Sandik.amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Sandik.amber.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(SandikRadius.sm),
              border: Border.all(color: Sandik.amber.withValues(alpha: 0.5)),
            ),
            child: Text(
              'SANDIK PREMIUM',
              style: context.t.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Sandik.amber,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Portföyünü daha derinlemesine\ntakip et',
            style: context.t.headlineLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sınırsız varlık, gelişmiş göstergeler ve günde 2 sinyal analizi.',
            style: context.t.bodyMedium?.copyWith(
              color: Sandik.text58,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feature listesi ───────────────────────────────────────────────────────

class _FeatureList extends StatelessWidget {
  const _FeatureList();

  // ⚠️ BURAYA YALNIZCA UYGULAMADA GERÇEKTEN VAR OLAN ÖZELLİK YAZILIR.
  // Henüz yazılmamış bir özelliği listelemek App Store 2.3.1 (yanıltıcı
  // tanıtım) ihlalidir ve parası alınıp verilmeyen özellik anlamına gelir.
  // Kaldırılanlar (yeniden eklemeden ÖNCE implementasyonu yaz):
  //   - "Aylık AI portföy raporu" → hiçbir servis/edge function yok
  //   - "Fiyat alarmları"        → yalnızca bu ekranda geçiyordu
  //   - "Yıllık vergi PDF raporu" → yalnızca bu ekranda geçiyordu
  static const _features = <(IconData, String)>[
    (Icons.all_inclusive_rounded, 'Sınırsız varlık ve tüm tipler (fon + emtia dahil)'),
    (Icons.trending_up_rounded, 'Premium göstergeler: ADX, Williams %R, CCI'),
    (Icons.notifications_active_outlined, 'Günde 2 sinyal analizi (11:00 + 15:00) + nötr bildirim'),
    (Icons.groups_2_outlined, 'Sınırsız partner paylaşımı'),
    (Icons.timeline_rounded, '5 yıl grafik geçmişi'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in _features) ...[
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Sandik.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Icon(f.$1, color: Sandik.amber, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  f.$2,
                  style: context.t.bodyMedium?.copyWith(
                    color: Colors.white,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// ── Plan kartı ────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final String title;
  final String price;
  final String subtitle;
  final String? badgeText;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.title,
    required this.price,
    required this.subtitle,
    required this.badgeText,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? Sandik.amber.withValues(alpha: 0.12)
              : Sandik.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(
            color: selected
                ? Sandik.amber
                : Colors.white.withValues(alpha: 0.08),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? Sandik.amber : Sandik.text36,
                  width: 2,
                ),
              ),
              child: selected
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Sandik.amber,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: context.t.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      if (badgeText != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Sandik.gain.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(SandikRadius.sm),
                          ),
                          child: Text(
                            badgeText!,
                            style: context.t.labelMedium?.copyWith(
                                letterSpacing: 0,
                                fontWeight: FontWeight.w800,
                                color: Sandik.gain),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: context.t.bodySmall?.copyWith(
                          color: Sandik.text58,
                          height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(price,
                style: context.t.numSmall.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Sandik.gold)),
          ],
        ),
      ),
    );
  }
}

// ── Alt bar (sticky CTA) ──────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final bool busy;
  final _Plan selectedPlan;
  final Future<void> Function() onSubscribe;
  final Future<void> Function() onRestore;

  const _BottomBar({
    required this.busy,
    required this.selectedPlan,
    required this.onSubscribe,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Sandik.background,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: busy ? null : onSubscribe,
                style: FilledButton.styleFrom(
                  backgroundColor: Sandik.amber,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      Sandik.amber.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SandikRadius.md)),
                ),
                child: busy
                    ? const CustomLoadingIndicator(size: 22)
                    : Text(
                        selectedPlan == _Plan.yearly
                            ? '7 gün ücretsiz dene'
                            : 'Premium ol',
                        style: context.t.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: busy ? null : onRestore,
              child: Text('Satın alımı geri yükle',
                  style: context.t.titleSmall?.copyWith(
                      color: Sandik.text58,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
