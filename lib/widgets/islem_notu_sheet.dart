// İşlem notu sayfası — hareket satırına dokununca açılır.
//
// Ekleme formundaki "Not ekle" alanına yazılan not 2026-09-29'a kadar hiçbir
// yerde okunmuyordu; düzenleme formu (`AddAssetScreen(editingAsset:)`) da
// hiçbir ekrandan açılmıyordu — not yazıldığı an kayboluyordu. Bu sayfa
// notun hem okunduğu hem düzenlendiği tek yer.
//
// Neden tam düzenleme formu DEĞİL: işlem kaydının miktarını/fiyatını
// sonradan değiştirmek defter değişmezlerine (satışın `refAssetId`'si,
// komisyon, kur) dokunur ve ayrı bir tasarım kararıdır. Not hiçbir hesaba
// girmez; onu düzenlemek güvenli ve tek başına yeterli.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/islem_notu.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import 'transaction_row.dart' show hareketTurEtiketi;

/// Not sayfasını açar; kullanıcı kaydederse notu yazar.
///
/// [not] satırda görünen not (`islemNotu(...)`) — ham `asset.notes` değil:
/// eski kopya not gizlenmişse alan boş açılır, kullanıcı o kopyayı kendi
/// notu sanıp düzenlemez.
Future<void> showIslemNotuSheet(
  BuildContext context,
  WidgetRef ref, {
  required Asset asset,
  required String? not,
}) async {
  final benimId = ref.read(authProvider).valueOrNull?.id;
  final duzenlenebilir = islemNotuDuzenlenebilir(asset, benimId: benimId);
  final sonuc = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.c.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
    ),
    builder: (_) => IslemNotuSheet(
      asset: asset,
      not: not,
      duzenlenebilir: duzenlenebilir,
      ortakKaydi: benimId != null && asset.userId != benimId,
    ),
  );
  if (sonuc == null || !context.mounted) return;
  final yeni = sonuc.trim();
  if (yeni == (not ?? '')) return;
  final l10n = context.l10n;
  try {
    await ref.read(portfolioProvider.notifier).updateNotes(asset, yeni);
    if (!context.mounted) return;
    sandikSnack(context, yeni.isEmpty ? l10n.noteRemoved : l10n.noteSaved,
        kind: SandikSnackKind.success);
  } catch (e) {
    if (!context.mounted) return;
    sandikSnackError(context, e, prefix: l10n.noteSaveFailed);
  }
}

/// Sayfanın gövdesi. Açık sınıf: widget testi doğrudan pump edebilsin.
class IslemNotuSheet extends StatefulWidget {
  const IslemNotuSheet({
    super.key,
    required this.asset,
    required this.not,
    required this.duzenlenebilir,
    this.ortakKaydi = false,
  });

  final Asset asset;
  final String? not;
  final bool duzenlenebilir;

  /// Salt okunur nedeni: ortağın kaydı mı (yoksa silinmiş kayıt mı).
  final bool ortakKaydi;

  @override
  State<IslemNotuSheet> createState() => _IslemNotuSheetState();
}

class _IslemNotuSheetState extends State<IslemNotuSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.not ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final a = widget.asset;
    final baslik = a.showTicker ? a.displayTicker! : a.name;
    final altBaslik =
        '${hareketTurEtiketi(l10n, a)} · ${fmtTarihSaat(a.addedDate)}';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        SandikSpace.screenH(context),
        SandikSpace.lg,
        SandikSpace.screenH(context),
        MediaQuery.of(context).viewInsets.bottom + SandikSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            baslik,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.t.headlineSmall?.copyWith(
              color: context.c.text90,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            altBaslik,
            style: context.t.bodyMedium?.copyWith(color: context.c.text58),
          ),
          const SizedBox(height: SandikSpace.md),
          if (widget.duzenlenebilir) ..._duzenleme(context) else
            ..._saltOkunur(context),
        ],
      ),
    );
  }

  List<Widget> _duzenleme(BuildContext context) {
    final l10n = context.l10n;
    return [
      TextField(
        controller: _ctrl,
        // Notu yoksa kullanıcı buraya not YAZMAK için geldi; varsa önce
        // okumak için — klavye metni örtmesin.
        autofocus: widget.not == null,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        style: context.t.bodyLarge?.copyWith(color: context.c.text90),
        // Boş alan ne yazılacağını söyler (UX denetimi 2026-09-29): satırın
        // dokunulabilir olduğunu keşfeden kullanıcıya notun işe yarar
        // örneğini verir.
        decoration: context.inputDecoration(
            widget.not == null ? l10n.noteAddHint : l10n.notesHint),
      ),
      const SizedBox(height: SandikSpace.md),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: context.c.amberFill,
          foregroundColor: context.c.onAmber,
        ),
        onPressed: () => Navigator.pop(context, _ctrl.text),
        child: Text(l10n.save,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      if (widget.not != null)
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: Text(l10n.noteRemove,
              style: TextStyle(color: context.c.text58)),
        ),
    ];
  }

  List<Widget> _saltOkunur(BuildContext context) {
    final l10n = context.l10n;
    return [
      Text(
        widget.not ?? l10n.noteNone,
        style: context.t.bodyLarge?.copyWith(
            color: widget.not == null ? context.c.text36 : context.c.text90),
      ),
      const SizedBox(height: SandikSpace.md),
      Text(
        widget.ortakKaydi
            ? l10n.noteReadOnlyPartner
            : l10n.noteReadOnlyDeleted,
        style: context.t.bodySmall?.copyWith(color: context.c.text36),
      ),
    ];
  }
}
