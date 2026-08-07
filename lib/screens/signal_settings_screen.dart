import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset_type.dart';
import '../models/signal_frequency.dart';
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
    final schedules = ref.watch(signalScheduleProvider);
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
              borderRadius: BorderRadius.circular(SandikRadius.md),
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
                      onChanged: (v) async {
                        await ref
                            .read(signalNeutralPushProvider.notifier)
                            .set(v);
                        // Sunucu analizi bu tercihi de okur — tüm türler
                        // için satırları güncelle.
                        await syncNeutralPushPreference(ref);
                      },
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
              schedule: schedules[type] ?? kDefaultSchedule,
              onFrequencyChanged: (f) => ref
                  .read(signalScheduleProvider.notifier)
                  .setFrequency(type, f),
              onHoursChanged: (h) =>
                  ref.read(signalScheduleProvider.notifier).setHours(type, h),
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
        borderRadius: BorderRadius.circular(SandikRadius.md),
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
  final SignalSchedule schedule;
  final void Function(SignalFrequency freq) onFrequencyChanged;
  final void Function(List<int> hours) onHoursChanged;

  const _CategorySection({
    required this.type,
    required this.selected,
    required this.premiumUnlocked,
    required this.paywallVisible,
    required this.threshold,
    required this.onToggle,
    required this.onThresholdChanged,
    required this.schedule,
    required this.onFrequencyChanged,
    required this.onHoursChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
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
          _FrequencyRow(
            type: type,
            schedule: schedule,
            onFrequencyChanged: onFrequencyChanged,
            onHoursChanged: onHoursChanged,
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

/// Bildirim sıklığı satırı: sıklık seçimi + (gerekiyorsa) saat seçimi.
///
/// Saatler TR 10:00–18:00 penceresiyle sınırlıdır; bu kısıt hem burada hem
/// sunucudaki check constraint'te vardır (bkz. 0024_signal_frequency.sql).
class _FrequencyRow extends StatelessWidget {
  final AssetType type;
  final SignalSchedule schedule;
  final void Function(SignalFrequency freq) onFrequencyChanged;
  final void Function(List<int> hours) onHoursChanged;

  const _FrequencyRow({
    required this.type,
    required this.schedule,
    required this.onFrequencyChanged,
    required this.onHoursChanged,
  });

  String _saatMetni(int h) => '${h.toString().padLeft(2, '0')}:00';

  Future<void> _saatSec(BuildContext context) async {
    final freq = schedule.frequency;
    final secili = <int>[...schedule.hours];

    final sonuc = await showModalBottomSheet<List<int>>(
      context: context,
      backgroundColor: Sandik.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final tam = secili.length == freq.hourCount;
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Sandik.text36,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    freq.hourCount == 1
                        ? 'Bildirim saatini seç'
                        : 'İki bildirim saati seç',
                    style: context.t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bildirimler yalnızca '
                    '${_saatMetni(kSignalWindowStart)}–'
                    '${_saatMetni(kSignalWindowEnd)} arasında gönderilir.',
                    style: context.t.bodySmall
                        ?.copyWith(color: Sandik.text58, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  // Seçili saatler her zaman görünür — kapasite dolduğunda
                  // hangi saatin değişeceği tahmin edilmesin diye.
                  Text(
                    secili.isEmpty
                        ? 'Henüz saat seçilmedi'
                        : 'Seçili: ${([...secili]..sort()).map(_saatMetni).join("  •  ")}',
                    style: context.t.bodySmall?.copyWith(
                        color: secili.isEmpty ? Sandik.text36 : Sandik.amber,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final h in signalSelectableHours)
                        _SaatChip(
                          label: _saatMetni(h),
                          secili: secili.contains(h),
                          onTap: () => setSheet(() {
                            if (secili.contains(h)) {
                              // "Günde 1"de tek saat zorunlu: son kalanı
                              // kaldırmak kullanıcıyı geçersiz duruma
                              // sokar, dokunuşu yok say.
                              if (secili.length > 1 || freq.hourCount > 1) {
                                secili.remove(h);
                              }
                            } else {
                              // Kapasite dolduysa en eskiyi çıkar — kullanıcı
                              // önce silmek zorunda kalmasın. Hangi saatin
                              // düştüğü yukarıdaki "Seçili:" satırında görülür.
                              if (secili.length >= freq.hourCount) {
                                secili.removeAt(0);
                              }
                              secili.add(h);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Sandik.amber,
                          disabledBackgroundColor:
                              Sandik.amber.withValues(alpha: 0.3)),
                      onPressed: tam
                          ? () => Navigator.pop(ctx, [...secili]..sort())
                          : null,
                      child: Text(tam
                          ? 'Kaydet'
                          : '${freq.hourCount} saat seçmelisin '
                              '(${secili.length}/${freq.hourCount})'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (sonuc != null && sonuc.isNotEmpty) onHoursChanged(sonuc);
  }

  @override
  Widget build(BuildContext context) {
    final freq = schedule.frequency;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bildirim sıklığı',
            style: context.t.titleSmall?.copyWith(
                color: Sandik.text58, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          // Liste seçimi (Wrap+chip DEĞİL).
          //
          // Chip'ler iki sorun çıkarıyordu:
          //   1. Seçili chip'in fontWeight'i değişince genişliği de değişiyor,
          //      Wrap satırları yeniden hesaplıyor ve TÜM chip'ler yer
          //      değiştiriyordu. Kullanıcı bir seçeneğe basınca diğerlerinin
          //      kayması, yanlış öğeye basmaya yol açan bir hata.
          //   2. HIG segmented control'ü 2-5 seçenek için önerir ama etiketler
          //      uzun ("2 saatte bir", "Günde 2 kez"); 5'ini yan yana
          //      sıkıştırmak okunaksız olurdu.
          //
          // Liste düzeni her satırı sabit yükseklikte tutar — seçim değişince
          // hiçbir şey kaymaz. iOS Ayarlar'ın kendi seçim deseni de budur.
          Container(
            decoration: BoxDecoration(
              color: Sandik.surface2,
              borderRadius: BorderRadius.circular(SandikRadius.sm),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < SignalFrequency.values.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 12,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  _FrequencyOption(
                    frequency: SignalFrequency.values[i],
                    secili: SignalFrequency.values[i] == freq,
                    // Saat gerektiren sıklıkta seçili satırın altında
                    // saatler gösterilir — ayrı bir kutu aramaya gerek kalmaz.
                    hoursLabel: SignalFrequency.values[i] == freq &&
                            freq.needsHourPicker
                        ? schedule.hours.map(_saatMetni).join('  •  ')
                        : null,
                    onTap: () => onFrequencyChanged(SignalFrequency.values[i]),
                    onHoursTap: () => _saatSec(context),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (!freq.needsHourPicker)
            Text(
              '${freq.description} — '
              '${_saatMetni(kSignalWindowStart)}–'
              '${_saatMetni(kSignalWindowEnd)} arası.',
              style: context.t.bodySmall
                  ?.copyWith(color: Sandik.text36, height: 1.4),
            ),
        ],
      ),
    );
  }
}

/// Sıklık listesinde tek satır.
///
/// Tasarım notu: seçili/seçili değil farkı YALNIZCA renk ve onay işaretiyle
/// anlatılır — font ağırlığı sabit kalır. Ağırlık değişimi metnin genişliğini
/// değiştirir ve satırın yeniden ölçülmesine yol açardı; chip düzenindeki
/// kayma sorununun kökü tam olarak buydu.
///
/// Dokunma hedefi en az 44pt (HIG minimumu).
class _FrequencyOption extends StatelessWidget {
  final SignalFrequency frequency;
  final bool secili;

  /// Seçili ve saat gerektiren sıklıkta gösterilecek saat metni.
  /// null ise saat satırı çizilmez.
  final String? hoursLabel;
  final VoidCallback onTap;
  final VoidCallback onHoursTap;

  const _FrequencyOption({
    required this.frequency,
    required this.secili,
    required this.hoursLabel,
    required this.onTap,
    required this.onHoursTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: secili,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    // Onay işareti sabit genişlikte bir kutuda durur; görünüp
                    // kaybolması metni ittirmez.
                    SizedBox(
                      width: 22,
                      child: secili
                          ? const Icon(Icons.check_rounded,
                              size: 18, color: Sandik.amber)
                          : null,
                    ),
                    Expanded(
                      child: Text(
                        frequency.label,
                        style: context.t.bodyMedium?.copyWith(
                          color: secili ? Sandik.amber : Colors.white,
                          // Ağırlık BİLİNÇLİ olarak sabit — bkz. sınıf notu.
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (hoursLabel != null)
                InkWell(
                  onTap: onHoursTap,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.fromLTRB(34, 0, 12, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule_rounded,
                            size: 15, color: Sandik.text58),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hoursLabel!,
                            style: context.t.bodySmall?.copyWith(
                                color: Colors.white, height: 1.3),
                          ),
                        ),
                        Text(
                          'Değiştir',
                          style: context.t.labelMedium?.copyWith(
                              color: Sandik.amber, letterSpacing: 0),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            size: 16, color: Sandik.text36),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seçilebilir çip — saat seçim sayfasında kullanılır.
class _SaatChip extends StatelessWidget {
  final String label;
  final bool secili;
  final VoidCallback onTap;
  const _SaatChip({
    required this.label,
    required this.secili,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: secili,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          // 44pt HIG minimum dokunma hedefi.
          constraints: const BoxConstraints(minHeight: 44, minWidth: 72),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: secili
                ? Sandik.amber.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(SandikRadius.sm),
            border: Border.all(
              color: secili
                  ? Sandik.amber.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            label,
            style: context.t.bodySmall?.copyWith(
              color: secili ? Sandik.amber : Sandik.text58,
              // Ağırlık SABİT: seçimle değişirse metin genişler, chip büyür
              // ve Wrap tüm satırı yeniden dizer. Seçim rengi zaten yeterli
              // ayrım sağlıyor.
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
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
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
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
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
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
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
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
        borderRadius: BorderRadius.circular(SandikRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final opt in kSignalThresholdOptions)
            GestureDetector(
              onTap: () => onChanged(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: SandikMotion.enter,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: value == opt
                      ? Sandik.amber.withValues(alpha: 0.20)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
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
