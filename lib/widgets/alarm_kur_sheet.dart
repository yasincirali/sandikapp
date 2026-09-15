import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/price_alert.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart' show priceAlertLimitProvider;
import '../providers/price_alert_provider.dart';
import '../services/analytics_service.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../l10n/l10n.dart';

/// Alarm kurulabilecek bir sembol: fiyat kaynağının kodu + kullanıcı adı +
/// bilinen güncel fiyat (0 = bilinmiyor).
class AlarmAdayi {
  final String sembol;
  final String ad;
  final double guncelFiyat;
  const AlarmAdayi(this.sembol, this.ad, this.guncelFiyat);
}

/// Sheet'in döndürdüğü seçim.
class AlarmKurulumu {
  final AlarmAdayi aday;
  final double hedef;
  final String yon;
  const AlarmKurulumu(this.aday, this.hedef, this.yon);
}

/// Fiyat kaynağının anladığı sembol.
///
/// Altında alt kategori (ALTIN_GRAM…) sembolün kendisidir; hissede ticker.
/// Manuel fiyatlı ya da kodu olmayan varlık alarm kuramaz — sunucu onun
/// fiyatını çekemez ve alarm hiç çalışmazdı.
String? alarmSembolu(String ticker, String? subCategory) {
  final sub = subCategory?.trim() ?? '';
  if (sub.startsWith('ALTIN_')) return sub;
  final t = ticker.trim();
  return t.isEmpty ? null : t;
}

/// Alarm kurma akışı — limit denetimi, sheet, sunucuya yazma, geri bildirim.
///
/// 2026-09-14: bu akış yalnızca Fiyat Alarmları ekranındaydı; alarm artık
/// varlık ekranındaki zilden de kurulur. [sabit] verilirse sheet sembol
/// seçtirmez (varlık ekranı: "bu varlık için"); [adaylar] verilirse liste
/// sunar (alarmlar ekranı). Başarıda kurulan alarm döner, iptalde `null`.
Future<PriceAlert?> alarmKurAkisi(
  BuildContext context,
  WidgetRef ref, {
  AlarmAdayi? sabit,
  List<AlarmAdayi> adaylar = const [],
}) async {
  final liste = sabit != null ? [sabit] : adaylar;
  if (liste.isEmpty) {
    sandikSnack(context, context.l10n.addAssetFirst,
        kind: SandikSnackKind.warning);
    return null;
  }

  final mevcut = ref.read(priceAlertsProvider).valueOrNull ?? const [];
  final limit = ref.read(priceAlertLimitProvider);
  if (mevcut.where((a) => a.isActive).length >= limit) {
    sandikSnack(context, 'En fazla $limit aktif alarm kurabilirsin.',
        kind: SandikSnackKind.warning);
    return null;
  }

  final sonuc = await showModalBottomSheet<AlarmKurulumu>(
    context: context,
    backgroundColor: context.c.surface1,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => AlarmKurSheet(adaylar: liste, sabit: sabit != null),
  );
  if (sonuc == null || !context.mounted) return null;

  final me = ref.read(authProvider).valueOrNull;
  if (me == null) return null;
  try {
    final kayit = await ref.read(priceAlertsProvider.notifier).create(PriceAlert(
      id: '',
      userId: me.id,
      symbol: sonuc.aday.sembol,
      label: sonuc.aday.ad,
      targetPrice: sonuc.hedef,
      direction: sonuc.yon,
      enabled: true,
      createdAt: DateTime.now(),
    ));
    unawaited(AnalyticsService.instance
        .logScreenView(screenName: 'price_alert_created'));
    if (context.mounted) {
      sandikSnack(
        context,
        sonuc.yon == 'above'
            ? context.l10n.alertSetAbove(
                sonuc.aday.ad, fmtTRY(sonuc.hedef, digits: 2))
            : context.l10n.alertSetBelow(
                sonuc.aday.ad, fmtTRY(sonuc.hedef, digits: 2)),
        kind: SandikSnackKind.success,
      );
    }
    return kayit;
  } catch (e) {
    if (context.mounted) {
      sandikSnackError(context, e, prefix: context.l10n.alertSetFailed);
    }
    return null;
  }
}

/// Hedef fiyat girişi. Yön SEÇTİRİLMEZ, güncel fiyata göre türetilir ve
/// kaydetmeden önce GÖSTERİLİR (kullanıcı ne kurduğunu görsün).
class AlarmKurSheet extends StatefulWidget {
  final List<AlarmAdayi> adaylar;

