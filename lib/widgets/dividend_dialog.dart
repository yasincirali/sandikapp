import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../demo/demo_modu.dart';
import '../models/asset.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/tr_format.dart';
import '../services/analytics_service.dart';
import '../services/remote_config_service.dart';
import '../services/review_prompt_service.dart';
import '../services/temettu_gecmisi.dart';
import 'sandik_async_button.dart';
import 'review_prompt_sheet.dart';
import '../l10n/l10n.dart';

/// Nakit temettü kaydı.
///
/// Temettü **miktarı değiştirmez** — eline geçen parayı kaydeder ve getiriye
/// eklenir. Kullanıcı stopaj sonrası NET tutarı girer; uygulama vergi hesabı
/// yapmaz (yatırım/vergi tavsiyesi vermemek için bilinçli tercih). Tek
/// istisna öneriyle açılış: mevzuattaki kâr payı stopajı (Remote Config,
/// varsayılan %15) brütten düşülür, düşülen tutar ve net AÇIKÇA yazılır ve
/// alan düzenlenebilir kalır — bir öneri, kesinleşmiş hesap değil.
///
/// ## Öneriyle açılış (temettü yakalama, 2026-09-29)
/// [oneri] verilirse (push `type: 'temettu'`, çan kaydı ya da "Son 12 ay
/// temettü" kartı) dayanak satırları görünür: brüt = lot × TL/pay; Remote
/// Config stopaj oranı biliniyorsa alan net öneriyle ÖN DOLU ve "stopaj %x
/// varsayıldı" notu, bilinmiyorsa alan BOŞ ve "Brüt ₺x — stopaj sonrası
/// eline geçeni yaz" notu (#12: brütle ön dolu alan tek dokunuşla brütü
/// net diye kaydediyordu). Kayıt yine AYNI yoldan
/// (`addDividend`) ve kullanıcı "Kaydet"e basınca gider — öneri hiçbir şeyi
/// kendiliğinden yazmaz. Tarih hak tarihi olur (BIST'te ödeme çoğunlukla o
/// gün); kullanıcı değiştirebilir.
///
/// [stopajKaynagi] testler için; verilmezse Remote Config okunur.
///
/// `WidgetRef` almaz: diyalog kendi `ref`'ini taşır (ConsumerStatefulWidget).
/// Push dokunuşu gibi widget ağacı DIŞINDAN açılış (NotificationService)
/// yalnızca `BuildContext` bilir.
Future<void> showDividendDialog(
  BuildContext context, {
  required Asset asset,
  TemettuOnerisi? oneri,
  double? Function()? stopajKaynagi,
}) async {
  if (DemoModu.yazmaKapisi('temettu')) return; // Demo: kaydetmek hesap ister (F1).
  final stopaj = oneri == null
      ? null
      : (stopajKaynagi ??
          () => RemoteConfigService.instance.temettuStopajOrani)();
  final kaydedildi = await showSandikGecisli<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _DividendDialog(
      asset: asset,
      oneri: oneri,
      stopaj: stopaj,
    ),
  );
  // Önerinin akıbeti ölçülür: "kaydedildi" oranı düşükse öneri ya yanlış
  // ya gereksizdir (bayrak kademeli açılırken karar verisi).
  if (oneri != null) {
    unawaited(AnalyticsService.instance.logDividendSuggestion(
        action: kaydedildi == true ? 'recorded' : 'dismissed'));
  }
  // Temettü kaydedildi — eline para geçmiş kullanıcı; diyalog kapandıktan
  // sonra sorulur. Karar ve sıklık `ReviewPromptService`'te.
  if (kaydedildi == true && context.mounted) {
    await ReviewPromptSheet.belkiGoster(context, ReviewAni.temettuKaydi);
  }
}

class _DividendDialog extends ConsumerStatefulWidget {
  final Asset asset;
  final TemettuOnerisi? oneri;

  /// 0..1 ya da `null` (bilinmiyor) — yalnız [oneri] varken anlamlı.
  final double? stopaj;

