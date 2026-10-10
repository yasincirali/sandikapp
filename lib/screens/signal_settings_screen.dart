import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset_type.dart';
import '../models/signal_frequency.dart';
import '../providers/preferences_provider.dart';
import '../providers/sinyal_on_ayar_provider.dart';
import '../services/analytics_service.dart';
import '../services/remote_config_service.dart';
import '../widgets/sandik_acilir.dart';
import '../services/technical_analysis_service.dart';
import '../theme/sandik.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/sandik_segment.dart';
import 'paywall_screen.dart';
import '../l10n/l10n.dart';

/// Kullanıcı her varlık türü için hangi teknik göstergelerin sinyal üretmesini
/// istediğini seçer. Premium göstergeler premium olmayan kullanıcıya kilitli
/// görünür — açmak için Premium'a geçmesi gerekir.
class SignalSettingsScreen extends ConsumerWidget {
  const SignalSettingsScreen({super.key});

  /// Ekran başlığı — kilitli ve açık gövde aynı metni kullanır.
  static const _baslik = 'Sinyal Ayarları';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Premium modeli (yasin 2026-10-10): paywall açıkken ücretsiz kullanıcı
    // ekranı GÖRÜR — RSI, MACD ve Bollinger'ı seçip ekranda kullanır; kalan
    // beş gösterge, periyot ayarları ve bütün bildirim ayarları Premium.
    // Eskiden ekranın tamamı tek kilit kartıydı ("sinyal tamamen Premium").
    // Kayıtlı tercihler silinmez, Premium'da aynen geri gelir.
    final prefs = ref.watch(indicatorPrefsProvider);
    // Gerçek hak (mağaza/sunucu/admin). Eskiden cihazdaki geliştirici
    // anahtarıydı ve aşağıdaki kartın "Aç" düğmesi onu açıyordu: paywall
    // açıkken herkes ödemesiz Premium alırdı (2026-10-06 bulgusu).
    final premium = ref.watch(premiumErisimProvider);
    final paywallOn = ref.watch(paywallVisibleProvider);
    final gelistirici = ref.watch(gelistiriciAnahtariSayilirProvider);
    final thresholds = ref.watch(signalThresholdProvider);
    final schedules = ref.watch(signalScheduleProvider);
    final neutralPush = ref.watch(signalNeutralPushProvider);
    final izinli = ref.watch(izinliGostergelerProvider);
    // Ücretsiz günlük bildirim kapısı (paywall kapalıyken / Premium'da
    // sınırsız). yasin 2026-10-10 akşam: üç ücretsiz göstergenin bildirimi
    // ücretsizde de gider, "limitli sayıda".
    final slot = ref.watch(sinyalSlotSiniriProvider);
    final kilitli = ref.watch(premiumKilitliProvider);
    final parametreDurumu = ref.watch(gostergeParametreDurumuProvider);
    final parametreler = ref.watch(gostergeParametreleriProvider);

