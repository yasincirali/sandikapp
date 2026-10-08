import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../demo/demo_modu.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../providers/portfolio_provider.dart';
import '../services/mevduat_hesabi.dart';
import '../services/sozlesme_deposu.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/tr_format.dart';
import 'sandik_async_button.dart';
import '../l10n/l10n.dart';

/// Bir varlığa hızlıca miktar EKLE veya ÇIKAR — form açmadan.
///
/// Al: yeni miktar + birim fiyat girer, ağırlıklı ortalama maliyet
/// yeniden hesaplanır (mevcut maliyet + yeni maliyet) / toplam adet.
///
/// Sat: sadece miktar girer; alış fiyatı (birim maliyet) korunur.
/// Miktar sıfıra düşerse varlık silinir.
///
/// Mevduat istisnadır: pay değil TL TUTARI girilir, birim fiyat alanı
/// yoktur (bkz. [mevduatTutarIslemi]).
enum QuickAdjustMode { add, remove }

/// Hızlı miktar çiplerinin SAYISAL önerileri — "Hepsi" çipi hariç.
///
/// ## Neden saf fonksiyon (bulgu #9, 2026-09-29 emülatör testi)
/// 1 lotluk ATATP'de Sat açılınca çipler "Hepsi (1) | 10 | 100 | 1000 |
/// Hepsi (1)" idi: türün sabit listesi eldekine bakmadan basılıyor, sona
/// eldeki miktar "Hepsi" diye ekleniyordu; üstelik listedeki `1` eldekine
/// EŞİT olduğu için o da "Hepsi" etiketini alıyordu. Eldekini aşan öneri
/// satışta zaten `cannotExceedQuantity` hatasına gider — basılması tuzaktı.
///
/// Kural: satışta yalnızca eldekinden KÜÇÜK öneriler (eşiti "Hepsi"
/// çipidir, ikinci kez yazılmaz); alışta türün makul adımları. Kripto
/// ayrı: tam sayı adet nadirdir, 100 BTC öneri olmaz (Varlık Ekle
/// formundaki `quantityPresets` ile aynı ölçek).
List<double> hizliMiktarOnerileri({
  required AssetType tur,
  required String birimTuru,
  required double eldeki,
  required bool satis,
}) {
  final List<double> taban;
  if (birimTuru == 'gram' || birimTuru == 'gr') {
    taban = const [1, 5, 10, 50];
  } else if (birimTuru == 'ounce' || birimTuru == 'oz') {
    taban = const [0.1, 0.5, 1];
  } else if (tur == AssetType.mevduat) {
    // Mevduatta alan TL tutarıdır (`mevduatTutarIslemi`); [eldeki] de
    // pay değil bakiye (₺) gelir.
    taban = const [1000, 5000, 10000, 50000];
  } else if (tur == AssetType.kripto) {
    taban = const [0.001, 0.01, 0.1, 1];
  } else if (tur == AssetType.doviz) {
    taban = const [10, 50, 100, 500];
  } else if (tur == AssetType.fon || tur == AssetType.hisse) {
    taban = const [1, 10, 100, 1000];
  } else {
    taban = const [1, 5, 10, 100];
  }
  if (!satis) return taban;
  // Kayan nokta payı: 10 − 1e-12 "10'dan küçük" sayılmasın.
  return [for (final v in taban) if (v < eldeki - 1e-9) v];
}

Future<void> showQuickAdjustDialog(
  BuildContext context,
  WidgetRef ref, {
  required Asset asset,
  required QuickAdjustMode mode,
}) async {
  if (DemoModu.yazmaKapisi('miktar')) return; // Demo: kaydetmek hesap ister (F1).
  return showSandikGecisli<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _QuickAdjustDialog(asset: asset, mode: mode, ref: ref),
  );
}

class _QuickAdjustDialog extends StatefulWidget {
  final Asset asset;
  final QuickAdjustMode mode;
  final WidgetRef ref;

  const _QuickAdjustDialog({
    required this.asset,
    required this.mode,
    required this.ref,
  });

  @override
  State<_QuickAdjustDialog> createState() => _QuickAdjustDialogState();
}

class _QuickAdjustDialogState extends State<_QuickAdjustDialog> {
  final _qtyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _isAdd => widget.mode == QuickAdjustMode.add;

  /// Mevduat TL tutarıyla girilir (bkz. [mevduatTutarIslemi]).
  bool get _tutarla => widget.asset.type == AssetType.mevduat;

