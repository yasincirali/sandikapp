import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/veri_kalitesi_provider.dart';
import '../screens/add_asset_screen.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import 'sandik_async_button.dart';
import 'sandik_skeleton.dart';

/// Ana ekran, Bugün kartının altında tek satır: "N varlıkta bilgi eksik".
///
/// ## Neden şerit (yasin onayı 2026-10-20; Ar-Ge 13:15 #1 + 17:15 #3)
/// Eksik bilgi (okunamayan alış fiyatı, 30 günden eski elle fiyat) toplamı
/// ya da kâr/zararı sessizce yanlış gösteriyor. Ana sayfa toplam kartına
/// dokunulmaz (yasin kuralı); satır yalnız SÖYLENECEK bir şey varken çıkar,
/// [RadarSeridi] ile aynı kalıp. Kapatılabilir: kapatıldığı andaki
/// eksikler bir daha sorulmaz, yeni bir eksik çıkınca satır geri gelir
/// (`veriSeridiGorunur`). Hepsi düzelince kendiliğinden kalkar.
///
/// Dokununca eksikler SIRAYLA açılır ([veriKalitesiAkisi]): alış fiyatı
/// eksik lot için var olan düzenleme formu, bayat elle fiyat için tek
/// alanlı fiyat sayfası. Bayraksız: mevcut veriye dayanan ek, eksik yoksa
/// yer kaplamaz.
class VeriKalitesiSeridi extends ConsumerWidget {
  const VeriKalitesiSeridi({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SandikBelirme(child: _belirenGovde(context, ref));

  Widget _belirenGovde(BuildContext context, WidgetRef ref) {
    final eksikler = ref.watch(veriEksikleriProvider);
    final kapatilan = ref.watch(veriKalitesiKapatilanProvider);
    if (!veriSeridiGorunur(eksikler, kapatilan)) {
      return const SizedBox.shrink();
    }
    final c = context.c;
    final t = context.t;
    final l = context.l10n;
    final sayi = eksikPozisyonSayisi(eksikler);
    return Padding(
      padding: padding,
      child: SandikCard(
        padding: const EdgeInsets.only(
            left: SandikSpace.md,
            top: SandikSpace.xs,
            bottom: SandikSpace.xs),
        onTap: () => veriKalitesiAkisi(context, ref),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Row(
            children: [
              // Renk tek başına anlam taşımaz: ikon + cümle de "eksik" der.
              Icon(Icons.info_outline_rounded,
                  color: c.amberText, size: SandikSpace.lgs),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.vkSeritSayi(sayi),
                        style: t.bodyMedium?.copyWith(
                            color: c.text90, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        l.vkSeritAlt,
                        style: t.bodySmall?.copyWith(color: c.text58),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: l.vkSeritKapat,
                icon:
                    Icon(Icons.close_rounded, size: 18, color: c.text36),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: SandikTouch.min, minHeight: SandikTouch.min),
                onPressed: () {
                  SandikHaptic.selection.perform();
                  ref.read(veriKalitesiKapatilanProvider.notifier).set({
                    ...kapatilan,
                    for (final e in eksikler) e.anahtar,
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eksikleri sırayla düzeltme akışı. Kullanıcı bir adımı geri tuşuyla
/// bırakırsa akış orada durur (zorla sürdürmek "kapat" demeyi yok sayardı);
/// satır kalanları için yerinde kalır.
Future<void> veriKalitesiAkisi(BuildContext context, WidgetRef ref) async {
  if (DemoModu.yazmaKapisi('veri_kalitesi')) return;
  final eksikler = [...ref.read(veriEksikleriProvider)];
  for (final e in eksikler) {
    if (!context.mounted) return;
    switch (e.tur) {
      case VeriEksigiTuru.alisFiyati:
        for (final lot in e.lotlar) {
          if (!context.mounted) return;
          final sonuc = await pushGuarded<Object>(
            context,
            adaptiveRoute(
              settings: const RouteSettings(name: 'add_asset'),
              builder: (_) => AddAssetScreen(editingAsset: lot),
            ),
          );
          if (sonuc == null) return;
        }
      case VeriEksigiTuru.eskiFiyat:
        final kaydedildi = await showElleFiyatSayfasi(context, ref, e);
        if (kaydedildi != true) return;
    }
  }
  if (context.mounted && ref.read(veriEksikleriProvider).isEmpty) {
    sandikSnack(context, context.l10n.vkHepsiTamam,
        kind: SandikSnackKind.success);
  }
}

/// Elle fiyatlı pozisyonun güncel fiyatı — tek alan, tek düğme.
///
/// Ayrı sayfa, çünkü düzenleme formundaki fiyat ALIŞ fiyatıdır; elle
/// fiyatlı varlığın bugünkü değerini yazacak bir yüzey yoktu (yalnız
/// `PortfolioNotifier.updateManualPrice` vardı, çağıranı yoktu).
Future<bool?> showElleFiyatSayfasi(
    BuildContext context, WidgetRef ref, VeriEksigi eksik) {
  return showSandikSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.c.surface2,
    shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
    builder: (_) => ElleFiyatSayfasi(
      temsilci: eksik.pozisyon.representative,
      lotlar: eksik.pozisyon.lots,
    ),
  );
}

class ElleFiyatSayfasi extends ConsumerStatefulWidget {
  const ElleFiyatSayfasi(
      {super.key, required this.temsilci, required this.lotlar});

  final Asset temsilci;
  final List<Asset> lotlar;

  @override
  ConsumerState<ElleFiyatSayfasi> createState() => _ElleFiyatSayfasiState();
}

class _ElleFiyatSayfasiState extends ConsumerState<ElleFiyatSayfasi> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.temsilci.currentPrice > 0
        ? fmtNumFlex(widget.temsilci.currentPrice)
        : '',
  );
  String? _hata;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final v = parseTrNumber(_ctrl.text);
    if (v == null || v <= 0) {
      setState(() => _hata = context.l10n.enterValidPrice);
      return;
    }
    try {
      await ref
          .read(portfolioProvider.notifier)
          .elleFiyatiGuncelle(widget.lotlar, v);
    } catch (e) {
      if (mounted) showAppError(context, e);
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final tarih = DateFormat('d MMM yyyy', context.tarihDili)
        .format(elleFiyatTarihi(widget.temsilci));
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SandikSpace.screenH(context),
        SandikSpace.sm2,
        SandikSpace.screenH(context),
        MediaQuery.of(context).viewInsets.bottom + SandikSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: SandikTutamac()),
          const SizedBox(height: SandikSpace.md),
          Text(
            l.vkFiyatBaslik(widget.temsilci.name),
            style: context.t.headlineSmall
                ?.copyWith(color: c.text90, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            l.vkFiyatAciklama(tarih),
            style: context.t.bodyMedium?.copyWith(color: c.text58),
          ),
          const SizedBox(height: SandikSpace.md),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: c.text90),
            decoration: InputDecoration(
              suffixText: widget.temsilci.currency,
              errorText: _hata,
              // Dolgu/çerçeve temadan (`inputDecorationTheme`).
            ),
          ),
          const SizedBox(height: SandikSpace.md),
          SandikAsyncButton(
            onPressed: _kaydet,
            child: Text(l.save),
          ),
        ],
      ),
    );
  }
}