    // Sadeleştirme 2 (bayrak `sinyal_on_ayar`): üstte tek soru + üç ön
    // ayar; kategori başına ayarlar katlanır bölüme taşınır, kaybolmaz.
    final onAyarAcik = RemoteConfigService.instance.sinyalOnAyar;
    final kategoriler = <Widget>[
      Text(
        kilitli
            ? context.l10n.sgnAyarAciklamaUcretsiz
            : 'Her varlık türü için hangi göstergelerin sinyal üretmesini istediğini ve bildirim güven eşiğini seç.',
        style: context.t.titleSmall
            ?.copyWith(color: context.c.text58, height: 1.5),
      ),
      const SizedBox(height: 16),

      // TÜM türler (kullanıcı kuralı, 2026-09-28): yeni eklenen her
      // kategori burada kendi bölümüyle görünür; liste elle tutulmaz.
      // Kripto önceden sunucu analizinde olmadığı için gizleniyordu —
      // artık `analyze-signals` ANALYZABLE'da. İki listenin eşitliğini
      // `sinyal_turleri_test` kilitler.
      //
      // Tek istisna mevduat (2026-09-30): piyasa serisi yok, eğrisi
      // sözleşmenin tahakkukudur; sunucu da analiz etmez. BES fonu
      // (TEFAS EMK) fon gibi analiz edilir ve burada görünür.
      for (final type in AssetType.values)
        if (type != AssetType.mevduat &&
            RemoteConfigService.instance.turSecenegi(type)) ...[
        _CategorySection(
          type: type,
          selected: prefs[type] ??
              TechnicalAnalysisService.defaultEnabledFor(type),
          izinli: izinli,
          paywallVisible: paywallOn,
          parametreDurumu: parametreDurumu,
          parametreler: parametreler[type] ?? const {},
          threshold: thresholds[type] ?? kSignalThresholdDefault,
          onToggle: (id) =>
              ref.read(indicatorPrefsProvider.notifier).toggle(type, id),
          onThresholdChanged: (v) => ref
              .read(signalThresholdProvider.notifier)
              .setForType(type, v),
          // Ekranda UYGULANAN zamanlama: ücretsizde kapıya sığdırılmış
          // hâl. Kayıtlı tercih değişmez, Premium'da geri gelir.
          schedule: slotaSigdir(schedules[type] ?? kDefaultSchedule, slot),
          slot: slot,
          onFrequencyChanged: (f) {
            if (f.gunlukEnFazla > slot) {
              AnalyticsService.instance
                  .logPremiumGateShown(feature: 'signal_frequency');
              PaywallScreen.show(context, source: 'signal_frequency');
              return;
            }
            ref.read(signalScheduleProvider.notifier).setFrequency(type, f);
          },
          onHoursChanged: (h) async {
            // Kısılmış hâlde saat seçmek, gösterilen sıklığı (günde 1)
            // bilerek seçmektir: kayıt da ona çekilir ki saat sayısı ile
            // sıklık tutarsız kalmasın.
            final kayitli = schedules[type] ?? kDefaultSchedule;
            final notifier = ref.read(signalScheduleProvider.notifier);
            final gosterilen = slotaSigdir(kayitli, slot);
            if (gosterilen.frequency != kayitli.frequency) {
              await notifier.setFrequency(type, gosterilen.frequency);
            }
            await notifier.setHours(type, h);
          },
          onParametre: (id, ayar) => ref
              .read(gostergeParametreleriProvider.notifier)
              .ayarla(type, id, ayar),
        ),
        const SizedBox(height: 20),
      ],
    ];

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: const SandikAppBar(
        title: _baslik,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: SandikSpace.screenH(context), vertical: 12),
        children: [
          const DisclaimerWidget(),
          const SizedBox(height: 16),

          // ── Premium kartı (paywall kapalıysa hiç gösterilmez) ────────────
          // Ücretsizde kilitler satırlarda (Premium gösterge, sıklık,
          // periyot); bu kart Premium'daki hâli ("açık") ya da debug
          // anahtarını taşır.
          if (paywallOn && premium) ...[
            _PremiumCard(
              unlocked: true,
              onUpgrade: () {},
              // Yalnız debug: geliştirici anahtarı (release'te çizilmez).
              onDevToggle: gelistirici
                  ? () => ref
                      .read(premiumUnlockedProvider.notifier)
                      .set(!ref.read(premiumUnlockedProvider))
                  : null,
            ),
            const SizedBox(height: 24),
          ],

          if (onAyarAcik) ...[
            _OnAyarKarti(
              slot: slot,
              onPaywall: () {
                AnalyticsService.instance
                    .logPremiumGateShown(feature: 'signal_on_ayar');
                PaywallScreen.show(context, source: 'signal_on_ayar');
              },
            ),
            const SizedBox(height: SandikSpace.md),
          ],

          // ── Genel bildirim ayarları ──────────────────────────────────────
          SandikCard(
            padding: const EdgeInsets.all(16),
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
                                  color: context.c.text90)),
                          const SizedBox(height: 3),
                          Text(
                            'Kapalıyken sadece AL/SAT bildirimi gelir. Nötr sinyaller yine geçmişe yazılır.',
                            style: context.t.bodySmall?.copyWith(
                                color: context.c.text58, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: neutralPush,
                      // TRACK, thumb DEĞİL. `Switch.adaptive` iOS'ta
                      // `CupertinoSwitch` çizer ve orada "açık" rengi
                      // track'tir; `activeThumbColor` amber bir topuzla
                      // varsayılan yeşil bir track üretirdi. Ayarlar
                      // ekranındaki anahtar da `activeTrackColor` kullanıyor —
                      // iki anahtar aynı görünmeli.
                      activeTrackColor: context.c.amberText,
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

          // Bayrak kapalıyken kategori listesi eskisi gibi doğrudan
          // burada; açıkken "Kategoriye göre özelleştir" altında, birebir.
          if (!onAyarAcik)
            ...kategoriler
          else
            _KategoriAcilir(children: kategoriler),
        ],
      ),
    );
  }
}

