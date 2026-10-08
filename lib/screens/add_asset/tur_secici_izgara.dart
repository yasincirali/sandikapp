import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../models/asset_type.dart';
import '../../models/eurobond.dart';
import '../../models/tur_secici_duzeni.dart';
import '../../providers/eurobond_provider.dart';
import '../../services/bugun_service.dart';
import '../../services/crash_reporter.dart';
import '../../services/remote_config_service.dart';
import '../../services/symbol_search_service.dart';
import '../../theme/sandik.dart';

/// Varlık Ekle'nin tür seçicisi — "B · Gruplu ızgara + arama" (bayrak
/// `tur_secici_izgara`, 2026-10-08; yasin: "göz alıcı ama işlevsel, sayfayı
/// karmaşıklaştırmasın").
///
/// ## Neden
/// Tür sayısı 11'e çıktı (ABD hissesi, eurobond); sarmalı çip satırı formun
/// İLK sorusunu üç satırlık bir yığına çeviriyordu ve "THYAO almıştım"
/// diyen kullanıcı önce türü, sonra hisseyi ayrı ayrı arıyordu.
/// - **Arama üstte:** sembol/ad/ISIN yazınca tür VE kimlik tek dokunuşta
///   seçilir (takip listesi aramasıyla aynı servis: `SymbolSearchService`).
/// - **Gruplu ızgara:** "param nerede duruyor" sorusuna göre üç grup
///   (`TurGrubu`); 4 sütun, büyük dokunma hedefi.
/// - **Seçimden sonra tek satır:** ızgara katlanır, form görünür;
///   "Değiştir" geri açar. Sayfa yalnız o an sorulan soruyu gösterir.
///
/// Durum: açık/katlı bilgisi formun sağlayıcısında
/// (`AddAssetFormState.turIzgarasiAcik`); burada yalnız arama metni ve
/// sonuçları tutulur. Kimlik/tür geçişlerini EKRAN yapar ([onKutu],
/// [onSonuc]) — formun var olan `select*` geçişleriyle; burada kural yok.
class TurSeciciIzgara extends ConsumerStatefulWidget {
  const TurSeciciIzgara({
    super.key,
    required this.secili,
    required this.acik,
    required this.sozlesmeliAcik,
    required this.onKutu,
    required this.onSonuc,
    required this.onDegistir,
  });

  /// Formun şu anki türü (ABD dahil).
  final TurKutusu secili;

  /// Izgara açık mı; değilse tek "seçili" satırı çizilir.
  final bool acik;

  /// Mevduat/BES gösterilsin mi (yalnız yeni kayıt; bkz.
  /// `turSeciciGruplari`).
  final bool sozlesmeliAcik;

  final ValueChanged<TurKutusu> onKutu;
  final ValueChanged<TurAramaSonucu> onSonuc;
  final VoidCallback onDegistir;

  @override
  ConsumerState<TurSeciciIzgara> createState() => _TurSeciciIzgaraState();
}

/// Ağ aramasının beklemesi — takip listesi aramasıyla aynı çeyrek saniye
/// (`AddWatchlistScreen._sorguDegisti`): her tuşta TEFAS'a gitmemek için.
/// Hareket süresi DEĞİL, bu yüzden `SandikMotion` değil. Yerleşik liste
/// (hisse/altın/döviz/ABD) beklemeden, her tuşta gösterilir.
final _aramaBeklemesi = const Duration(seconds: 1) ~/ 4;

class _TurSeciciIzgaraState extends ConsumerState<TurSeciciIzgara> {
  final _ctrl = TextEditingController();
  Timer? _gecikme;
  int _seq = 0;
  String _q = '';
  List<SymbolHit> _hits = const [];

  @override
  void didUpdateWidget(covariant TurSeciciIzgara old) {
    super.didUpdateWidget(old);
    // Katlanınca (seçim yapıldı) ya da "Değiştir"le yeniden açılınca arama
    // boş başlar: eski sorgu ızgarayı gizli tutmasın.
    if (old.acik != widget.acik && _q.isNotEmpty) _temizle();
  }

