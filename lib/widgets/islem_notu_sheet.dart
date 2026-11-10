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
import '../models/asset_type.dart' show AssetType, kotasyonSembolu;
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/crash_reporter.dart';
import '../services/islem_notu.dart';
import '../services/hizli_tekrar_al.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import 'quick_adjust_dialog.dart';
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
  // "Bunu tekrar al" (Ar-Ge 8 Kas #1): yalnız kendi, silinmemiş ALIŞ
  // hareketinde ve pozisyon açıkken (`tekrarAlHedefi`). Pozisyon
  // kullanıcının kendi defterinden (`portfolioProvider`); Tüm Hareketler'in
  // "Birlikte" defteri ortak lot'larını da taşır.
  final tekrarHedefi = tekrarAlHedefi(
    ref.read(portfolioProvider).valueOrNull?.assets ?? const [],
    asset,
    benimId: benimId,
  );
  var tekrarAlIstendi = false;
  final l10n = context.l10n;
  // Notifier ŞİMDİ alınır: "Geri al" snackbar'ı çağıran ekran kapandıktan
  // sonra da dokunulabilir; o an `ref` ölmüş olabilir.
  final notifier = ref.read(portfolioProvider.notifier);
  // Yazma sayfanın Kaydet/Notu sil düğmesinin İÇİNDE koşar (tek yükleniyor
  // davranışı, 2026-10-08): eskiden sayfa kapanıyor, `updateNotes` ardından
  // göstergesiz sürüyordu. Sayfa yalnızca yazma başarılıysa kapanır; hata
  // olursa açık kalır (yazılan not kaybolmaz) ve hata sayfanın üstünde
  // söylenir.
  final sonuc = await showSandikSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
    ),
    builder: (_) => IslemNotuSheet(
      asset: asset,
      not: not,
      duzenlenebilir: duzenlenebilir,
      ortakKaydi: benimId != null && asset.userId != benimId,
      tekrarAl: tekrarHedefi == null ? null : () => tekrarAlIstendi = true,
      kaydet: (metin) async {
        final yeni = metin.trim();
        // Değişmemiş not için istek gitmez (eski davranış).
        if (yeni == (not ?? '')) return;
        await notifier.updateNotes(asset, yeni);
      },
    ),
  );
  // Hızlı Al sayfa KAPANDIKTAN sonra açılır: iki modal üst üste binmez,
  // geri hareketi Hızlı Al'dan hareket listesine döner. Kayıt mevcut Hızlı
  // Al yolu; miktar o hareketinki, fiyat bugünün (diyalog kendisi doldurur).
  if (tekrarAlIstendi && tekrarHedefi != null) {
    if (!context.mounted) return;
    await showQuickAdjustDialog(
      context,
      ref,
      asset: tekrarHedefi.pozisyon,
      mode: QuickAdjustMode.add,
      baslangicMiktar: tekrarHedefi.miktar,
    );
    return;
  }
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

/// Sayfanın alt başlığı: "Alım · 120 lot × ₺287,50 · 12 Mar 2026 14:05".
///
/// Birim fiyat (müşteri raporu 2026-11-10 #3): not çoğu zaman "neden bu
/// fiyattan aldım" sorusuna cevaptır; fiyat yazmayınca kullanıcı hangi
/// alım olduğunu hareket listesine dönüp bakıyordu. Fiyat kaydın kendi
/// para birimiyle, birim fiyat kuralıyla (`fmtFiyat`) yazılır. Bilinmiyorsa
/// parça hiç yazılmaz (uydurma sayı yok): "maliyet sonra" işaretli alış,
/// satış fiyatı olmayan satış, temettü/silme kaydı ve miktarı gösterilmeyen
/// mevduat ("Alım × ₺…" anlamsız olurdu).
String islemNotuAltBasligi(AppLocalizations l10n, Asset a) {
  final tur = hareketTurEtiketi(l10n, a);
  final tarih = fmtTarihSaat(a.addedDate);
  final fiyat = _birimFiyat(a);
  if (fiyat == null) return '$tur · $tarih';
  final metin = fmtFiyat(fiyat, symbol: kotasyonSembolu('', a.currency));
  return '$tur × $metin · $tarih';
}

