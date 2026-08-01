import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset_type.dart';
import '../providers/preferences_provider.dart';
import '../services/analytics_service.dart';
import '../services/remote_config_service.dart';
import '../services/technical_analysis_service.dart';
import '../theme/sandik.dart';
import '../widgets/disclaimer_widget.dart';
import 'paywall_screen.dart';

/// Kullanıcı her varlık türü için hangi teknik göstergelerin sinyal üretmesini
/// istediğini seçer. Premium göstergeler premium olmayan kullanıcıya kilitli
/// görünür — açmak için Premium'a geçmesi gerekir.
class SignalSettingsScreen extends ConsumerWidget {
  const SignalSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(indicatorPrefsProvider);
    final premium = ref.watch(premiumUnlockedProvider);
    final paywallOn = ref.watch(paywallVisibleProvider);
    final thresholds = ref.watch(signalThresholdProvider);
    final neutralPush = ref.watch(signalNeutralPushProvider);

    return Scaffold(
      backgroundColor: Sandik.background,
      appBar: AppBar(
        backgroundColor: Sandik.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Sinyal Ayarları',
          style: context.t.headlineMedium?.copyWith(
            color: Colors.white,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          const DisclaimerWidget(),
          const SizedBox(height: 16),

          // ── Premium banner (paywall kapalıysa hiç gösterilmez) ───────────
          if (paywallOn) ...[
            _PremiumCard(
              unlocked: premium,
              onToggle: () => ref
                  .read(premiumUnlockedProvider.notifier)
                  .set(!premium),
            ),
            const SizedBox(height: 24),
          ],

          // â”€â”€ Genel bildirim ayarlarÄ± â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Sandik.surface1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Nötr sinyalleri de bildir',
                              style: context.t.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                          const SizedBox(height: 3),
                          Text(
                            'Kapalıyken sadece AL/SAT bildirimi gelir. Nötr sinyaller yine geçmişe yazılır.',
                            style: context.t.bodySmall?.copyWith(
                                color: Sandik.text58,
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: neutralPush,
                      activeColor: Sandik.amber,
                      onChanged: (v) => ref
                          .read(signalNeutralPushProvider.notifier)
                          .set(v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Her varlık türü için hangi göstergelerin sinyal üretmesini istediğini ve bildirim güven eşiğini seç.',
            style: context.t.titleSmall?.copyWith(
                color: Sandik.text58, height: 1.5),
          ),
          const SizedBox(height: 16),

          for (final type in RemoteConfigService.instance.visibleAssetTypes) ...[
            _CategorySection(
              type: type,
              selected: prefs[type] ??
                  TechnicalAnalysisService.defaultEnabledFor(type),
              // Paywall kapalıyken herkes premium'muş gibi davranır (kilit yok,
              // "PREMIUM" chip'i yok). Store hazır olunca RC'den açılır.
              premiumUnlocked: !paywallOn || premium,
              paywallVisible: paywallOn,
              threshold:
                  thresholds[type] ?? kSignalThresholdDefault,
              onToggle: (id) => ref
                  .read(indicatorPrefsProvider.notifier)
                  .toggle(type, id),
              onThresholdChanged: (v) => ref
                  .read(signalThresholdProvider.notifier)
                  .setForType(type, v),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

class _PremiumCard extends StatelessWidget {
  final bool unlocked;
  final VoidCallback onToggle;
  const _PremiumCard({required this.unlocked, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: unlocked
              ? [Sandik.amber.withValues(alpha: 0.18), Sandik.amber.withValues(alpha: 0.05)]
              : [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.02)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unlocked
              ? Sandik.amber.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(
            unlocked ? Icons.workspace_premium_rounded : Icons.lock_outline_rounded,
            color: unlocked ? Sandik.amber : Sandik.text58,
            size: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unlocked ? 'Premium aktif' : 'Premium göstergeler',
                  style: context.t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unlocked
                      ? 'ADX, Williams %R ve CCI göstergeleri kullanılabilir.'
                      : 'ADX, Williams %R, CCI göstergelerini açmak için Premium\'a geç.',
                  style: context.t.bodySmall?.copyWith(
                      color: Sandik.text58, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onToggle,
            style: TextButton.styleFrom(
              backgroundColor:
                  unlocked ? Colors.white.withValues(alpha: 0.08) : Sandik.amber,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: Text(
              unlocked ? 'Kapat' : 'Aç',
              style: TextStyle(
                color: unlocked ? Colors.white : Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final AssetType type;
  final Set<String> selected;
  final bool premiumUnlocked;
  final bool paywallVisible;
  final int threshold;
  final void Function(String id) onToggle;
  final void Function(int threshold) onThresholdChanged;

  const _CategorySection({
    required this.type,
    required this.selected,
    required this.premiumUnlocked,
    required this.paywallVisible,
    required this.threshold,
    required this.onToggle,
    required this.onThresholdChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(type.icon, size: 18, color: type.color),
                const SizedBox(width: 10),
                Text(
                  type.label,
                  style: context.t.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                Text(
                  'Bildirim eşiği',
                  style: context.t.titleSmall?.copyWith(
                      color: Sandik.text58,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                _ThresholdSegment(
                  value: threshold,
                  onChanged: onThresholdChanged,
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: Colors.white.withValues(alpha: 0.05),
          ),
          for (final id in IndicatorId.all)
            _IndicatorRow(
              id: id,
              checked: selected.contains(id),
              locked: IndicatorId.premium.contains(id) && !premiumUnlocked,
              recommended: IndicatorId.recommendedFor(type).contains(id),
              showPremiumChip: paywallVisible,
              onTap: () {
                if (IndicatorId.premium.contains(id) && !premiumUnlocked) {
                  AnalyticsService.instance
                      .logPremiumGateShown(feature: 'indicator_$id');
                  PaywallScreen.show(context,
                      source: 'signal_settings_$id');
                  return;
                }
                onToggle(id);
              },
            ),
        ],
      ),
    );
  }
}

class _IndicatorRow extends StatelessWidget {
  final String id;
  final bool checked;
  final bool locked;
  final bool recommended;
  final bool showPremiumChip;
  final VoidCallback onTap;

  const _IndicatorRow({
    required this.id,
    required this.checked,
    required this.locked,
    required this.recommended,
    required this.showPremiumChip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(
              locked
                  ? Icons.lock_outline_rounded
                  : (checked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded),
              color: locked
                  ? Sandik.text36
                  : (checked ? Sandik.amber : Sandik.text58),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                IndicatorId.labelOf(id),
                style: context.t.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: locked ? Sandik.text36 : Colors.white,
                ),
              ),
            ),
            if (recommended && !IndicatorId.premium.contains(id))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'ÖNERİLEN',
                  style: context.t.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.green,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            if (IndicatorId.premium.contains(id)) ...[
              if (recommended) const SizedBox(width: 6),
              if (recommended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ÖNERİLEN',
                    style: context.t.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.green,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              if (showPremiumChip && recommended) const SizedBox(width: 6),
              if (showPremiumChip)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Sandik.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'PREMIUM',
                    style: context.t.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Sandik.amber,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThresholdSegment extends StatelessWidget {
  final int value;
  final void Function(int) onChanged;

  const _ThresholdSegment({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final opt in kSignalThresholdOptions)
            GestureDetector(
              onTap: () => onChanged(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: value == opt
                      ? Sandik.amber.withValues(alpha: 0.20)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: value == opt
                        ? Sandik.amber.withValues(alpha: 0.55)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  '%$opt',
                  style: context.t.titleSmall?.copyWith(
                    fontWeight:
                        value == opt ? FontWeight.w800 : FontWeight.w600,
                    color: value == opt
                        ? Sandik.amber
                        : Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