  /// `true` → tek aday, seçici çizilmez; başlıkta varlığın adı yazar.
  final bool sabit;
  const AlarmKurSheet({super.key, required this.adaylar, this.sabit = false});

  @override
  State<AlarmKurSheet> createState() => _AlarmKurSheetState();
}

class _AlarmKurSheetState extends State<AlarmKurSheet> {
  late AlarmAdayi _secili = widget.adaylar.first;
  final _controller = TextEditingController();
  String? _hata;

  /// Hızlı hedefler: güncel fiyatın ±%'si. Kullanıcı çoğu zaman "biraz
  /// yükselince / düşünce" der, rakam hesaplamak istemez.
  static const _hizliYuzdeler = [-10, -5, 5, 10];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _hedef {
    final v = parseTrNumber(_controller.text);
    return (v == null || v <= 0) ? null : v;
  }

  void _hizli(int yuzde) {
    final f = _secili.guncelFiyat * (1 + yuzde / 100);
    _controller.text = fmtNum(f, digits: 2);
    setState(() => _hata = null);
  }

  void _kaydet() {
    final hedef = _hedef;
    if (hedef == null) {
      setState(() => _hata = context.l10n.enterValidPrice);
      return;
    }
    // Yön otomatik: güncel fiyatın üstündeki hedef "yükselince", altındaki
    // "düşünce" demektir. Kullanıcıya ayrıca sormak, yanlış seçimde alarmın
    // hiç çalışmaması ve sebebinin anlaşılmaması riskini getirirdi.
    final yon = PriceAlert.suggestDirection(
      currentPrice: _secili.guncelFiyat,
      targetPrice: hedef,
    );
    Navigator.of(context).pop(AlarmKurulumu(_secili, hedef, yon));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hedef = _hedef;
    final yon = hedef == null
        ? null
        : PriceAlert.suggestDirection(
            currentPrice: _secili.guncelFiyat, targetPrice: hedef);
    final fiyatVar = _secili.guncelFiyat > 0;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.lg, SandikSpace.md, SandikSpace.lg, SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.sabit ? context.l10n.alertForAsset(_secili.ad) : 'Alarm kur',
                style: context.t.headlineSmall?.copyWith(color: c.text90),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: SandikSpace.md),
            if (!widget.sabit) ...[
              // `DropdownButton` + `value`: projede kararlı kalıp
              // (bkz. add_asset_screen).
              Container(
                padding: const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(color: c.hairline),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AlarmAdayi>(
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
              const SizedBox(height: SandikSpace.xs2),
            ],
            Text(
              fiyatVar
                  ? context.l10n.currentlyPrice(fmtTRY(_secili.guncelFiyat, digits: 2))
                  : context.l10n.currentPriceUnknown,
              style: context.t.bodyMedium?.copyWith(color: c.text58),
            ),
            const SizedBox(height: SandikSpace.md),
            TextField(
              controller: _controller,
              autofocus: widget.sabit,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Hedef fiyat',
                errorText: _hata,
              ),
              onChanged: (_) => setState(() => _hata = null),
            ),
            if (fiyatVar) ...[
              const SizedBox(height: SandikSpace.smd),
              Wrap(
                spacing: SandikSpace.xs2,
                children: [
                  for (final y in _hizliYuzdeler)
                    Semantics(
                      button: true,
                      label: context.l10n.targetPctSemantics(
                          y > 0 ? context.l10n.plusWord : context.l10n.minusWord,
                          y.abs()),
                      child: SandikTappable(
                        onTap: () => _hizli(y),
                        child: Container(
                          constraints:
                              const BoxConstraints(minHeight: SandikTouch.min),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                              horizontal: SandikSpace.smd),
                          decoration: BoxDecoration(
                            color: c.surface2,
                            borderRadius: BorderRadius.circular(SandikRadius.sm),
                            border: Border.all(color: c.hairline),
                          ),
                          child: Text(
                            '${y > 0 ? '+' : '−'}%${y.abs()}',
                            style: context.t.labelLarge?.copyWith(
                              color: y > 0 ? c.gain : c.loss,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: SandikSpace.smd),
            if (yon != null)
              Text(
                yon == 'above'
                    ? context.l10n.notifyWhenAbove
                    : context.l10n.notifyWhenBelow,
                style: context.t.bodyMedium?.copyWith(color: c.amberText),
              ),
            const SizedBox(height: SandikSpace.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.amberFill,
                  foregroundColor: c.onAmber,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _kaydet,
                child: Text(context.l10n.setAlert),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
