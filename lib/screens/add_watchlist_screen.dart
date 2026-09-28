import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        Icons,
        Material,
        Colors,
        SnackBarAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../models/varlik_kimligi.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/symbol_search_service.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import 'paywall_screen.dart';
import 'varlik_sayfasi.dart';
import '../l10n/l10n.dart';

/// Takibe alınacak varlığı seçme ekranı.
///
/// Arama, karşılaştırma ekranıyla AYNI `SymbolSearchService` üzerinden
/// yapılır: BIST hisseleri, TEFAS fonları (kurucu-only fonlar dahil),
/// altın ürünleri, döviz, **endeksler** ve **emtia**.
///
/// Eskiden bu ekran kendi listesini tutuyordu ve iki ekran ayrışmıştı —
/// endeksler (XU100/XU030) ile emtia (ons altın, gümüş, Brent/WTI petrol,
/// doğalgaz) takip listesine HİÇ eklenemiyordu. Tek kaynak bu ayrışmayı
/// yapısal olarak engelliyor.
///
/// **Portföyde olan varlık ayrı grupta ve pasif gösterilir** — aynı şeyi hem
/// sahiplenip hem takip etmenin anlamı yok, ama gizlemek de yanlış olurdu
/// (kullanıcı aradığını bulamayınca uygulamanın onu tanımadığını sanır).
class AddWatchlistScreen extends ConsumerStatefulWidget {
  const AddWatchlistScreen({super.key});

  @override
  ConsumerState<AddWatchlistScreen> createState() => _AddWatchlistScreenState();
}

class _AddWatchlistScreenState extends ConsumerState<AddWatchlistScreen> {
  final _ctrl = TextEditingController();
  String _q = '';
  List<VarlikKimligi> _results = const [];
  bool _loading = true;

  /// Yalnızca EN SON aramanın sonucu uygulanır.
  ///
  /// Kullanıcı hızlı yazarken istekler sırasız dönebilir; sayaç olmadan
  /// eski bir sorgunun sonucu yenisinin üstüne yazılabilirdi.
  int _seq = 0;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ara(''); // boş sorgu → popüler öneriler
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _sorguDegisti(String v) {
    setState(() => _q = v);
    // 250 ms: her tuş vuruşunda TEFAS'a gitmemek için. Yerleşik listeler
    // zaten bellekte ama fon araması ağa çıkabiliyor.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _ara(v));
  }

