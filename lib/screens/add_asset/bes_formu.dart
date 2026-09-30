import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/demo_modu.dart';
import '../../l10n/l10n.dart';
import '../../models/asset_type.dart';
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
import '../../widgets/sozlesme_formu_ortak.dart';

/// BES sözleşmesi girişi (seçenek B3).
///
/// Kullanıcının BİLDİĞİ sayılarla girilir: şirket, sisteme giriş, bugünkü
/// birikim, bugüne kadar ödenen katkı, fon dağılımı. Pay adedi sorulmaz —
/// kimse bilmez; açılışta birikim ÷ bugünkü fon fiyatından hesaplanır
/// (`SozlesmeNotifier.besAc`). Devlet katkısı ayrı ve isteğe bağlıdır:
/// fonu bilinmeyen devlet katkısı değerlenemez, uydurma fiyatla eklenmez.
class BesFormu extends ConsumerStatefulWidget {
  const BesFormu({super.key});

  @override
  ConsumerState<BesFormu> createState() => BesFormuState();
}

class _FonSatiri {
  _FonSatiri(this.fon, String oran) : oran = TextEditingController(text: oran);
  final TefasFund fon;
  final TextEditingController oran;
}

class BesFormuState extends ConsumerState<BesFormu> implements SozlesmeFormu {
  final _form = GlobalKey<FormState>();
  final _sirket = TextEditingController();
  final _birikim = TextEditingController();
  final _odenen = TextEditingController();
  final _dkBirikim = TextEditingController();
  final _aylik = TextEditingController();
  final _gun = TextEditingController();
  final _fonlar = <_FonSatiri>[];
  TefasFund? _dkFonu;
  DateTime _giris = DateTime.now();
  String? _dagilimHatasi;

  @override
  void dispose() {
    for (final c in [_sirket, _birikim, _odenen, _dkBirikim, _aylik, _gun]) {
      c.dispose();
    }
    for (final f in _fonlar) {
      f.oran.dispose();
    }
    super.dispose();
  }

  List<FonPayi> get _dagilim => [
        for (final f in _fonlar)
          FonPayi(kod: f.fon.code, oran: parseTrNumber(f.oran.text) ?? 0),
      ];

  double get _oranToplami =>
      _dagilim.fold<double>(0, (t, f) => t + f.oran);

  Future<void> _fonEkle() async {
    final f = await emeklilikFonuSec(context, devletKatkisi: false);
    if (f == null || !mounted) return;
    if (_fonlar.any((x) => x.fon.code == f.code)) return;
    setState(() {
      // İlk fon %100, sonrakiler kalan yüzdeyle açılır.
      final kalan = 100 - _oranToplami;
      _fonlar.add(_FonSatiri(
          f, fmtNumFlex(kalan > 0 ? kalan : 0, maxDigits: 2)));
      _dagilimHatasi = null;
    });
  }

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
    final dagilim = _dagilim;
    String? dagilimHatasi;
    if (dagilim.isEmpty) {
      dagilimHatasi = l10n.pensionFundError;
    } else if (!BesHesabi.dagilimGecerli(dagilim)) {
      dagilimHatasi = l10n.pensionShareError;
    }
    setState(() => _dagilimHatasi = dagilimHatasi);
    if (!formGecerli || dagilimHatasi != null) return false;

    final kurum = _sirket.text.trim();
    final dk = parseTrNumber(_dkBirikim.text);
    final devletEtiketi = l10n.pensionGovShort;
    try {
      await ref.read(sozlesmeProvider.notifier).besAc(
            kurum: kurum,
            giris: _giris,
            birikim: parseTrNumber(_birikim.text)!,
            odenen: parseTrNumber(_odenen.text) ?? parseTrNumber(_birikim.text)!,
            dagilim: dagilim,
            adUret: (kod, {required devlet}) =>
                devlet ? '$kurum · $kod · $devletEtiketi' : '$kurum · $kod',
            dkBirikim: dk != null && dk > 0 ? dk : null,
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
    final renk = AssetType.bes.onSurface(context);
    return Form(
      key: _form,
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
          SozlesmeEtiketi(l10n.pensionBalance),
          SozlesmeAlani(
            controller: _birikim,
            ipucu: '0',
            sonek: '₺',
            sayi: true,
            dogrula: (v) => _pozitif(v, l10n.pensionErrorBalance),
          ),
          SozlesmeNotu(l10n.pensionBalanceHint),
          const SizedBox(height: SandikSpace.lgs),
          SozlesmeEtiketi(l10n.pensionPaid, ek: l10n.optional),
          SozlesmeAlani(
            controller: _odenen,
            ipucu: '0',
            sonek: '₺',
            sayi: true,
          ),
          const SizedBox(height: SandikSpace.lg),

          // ── Fon dağılımı ────────────────────────────────────────────
          SozlesmeEtiketi(l10n.pensionFunds),
          for (final f in _fonlar) ...[
            _FonSatiriGorunumu(
              satir: f,
              renk: renk,
              degisti: () => setState(() => _dagilimHatasi = null),
              sil: () => setState(() {
                _fonlar.remove(f);
                f.oran.dispose();
              }),
            ),
            const SizedBox(height: SandikSpace.sm),
          ],
          // Sarmalı: büyük metin ölçeğinde (320pt × 3.0) düğme ve toplam
          // yan yana sığmıyordu; toplam alt satıra iner.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: SandikSpace.sm,
            children: [
              TextButton.icon(
                onPressed: _fonEkle,
                icon: Icon(Icons.add_rounded, color: context.c.amberText),
                label: Text(l10n.pensionAddFund,
                    style: context.t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.c.amberText)),
              ),
              if (_fonlar.isNotEmpty)
                Text(
                  l10n.pensionShareTotal(fmtPct(_oranToplami, digits: 0)),
                  style: context.t.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: BesHesabi.dagilimGecerli(_dagilim)
                        ? context.c.text58
                        : context.c.danger,
                  ),
                ),
            ],
          ),
          if (_dagilimHatasi != null)
            Text(_dagilimHatasi!,
                style: context.t.bodySmall?.copyWith(color: context.c.danger)),
          const SizedBox(height: SandikSpace.lg),

          // ── Devlet katkısı ─────────────────────────────────────────
          SozlesmeEtiketi(l10n.pensionGovBalance, ek: l10n.optional),
          SozlesmeAlani(
            controller: _dkBirikim,
            ipucu: '0',
            sonek: '₺',
            sayi: true,
            dogrula: (v) {
              final x = parseTrNumber(v ?? '');
              if (x != null && x > 0 && _dkFonu == null) {
                return l10n.pensionErrorGovFund;
              }
              return null;
            },
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

class _FonSatiriGorunumu extends StatelessWidget {
  const _FonSatiriGorunumu({
    required this.satir,
    required this.renk,
    required this.degisti,
    required this.sil,
  });

  final _FonSatiri satir;
  final Color renk;
  final VoidCallback degisti;
  final VoidCallback sil;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(satir.fon.code,
                    style: context.t.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800, color: renk)),
                Text(satir.fon.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58)),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          SizedBox(
            width: 96,
            child: SozlesmeAlani(
              controller: satir.oran,
              ipucu: '0',
              sonek: '%',
              sayi: true,
              degisti: (_) => degisti(),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            onPressed: sil,
            icon: Icon(Icons.close_rounded, color: context.c.text36),
          ),
        ],
      );
}
