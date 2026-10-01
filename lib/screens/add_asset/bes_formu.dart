import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/demo_modu.dart';
import '../../l10n/l10n.dart';
import '../../models/sozlesme.dart';
import '../../providers/sozlesme_provider.dart';
import '../../services/bes_hesabi.dart';
import '../../services/crash_reporter.dart';
import '../../services/tefas_service.dart';
import '../../theme/sandik.dart';
import '../../utils/friendly_error.dart';
import '../../utils/sandik_snack.dart';
import '../../utils/tr_format.dart';
import 'emeklilik_fonu_secici.dart';
import '../../widgets/bes_dagilim_editoru.dart';
import '../../widgets/sozlesme_formu_ortak.dart';

/// BES sözleşmesi girişi (seçenek B3).
///
/// Kullanıcının BİLDİĞİ sayılarla, ekstresindeki sırayla girilir (karar
/// 2026-10-01): şirket, sisteme giriş, ana para (ödediği katkı), getiri,
/// devlet katkısı ana parası ve getirisi, fon dağılımı. Birikim = ana para
/// + getiri; ayrıca sorulmaz. Pay adedi sorulmaz — kimse bilmez; açılışta
/// birikim ÷ bugünkü fon fiyatından hesaplanır (`SozlesmeNotifier.besAc`).
/// Geçmiş, giriş tarihinden bugüne bu değerle DÜZ çizilir (`BesAcilis`).
/// Devlet katkısı isteğe bağlıdır: fonu bilinmeyen devlet katkısı
/// değerlenemez, uydurma fiyatla eklenmez.
class BesFormu extends ConsumerStatefulWidget {
  const BesFormu({super.key});

  @override
  ConsumerState<BesFormu> createState() => BesFormuState();
}

class BesFormuState extends ConsumerState<BesFormu> implements SozlesmeFormu {
  final _form = GlobalKey<FormState>();
  final _dagilimEditoru = GlobalKey<BesDagilimEditoruState>();
  final _sirket = TextEditingController();
  final _anaPara = TextEditingController();
  final _getiri = TextEditingController();
  final _dkAnaPara = TextEditingController();
  final _dkGetiri = TextEditingController();
  final _aylik = TextEditingController();
  final _gun = TextEditingController();
  TefasFund? _dkFonu;
  bool _denendi = false;
  DateTime _giris = DateTime.now();
  String? _dagilimHatasi;

  @override
  void initState() {
    super.initState();
    // Birikim satırı canlı: ana para + getiri.
    for (final c in [_anaPara, _getiri, _dkAnaPara, _dkGetiri]) {
      c.addListener(_yenile);
    }
  }

  void _yenile() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      _sirket,
      _anaPara,
      _getiri,
      _dkAnaPara,
      _dkGetiri,
      _aylik,
      _gun,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _birikim =>
      (parseTrNumber(_anaPara.text) ?? 0) + (parseTrNumber(_getiri.text) ?? 0);

  double get _dkBirikim =>
      (parseTrNumber(_dkAnaPara.text) ?? 0) +
      (parseTrNumber(_dkGetiri.text) ?? 0);

  Future<void> _dkFonuSec() async {
    final f = await emeklilikFonuSec(context, devletKatkisi: true);
    if (f == null || !mounted) return;
    setState(() => _dkFonu = f);
  }