  /// Mevduatın bugünkü birim değeri. Önce sözleşmeden — sözleşme kartının
  /// "bugün" değeri ve "Çektim" tutarı da oradan (`sozlesme_karti`); lot'un
  /// son yazılan fiyatı vade gününde fiyat turundan önce eski kalabilir.
  late final double _birim = () {
    final a = widget.asset;
    final s = SozlesmeDeposu.instance
        .mevduatBirimDegeri(a.ticker, DateTime.now());
    if (s != null && s > 0) return s;
    return a.currentPrice > 0 ? a.currentPrice : a.purchasePrice;
  }();

  /// Mevduatın eldeki bakiyesi (₺), kuruşa yuvarlı — "Hepsi" çipi ve
  /// "Mevcut" satırı bunu yazar, `mevduatTutarIslemi` kuruş payıyla eşler.
  double get _bakiye => (widget.asset.quantity * _birim * 100).round() / 100;

  @override
  void initState() {
    super.initState();
    if (_isAdd && !_tutarla) {
      final currentPrice = widget.asset.currentPrice > 0
          ? widget.asset.currentPrice
          : widget.asset.purchasePrice;
      if (currentPrice > 0) {
        _priceCtrl.text = _fmt(currentPrice);
      }
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  /// Alan metni `parseTrNumber` ile okunur; `toString()` (`41.235`) binlik
  /// sanılıp 1000 kat büyüyordu (2026-09-23 denetimi F1).
  String _fmt(double v) => fmtInputTr(v);

  /// Türkçe biçimi doğru çözer. Eski hâli `replaceAll(',', '.')` idi ve
  /// "1.000" girdisini 1.0 olarak okuyordu — kullanıcı 1000 lot yazıp
  /// portföyüne 1 lot kaydediyordu, üstelik hiçbir uyarı almadan.
  double? _parse(String text) => parseTrNumber(text);

  String get _unitLabel => widget.asset.unitLabel;

  String get _currencySymbol {
    switch (widget.asset.currency.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return '₺';
    }
  }

  Future<void> _submit() async {
    if (_tutarla) return _tutarlaKaydet();
    final qty = _parse(_qtyCtrl.text);
    if (qty == null || qty <= 0) {
      setState(() => _error = context.l10n.enterValidQuantity);
      return;
    }

    if (_isAdd) {
      final price = _parse(_priceCtrl.text);
      if (price == null || price <= 0) {
        setState(() => _error = context.l10n.enterValidUnitPrice);
        return;
      }
    } else {
      if (qty > widget.asset.quantity) {
        setState(() => _error =
            context.l10n.cannotExceedQuantity(_fmt(widget.asset.quantity)));
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final asset = widget.asset;
      final notifier = widget.ref.read(portfolioProvider.notifier);

      if (_isAdd) {
        final addPrice = _parse(_priceCtrl.text)!;
        await notifier.addAsset(
          name: asset.name,
          ticker: asset.ticker,
          type: asset.type,
          quantity: qty,
          purchasePrice: addPrice,
          currency: asset.currency,
          // Yeni alış yeni bir işlemdir; önceki lot'un notu ona ait değil.
          notes: '',
          isManualPrice: asset.isManualPrice,
          subCategory: asset.subCategory,
          unitType: asset.unitType,
          sozlesmeId: asset.sozlesmeId,
        );
      } else {
        await notifier.addSellTransaction(
          asset: asset,
          quantity: qty,
          sellPrice: asset.currentPrice > 0 ? asset.currentPrice : asset.purchasePrice,
        );
      }

      if (!mounted) return;
      // Başarı toast'ı YOK (kullanıcı kararı, 2026-09-16): sheet kapanıyor ve
      // varlığın miktarı arkadaki listede anında değişiyor — onay zaten
      // ekranda. Hata yolu sessiz değil; `_error` ile sheet içinde kalır.
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.l10n.transactionFailed(friendlyError(e));
      });
    }
  }

  /// Mevduat: yazılan tutar alışın maliyeti / satışın değeri olur; pay
  /// tutarın birim değere bölümüdür. Faiz birim değerde kalır, satış
  /// tutarına ikinci kez binmez (kullanıcı bildirimi, 2026-10-08).
  Future<void> _tutarlaKaydet() async {
    final tutar = _parse(_qtyCtrl.text);
    if (tutar == null || tutar <= 0) {
      setState(() => _error = context.l10n.enterValidAmount);
      return;
    }
    final islem = mevduatTutarIslemi(
      tutar: tutar,
      birim: _birim,
      eldekiPay: widget.asset.quantity,
      satis: !_isAdd,
    );
    if (islem == null) {
      setState(() => _error = _isAdd
          ? context.l10n.enterValidAmount
          : context.l10n.cannotExceedBalance(fmtTRY(_bakiye, digits: 2)));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final asset = widget.asset;
      final notifier = widget.ref.read(portfolioProvider.notifier);
      if (_isAdd) {
        await notifier.addAsset(
          name: asset.name,
          ticker: asset.ticker,
          type: asset.type,
          quantity: islem.pay,
          purchasePrice: islem.birim,
          currency: asset.currency,
          notes: '',
          isManualPrice: asset.isManualPrice,
          subCategory: asset.subCategory,
          unitType: asset.unitType,
          sozlesmeId: asset.sozlesmeId,
        );
      } else {
        await notifier.addSellTransaction(
          asset: asset,
          quantity: islem.pay,
          sellPrice: islem.birim,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.l10n.transactionFailed(friendlyError(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final numFmt = qtyFormatter(maxDigits: asset.azamiOndalik);
    final accent = _isAdd ? context.c.gain : context.c.loss;
    final qty = _parse(_qtyCtrl.text) ?? 0;
    final price = _parse(_priceCtrl.text) ?? 0;
    // Satışta önizleme, KAYDEDİLECEK satış fiyatını kullanır (bkz.
    // `addSellTransaction` çağrısı). Eskiden "Satış değeri" etiketiyle alış
    // maliyeti gösteriliyordu; kaydedilen tutar başkaydı (2026-09-23
    // denetimi F10).
    final satisFiyati =
        asset.currentPrice > 0 ? asset.currentPrice : asset.purchasePrice;
    final total = qty * (_isAdd ? price : satisFiyati);

    return Dialog(
      backgroundColor: context.c.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SandikRadius.lg)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          // Klavye açıkken (miktar alanı autofocus) diyalog ekranın
          // yarısına sığmak zorunda: başlık + iki alan + toplam + düğmeler
          // ~490px, iOS ondalık klavyeyle kalan ~410–490px. Gövde kayar,
          // düğme satırı DIŞARIDA kalır — Al/Sat hiçbir yükseklikte
          // kırpılmaz (klavye denetimi 2026-10-08).
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
           Flexible(
            child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // ── Başlık ────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                  ),
                  child: Icon(
                    _isAdd
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // Swipe etiketiyle aynı dil: orada "Al/Sat" deyip
                        // burada "Ekle/Çıkar" göstermek akışı kopartıyordu.
                        // Aynı anahtar (`buyAction`/`sellAction`).
                        _isAdd
                            ? context.l10n.buyAction
                            : context.l10n.sellAction,
                        style: context.t.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: context.c.text90,
                        ),
                      ),
                      Text(
                        asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.titleSmall?.copyWith(
                          color: context.c.text58,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: context.c.text58, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Mevcut durum ──────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.c.overlay,
                borderRadius: BorderRadius.circular(SandikRadius.md),
              ),
              child: Row(
                children: [
                  Text(context.l10n.quickHolding,
                      style: context.t.bodySmall?.copyWith(color: context.c.text36)),
                  const Spacer(),
                  Text(
                    // Mevduatta pay ve "ort. 1,00 ₺" kullanıcıya bir şey
                    // söylemez; bakiye söyler.
                    _tutarla
                        ? fmtTRY(_bakiye, digits: 2)
                        : '${numFmt.format(asset.quantity)} $_unitLabel · '
                            '${context.l10n.quickAvgShort('${numFmt.format(asset.purchasePrice)} $_currencySymbol')}',
                    style: context.t.numSmall.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.c.text90,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Miktar ────────────────────────────────────────────────
            Text(_tutarla ? context.l10n.depositAmountLabel : context.l10n.quantity,
                style: context.t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.c.text58)),
            const SizedBox(height: 6),
            TextField(
              controller: _qtyCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              style: context.t.numLarge.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.c.text90),
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle:
                    context.t.headlineSmall?.copyWith(color: context.c.text36),
                suffixText: _tutarla ? _currencySymbol : _unitLabel,
                suffixStyle:
                    context.t.titleMedium?.copyWith(color: context.c.text58),
                // Dolgu/çerçeve temadan (`inputDecorationTheme` = `inputFill` kuralı).
              ),
            ),
            const SizedBox(height: 8),
            _quickChips(),

            // Remove modunda tüm miktarı çıkarırken kısa bilgi: bu bir
            // "satış" kaydı; delete değil. Kullanıcı "sattım = sil" diye
            // düşünmesin diye net bir metinle ayrımı vurguluyoruz.
            if (!_isAdd &&
                qty > 0 &&
                (_tutarla
                    ? (qty - _bakiye).abs() < 0.01
                    : (qty - asset.quantity).abs() < 0.0001))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    border: Border.all(
                        color: context.c.amberFill.withValues(alpha: 0.30)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: context.c.amberText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.sellAllWarning,
                          style: context.t.bodySmall?.copyWith(
                            color: context.c.text58,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Fiyat (sadece ekleme için) ────────────────────────────
            if (_isAdd && !_tutarla) ...[
              const SizedBox(height: 16),
              Text(context.l10n.quickUnitPrice,
                  style: context.t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.c.text58)),
              const SizedBox(height: 6),
              TextField(
                controller: _priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                style: context.t.numMedium.copyWith(
                    fontWeight: FontWeight.w500, color: context.c.text90),
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  hintText: '0.00',
                  hintStyle:
                      context.t.titleLarge?.copyWith(color: context.c.text36),
                  suffixText: _currencySymbol,
                  suffixStyle:
                      context.t.titleMedium?.copyWith(color: context.c.text58),
                  // Dolgu/çerçeve temadan (`inputDecorationTheme` = `inputFill` kuralı).
                ),
              ),
            ],

            // ── Toplam önizleme ──────────────────────────────────────
            // Mevduatta toplam yazılan tutarın kendisidir; tekrar etmez.
            if (qty > 0 && !_tutarla) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(
                      color: accent.withValues(alpha: 0.25), width: 1),
                ),
                child: Row(
                  children: [
                    Text(
                        _isAdd
                            ? context.l10n.quickTotalCost
                            : context.l10n.saleValue,
                        style: context.t.titleSmall?.copyWith(color: context.c.text58)),
                    const Spacer(),
                    Text(
                      '${numFmt.format(total)} $_currencySymbol',
                      style: context.t.numSmall.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: context.t.titleSmall?.copyWith(color: context.c.loss),
              ),
            ],

            ],
            ),
            ),
           ),

            const SizedBox(height: 20),

            // ── Butonlar ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: context.c.overlay,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SandikRadius.md)),
                    ),
                    child: Text(context.l10n.cancelWord,
                        style: context.t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: context.c.text90)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  // Gösterge + çift dokunuş kilidi standart bileşende (tek
                  // yükleniyor davranışı, 2026-10-08). `_saving` kalır:
                  // kayıt sürerken İptal pasif.
                  child: SandikAsyncButton.kompakt(
                    onPressed: _submit,
                    mesgul: _saving,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SandikRadius.md)),
                    ),
                    child: Text(
                        _isAdd
                            ? context.l10n.buyAction
                            : context.l10n.sellAction,
                        style: context.t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: context.c.text90)),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _quickChips() {
    // Öneriler `hizliMiktarOnerileri`'nden (saf, testli). Alanın metni ve
    // çipin yazısı AYNI Türkçe biçimde (`_fmt`): eski '0.1' ham yazımı
    // ekranda "0.1" görünüyordu.
    // Mevduatta alan tutar olduğu için çipler de bakiyeyle (₺) kurulur.
    final eldeki = _tutarla ? _bakiye : widget.asset.quantity;
    final chips = <({String deger, String etiket})>[
      for (final v in hizliMiktarOnerileri(
        tur: widget.asset.type,
        birimTuru: widget.asset.unitType,
        eldeki: eldeki,
        satis: !_isAdd,
      ))
        (deger: _fmt(v), etiket: _fmt(v)),
      // Satışta TEK "Hepsi" — eldekinin tamamı (bkz. bulgu #9).
      if (!_isAdd && eldeki > 0)
        (deger: _fmt(eldeki), etiket: context.l10n.quickAllChip(_fmt(eldeki))),
    ];

    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final chip in chips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SandikBasma(
                onTap: () => setState(() {
                  _qtyCtrl.text = chip.deger;
                  _error = null;
                }),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.c.overlay,
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    chip.etiket,
                    style: context.t.numSmall.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.c.text90,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
