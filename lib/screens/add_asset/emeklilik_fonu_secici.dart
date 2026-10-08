import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/asset_type.dart';
import '../../services/crash_reporter.dart';
import '../../services/tefas_service.dart';
import '../../theme/sandik.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/custom_loading_indicator.dart';

/// TEFAS emeklilik fonu (EMK) seçici — alt sayfa.
///
/// [devletKatkisi] `true`: yalnız devlet katkısı fonları (adında "DEVLET
/// KATKI" geçen EMK fonları); `false`: onlar HARİÇ tüm EMK fonları.
/// Katılımcı kendi katkısını devlet katkısı fonuna yönlendiremez; iki liste
/// ayrık olursa yanlış seçim baştan engellenir.
Future<TefasFund?> emeklilikFonuSec(
  BuildContext context, {
  required bool devletKatkisi,
}) =>
    showSandikSheet<TefasFund>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => _Secici(devletKatkisi: devletKatkisi),
    );

/// Adı devlet katkısı fonu mu? Kural tek yerde: `devletKatkisiAdiMi`.
bool devletKatkisiFonuMu(TefasFund f) => devletKatkisiAdiMi(f.name);

class _Secici extends StatefulWidget {
  const _Secici({required this.devletKatkisi});
  final bool devletKatkisi;

  @override
  State<_Secici> createState() => _SeciciState();
}

class _SeciciState extends State<_Secici> {
  final _ara = TextEditingController();
  List<TefasFund>? _fonlar;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _ara.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      // Katkı fonları kataloğa güvenilmeden doğrudan çekilir (bkz.
      // `fetchDevletKatkisiFonlari`).
      final fonlar = widget.devletKatkisi
          ? await TefasService.instance.fetchDevletKatkisiFonlari()
          : _suz(await TefasService.instance.fetchAllFunds());
      if (!mounted) return;
      setState(() => _fonlar = fonlar);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'emeklilikFonuSec.yukle');
      if (mounted) setState(() => _hata = friendlyError(e));
    }
  }

  List<TefasFund> _suz(List<TefasFund> hepsi) => [
        for (final f in hepsi)
          if (f.fundType == 'EMK' &&
              devletKatkisiFonuMu(f) == widget.devletKatkisi)
            f,
      ]..sort((a, b) => a.name.compareTo(b.name));

  List<TefasFund> get _suzulmus {
    final q = _ara.text.trim().toLowerCase();
    final l = _fonlar ?? const <TefasFund>[];
    if (q.isEmpty) return l;
    return [
      for (final f in l)
        if (f.code.toLowerCase().contains(q) ||
            f.name.toLowerCase().contains(q))
          f,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final liste = _suzulmus;
    final yukseklik = MediaQuery.sizeOf(context).height * 0.8;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: yukseklik,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(SandikSpace.lgs,
                  SandikSpace.lgs, SandikSpace.lgs, SandikSpace.smd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.devletKatkisi
                        ? l10n.pensionPickGovFund
                        : l10n.pensionPickFund,
                    style: context.t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700, color: context.c.text90),
                  ),
                  const SizedBox(height: SandikSpace.smd),
                  TextField(
                    controller: _ara,
                    autofocus: false,
                    onChanged: (_) => setState(() {}),
                    decoration: context.inputDecoration(
                      l10n.pensionSearchFund,
                      prefixIcon: Icon(Icons.search_rounded,
                          color: context.c.text58),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _govde(context, liste)),
          ],
        ),
      ),
    );
  }

  Widget _govde(BuildContext context, List<TefasFund> liste) {
    if (_hata != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SandikSpace.lg),
          child: Text(_hata!,
              textAlign: TextAlign.center,
              style: context.t.bodyMedium?.copyWith(color: context.c.text58)),
        ),
      );
    }
    if (_fonlar == null) {
      return const Center(child: CustomLoadingIndicator(size: 28));
    }
    if (liste.isEmpty) {
      return Center(
        child: Text(context.l10n.pensionNoFundFound,
            style: context.t.bodyMedium?.copyWith(color: context.c.text58)),
      );
    }
    final renk = AssetType.bes.onSurface(context);
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: SandikSpace.lg),
      itemCount: liste.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: context.c.hairline),
      itemBuilder: (context, i) {
        final f = liste[i];
        return InkWell(
          onTap: () => Navigator.of(context).pop(f),
          child: Container(
            constraints: const BoxConstraints(minHeight: SandikTouch.min),
            padding: const EdgeInsets.symmetric(
                horizontal: SandikSpace.lgs, vertical: SandikSpace.sm2),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(f.code,
                      style: context.t.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800, color: renk)),
                ),
                const SizedBox(width: SandikSpace.sm),
                Expanded(
                  child: Text(f.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodyMedium
                          ?.copyWith(color: context.c.text90)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