class _PremiumCard extends StatelessWidget {
  final bool unlocked;
  final VoidCallback onUpgrade;
  final VoidCallback? onDevToggle;
  const _PremiumCard({
    required this.unlocked,
    required this.onUpgrade,
    this.onDevToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: unlocked
              ? [
                  context.c.amberFill.withValues(alpha: 0.18),
                  context.c.amberFill.withValues(alpha: 0.05)
                ]
              : [context.c.overlay, context.c.overlay],
        ),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(
          color: unlocked
              ? context.c.amberFill.withValues(alpha: 0.4)
              : context.c.overlay,
        ),
      ),
      child: Row(
        children: [
          Icon(
            unlocked
                ? Icons.workspace_premium_rounded
                : Icons.lock_outline_rounded,
            color: unlocked ? context.c.amberText : context.c.text58,
            size: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              // Geliştirici anahtarı: yalnız debug'da uzun basış.
              onLongPress: onDevToggle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unlocked ? l10n.sgnPremiumAktif : l10n.sgnPremiumKilitBaslik,
                    style: context.t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.c.text90,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unlocked ? l10n.sgnPremiumAktifGovde : l10n.sgnPremiumKilitGovde,
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          // Premium'daysa eylem yok: iptal/plan değişikliği mağazada yapılır
          // (Profil › abonelik satırı › Yönet). Değilse paywall'a gider.
          if (!unlocked) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: onUpgrade,
              style: TextButton.styleFrom(
                backgroundColor: context.c.amberFill,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(
                l10n.sgnPremiumGec,
                style: context.t.labelMedium?.copyWith(
                  color: context.c.onAmber,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final AssetType type;
  final Set<String> selected;

  /// Bu kullanıcıda hesaplanan göstergeler (`izinliGostergelerProvider`).
  final Set<String> izinli;
  final bool paywallVisible;

  /// Ücretsiz günlük bildirim sınırı; bunu aşan sıklıklar kilitli çizilir.
  final int slot;
  final OzellikDurumu parametreDurumu;
  final Map<String, GostergeAyari> parametreler;
  final int threshold;
  final void Function(String id) onToggle;
  final void Function(int threshold) onThresholdChanged;
  final SignalSchedule schedule;
  final void Function(SignalFrequency freq) onFrequencyChanged;
  final void Function(List<int> hours) onHoursChanged;
  final void Function(String id, GostergeAyari? ayar) onParametre;

  const _CategorySection({
    required this.type,
    required this.selected,
    required this.izinli,
    required this.paywallVisible,
    required this.slot,
    required this.parametreDurumu,
    required this.parametreler,
    required this.threshold,
    required this.onToggle,
    required this.onThresholdChanged,
    required this.schedule,
    required this.onFrequencyChanged,
    required this.onHoursChanged,
    required this.onParametre,
  });

  @override
  Widget build(BuildContext context) {
    return SandikCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(type.icon, size: 18, color: type.onSurface(context)),
                const SizedBox(width: 10),
                Text(
                  type.labelOf(context.l10n),
                  style: context.t.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.c.text90,
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
                      color: context.c.text58, fontWeight: FontWeight.w600),
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
            color: context.c.overlay,
          ),
          _FrequencyRow(
            type: type,
            schedule: schedule,
            slot: slot,
            onFrequencyChanged: onFrequencyChanged,
            onHoursChanged: onHoursChanged,
          ),
          Divider(
            height: 1,
            color: context.c.overlay,
          ),
          // İleri göstergeler (ADX, W%R, CCI) paywall kapalıyken hiç
          // hesaplanmadığı için listelenmez: anahtar bir şey yapmıyordu
          // ("ölü anahtar" bulgusu, 2026-10-10). Kayıtlı seçim silinmez.
          for (final id in IndicatorId.all)
            if (paywallVisible || !IndicatorId.ileri.contains(id))
              _IndicatorRow(
                id: id,
                checked: selected.contains(id),
                locked: !izinli.contains(id),
                recommended: IndicatorId.recommendedFor(type).contains(id),
                showPremiumChip: paywallVisible && IndicatorId.premiumMu(id),
                parametreDurumu: parametreDurumu,
                ozelAyar: GostergeParametreleri.dogrula(id, parametreler[id]),
                onTap: () {
                  if (!izinli.contains(id)) {
                    AnalyticsService.instance
                        .logPremiumGateShown(feature: 'indicator_$id');
                    PaywallScreen.show(context, source: 'signal_settings_$id');
                    return;
                  }
                  onToggle(id);
                },
                onParametre: () {
                  if (parametreDurumu == OzellikDurumu.kilitli) {
                    AnalyticsService.instance
                        .logPremiumGateShown(feature: 'gosterge_parametre');
                    PaywallScreen.show(context, source: 'gosterge_parametre');
                    return;
                  }
                  _parametreSheet(context, id);
                },
              ),
        ],
      ),
    );
  }

  Future<void> _parametreSheet(BuildContext context, String id) async {
    final sonuc = await showSandikSheet<_ParametreSonucu>(
      context: context,
      backgroundColor: context.c.surface1,
      isScrollControlled: true,
      builder: (_) => _ParametreSayfasi(
        id: id,
        type: type,
        mevcut: GostergeParametreleri.dogrula(id, parametreler[id]),
      ),
    );
    if (sonuc != null) onParametre(id, sonuc.ayar);
  }
}

/// Parametre sayfasının dönüşü: [ayar] null = varsayılana dön.
typedef _ParametreSonucu = ({GostergeAyari? ayar});

/// Bir göstergenin periyot ayarları (Premium, 2026-10-10).
///
/// Her parametre bir adımlayıcı: − değer +. Klavye yerine adımlayıcı,
/// çünkü değerler küçük tam sayılar ve dar aralıkta (bkz.
/// `GostergeParametreleri.tanimlar`); sayı klavyesi geçersiz değer yazmaya
/// izin verip sonra hata göstermek demek olurdu. Düğmeler 44 pt.
class _ParametreSayfasi extends StatefulWidget {
  const _ParametreSayfasi(
      {required this.id, required this.type, required this.mevcut});

  final String id;
  final AssetType type;
  final GostergeAyari? mevcut;

  @override
  State<_ParametreSayfasi> createState() => _ParametreSayfasiState();
}

class _ParametreSayfasiState extends State<_ParametreSayfasi> {
  late final GostergeAyari _varsayilan =
      GostergeParametreleri.varsayilan(widget.id, widget.type);
  late final Map<String, int> _deger = {..._varsayilan, ...?widget.mevcut};

  List<GostergeParametresi> get _tanim =>
      GostergeParametreleri.tanimlar[widget.id] ?? const [];

  bool get _gecerli =>
      GostergeParametreleri.dogrula(widget.id, _deger) != null ||
      _varsayilanMi;

  bool get _varsayilanMi =>
      _tanim.every((t) => _deger[t.anahtar] == _varsayilan[t.anahtar]);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
            SandikSpace.smd, SandikSpace.screenH(context), SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: SandikTutamac()),
            const SizedBox(height: SandikSpace.md),
            Text(IndicatorId.labelOf(widget.id),
                style: context.t.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
            const SizedBox(height: SandikSpace.xs),
            Text(l.sgnParametreAciklama(widget.type.labelOf(l)),
                style: context.t.bodySmall
                    ?.copyWith(color: c.text58, height: 1.4)),
            const SizedBox(height: SandikSpace.md),
            for (final t in _tanim)
              _Adimlayici(
                etiket: t.etiket,
                deger: _deger[t.anahtar] ?? t.enAz,
                varsayilan: _varsayilan[t.anahtar],
                enAz: t.enAz,
                enCok: t.enCok,
                onDegis: (v) => setState(() => _deger[t.anahtar] = v),
              ),
            if (!_gecerli) ...[
              const SizedBox(height: SandikSpace.xs),
              Text(l.sgnParametreSiraHatasi,
                  style: context.t.bodySmall?.copyWith(color: c.loss)),
            ],
            const SizedBox(height: SandikSpace.md),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _varsayilanMi
                        ? null
                        : () => Navigator.pop<_ParametreSonucu>(
                            context, (ayar: null)),
                    child: Text(l.sgnParametreVarsayilan),
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: c.amberFill,
                        foregroundColor: c.onAmber,
                        minimumSize: const Size.fromHeight(SandikTouch.min)),
                    onPressed: _gecerli
                        ? () => Navigator.pop<_ParametreSonucu>(
                            context, (ayar: _varsayilanMi ? null : {..._deger}))
                        : null,
                    child: Text(l.sgnParametreKaydet),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Adimlayici extends StatelessWidget {
  const _Adimlayici({
    required this.etiket,
    required this.deger,
    required this.varsayilan,
    required this.enAz,
    required this.enCok,
    required this.onDegis,
  });

  final String etiket;
  final int deger;
  final int? varsayilan;
  final int enAz;
  final int enCok;
  final ValueChanged<int> onDegis;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l10n;
    return Semantics(
      label: etiket,
      value: '$deger',
      increasedValue: deger < enCok ? '${deger + 1}' : null,
      decreasedValue: deger > enAz ? '${deger - 1}' : null,
      onIncrease: deger < enCok ? () => onDegis(deger + 1) : null,
      onDecrease: deger > enAz ? () => onDegis(deger - 1) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(etiket,
                      style: context.t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600, color: c.text90)),
                  if (varsayilan != null)
                    Text(l.sgnParametreVarsayilanDeger(varsayilan!),
                        style:
                            context.t.bodySmall?.copyWith(color: c.text36)),
                ],
              ),
            ),
            ExcludeSemantics(
              child: IconButton(
                tooltip: l.sgnParametreAzalt,
                constraints: const BoxConstraints(
                    minWidth: SandikTouch.min, minHeight: SandikTouch.min),
                onPressed: deger > enAz ? () => onDegis(deger - 1) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
            ),
            SizedBox(
              width: SandikSpace.xl,
              child: ExcludeSemantics(
                child: Text('$deger',
                    textAlign: TextAlign.center,
                    style: context.t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.text90,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
            ExcludeSemantics(
              child: IconButton(
                tooltip: l.sgnParametreArtir,
                constraints: const BoxConstraints(
                    minWidth: SandikTouch.min, minHeight: SandikTouch.min),
                onPressed: deger < enCok ? () => onDegis(deger + 1) : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ),
          ],
        ),
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

  /// Günlük bildirim sınırı; bunu aşan sıklıklar kilitli çizilir.
  final int slot;
  final void Function(SignalFrequency freq) onFrequencyChanged;
  final void Function(List<int> hours) onHoursChanged;

  const _FrequencyRow({
    required this.type,
    required this.schedule,
    required this.slot,
    required this.onFrequencyChanged,
    required this.onHoursChanged,
  });

  String _saatMetni(int h) => '${h.toString().padLeft(2, '0')}:00';

  Future<void> _saatSec(BuildContext context) async {
    final freq = schedule.frequency;
    final secili = <int>[...schedule.hours];

    final sonuc = await showSandikSheet<List<int>>(
      context: context,
      backgroundColor: context.c.surface1,
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
              padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 14, SandikSpace.screenH(context), 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: const SandikTutamac(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    freq.hourCount == 1
                        ? 'Bildirim saatini seç'
                        : 'İki bildirim saati seç',
                    style: context.t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: context.c.text90),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bildirimler yalnızca '
                    '${_saatMetni(kSignalWindowStart)}-'
                    '${_saatMetni(kSignalWindowEnd)} arasında gönderilir.',
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  // Seçili saatler her zaman görünür — kapasite dolduğunda
                  // hangi saatin değişeceği tahmin edilmesin diye.
                  Text(
                    secili.isEmpty
                        ? 'Henüz saat seçilmedi'
                        : 'Seçili: ${([
                            ...secili
                          ]..sort()).map(_saatMetni).join("  •  ")}',
                    style: context.t.bodySmall?.copyWith(
                        color: secili.isEmpty
                            ? context.c.text36
                            : context.c.amberText,
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
                          backgroundColor: context.c.amberFill,
                          disabledBackgroundColor:
                              context.c.amberFill.withValues(alpha: 0.3)),
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
                color: context.c.text58, fontWeight: FontWeight.w600),
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
          SandikCard(
            padding: EdgeInsets.zero,
            elevated: true,
            radius: SandikRadius.sm,
            child: Column(
              children: [
                for (var i = 0; i < SignalFrequency.values.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 12,
                      color: context.c.overlay,
                    ),
                  _FrequencyOption(
                    frequency: SignalFrequency.values[i],
                    secili: SignalFrequency.values[i] == freq,
                    kilitli: SignalFrequency.values[i].gunlukEnFazla > slot,
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
          if (SignalFrequency.values.any((f) => f.gunlukEnFazla > slot))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                context.l10n.sgnSlotNotu,
                style: context.t.bodySmall
                    ?.copyWith(color: context.c.text58, height: 1.4),
              ),
            ),
          if (!freq.needsHourPicker)
            Text(
              '${freq.description}, '
              '${_saatMetni(kSignalWindowStart)}-'
              '${_saatMetni(kSignalWindowEnd)} arası.',
              style: context.t.bodySmall
                  ?.copyWith(color: context.c.text36, height: 1.4),
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

  /// Ücretsiz günlük sınırı aşıyor: kilit simgesiyle çizilir, dokunuş
  /// paywall'u açar (karar üst katmanda, `onFrequencyChanged`).
  final bool kilitli;

  /// Seçili ve saat gerektiren sıklıkta gösterilecek saat metni.
  /// null ise saat satırı çizilmez.
  final String? hoursLabel;
  final VoidCallback onTap;
  final VoidCallback onHoursTap;

  const _FrequencyOption({
    required this.frequency,
    required this.secili,
    this.kilitli = false,
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
      label: kilitli
          ? context.l10n.sgnSlotKilitli(frequency.label)
          : null,
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
                          ? Icon(Icons.check_rounded,
                              size: 18, color: context.c.amberText)
                          : null,
                    ),
                    Expanded(
                      child: Text(
                        frequency.label,
                        style: context.t.bodyMedium?.copyWith(
                          color: secili
                              ? context.c.amberText
                              : kilitli
                                  ? context.c.text36
                                  : context.c.text90,
                          // Ağırlık BİLİNÇLİ olarak sabit — bkz. sınıf notu.
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (kilitli)
                      Icon(Icons.lock_outline_rounded,
                          size: 16, color: context.c.amberText),
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
                        Icon(Icons.schedule_rounded,
                            size: 15, color: context.c.text58),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hoursLabel!,
                            style: context.t.bodySmall?.copyWith(
                                color: context.c.text90, height: 1.3),
                          ),
                        ),
                        Text(
                          'Değiştir',
                          style: context.t.labelMedium?.copyWith(
                              color: context.c.amberText, letterSpacing: 0),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 16, color: context.c.text36),
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
      child: SandikBasma(
        onTap: onTap,
        child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          // 44pt HIG minimum dokunma hedefi.
          constraints: const BoxConstraints(minHeight: 44, minWidth: 72),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: secili
                ? context.c.amberFill.withValues(alpha: 0.18)
                : context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.sm),
            border: Border.all(
              color: secili
                  ? context.c.amberFill.withValues(alpha: 0.6)
                  : context.c.overlay,
            ),
          ),
          child: Text(
            label,
            style: context.t.bodySmall?.copyWith(
              color: secili ? context.c.amberText : context.c.text58,
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
  final OzellikDurumu parametreDurumu;

  /// Kullanıcının bu göstergedeki geçerli ayarı (null = varsayılan).
  final GostergeAyari? ozelAyar;
  final VoidCallback onTap;
  final VoidCallback onParametre;

  const _IndicatorRow({
    required this.id,
    required this.checked,
    required this.locked,
    required this.recommended,
    required this.showPremiumChip,
    required this.parametreDurumu,
    required this.ozelAyar,
    required this.onTap,
    required this.onParametre,
  });

  @override
  Widget build(BuildContext context) {
    // Ayar düğmesi yalnız seçili ve kilitsiz göstergede: seçilmemiş
    // göstergenin periyodunu ayarlamak hiçbir şeyi değiştirmez.
    final ayarGoster =
        checked && !locked && parametreDurumu != OzellikDurumu.gizli;
    final ayar = ozelAyar;
    final ayarMetni = ayar == null
        ? null
        : [
            for (final t in GostergeParametreleri.tanimlar[id] ?? const <GostergeParametresi>[])
              if (ayar[t.anahtar] != null) '${t.etiket} ${ayar[t.anahtar]}'
          ].join(' · ');
    return Row(
      children: [
        Expanded(child: _satir(context, ayarMetni)),
        if (ayarGoster)
          IconButton(
            tooltip: parametreDurumu == OzellikDurumu.kilitli
                ? context.l10n.sgnParametreKilitli
                : context.l10n.sgnParametreAyarla(IndicatorId.labelOf(id)),
            constraints: const BoxConstraints(
                minWidth: SandikTouch.min, minHeight: SandikTouch.min),
            onPressed: onParametre,
            icon: Icon(
              parametreDurumu == OzellikDurumu.kilitli
                  ? Icons.lock_outline_rounded
                  : Icons.tune_rounded,
              size: 20,
              color: ayar != null ? context.c.amberText : context.c.text58,
            ),
          ),
      ],
    );
  }

  Widget _satir(BuildContext context, String? ayarMetni) {
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
                  ? context.c.text36
                  : (checked ? context.c.amberText : context.c.text58),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    IndicatorId.labelOf(id),
                    style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: locked ? context.c.text36 : context.c.text90,
                    ),
                  ),
                  if (ayarMetni != null && !locked)
                    Text(ayarMetni,
                        style: context.t.bodySmall
                            ?.copyWith(color: context.c.amberText)),
                ],
              ),
            ),
            // "ÖNERİLEN" çipi premium/normal ayrımından bağımsızdır; iki dal
            // birebir aynı widget'ı kuruyordu. Tek çıkış noktası bırakıldı,
            // premium'a özel olan yalnızca öndeki boşluk.
            //
            // Renk notu: burada sabit `Colors.green` (#4CAF50) vardı ve temayı
            // takip etmiyordu — light yüzeyde 2.78:1. Palet `gain`i 5.37:1.
            if (recommended) ...[
              // Uzun etiket ("MACD (Hareketli Ortalama Yakınsaması)") çipe
              // yapışıyordu (web ekran görüntüsü 2026-10-08); `Expanded`
              // metin kırılır ama aralık hiç yoktu.
              const SizedBox(width: SandikSpace.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.c.gain.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Text(
                  'ÖNERİLEN',
                  style: context.t.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: context.c.gain,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
            if (showPremiumChip) ...[
              // Boşluğu PREMIUM çipi kendi sahiplenir — "ÖNERİLEN" tarafına da
              // koyarsak, ikisi birlikte göründüğünde araya çift boşluk girer.
              if (showPremiumChip && recommended) const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                  child: Text(
                    'PREMIUM',
                    style: context.t.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.c.amberText,
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

/// Bildirim eşiği (%50 · %70 · %85).
///
/// Kabuk ortak [SandikSegment] (tek seçici, 2026-10-08 — yol haritası
/// 2.12): eskiden amber çerçeveli, elle yazılmış bir kopyaydı ve dokunma
/// hedefi metnin boyu kadardı (~30 pt). Satırda `Spacer`'ın yanında durduğu
/// için genişliği sabit verilir — bileşen genişliği paylardan hesaplar,
/// kendi içeriğine göre boyutlanmaz. Segment başına bir dokunma hedefi
/// (44 pt): üç kısa etiket rahat sığar, satır 360pt'te taşmaz.
class _ThresholdSegment extends StatelessWidget {
  final int value;
  final void Function(int) onChanged;

  const _ThresholdSegment({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const secenekler = kSignalThresholdOptions;
    return SizedBox(
      width: SandikTouch.min * (secenekler.length + 1),
      child: SandikSegment(
        adet: secenekler.length,
        secili: secenekler.indexOf(value),
        onSec: (i) => onChanged(secenekler[i]),
        oge: (_, i, __) => Text('%${secenekler[i]}'),
      ),
    );
  }
}

// ── Ön ayar (bayrak `sinyal_on_ayar`) ────────────────────────────────────────

/// "Ne sıklıkta haber verelim?" — Az · Dengeli · Çok.
///
/// Seçim kayıtlı tercihlerden TÜRETİLİR (`sinyalOnAyarProvider`); hiçbir
/// ön ayara birebir uymayan kullanıcı "Özel" görür ve hiçbir şey
/// değişmez — Özel dokunulmaz bir etikettir, segment değildir (segmentte
/// olsaydı dokununca neye döneceği belirsiz kalırdı). Ön ayar seçmek iyimser
/// bir yazmadır (anahtar gibi): yerel durum anında değişir, sunucu arkadan.
class _OnAyarKarti extends ConsumerWidget {
  const _OnAyarKarti({required this.slot, required this.onPaywall});

  final int slot;
  final VoidCallback onPaywall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final secili = ref.watch(sinyalOnAyarProvider);
    final etiketler = [l10n.s5OnAyarAz, l10n.s5OnAyarDengeli, l10n.s5OnAyarCok];
    final aciklama = switch (secili) {
      SinyalOnAyar.az => l10n.s5OnAyarAzAciklama,
      SinyalOnAyar.dengeli => l10n.s5OnAyarDengeliAciklama,
      SinyalOnAyar.cok => l10n.s5OnAyarCokAciklama,
      null => l10n.s5OnAyarOzelAciklama,
    };
    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.s5OnAyarSoru,
                  style: context.t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600, color: context.c.text90),
                ),
              ),
              if (secili == null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.sm, vertical: SandikSpace.xxs),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                    border: Border.all(
                        color: context.c.amberFill.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    l10n.s5OnAyarOzel,
                    style: context.t.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.c.amberText,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: SandikSpace.smd),
          SandikSegment(
            adet: etiketler.length,
            // Özel: aralık dışı → zemin çizilmez, üç seçenek de dokunulur.
            secili: secili?.index ?? -1,
            onSec: (i) {
              final a = SinyalOnAyar.values[i];
              // Kategori satırındaki kapıyla aynı kural: ücretsiz günlük
              // bildirim sınırını aşan sıklık Premium ister, hiçbir şey
              // yazılmaz.
              if (sinyalOnAyarTanimi(a, AssetType.hisse).siklik.gunlukEnFazla >
                  slot) {
                onPaywall();
                return;
              }
              sinyalOnAyariUygula(ref, a);
            },
            oge: (context, i, _) => Text(etiketler[i]),
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(
            aciklama,
            style: context.t.bodySmall
                ?.copyWith(color: context.c.text58, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// "Kategoriye göre özelleştir": bugünkü kategori ayarlarının TAMAMI,
/// katlanmış. Kapalı başlar — ön ayar çoğu kullanıcıya yeter; açınca eski
/// ekran birebir (aynı `_CategorySection`'lar, aynı geri çağrılar).
class _KategoriAcilir extends StatefulWidget {
  const _KategoriAcilir({required this.children});

  final List<Widget> children;

  @override
  State<_KategoriAcilir> createState() => _KategoriAcilirState();
}

class _KategoriAcilirState extends State<_KategoriAcilir> {
  bool _acik = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SandikTappable(
          selected: _acik,
          onTap: () => setState(() => _acik = !_acik),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: SandikTouch.min),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.s5KategoriyeGoreOzellestir,
                    style: context.t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.c.text90,
                    ),
                  ),
                ),
                SandikAcilirOk(
                  acik: _acik,
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      color: context.c.text36),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: SandikSpace.sm),
        SandikAcilir(
          acik: _acik,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        ),
      ],
    );
  }
}