double? _birimFiyat(Asset a) {
  if (a.isDividend || a.isDeleteLog || a.type == AssetType.mevduat) {
    return null;
  }
  final fiyat = a.isSell
      ? a.sellPrice
      : (a.maliyetBilinmiyor == true ? null : a.purchasePrice);
  return fiyat != null && fiyat > 0 ? fiyat : null;
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
    this.tekrarAl,
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

  /// Verilirse sayfanın altında "Bunu tekrar al" satırı çizilir; dokununca
  /// bu çağrılır ve sayfa SONUÇSUZ kapanır (not yazılmaz, Hızlı Al'ı
  /// çağıran açar). `null` → satır yok (satış, ortağın ya da silinmiş
  /// hareket, kapanmış pozisyon; karar `tekrarAlHedefi`).
  final VoidCallback? tekrarAl;

  @override
  State<IslemNotuSheet> createState() => _IslemNotuSheetState();
}

class _IslemNotuSheetState extends State<IslemNotuSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.not ?? '')..addListener(_degisti);

  /// Kaydet yalnız metin asıl nottan farklıyken açık (müşteri raporu
  /// 2026-11-10 #3): değişmemiş notta basınca hiçbir şey yazılmadan
  /// "Not kaydedildi" hissi veriyordu. Karşılaştırma `showIslemNotuSheet`'in
  /// erken dönüşüyle aynı (kırpılmış metin == not), ikisi ayrı karar vermesin.
  bool _degismis = false;

  void _degisti() {
    final d = _ctrl.text.trim() != (widget.not ?? '');
    if (d != _degismis) setState(() => _degismis = d);
  }

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
    final altBaslik = islemNotuAltBasligi(l10n, a);

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
          SandikSheetBasligi(baslik),
          const SizedBox(height: SandikSpace.xs),
          Text(
            altBaslik,
            style: context.t.bodyMedium?.copyWith(color: context.c.text58),
          ),
          const SizedBox(height: SandikSpace.md),
          if (widget.duzenlenebilir) ..._duzenleme(context) else
            ..._saltOkunur(context),
          if (widget.tekrarAl != null) ..._tekrarAlSatiri(context),
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
      // Kapalıyken temanın kapalı düğme rengi (`styleFrom` yalnız açık
      // hâli boyar): soluk düğme metinle de "değişiklik yok" der.
      SandikAsyncButton.kompakt(
        key: const ValueKey('islem-notu-kaydet'),
        style: FilledButton.styleFrom(
          backgroundColor: context.c.amberFill,
          foregroundColor: context.c.onAmber,
        ),
        onPressed: _degismis ? () => _bitir(_ctrl.text) : null,
        child: Text(l10n.save,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      if (widget.not != null)
        SandikAsyncButton.kompakt(
          tur: SandikAsyncTur.metin,
          onPressed: () => _bitir(''),
          child: Text(l10n.noteRemove,
              style: TextStyle(color: context.c.text58)),
        ),
    ];
  }

  /// "Bunu tekrar al" satırı: kıl çizgisiyle nottan ayrılır, 44 pt satır.
  /// Amber metin eylemi söyler (sayfadaki ikincil eylemlerin dili), ok
  /// başka bir yüzeye geçileceğini; anlam yalnız renkte değil, metinde.
  List<Widget> _tekrarAlSatiri(BuildContext context) {
    final l10n = context.l10n;
    return [
      const SizedBox(height: SandikSpace.sm),
      Divider(color: context.c.hairline, height: 1),
      SandikTappable(
        key: const ValueKey('tekrar_al_satiri'),
        semanticLabel: l10n.txBuyAgain,
        onTap: () {
          widget.tekrarAl!();
          Navigator.pop(context);
        },
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: SandikTouch.min),
            child: Row(
              children: [
                Icon(Icons.replay_rounded,
                    size: SandikSpace.lgs, color: context.c.amberText),
                const SizedBox(width: SandikSpace.smd),
                Expanded(
                  child: Text(
                    l10n.txBuyAgain,
                    style: context.t.bodyLarge?.copyWith(
                        color: context.c.amberText,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: SandikSpace.lgs, color: context.c.text36),
              ],
            ),
          ),
        ),
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