  Future<void> _ara(String q) async {
    final id = ++_seq;
    if (mounted) setState(() => _loading = true);
    try {
      final hits = await SymbolSearchService.instance.search(q);
      if (!mounted || id != _seq) return;
      setState(() {
        _results = [
          for (final h in hits)
            if (VarlikKimligi.fromSymbolHit(h) case final c?) c,
        ];
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _seq) return;
      // Arama başarısızsa liste boş kalır; kullanıcı yeniden yazabilir.
      setState(() => _loading = false);
    }
  }

  // Sembol → tür/alt kategori/para birimi kuralı `VarlikKimligi.fromSymbolHit`
  // içinde: varlık sayfası dört giriş noktasından aynı kimlikle açılır ve
  // "zaten takipte" tespiti ekranlar arasında ayrışmamalı.

  @override
  Widget build(BuildContext context) {
    final watchlist = ref.watch(watchlistProvider).valueOrNull ?? const [];
    final watchedKeys = {for (final w in watchlist) w.key};

    // Portföydeki varlıkların anahtarları — pasif göstermek için.
    //
    // `aktifLotlar`: tamamen satılmış pozisyon "portföyde var" sayılmamalı.
    // Ham `isActive` ile kullanıcı, elinden çıkardığı bir hisseyi takip
    // listesine EKLEYEMİYORDU — satır "zaten portföyünde" diye pasifti.
    final owned =
        aktifLotlar(ref.watch(portfolioProvider).valueOrNull?.assets ?? const []);
    final ownedKeys = <String>{
      for (final a in owned)
        '${a.type.name}|${(a.subCategory?.trim().isNotEmpty ?? false) ? 'sub:${a.subCategory!.trim().toUpperCase()}' : a.ticker.trim().toUpperCase()}',
    };

    final results = _results;
    final available = results.where((c) => !ownedKeys.contains(c.key)).toList();
    final inPortfolio =
        results.where((c) => ownedKeys.contains(c.key)).toList();

    return DefaultTextStyle(
      style: sandikFont(
          color: context.c.text90, decoration: TextDecoration.none),
      child: CupertinoPageScaffold(
        backgroundColor: context.c.background,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Column(
              children: [
                _header(context),
                _searchField(context),
                if (_loading)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(context.l10n.searchingEllipsis,
                        style: context.t.bodySmall
                            ?.copyWith(color: context.c.text36)),
                  ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 8, SandikSpace.screenH(context), 20),
                    children: [
                      if (available.isEmpty && inPortfolio.isEmpty && !_loading)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Text(
                            _q.trim().isEmpty
                                ? context.l10n.startTypingToSearch
                                : context.l10n.noResultForQuery(_q.trim()),
                            textAlign: TextAlign.center,
                            style: context.t.bodyMedium
                                ?.copyWith(color: context.c.text58),
                          ),
                        ),
                      for (final c in available) ...[
                        _tile(context, c, watched: watchedKeys.contains(c.key)),
                        const SizedBox(height: SandikSpace.sm),
                      ],
                      if (inPortfolio.isNotEmpty) ...[
                        const SizedBox(height: SandikSpace.sm),
                        Text(
                          context.l10n.inYourPortfolioUpper,
                          style: context.t.labelSmall?.copyWith(
                              letterSpacing: 0.9,
                              fontWeight: FontWeight.w700,
                              color: context.c.text36),
                        ),
                        const SizedBox(height: SandikSpace.sm),
                        for (final c in inPortfolio) ...[
                          _tile(context, c, owned: true),
                          const SizedBox(height: SandikSpace.sm),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 12, SandikSpace.screenH(context), 8),
        child: Row(
          children: [
            SizedBox(
              // Ölçek içi (`SandikSpace`): 36 ölçek dışıydı ve
              // `spacing_scale_test` bunu yakaladı. Dokunma hedefi
              // `height: 44` ile zaten HIG minimumunda.
              width: SandikTouch.min,
              height: SandikTouch.min,
              child: CupertinoButton(
                minimumSize: SandikTouch.minSize,
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                onPressed: () => Navigator.pop(context),
                child: Icon(Icons.close_rounded,
                    size: 22, color: context.c.text90),
              ),
            ),
            Expanded(
              child: Text('Takibe Al',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: context.c.text90)),
            ),
          ],
        ),
      );

  Widget _searchField(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: SandikSpace.screenH(context)),
        child: CupertinoTextField(
          controller: _ctrl,
          onChanged: _sorguDegisti,
          placeholder: context.l10n.searchAllAssetsHint,
          placeholderStyle:
              context.t.bodyMedium?.copyWith(color: context.c.text36),
          style: context.t.bodyMedium?.copyWith(color: context.c.text90),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          prefix: Padding(
            padding: const EdgeInsets.only(left: 10),
            child:
                Icon(Icons.search_rounded, size: 18, color: context.c.text58),
          ),
          decoration: BoxDecoration(
            // Seçici alt sayfasıyla aynı dolgu (tema `inputFill`).
            color: context.inputFill,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(color: context.c.hairline),
          ),
        ),
      );

  /// Arama sonucu satırı.
  ///
  /// **Satıra dokunmak ÖNİZLER, "+" hemen takibe alır** (kullanıcı kararı,
  /// 2026-09-28). Eskiden satırın tamamı "takibe al" idi; kullanıcı bir
  /// varlığa bakmak için önce listeye eklemek, sonra çıkarmak zorundaydı.
  /// Hızlı ekleme alışkanlığı bozulmasın diye "+" satırın sağında kaldı.
  /// Portföydeki varlık da önizlenebilir; sayfa onu pozisyona yönlendirir.
  Widget _tile(BuildContext context, VarlikKimligi c,
      {bool watched = false, bool owned = false}) {
    return Opacity(
      opacity: owned ? 0.5 : 1.0,
      child: SandikTappable(
        onTap: () => showVarlikSayfasi(context, c),
        semanticLabel: context.l10n.vsOpenDetailSemantics(c.name),
        child: Container(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            color: context.c.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(color: context.c.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: c.type.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.bodyMedium
                              ?.copyWith(color: context.c.text90)),
                      Text('${c.ticker} · ${c.type.labelOf(context.l10n)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.bodySmall?.copyWith(
                              color: context.c.text36, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (owned)
                const _SatirSonu(child: _SahipIsareti())
              else if (watched)
                _SatirSonu(
                  child: Text(context.l10n.watchlistInListLabel,
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text36, fontSize: 11)),
                )
              else
                _HizliTakipDugmesi(
                  semanticLabel: context.l10n.vsWatchSemantics(c.name),
                  onTap: () => _add(c),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _add(VarlikKimligi c) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    try {
      await ref
          .read(watchlistProvider.notifier)
          .add(c.toWatchlistItem(userId: user.id));
      // Başarı toast'ı YOK (kullanıcı kararı, 2026-09-16): satırdaki "+"
      // ikonu eklendi durumuna geçiyor, onay orada. Hata yolları (limit,
      // çakışma) toast'ını KORUR — orada geri bildirim tek kanal.
    } on WatchlistLimitException catch (e) {
      if (!mounted) return;
      // Limit hatası ağ hatasından AYRI ele alınır: kullanıcıya neden
      // eklenemediğini ve ÇIKIŞ YOLUNU söylemek gerekir. "Eklenemedi" deyip
      // bırakmak kullanıcıyı çıkışsız bırakırdı.
      // Paywall kapalıyken limit bir ÜRÜN sınırıdır (2026-09-25, 7 varlık):
      // "Premium" düğmesi olmayan bir şeyi satar, "ücretsiz plan" sözü de
      // olmayan bir planı ima ederdi. Çıkış yolu açıkça söylenir: birini çıkar.
      final paywallOn = ref.read(paywallVisibleProvider);
      sandikSnack(
        context,
        paywallOn
            ? context.l10n.watchlistLimitFree(e.limit)
            : context.l10n.watchlistLimitReached(e.limit),
        kind: SandikSnackKind.warning,
        action: paywallOn
            ? SnackBarAction(
                label: 'Premium',
                textColor: context.c.onAmber,
                onPressed: () =>
                    PaywallScreen.show(context, source: 'watchlist_limit'),
              )
            : null,
      );
    } catch (_) {
      if (!mounted) return;
      // Sunucudaki unique index çakışması da buraya düşer — kullanıcıya
      // teknik hata değil, ne olduğunu söyle.
      sandikSnack(context, 'Eklenemedi. Zaten takipte olabilir.',
          kind: SandikSnackKind.error);
    }
  }
}

/// Satırın sağ ucu — 44pt yükseklikte, sağ dolgulu.
class _SatirSonu extends StatelessWidget {
  const _SatirSonu({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: child,
      );
}

class _SahipIsareti extends StatelessWidget {
  const _SahipIsareti();

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.check_rounded, size: 18, color: context.c.text36);
}

/// "+ Takip" — satırın içinde AYRI bir dokunma hedefi. Satırın geri kalanı
/// önizler; bu düğme önizlemeden geçmeden hemen takibe alır.
class _HizliTakipDugmesi extends StatelessWidget {
  const _HizliTakipDugmesi({required this.semanticLabel, required this.onTap});
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SandikTappable(
        onTap: onTap,
        semanticLabel: semanticLabel,
        child: Container(
          constraints: const BoxConstraints(
              minWidth: SandikTouch.min, minHeight: SandikTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text('+ ${context.l10n.vsWatch}',
              style: context.t.titleSmall?.copyWith(
                  color: context.c.amberText, fontWeight: FontWeight.w700)),
        ),
      );
}