  const _DividendDialog({
    required this.asset,
    this.oneri,
    this.stopaj,
  });

  @override
  ConsumerState<_DividendDialog> createState() => _DividendDialogState();
}

class _DividendDialogState extends ConsumerState<_DividendDialog> {
  final _amount = TextEditingController();
  late DateTime _paidAt;
  bool _saving = false;
  String? _error;

  /// Öneri tutarı net mi (stopaj uygulandı) — not satırı buna göre.
  bool _oneriNet = false;

  @override
  void initState() {
    super.initState();
    _paidAt = DateTime.now();
    final o = widget.oneri;
    if (o != null) {
      final t = TemettuGecmisi.oneriTutari(o.brut, widget.stopaj);
      _oneriNet = t.net;
      // Alan `parseTrNumber` ile okunur; `fmtInputTr` gidiş-dönüşte kayıpsız.
      // Stopaj bilinmiyorsa alan BOŞ kalır (#12): "ele geçen NET" alanına
      // brüt yazmak tek dokunuşla yanlış kayıt demekti.
      final tutar = t.tutar;
      if (tutar != null) _amount.text = fmtInputTr(tutar, maxDigits: 2);
      // Öğlen: cihaz hangi saat diliminde olursa olsun kayıt TR takviminde
      // hak gününe düşsün (gece yarısı bir gün geri kayabilirdi).
      final h = o.hakTarihi;
      _paidAt = DateTime(h.year, h.month, h.day, 12);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  // Uygulamanın tek girdi kuralı. Eski `replaceAll('.', '')` "12.5" TL
  // temettüyü 125 okuyordu (2026-09-23 denetimi F5).
  double? _parse(String raw) => parseTrNumber(raw);

  Future<void> _save() async {
    final amount = _parse(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = context.l10n.enterValidAmount);
      return;
    }
    // Net, brütü aşamaz. Emülatör testinde (2026-10-01) SAHOL'da 777,46
    // brütlük temettü ₺150.660,84 kayıtlıydı: ön dolu "660,84"ün önüne
    // silinmeden "150" yazılmış, satır kârı −%7,91 yerine +%285 görünüyordu.
    // Dayanak (brüt) biliniyorsa böyle bir kayıt baştan durdurulur.
    final o = widget.oneri;
    if (o != null && o.brut > 0 && amount > o.brut * 1.0001) {
      setState(() => _error =
          context.l10n.dividendAboveGross(fmtTRY(o.brut, digits: 2)));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(portfolioProvider.notifier).addDividend(
            asset: widget.asset,
            amount: amount,
            paidAt: _paidAt,
          );
      if (!mounted) return;
      // Başarı toast'ı YOK (kullanıcı kararı, 2026-09-16): diyalog kapanıyor
      // ve temettü hareket listesine düşüyor. Hata yolu `_error` ile diyalogda
      // kalmaya devam eder.
      // `true`: çağıran öneri akıbetini "recorded" diye ölçer.
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Kaydedilemedi. ${friendlyError(e)}';
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await pickSandikDate(
      context,
      initialDate: _paidAt,
      helpText: context.l10n.dividendPayDate,
    );
    if (picked != null) setState(() => _paidAt = picked);
  }

  /// Önerinin dayanağı: hangi olay, hangi lot, brüt ne. Kullanıcı tutarı
  /// buradan doğrular ("100 lotum vardı, doğru").
  List<Widget> _oneriSatirlari(TemettuOnerisi o, DateFormat dateFmt) {
    final kod = o.ticker.replaceAll(RegExp(r'\.IS$', caseSensitive: false), '');
    final stil = context.t.bodySmall?.copyWith(color: context.c.text90);
    return [
      const SizedBox(height: SandikSpace.sm),
      Text(
        context.l10n.dividendSuggestionLine(
            kod, dateFmt.format(o.hakTarihi)),
        style: stil?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: SandikSpace.xs2),
      Text(
        context.l10n.dividendSuggestionGross(
          fmtNumFlex(o.lot),
          '₺${fmtNumFlex(o.tutarPay)}',
          fmtTRY(o.brut, digits: 2),
        ),
        style: stil,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    final dateFmt = DateFormat('dd/MM/yyyy', 'tr_TR');

    return AlertDialog(
      // Öneri satırları içeriği uzatır; küçük ekranda + klavye açıkken
      // taşmasın. Önerisiz (elle) açılış eskisi gibi.
      scrollable: widget.oneri != null,
      backgroundColor: context.c.surface2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      title: Row(
        children: [
          Icon(Icons.savings_outlined, color: context.c.gain, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(context.l10n.addDividend,
                style: context.t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: context.c.text90)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.netAmountReceived(a.displayTicker ?? a.name),
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
          if (widget.oneri != null) ..._oneriSatirlari(widget.oneri!, dateFmt),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: context.t.titleMedium?.copyWith(color: context.c.text90),
            decoration: InputDecoration(
              hintText: '0',
              suffixText: a.currency,
              suffixStyle: context.t.titleSmall?.copyWith(
                  color: context.c.text58, fontWeight: FontWeight.w700),
              // Dolgu/çerçeve temadan (`inputDecorationTheme` = `inputFill` kuralı).
            ),
            onSubmitted: (_) => _saving ? null : _save(),
          ),
          const SizedBox(height: 12),
          // Ödeme tarihi — TRY karşılığı bu günün kuruyla sabitlenir.
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(SandikRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Icon(Icons.event_outlined,
                      size: 18, color: context.c.text58),
                  const SizedBox(width: 8),
                  // Flexible: dar ekran + büyük metinde tarih satırı taşıyordu
                  // (temettü önerisi testinde yakalandı, 2026-09-29).
                  Flexible(
                    child: Text(context.l10n.paymentDate(dateFmt.format(_paidAt)),
                        style: context.t.bodyMedium
                            ?.copyWith(color: context.c.text90)),
                  ),
                ],
              ),
            ),
          ),
          if (widget.oneri != null) ...[
            const SizedBox(height: 6),
            // Tutarın ne olduğunu SÖYLE: net öneri mi (varsayılan oranla),
            // yoksa boş alan + brüt dayanak mı. Kullanıcı düzeltmeden
            // kaydederse bile neyi onayladığını bilir.
            //
            // Net öneride kesinti TUTARI ve net de yazılır (karar 8.2,
            // 2026-09-30): yalnız oranı yazmak hesabı kullanıcıya bırakıyordu,
            // "gizli kesinti" okunmasın. Sayılar alandaki öneriyle aynı
            // kaynaktan (`oneriTutari`); kullanıcı alanı değiştirirse satır
            // önerinin dayanağı olarak kalır.
            Text(
              _oneriNet
                  ? context.l10n.dividendWithholdingAssumed(
                      fmtPct(widget.stopaj! * 100, digits: 0),
                      fmtTRY(widget.oneri!.brut * widget.stopaj!, digits: 2),
                      fmtTRY(
                          TemettuGecmisi.oneriTutari(
                                  widget.oneri!.brut, widget.stopaj)
                              .tutar!,
                          digits: 2))
                  : context.l10n
                      .dividendEnterNet(fmtTRY(widget.oneri!.brut, digits: 2)),
              style: context.t.bodySmall?.copyWith(color: context.c.amberText),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            context.l10n.dividendNote,
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: context.t.bodySmall
                    ?.copyWith(color: context.c.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        // Gösterge + çift dokunuş kilidi standart bileşende (tek yükleniyor
        // davranışı, 2026-10-08; eski elle yazılmış 18pt gösterge kalktı).
        // `_saving` kalır: kayıt sürerken İptal ve klavye "gönder"i pasif.
        SandikAsyncButton.kompakt(
          style: FilledButton.styleFrom(
            backgroundColor: context.c.gain,
            foregroundColor: context.c.onStatus,
          ),
          onPressed: _save,
          mesgul: _saving,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
