import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../models/asset_type.dart';
import '../../models/mevduat_bankasi.dart';
import '../../providers/mevduat_banka_provider.dart';
import '../../theme/sandik.dart';
import '../../widgets/custom_loading_indicator.dart';

/// Seçicinin sonucu: listeden bir banka ya da kullanıcının yazdığı ad
/// (listede yoksa — küçük banka, yeni marka). [banka] `null` → elle ad.
typedef MevduatBankaSecimi = ({MevduatBankasi? banka, String ad});

/// Mevduat banka seçici — alt sayfa (bayrak `mevduat_banka_secici`).
///
/// Emeklilik fonu seçicisiyle aynı iskelet (arama + liste). Liste
/// `mevduatKaynaklariProvider`'dan gelir; yüklenemezse kullanıcı yazdığı
/// adı kullanır — seçici hiçbir zaman çıkmaz sokak değildir.
Future<MevduatBankaSecimi?> mevduatBankasiSec(
  BuildContext context, {
  String? seciliKod,
}) =>
    showSandikSheet<MevduatBankaSecimi>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => _Secici(seciliKod: seciliKod),
    );

class _Secici extends ConsumerStatefulWidget {
  const _Secici({this.seciliKod});
  final String? seciliKod;

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
    final kaynak = ref.watch(mevduatKaynaklariProvider);
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
                    l10n.depositBankPick,
                    style: context.t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700, color: context.c.text90),
                  ),
                  const SizedBox(height: SandikSpace.smd),
                  TextField(
                    controller: _ara,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: context.inputDecoration(
                      l10n.depositBankSearchHint,
                      prefixIcon:
                          Icon(Icons.search_rounded, color: context.c.text58),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: kaynak.when(
                loading: () =>
                    const Center(child: CustomLoadingIndicator(size: 28)),
                // Sağlayıcı hatayı boş listeye çevirir; buraya düşmez ama
                // düşerse de elle ad yolu açık kalsın.
                error: (_, __) => _liste(context, const []),
                data: (k) => _liste(context, k.bankalar),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _liste(BuildContext context, List<MevduatBankasi> hepsi) {
    final l10n = context.l10n;
    final q = _ara.text.trim();
    final suzulmus = [
      for (final b in hepsi)
        if (b.eslesir(q)) b
    ];
    final mevduat = [
      for (final b in suzulmus)
        if (!b.katilim) b
    ];
    final katilim = [
      for (final b in suzulmus)
        if (b.katilim) b
    ];
    // Yazılan ad listedeki bir adla birebir aynıysa ayrıca "kullan" satırı
    // gösterilmez (aynı bankanın iki satırı olurdu).
    final birebir = suzulmus.any((b) =>
        b.ad.toLowerCase() == q.toLowerCase() ||
        b.digerAdlar.any((x) => x.toLowerCase() == q.toLowerCase()));

    final satirlar = <Widget>[
      if (hepsi.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
              SandikSpace.lgs, SandikSpace.sm, SandikSpace.lgs, SandikSpace.md),
          child: Text(l10n.depositBankListUnavailable,
              style: context.t.bodyMedium?.copyWith(color: context.c.text58)),
        ),
      if (q.isNotEmpty && !birebir)
        _Satir(
          rozet: null,
          ad: l10n.depositBankUseTyped(q),
          secili: false,
          dokununca: () => Navigator.of(context).pop((banka: null, ad: q)),
        ),
      if (mevduat.isNotEmpty && katilim.isNotEmpty)
        _Baslik(l10n.depositBankSectionDeposit),
      for (final b in mevduat) _bankaSatiri(context, b),
      if (katilim.isNotEmpty) _Baslik(l10n.depositBankSectionParticipation),
      for (final b in katilim) _bankaSatiri(context, b),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: SandikSpace.lg),
      children: satirlar,
    );
  }

  Widget _bankaSatiri(BuildContext context, MevduatBankasi b) => _Satir(
        rozet: b.rozet,
        ad: b.ad,
        secili: b.kod == widget.seciliKod,
        dokununca: () => Navigator.of(context).pop((banka: b, ad: b.ad)),
      );
}

class _Baslik extends StatelessWidget {
  const _Baslik(this.metin);
  final String metin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.lgs, SandikSpace.md, SandikSpace.lgs, SandikSpace.xs),
        child: Text(
          metin,
          style: context.t.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.c.text36,
          ),
        ),
      );
}

class _Satir extends StatelessWidget {
  const _Satir({
    required this.rozet,
    required this.ad,
    required this.secili,
    required this.dokununca,
  });

  /// `null` → "yazdığını kullan" satırı (kalem ikonu).
  final String? rozet;
  final String ad;
  final bool secili;
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
              rozet == null
                  ? SizedBox(
                      width: MevduatBankaRozeti.cap,
                      child: Icon(Icons.edit_rounded,
                          size: 18, color: context.c.text58),
                    )
                  : MevduatBankaRozeti(rozet!),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Text(ad,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodyLarge?.copyWith(
                        color: context.c.text90,
                        fontWeight: secili ? FontWeight.w700 : null)),
              ),
              if (secili)
                Icon(Icons.check_rounded,
                    size: 20, color: AssetType.mevduat.onSurface(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bankanın harf rozeti — `VarlikRozeti` ile aynı dil (tür renginde daire,
/// harf tür renginde). Logo değil (marka hakkı; bkz. [MevduatBankasi]).
class MevduatBankaRozeti extends StatelessWidget {
  const MevduatBankaRozeti(this.harfler, {super.key});

  final String harfler;

  static const double cap = 28;

  @override
  Widget build(BuildContext context) {
    final tur = AssetType.mevduat;
    return ExcludeSemantics(
      child: Container(
        width: cap,
        height: cap,
        decoration: BoxDecoration(
          color: tur.color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              harfler,
              maxLines: 1,
              style: context.t.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                height: 1,
                color: tur.onSurface(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
