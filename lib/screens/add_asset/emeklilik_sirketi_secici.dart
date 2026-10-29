import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../models/asset_type.dart';
import '../../models/emeklilik_sirketi.dart';
import '../../providers/fon_karnesi_provider.dart';
import '../../theme/sandik.dart';
import '../../utils/tr_katla.dart';
import '../../widgets/custom_loading_indicator.dart';

/// Emeklilik şirketi seçici — alt sayfa (2026-10-29).
///
/// Mevduat banka seçicisiyle aynı iskelet (arama + liste + "yazdığını
/// kullan"). Liste TEFAS EMK fon unvanlarından türetilir
/// ([emeklilikSirketleri]); elle tutulan bir şirket listesi yok, uydurma
/// şirket görünmez. Liste yüklenemezse ya da şirket listede yoksa kullanıcı
/// yazdığı adı kullanır — seçici çıkmaz sokak değildir, eski serbest metin
/// davranışı bu satırda yaşar.
///
/// Dönen değer: seçilen ya da yazılan ad; vazgeçilirse `null`.
Future<String?> emeklilikSirketiSec(BuildContext context, {String? secili}) =>
    showSandikSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => _Secici(secili: secili),
    );

class _Secici extends ConsumerStatefulWidget {
  const _Secici({this.secili});
  final String? secili;

  @override
  ConsumerState<_Secici> createState() => _SeciciState();
}

class _SeciciState extends ConsumerState<_Secici> {
  final _ara = TextEditingController();

  @override
  void dispose() {
    _ara.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final yukseklik = MediaQuery.sizeOf(context).height * 0.8;
    final katalog = ref.watch(fonKatalogProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                    l10n.pensionPickCompany,
                    style: context.t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700, color: context.c.text90),
                  ),
                  const SizedBox(height: SandikSpace.smd),
                  TextField(
                    controller: _ara,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: context.inputDecoration(
                      l10n.pensionCompanyHint,
                      prefixIcon:
                          Icon(Icons.search_rounded, color: context.c.text58),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: katalog.when(
                loading: () =>
                    const Center(child: CustomLoadingIndicator(size: 28)),
                // Katalog hatayı boş listeye çevirir; buraya düşerse de
                // elle ad yolu açık kalsın.
                error: (_, __) => _liste(context, const []),
                data: (fonlar) => _liste(
                    context,
                    emeklilikSirketleri([
                      for (final f in fonlar)
                        if (f.fundType == 'EMK') f.name,
                    ])),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _liste(BuildContext context, List<EmeklilikSirketi> hepsi) {
    final l10n = context.l10n;
    final q = _ara.text.trim();
    final qk = trKatla(q);
    final suzulmus = [
      for (final s in hepsi)
        if (qk.isEmpty || trKatla(s.ad).contains(qk)) s,
    ];
    final birebir = suzulmus.any((s) => trKatla(s.ad) == qk);
    final secili = emeklilikSirketiBul(widget.secili, hepsi);
    return ListView(
      padding: const EdgeInsets.only(bottom: SandikSpace.lg),
      children: [
        if (hepsi.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(SandikSpace.lgs, SandikSpace.sm,
                SandikSpace.lgs, SandikSpace.md),
            child: Text(l10n.pensionCompanyListUnavailable,
                style:
                    context.t.bodyMedium?.copyWith(color: context.c.text58)),
          ),
        if (q.isNotEmpty && !birebir)
          _Satir(
            ad: l10n.pensionCompanyUseTyped(q),
            yazilan: true,
            secili: false,
            dokununca: () => Navigator.of(context).pop(q),
          ),
        for (final s in suzulmus)
          _Satir(
            ad: s.ad,
            ek: l10n.pensionFundCount(s.fonSayisi),
            secili: s == secili,
            dokununca: () => Navigator.of(context).pop(s.ad),
          ),
      ],
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({
    required this.ad,
    required this.secili,
    required this.dokununca,
    this.ek,
    this.yazilan = false,
  });

  final String ad;
  final String? ek;
  final bool secili;
  final bool yazilan;
  final VoidCallback dokununca;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: secili,
      child: InkWell(
        onTap: dokununca,
        child: Container(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.lgs, vertical: SandikSpace.sm),
          child: Row(
            children: [
              Icon(
                  yazilan
                      ? Icons.edit_rounded
                      : Icons.account_balance_outlined,
                  size: 18,
                  color: yazilan
                      ? context.c.text58
                      : AssetType.bes.onSurface(context)),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Text(ad,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodyLarge?.copyWith(
                        color: context.c.text90,
                        fontWeight: secili ? FontWeight.w700 : null)),
              ),
              if (ek != null) ...[
                const SizedBox(width: SandikSpace.sm),
                Text(ek!,
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58)),
              ],
              if (secili) ...[
                const SizedBox(width: SandikSpace.sm),
                Icon(Icons.check_rounded,
                    size: 20, color: AssetType.bes.onSurface(context)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