  @override
  void dispose() {
    _gecikme?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _temizle() {
    _gecikme?.cancel();
    _seq++;
    _ctrl.clear();
    _q = '';
    _hits = const [];
  }

  void _degisti(String v) {
    _gecikme?.cancel();
    setState(() {
      _q = v;
      _hits = v.trim().isEmpty
          ? const []
          : SymbolSearchService.instance.yerelAra(v);
    });
    if (v.trim().isEmpty) return;
    _gecikme = Timer(_aramaBeklemesi, () => _ara(v));
  }

  /// Fon ve kripto katmanı ağdan gelir; yerleşik sonuçların yerine geçer.
  /// Arama servisi hatayı kendi yutuyor (fonsuz/kriptosuz devam); buraya
  /// düşen beklenmedik hata yalnız raporlanır, yerel sonuç kalır.
  Future<void> _ara(String q) async {
    final id = ++_seq;
    try {
      final h = await SymbolSearchService.instance.search(q);
      if (!mounted || id != _seq) return;
      setState(() => _hits = h);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'tur_secici.ara');
    }
  }

  bool _turAcik(AssetType t) => RemoteConfigService.instance.turSecenegi(t);

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: SandikMotion.surfaceOf(context),
      curve: SandikMotion.enter,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: SandikMotion.stateOf(context),
        switchInCurve: SandikMotion.enter,
        switchOutCurve: SandikMotion.exit,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, if (current != null) current],
        ),
        child: widget.acik
            ? KeyedSubtree(
                key: const ValueKey('tur_izgara_acik'), child: _acikGovde())
            : KeyedSubtree(
                key: const ValueKey('tur_izgara_kapali'),
                child: _seciliSatir()),
      ),
    );
  }

  // ── Açık: arama + gruplar ────────────────────────────────────────────────

  Widget _acikGovde() {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          onChanged: _degisti,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          style: context.t.bodyLarge?.copyWith(color: context.c.text90),
          // Örnekler bayrağa göre: kapalı pazarı ("Apple", "ISIN") ipucunda
          // vaat etmek, sonuç gelmeyince yanlış bilgi olurdu.
          decoration: context.inputDecoration(
            l.typePickerSearchHint([
              'THYAO',
              if (RemoteConfigService.instance.abdHisse) 'Apple',
              'BTC',
              if (_turAcik(AssetType.eurobond)) 'ISIN',
            ].join(', ')),
            prefixIcon: Icon(Icons.search_rounded, color: context.c.text58),
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    tooltip: l.clearSearch,
                    icon: Icon(Icons.close_rounded, color: context.c.text58),
                    onPressed: () => setState(_temizle),
                  ),
          ),
        ),
        const SizedBox(height: SandikSpace.smd),
        if (_q.trim().isNotEmpty) _sonucListesi() else ..._gruplar(),
      ],
    );
  }

  List<Widget> _gruplar() {
    final l = context.l10n;
    final gruplar = turSeciciGruplari(
      turAcik: _turAcik,
      abdAcik: RemoteConfigService.instance.abdHisse,
      sozlesmeliAcik: widget.sozlesmeliAcik,
    );
    final seansAcik = BugunService.seansAcikMi(DateTime.now());
    // Büyük metin ayarında 4 sütun etiketi tek harfe keserdi; 2 sütuna
    // düşülür (metin ölçeği korunur, `TextScaler.noScaling` yok).
    final sutun = MediaQuery.textScalerOf(context).scale(1) >= 1.6 ? 2 : 4;
    String baslik(TurGrubu g) => switch (g) {
          TurGrubu.borsaVeFon => l.typePickerGroupMarkets,
          TurGrubu.dovizVeDegerli => l.typePickerGroupFxPrecious,
          TurGrubu.birikim => l.typePickerGroupSavings,
        };
    return [
      for (final (i, (g, kutular)) in gruplar.indexed) ...[
        if (i > 0) const SizedBox(height: SandikSpace.md),
        // `ustHarf`: Türkçe büyük harf ("Birikim" → "BİRİKİM"); bkz.
        // `_sectionLabel`.
        Text(
          ustHarf(baslik(g), l),
          style: context.t.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: context.c.text36,
          ),
        ),
        const SizedBox(height: SandikSpace.sm),
        for (var r = 0; r < kutular.length; r += sutun) ...[
          if (r > 0) const SizedBox(height: SandikSpace.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < sutun; c++) ...[
                  if (c > 0) const SizedBox(width: SandikSpace.sm),
                  Expanded(
                    child: r + c < kutular.length
                        ? _kutu(kutular[r + c], seansAcik)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    ];
  }

  String _kutuEtiketi(TurKutusu k) =>
      k.abd ? context.l10n.typePickerUsStock : k.tur.labelOf(context.l10n);

  IconData _kutuIkonu(TurKutusu k) =>
      k.abd ? Icons.language_rounded : k.tur.icon;

  String? _ipucuMetni(TurIpucu? i) => switch (i) {
        null => null,
        TurIpucu.bistAcik => context.l10n.typePickerHintBistOpen,
        TurIpucu.bistKapali => context.l10n.typePickerHintBistClosed,
        TurIpucu.yediYirmiDort => context.l10n.typePickerHint247,
      };

  Widget _kutu(TurKutusu k, bool seansAcik) {
    final secili = widget.secili == k;
    final renk = k.tur.color;
    final ipucu = _ipucuMetni(turKutusuIpucu(k, bistSeansAcik: seansAcik));
    final etiket = _kutuEtiketi(k);
    return Semantics(
      button: true,
      selected: secili,
      label: context.l10n.assetTypeSemantics(etiket),
      excludeSemantics: true,
      child: SandikBasma(
        olcek: 0.95,
        onTap: () => widget.onKutu(k),
        child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          // 48 pt: en küçük dokunma hedefi (touch_target_size_test, HIG).
          constraints: const BoxConstraints(minHeight: SandikSpace.xxl),
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.xs, vertical: SandikSpace.sm2),
          decoration: BoxDecoration(
            color: secili ? renk.withValues(alpha: 0.14) : context.c.surface1,
            borderRadius: SandikRadius.mdAll,
            border: Border.all(
              color: secili ? renk : context.c.overlay,
              width: secili ? 1.4 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ikonKutusu(k, renk),
              const SizedBox(height: SandikSpace.xs2),
              Text(
                etiket,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: context.t.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: secili ? context.c.text90 : context.c.text58,
                ),
              ),
              if (ipucu != null) ...[
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  ipucu,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelSmall
                      ?.copyWith(color: context.c.text36),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Türün renginde, hafif dolgulu yuvarlak kare içinde ikon. İkon light
  /// zeminde `onSurface` tonuyla (kontrast; `asset_type_light_contrast_test`).
  Widget _ikonKutusu(TurKutusu k, Color renk) => Container(
        width: SandikSpace.xl + SandikSpace.xs,
        height: SandikSpace.xl + SandikSpace.xs,
        decoration: BoxDecoration(
          color: renk.withValues(alpha: 0.16),
          borderRadius: SandikRadius.smAll,
        ),
        alignment: Alignment.center,
        child: Icon(_kutuIkonu(k), size: 20, color: k.tur.onSurface(context)),
      );

  // ── Arama sonuçları ──────────────────────────────────────────────────────

  Widget _sonucListesi() {
    final ebAcik = _turAcik(AssetType.eurobond);
    // Arama servisi ISIN/eurobond bilmez: katalogdan eşleşenler eklenir.
    // Katalog yalnız eurobond açıkken ve sorgu varken izlenir (ağ turu).
    final katalog = ebAcik
        ? ref.watch(eurobondKatalogProvider).valueOrNull ?? const []
        : const <(EurobondSozlesmesi, EurobondFiyati?)>[];
    final eb = ebAcik
        ? eurobondAra(
            eklenebilirEurobondlar(katalog, simdi: DateTime.now()), _q)
        : const <(EurobondSozlesmesi, EurobondFiyati?)>[];
    final sonuclar = turAramaSonuclari(
      _hits,
      eurobondlar: eb,
      turAcik: _turAcik,
      abdAcik: RemoteConfigService.instance.abdHisse,
    );
    if (sonuclar.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.md),
        child: Text(
          context.l10n.noResultsShort,
          textAlign: TextAlign.center,
          style: context.t.bodyMedium?.copyWith(color: context.c.text58),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in sonuclar.indexed) ...[
          if (i > 0) Divider(height: 1, color: context.c.hairline),
          _sonucSatiri(s),
        ],
      ],
    );
  }

  String _pazarMetni(PazarEtiketi p) {
    final l = context.l10n;
    return switch (p) {
      PazarEtiketi.bist => l.stockMarketBist,
      PazarEtiketi.abd => l.stockMarketUs,
      PazarEtiketi.tefas => 'TEFAS',
      PazarEtiketi.kripto => l.assetTypeCrypto,
      PazarEtiketi.eurobond => l.assetTypeEurobond,
      PazarEtiketi.altin => l.assetTypeGold,
      PazarEtiketi.doviz => l.assetTypeFx,
    };
  }

  Widget _sonucSatiri(TurAramaSonucu s) {
    final renk = s.kutu.tur.color;
    final pazar = _pazarMetni(s.etiket);
    return Semantics(
      button: true,
      label: '${s.sembol}, ${s.ad}, $pazar',
      excludeSemantics: true,
      child: SandikBasma(
        olcek: 0.98,
        onTap: () => widget.onSonuc(s),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikSpace.xxl),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: SandikSpace.xs, vertical: SandikSpace.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.sembol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.c.text90,
                        ),
                      ),
                      if (s.ad != s.sembol)
                        Text(
                          s.ad,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.bodySmall
                              ?.copyWith(color: context.c.text58),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.xs2, vertical: SandikSpace.xxs),
                  decoration: BoxDecoration(
                    color: renk.withValues(alpha: 0.14),
                    borderRadius: SandikRadius.smAll,
                  ),
                  child: Text(
                    pazar,
                    maxLines: 1,
                    style: context.t.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: s.kutu.tur.onSurface(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Katlı: seçili tür satırı ─────────────────────────────────────────────

  Widget _seciliSatir() {
    final k = widget.secili;
    final renk = k.tur.color;
    final l = context.l10n;
    return Container(
      constraints: const BoxConstraints(minHeight: SandikSpace.xxl),
      padding: const EdgeInsets.fromLTRB(
          SandikSpace.sm, SandikSpace.xs2, SandikSpace.xs, SandikSpace.xs2),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: 0.10),
        borderRadius: SandikRadius.mdAll,
        border: Border.all(color: renk.withValues(alpha: 0.6)),
      ),
      // Etiket ve "Değiştir" `Wrap`'ta: büyük metin ayarında düğme alt
      // satıra iner (320pt × 3.0'da tek satırda 111 px taşıyordu).
      child: Row(
        children: [
          _ikonKutusu(k, renk),
          const SizedBox(width: SandikSpace.smd),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  selected: true,
                  child: Text(
                    _kutuEtiketi(k),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.c.text90,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: l.typePickerChangeSemantics,
                  excludeSemantics: true,
                  child: TextButton(
                    onPressed: widget.onDegistir,
                    style: TextButton.styleFrom(
                      minimumSize:
                          const Size(SandikSpace.xxl, SandikSpace.xxl),
                      foregroundColor: context.c.amberText,
                    ),
                    child: Text(l.typePickerChange,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
