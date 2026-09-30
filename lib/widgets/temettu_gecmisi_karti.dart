import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../providers/preferences_provider.dart';
import '../services/analytics_service.dart';
import '../services/fiyat_kaynagi.dart';
import '../services/remote_config_service.dart';
import '../services/temettu_gecmisi.dart';
import '../theme/sandik.dart';
import '../utils/money_format.dart';
import '../utils/tr_format.dart';
import 'dividend_dialog.dart';

/// Hisse varlık ekranında "Son 12 ay temettü" kartı (plan §F5, 1. aşama).
///
/// ## Ne gösterir
/// Yahoo'ya göre son 12 ayda GERÇEKLEŞMİŞ temettüler; her biri için hak
/// tarihindeki lotun, brüt tutar ve kaydedip kaydetmediğin. Kaydedilmemiş
/// satırda "Kaydet" → ön dolu temettü diyaloğu (kayıt yine `addDividend`
/// yolundan, senin onayınla). Tahmin DEĞİL, geçmiş: ilan edilmiş gelecek
/// temettü Yahoo'da yok (KAP gelince, ADR-2 B).
///
/// ## Ne zaman hiç görünmez (tek piksel yer kaplamaz)
///   · `dividend_capture_enabled` bayrağı kapalı (release varsayılanı),
///   · varlık TRY kote BIST hissesi değil (`FiyatKaynagi.temettuSembolu`),
///   · 12 ayda hak tarihinde lotun olduğu olay yok, ya da veri çekilemedi.
/// Boş kart "temettü yok" demek olurdu; veri çekilemediyse bu yanlış olur.
class TemettuGecmisiKarti extends ConsumerStatefulWidget {
  /// Pozisyonun ekran görünümü (`asDisplayAsset`) — sahibi ve anahtarı.
  final Asset varlik;

  /// Sahibin defteri (alım/satım/temettü satırları). Geçmişi soran hesap:
  /// kapalı pozisyonun eski temettüsü de görünür (CLAUDE.md "Kapanmış
  /// pozisyon").
  final List<Asset> defter;

  /// Testler için; verilmezse Remote Config bayrağı.
  final bool? etkin;

  /// Testler için; verilmezse `TemettuGecmisiService`.
  final Future<List<TemettuOlayi>> Function(String sembol)? olayCekici;

  const TemettuGecmisiKarti({
    super.key,
    required this.varlik,
    required this.defter,
    this.etkin,
    this.olayCekici,
  });

  @override
  ConsumerState<TemettuGecmisiKarti> createState() =>
      _TemettuGecmisiKartiState();
}

class _TemettuGecmisiKartiState extends ConsumerState<TemettuGecmisiKarti> {
  String? _sembol;
  List<TemettuOlayi>? _olaylar;

  /// Olay × defter sonucu — build'de değil, veri ya da defter değişince.
  List<TemettuSatiri> _satirlar = const [];
  double _kaydedilen = 0;
  bool _gosterildiLoglandi = false;

  @override
  void initState() {
    super.initState();
    final etkin =
        widget.etkin ?? RemoteConfigService.instance.dividendCaptureEnabled;
    _sembol = etkin ? FiyatKaynagi.temettuSembolu(widget.varlik) : null;
    final s = _sembol;
    if (s == null) return;
    final cek = widget.olayCekici ??
        (String x) => TemettuGecmisiService.instance.olaylariCek(x);
    cek(s).then((o) {
      if (!mounted) return;
      setState(() {
        _olaylar = o;
        _hesapla();
      });
    });
  }

  @override
  void didUpdateWidget(TemettuGecmisiKarti old) {
    super.didUpdateWidget(old);
    // Kayıt eklenince defter yeni liste olarak gelir → eşleme tazelenir,
    // satır "Kaydedildi"ye döner.
    if (!identical(old.defter, widget.defter) && _olaylar != null) {
      _hesapla();
    }
  }

  void _hesapla() {
    final olaylar = _olaylar;
    if (olaylar == null) return;
    _satirlar = TemettuGecmisi.satirlar(
      varlik: widget.varlik,
      defter: widget.defter,
      olaylar: olaylar,
    );
    _kaydedilen = TemettuGecmisi.kaydedilenToplam(
      widget.defter,
      widget.varlik,
      simdi: DateTime.now(),
    );
    if (!_gosterildiLoglandi && _satirlar.any((s) => !s.kaydedildi)) {
      _gosterildiLoglandi = true;
      unawaited(
          AnalyticsService.instance.logDividendSuggestion(action: 'shown'));
    }
  }

  Future<void> _kaydet(TemettuSatiri s) => showDividendDialog(
        context,
        asset: widget.varlik,
        oneri: s.oneri(_sembol!),
      );

  @override
  Widget build(BuildContext context) {
    if (_sembol == null || _satirlar.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final c = context.c;
    final tarih = DateFormat('dd.MM.yyyy', 'tr_TR');
    // "Bakiyeyi gizle" (bulgu #3): kaydedilen toplam ve brüt tutar senin
    // lotunla çarpılmış paradır → maskelenir. Pay başı tutar ve lot sayısı
    // açık kalır (hareket satırında da miktar açık; kural Ana ile aynı).
    final gizli = ref.watch(balanceHiddenProvider);
    String tl(double v) =>
        gizli ? const BazPara.lira().gizliTutar : fmtTRY(v, digits: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Üst boşluk kartın İÇİNDE: kart gizliyken ekranda boş şerit kalmasın.
        const SizedBox(height: SandikSpace.lg),
        SandikSectionHeader(title: l.dividendHistoryUpper),
        const SizedBox(height: SandikSpace.sm),
        SandikCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_kaydedilen > 0) ...[
                Text(
                  l.dividendRecordedTotal(tl(_kaydedilen)),
                  style: context.t.bodyMedium?.copyWith(
                      color: c.gain, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: SandikSpace.sm),
              ],
              for (var i = 0; i < _satirlar.length; i++) ...[
                if (i > 0) Divider(height: SandikSpace.md, color: c.hairline),
                _satir(_satirlar[i], tarih, tl),
              ],
              const SizedBox(height: SandikSpace.sm),
              Text(
                l.dividendSourceNote,
                style: context.t.bodySmall?.copyWith(color: c.text36),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _satir(
      TemettuSatiri s, DateFormat tarih, String Function(double) tl) {
    final l = context.l10n;
    final c = context.c;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tarih.format(s.olay.hakTarihi),
                style: context.t.bodyMedium
                    ?.copyWith(color: c.text90, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: SandikSpace.xxs),
              // Pay tutarı ondalığı KIRPILMAZ: 3,442 → 3,44 yazılsa kullanıcı
              // KAP'taki rakamla karşılaştırınca tutmaz.
              Text(
                '${l.dividendEventLine(fmtNumFlex(s.lot), '₺${fmtNumFlex(s.olay.tutarPay)}')}'
                ' · ${l.dividendGrossAmount(tl(s.brut))}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.t.bodySmall?.copyWith(color: c.text58),
              ),
            ],
          ),
        ),
        const SizedBox(width: SandikSpace.sm),
        if (s.kaydedildi)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 16, color: c.gain),
              const SizedBox(width: SandikSpace.xs),
              Text(
                l.dividendRecorded,
                style: context.t.bodySmall?.copyWith(color: c.gain),
              ),
            ],
          )
        else
          TextButton(
            onPressed: () => _kaydet(s),
            child: Text(l.dividendRecordAction),
          ),
      ],
    );
  }
}
