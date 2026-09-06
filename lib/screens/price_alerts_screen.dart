import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/price_alert.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart' show priceAlertLimitProvider;
import '../providers/watchlist_provider.dart';
import '../services/analytics_service.dart';
import '../services/price_alert_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/sandik_error_view.dart';

/// Fiyat alarmları.
///
/// **Neden bu ekran değerli:** alarm, kullanıcının KENDİSİNİN istediği tek
/// bildirimdir. Alaka garantili, opt-out riski yok, ve alarm kuran kullanıcı
/// uygulamayı kurulu bırakmak için bir sebep edinir.
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
  late Future<List<PriceAlert>> _future;

  @override
  void initState() {
    super.initState();
    _future = _yukle();
    AnalyticsService.instance.logScreenView(screenName: 'price_alerts');
  }

  Future<List<PriceAlert>> _yukle() async {
    final me = ref.read(authProvider).valueOrNull;
    if (me == null) return const [];
    return PriceAlertService.instance.fetchAll(me.id);
  }

  void _tazele() => setState(() => _future = _yukle());

  /// Alarm kurulabilecek semboller: portföydeki aktif alımlar + takip listesi.
  List<_Aday> _adaylar() {
    final out = <String, _Aday>{};

    final assets = ref.read(portfolioProvider).valueOrNull?.assets ?? const [];
    for (final a in assets) {
      if (!a.isBuy || !a.isActive) continue;
      final sembol = _sembol(a.ticker, a.subCategory);
      if (sembol == null) continue;
      out[sembol] = _Aday(sembol, a.name, a.currentPrice);
    }

    final watch = ref.read(watchlistProvider).valueOrNull ?? const [];
    for (final w in watch) {
      final sembol = _sembol(w.ticker, w.subCategory);
      if (sembol == null) continue;
      out.putIfAbsent(
        sembol,
        () => _Aday(sembol, w.name, w.currentPrice ?? 0),
      );
    }

    final liste = out.values.toList()
      ..sort((a, b) => a.ad.toLowerCase().compareTo(b.ad.toLowerCase()));
    return liste;
  }

  /// Fiyat kaynağının anladığı sembol.
  ///
  /// Altında alt kategori (ALTIN_GRAM…) sembolün kendisidir; hissede ticker.
  /// Manuel fiyatlı ya da kodu olmayan varlık alarm kuramaz — sunucu onun
  /// fiyatını çekemez ve alarm hiç çalışmazdı.
  static String? _sembol(String ticker, String? subCategory) {
    final sub = subCategory?.trim() ?? '';
    if (sub.startsWith('ALTIN_')) return sub;
    final t = ticker.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _alarmKur() async {
    final adaylar = _adaylar();
    if (adaylar.isEmpty) {
      _uyar('Önce portföyüne ya da takip listene bir varlık ekle.');
      return;
    }

    final mevcut = await _future;
    final limit = ref.read(priceAlertLimitProvider);
    if (mevcut.where((a) => a.isActive).length >= limit) {
      _uyar('En fazla $limit aktif alarm kurabilirsin.');
      return;
    }

    if (!mounted) return;
    final sonuc = await showModalBottomSheet<_Kurulum>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AlarmKurSheet(adaylar: adaylar),
    );
    if (sonuc == null) return;

    final me = ref.read(authProvider).valueOrNull;
    if (me == null) return;
    try {
      await PriceAlertService.instance.create(PriceAlert(
        id: '',
        userId: me.id,
        symbol: sonuc.aday.sembol,
        label: sonuc.aday.ad,
        targetPrice: sonuc.hedef,
        direction: sonuc.yon,
        enabled: true,
        createdAt: DateTime.now(),
      ));
      AnalyticsService.instance.logScreenView(screenName: 'price_alert_created');
      _tazele();
    } catch (e) {
      _uyar('Alarm kurulamadı: $e');
    }
  }

  void _uyar(String mesaj) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mesaj)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: const Text('Fiyat Alarmları'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.amberFill,
        foregroundColor: c.onAmber,
        onPressed: _alarmKur,
        icon: const Icon(Icons.add_alert_rounded),
        label: const Text('Alarm kur'),
      ),
      body: FutureBuilder<List<PriceAlert>>(
        future: _future,
        builder: (_, snap) {
          if (snap.hasError) {
            return SandikErrorView(
              error: snap.error!,
              onRetry: _tazele,
            );
          }
          final liste = snap.data;
          if (liste == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (liste.isEmpty) return _bosDurum(c);
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: liste.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _AlarmSatiri(
              alarm: liste[i],
              onDelete: () async {
                await PriceAlertService.instance.delete(liste[i].id);
                _tazele();
              },
              onRearm: () async {
                await PriceAlertService.instance.rearm(liste[i].id);
                _tazele();
              },
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
                'Henüz alarmın yok',
                style: context.t.headlineSmall?.copyWith(color: c.text90),
              ),
              const SizedBox(height: 6),
              Text(
                'Bir fiyat hedefi koy, uygulama kapalıyken bile haber verelim.',
                textAlign: TextAlign.center,
                style: context.t.bodyLarge?.copyWith(color: c.text58),
              ),
            ],
          ),
        ),
      );
}

