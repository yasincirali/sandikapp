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

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/crash_reporter.dart';
import '../services/islem_notu.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import 'sandik_async_button.dart';
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
  if (DemoModu.yazmaKapisi('not')) return; // Demo: not kaydı hesap ister (F1).
  final benimId = ref.read(authProvider).valueOrNull?.id;
  final duzenlenebilir = islemNotuDuzenlenebilir(asset, benimId: benimId);
  final l10n = context.l10n;
  // Notifier ŞİMDİ alınır: "Geri al" snackbar'ı çağıran ekran kapandıktan
  // sonra da dokunulabilir; o an `ref` ölmüş olabilir.
  final notifier = ref.read(portfolioProvider.notifier);
  // Yazma sayfanın Kaydet/Notu sil düğmesinin İÇİNDE koşar (tek yükleniyor
  // davranışı, 2026-10-08): eskiden sayfa kapanıyor, `updateNotes` ardından
  // göstergesiz sürüyordu. Sayfa yalnızca yazma başarılıysa kapanır; hata
  // olursa açık kalır (yazılan not kaybolmaz) ve hata sayfanın üstünde
  // söylenir.
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
      kaydet: (metin) async {
        final yeni = metin.trim();
        // Değişmemiş not için istek gitmez (eski davranış).
        if (yeni == (not ?? '')) return;
        await notifier.updateNotes(asset, yeni);
      },
    ),
  );
  if (sonuc == null || !context.mounted) return;
  final yeni = sonuc.trim();
  if (yeni == (not ?? '')) return;
  // Silme onaysızdı ve geri alınamıyordu (emülatör testi #25, 2026-09-29).
  // Onay diyaloğu yerine "Geri al": silme nadiren yanlışlıkla olur, her
  // silmede ek dokunuş istemek hafif olanı ağırlaştırırdı. Alanı boşaltıp
  // "Kaydet"e basmak da silmedir — aynı geri alma onu da kapsar.
  final eski = not;
  sandikSnack(
    context,
    yeni.isEmpty ? l10n.noteRemoved : l10n.noteSaved,
    kind: SandikSnackKind.success,
    onUndo: yeni.isEmpty && eski != null && eski.isNotEmpty
        ? () => CrashReporter.arkaPlan(
            _notuGeriYaz(context, notifier, asset, eski,
                hataOnEki: l10n.noteSaveFailed),
            reason: 'islemNotu.geriAl')
        : null,
  );
}

/// Silinen notu geri yazar. Hata kullanıcıya söylenir (sessiz "geri alındı"
/// sanısı, notu ikinci kez kaybettirirdi).
Future<void> _notuGeriYaz(
  BuildContext context,
  PortfolioNotifier notifier,
  Asset asset,
  String not, {
  required String hataOnEki,
}) async {
  // `hataOnEki` önceden çözülür: dokunuş anında çağıran ekran kapanmış
  // olabilir, ölü context'ten l10n okunamaz.
  try {
    await notifier.updateNotes(asset, not);
  } catch (e) {
    if (!context.mounted) return;
    sandikSnackError(context, e, prefix: hataOnEki);
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
    this.kaydet,
  });

  final Asset asset;
  final String? not;
  final bool duzenlenebilir;

  /// Salt okunur nedeni: ortağın kaydı mı (yoksa silinmiş kayıt mı).
  final bool ortakKaydi;

  /// Verilirse Kaydet/Notu sil düğmesi bu yazmayı bekler (düğmede gösterge),
  /// başarıda sayfa metinle kapanır; hata olursa açık kalır. `null` → eski
  /// davranış: sayfa metni hemen döndürür (widget testi bunu kullanır).
  final Future<void> Function(String metin)? kaydet;

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

  /// Yazar (verildiyse) ve sayfayı [metin] ile kapatır. Hata sayfayı
  /// kapatmaz: kullanıcının yazdığı not alanda kalır, yeniden dener.
  Future<void> _bitir(String metin) async {
    final kaydet = widget.kaydet;
    if (kaydet != null) {
      try {
        await kaydet(metin);
      } catch (e) {
        if (!mounted) return;
        // Snackbar modal sayfanın ALTINDA kalırdı; hata sayfanın üstünde,
        // eski snackbar'ın önekiyle (başlık) söylenir.
        // Beklenmez: düğmenin kilidi diyalog kapanana dek sürmesin.
        CrashReporter.arkaPlan(
            showSandikDialog(
              context: context,
              kind: SandikDialogKind.error,
              title: context.l10n.noteSaveFailed,
              message: friendlyError(e),
            ),
            reason: 'islemNotu.hataDiyalogu');
        return;
      }
    }
    if (mounted) Navigator.pop(context, metin);
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
      SandikAsyncButton.kompakt(
        style: FilledButton.styleFrom(
          backgroundColor: context.c.amberFill,
          foregroundColor: context.c.onAmber,
        ),
        // Eski düz FilledButton titreşimsizdi.
        haptic: SandikHaptic.none,
        onPressed: () => _bitir(_ctrl.text),
        child: Text(l10n.save,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      if (widget.not != null)
        SandikAsyncButton.kompakt(
          tur: SandikAsyncTur.metin,
          haptic: SandikHaptic.none,
          onPressed: () => _bitir(''),
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