  @override
  Future<bool> kaydet() async {
    if (DemoModu.yazmaKapisi('bes')) return false;
    final l10n = context.l10n;
    final formGecerli = _form.currentState?.validate() ?? false;
    final dagilim = _dagilimEditoru.currentState?.dagilim ?? const <FonPayi>[];
    String? dagilimHatasi;
    if (dagilim.isEmpty) {
      dagilimHatasi = l10n.pensionFundError;
    } else if (!BesHesabi.dagilimGecerli(dagilim)) {
      dagilimHatasi = l10n.pensionShareError;
    }
    setState(() {
      _dagilimHatasi = dagilimHatasi;
      if (!formGecerli) _denendi = true;
    });
    if (!formGecerli || dagilimHatasi != null) return false;

    final kurum = _sirket.text.trim();
    final dkAnaPara = parseTrNumber(_dkAnaPara.text) ?? 0;
    final dkBirikim = _dkBirikim;
    final devletEtiketi = l10n.pensionGovShort;
    try {
      await ref.read(sozlesmeProvider.notifier).besAc(
            kurum: kurum,
            giris: _giris,
            birikim: _birikim,
            odenen: parseTrNumber(_anaPara.text)!,
            dagilim: dagilim,
            adUret: (kod, {required devlet}) =>
                devlet ? '$kurum · $kod · $devletEtiketi' : '$kurum · $kod',
            dkBirikim: dkBirikim > 0 ? dkBirikim : null,
            dkOdenen: dkBirikim > 0 && dkAnaPara > 0 ? dkAnaPara : null,
            dkFonKodu: _dkFonu?.code,
            aylikKatki: parseTrNumber(_aylik.text),
            katkiGunu: int.tryParse(_gun.text.trim()),
          );
      return true;
    } on BesFiyatYokException catch (e) {
      if (mounted) {
        sandikSnack(context, l10n.pensionPriceMissing(e.kod),
            kind: SandikSnackKind.error);
      }
      return false;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'BesFormu.kaydet');
      if (mounted) {
        sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      }
      return false;
    }
  }

  String? _pozitif(String? v, String hata) {
    final x = parseTrNumber(v ?? '');
    return x == null || x <= 0 ? hata : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Form(
      key: _form,
      // Mevduat formuyla aynı: ilk başarısız denemeden sonra hata metni alan
      // düzeltilince kalkar (2026-10-01 emülatör testi).
      autovalidateMode: _denendi
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SozlesmeEtiketi(l10n.pensionCompany),
          SozlesmeAlani(
            controller: _sirket,
            ipucu: l10n.pensionCompanyHint,
            buyukHarf: true,
            dogrula: (v) =>
                (v ?? '').trim().isEmpty ? l10n.pensionErrorCompany : null,
          ),
          const SizedBox(height: SandikSpace.lgs),
          SozlesmeTarihi(
            etiket: l10n.pensionEntryDate,
            tarih: _giris,
            // BES 27 Ekim 2003'te başladı; öncesi seçilemez.
            ilk: DateTime(2003, 10, 27),
            degisti: (d) => setState(() => _giris = d),
          ),
          SozlesmeNotu(l10n.pensionEntryDateHint),
          const SizedBox(height: SandikSpace.lgs),
          SozlesmeEtiketi(l10n.pensionPrincipal),
          SozlesmeAlani(
            controller: _anaPara,
            ipucu: '0',
            sonek: '₺',
            sayi: true,
            dogrula: (v) => _pozitif(v, l10n.pensionErrorPrincipal),
          ),
          SozlesmeNotu(l10n.pensionPrincipalHint),
          const SizedBox(height: SandikSpace.lgs),
          SozlesmeEtiketi(l10n.pensionGain, ek: l10n.optional),
          SozlesmeAlani(
            controller: _getiri,
            ipucu: '0',
            sonek: '₺',
            sayi: true,
            isaretli: true,
            dogrula: (_) =>
                _birikim <= 0 && (parseTrNumber(_anaPara.text) ?? 0) > 0
                    ? l10n.pensionErrorBalance
                    : null,
          ),
          SozlesmeNotu(l10n.pensionGainHint),
          const SizedBox(height: SandikSpace.sm),
          SozlesmeOzetSatiri(
            etiket: l10n.pensionTotal,
            deger: fmtTRY(_birikim > 0 ? _birikim : 0),
            vurgulu: true,
          ),
          SozlesmeNotu(l10n.pensionHistoryHint),
          const SizedBox(height: SandikSpace.lg),

          // ── Fon dağılımı ────────────────────────────────────────────
          SozlesmeEtiketi(l10n.pensionFunds),
          BesDagilimEditoru(
            key: _dagilimEditoru,
            hata: _dagilimHatasi,
            degisti: () {
              if (_dagilimHatasi != null) {
                setState(() => _dagilimHatasi = null);
              }
            },
          ),
          const SizedBox(height: SandikSpace.lg),

          // ── Devlet katkısı ─────────────────────────────────────────
          SozlesmeEtiketi(l10n.pensionGovPrincipal, ek: l10n.optional),
          SozlesmeAlani(
            controller: _dkAnaPara,
            ipucu: '0',
            sonek: '₺',
            sayi: true,
            dogrula: (_) => _dkBirikim > 0 && _dkFonu == null
                ? l10n.pensionErrorGovFund
                : null,
          ),
          const SizedBox(height: SandikSpace.sm),
          SozlesmeEtiketi(l10n.pensionGovGain, ek: l10n.optional),
          SozlesmeAlani(
            controller: _dkGetiri,
            ipucu: '0',
            sonek: '₺',
            sayi: true,
            isaretli: true,
          ),
          const SizedBox(height: SandikSpace.sm),
          InkWell(
            borderRadius: SandikRadius.mdAll,
            onTap: _dkFonuSec,
            child: Container(
              constraints: const BoxConstraints(minHeight: SandikTouch.min),
              padding: const EdgeInsets.symmetric(
                  horizontal: SandikSpace.md2, vertical: SandikSpace.smd),
              decoration: BoxDecoration(
                color: context.c.surface1,
                borderRadius: SandikRadius.mdAll,
                border: Border.all(color: context.c.overlay),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance_outlined,
                      size: 16, color: context.c.text58),
                  const SizedBox(width: SandikSpace.sm2),
                  Expanded(
                    child: Text(
                      _dkFonu == null
                          ? l10n.pensionGovFund
                          : '${_dkFonu!.code} · ${_dkFonu!.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _dkFonu == null
                            ? context.c.text58
                            : context.c.text90,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 16, color: context.c.text36),
                ],
              ),
            ),
          ),
          SozlesmeNotu(l10n.pensionGovFundHint),
          const SizedBox(height: SandikSpace.lg),

          // ── Katkı planı ────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SozlesmeEtiketi(l10n.pensionMonthly, ek: l10n.optional),
                    SozlesmeAlani(
                      controller: _aylik,
                      ipucu: '0',
                      sonek: '₺',
                      sayi: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SozlesmeEtiketi(l10n.pensionDay),
                    SozlesmeAlani(
                      controller: _gun,
                      ipucu: '1-28',
                      sayi: true,
                      dogrula: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return null;
                        final g = int.tryParse(t);
                        return g == null || g < 1 || g > 28 ? '1-28' : null;
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