class _Aday {
  final String sembol;
  final String ad;
  final double guncelFiyat;
  const _Aday(this.sembol, this.ad, this.guncelFiyat);
}

class _Kurulum {
  final _Aday aday;
  final double hedef;
  final String yon;
  const _Kurulum(this.aday, this.hedef, this.yon);
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.text20.withValues(alpha: 0.22)),
      ),
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
                      ? 'Çalıştı · ${fmtTRY(alarm.targetPrice, digits: 2)}'
                      : '${alarm.isAbove ? "Üstüne çıkınca" : "Altına inince"}'
                          ' · ${fmtTRY(alarm.targetPrice, digits: 2)}',
                  style: context.t.bodyMedium?.copyWith(color: c.text58),
                ),
              ],
            ),
          ),
          if (tetiklendi)
            TextButton(onPressed: onRearm, child: const Text('Yeniden kur')),
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

// ── Alarm kurma sheet'i ──────────────────────────────────────────────────────

class _AlarmKurSheet extends StatefulWidget {
  final List<_Aday> adaylar;
  const _AlarmKurSheet({required this.adaylar});

  @override
  State<_AlarmKurSheet> createState() => _AlarmKurSheetState();
}

class _AlarmKurSheetState extends State<_AlarmKurSheet> {
  late _Aday _secili = widget.adaylar.first;
  final _controller = TextEditingController();
  String? _hata;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _kaydet() {
    final ham = _controller.text.trim().replaceAll('.', '').replaceAll(',', '.');
    final hedef = double.tryParse(ham);
    if (hedef == null || hedef <= 0) {
      setState(() => _hata = 'Geçerli bir fiyat gir');
      return;
    }
    // Yön otomatik: güncel fiyatın üstündeki hedef "yükselince", altındaki
    // "düşünce" demektir. Kullanıcıya ayrıca sormak, yanlış seçimde alarmın
    // hiç çalışmaması ve sebebinin anlaşılmaması riskini getirirdi.
    final yon = PriceAlert.suggestDirection(
      currentPrice: _secili.guncelFiyat,
      targetPrice: hedef,
    );
    Navigator.of(context).pop(_Kurulum(_secili, hedef, yon));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final yon = () {
      final ham =
          _controller.text.trim().replaceAll('.', '').replaceAll(',', '.');
      final hedef = double.tryParse(ham);
      if (hedef == null || hedef <= 0) return null;
      return PriceAlert.suggestDirection(
        currentPrice: _secili.guncelFiyat,
        targetPrice: hedef,
      );
    }();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, 24 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Alarm kur',
                style: context.t.headlineSmall?.copyWith(color: c.text90)),
            const SizedBox(height: 16),
            // `DropdownButton` + `value` kullanılıyor:
            // `DropdownButtonFormField.initialValue` yalnızca yeni Flutter
            // sürümlerinde var, `value` ise uzun süredir kararlı ve projede
            // zaten bu kalıp kullanılıyor (bkz. add_asset_screen).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.text20.withValues(alpha: 0.25)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_Aday>(
                  value: _secili,
                  isExpanded: true,
                  dropdownColor: c.surface2,
                  style: context.t.titleMedium?.copyWith(color: c.text90),
                  icon: Icon(Icons.arrow_drop_down, color: c.amberText),
                  items: [
                    for (final a in widget.adaylar)
                      DropdownMenuItem(
                        value: a,
                        child: Text(a.ad, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _secili = v ?? _secili),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _secili.guncelFiyat > 0
                  ? 'Şu an ${fmtTRY(_secili.guncelFiyat, digits: 2)}'
                  : 'Güncel fiyat bilinmiyor',
              style: context.t.bodyMedium?.copyWith(color: c.text58),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Hedef fiyat',
                errorText: _hata,
              ),
              onChanged: (_) => setState(() => _hata = null),
            ),
            const SizedBox(height: 12),
            // Yön SEÇTİRİLMEZ ama GÖSTERİLİR: kullanıcı ne kurduğunu
            // kaydetmeden önce görmeli.
            if (yon != null)
              Text(
                yon == 'above'
                    ? 'Fiyat bu seviyeye çıkınca haber vereceğiz.'
                    : 'Fiyat bu seviyeye inince haber vereceğiz.',
                style: context.t.bodyMedium?.copyWith(color: c.amberText),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.amberFill,
                  foregroundColor: c.onAmber,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _kaydet,
                child: const Text('Alarmı kur'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
