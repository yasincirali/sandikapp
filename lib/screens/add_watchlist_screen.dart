import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        Icons,
        Material,
        Colors,
        ScaffoldMessenger,
        SnackBar,
        SnackBarAction,
        SnackBarBehavior;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/asset_type.dart';
import '../models/watchlist_item.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/symbol_search_service.dart';
import '../theme/sandik.dart';
import 'paywall_screen.dart';

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

/// Arama sonucundaki tek bir aday.
class _Candidate {
  final String ticker;
  final String name;
  final AssetType type;
  final String? subCategory;

  /// Fiyatın hangi para biriminde olduğu. Döviz ve ons altın gibi kalemler
  /// TRY'ye çevrilerek gösterilse de kaydın kendisi kaynak birimi taşır —
  /// `assets` tarafındaki `currency` ile aynı anlam.
  final String currency;

  const _Candidate({
    required this.ticker,
    required this.name,
    required this.type,
    this.subCategory,
    required this.currency,
  });

  /// `WatchlistItem.key` ile AYNI kural — iki taraf ayrışırsa "zaten takipte"
  /// tespiti yanlış çalışır.
  String get key {
    final core = (subCategory?.trim().isNotEmpty ?? false)
        ? 'sub:${subCategory!.trim().toUpperCase()}'
        : ticker.trim().toUpperCase();
    return '${type.name}|$core';
  }
}

class _AddWatchlistScreenState extends ConsumerState<AddWatchlistScreen> {
  final _ctrl = TextEditingController();
  String _q = '';
  List<_Candidate> _results = const [];
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
            if (_toCandidate(h) case final c?) c,
        ];
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _seq) return;
      // Arama başarısızsa liste boş kalır; kullanıcı yeniden yazabilir.
      setState(() => _loading = false);
    }
  }

  /// Arama sonucunu `SymbolHit` → `_Candidate` olarak çevirir.
  ///
  /// Kaynak `SymbolSearchService` — karşılaştırma ekranıyla AYNI servis.
  /// Kendi listesini tutmak, iki ekranın farklı varlık kümesi göstermesine
  /// yol açıyordu: takip listesinde endeksler (XU100/XU030) ve emtia
  /// (ons altın, gümüş, Brent/WTI petrol, doğalgaz) HİÇ çıkmıyordu, ayrıca
  /// TEFAS'ın liste API'sinde görünmeyen kurucu-only fonlar (ALE, YLB)
  /// aranamıyordu.
  ///
  /// Tür ve para birimi ticker biçiminden çıkarılır — `SymbolHit` bunları
  /// taşımaz çünkü karşılaştırma ekranının ihtiyacı yok.
  static _Candidate? _toCandidate(SymbolHit h) {
    // Portföy serileri (PORTFOLIO:*) sanal tickerlardır; takip edilemezler.
    if (PortfolioSeries.isPortfolio(h.ticker)) return null;

    final t = h.ticker;

    if (t.startsWith('TEFAS:')) {
      return _Candidate(
          ticker: t, name: h.name, type: AssetType.fon, currency: 'TRY');
    }
    if (t.startsWith('ALTIN_')) {
      return _Candidate(
        ticker: t,
        name: h.name,
        type: AssetType.altin,
        subCategory: h.name,
        currency: 'TRY',
      );
    }
    if (t == 'XAUUSD=X') {
      // Ons altın Yahoo'dan USD gelir.
      return _Candidate(
        ticker: t,
        name: h.name,
        type: AssetType.altin,
        subCategory: h.name,
        currency: 'USD',
      );
    }
    if (t.endsWith('TRY=X')) {
      // Kur çiftinin fiyatı TRY cinsindendir (USDTRY=X → ₺).
      return _Candidate(
        ticker: t,
        name: h.name,
        type: AssetType.doviz,
        subCategory: t.replaceAll('TRY=X', ''), // USD / EUR / GBP
        currency: 'TRY',
      );
    }
    if (t.endsWith('=F')) {
      // Emtia vadelileri USD kote; `getSymbolHistory` günün kuruyla çevirir.
      return _Candidate(
          ticker: t, name: h.name, type: AssetType.emtia, currency: 'USD');
    }
    // Kalanlar BIST: hisseler ve endeksler (`XU100.IS`).
    return _Candidate(
        ticker: t, name: h.name, type: AssetType.hisse, currency: 'TRY');
  }

  @override
  Widget build(BuildContext context) {
    final watchlist = ref.watch(watchlistProvider).valueOrNull ?? const [];
    final watchedKeys = {for (final w in watchlist) w.key};

    // Portföydeki varlıkların anahtarları — pasif göstermek için.
    final owned = ref.watch(portfolioProvider).valueOrNull?.assets ?? const [];
    final ownedKeys = <String>{
      for (final a in owned)
        if (a.isActive)
          '${a.type.name}|${(a.subCategory?.trim().isNotEmpty ?? false) ? 'sub:${a.subCategory!.trim().toUpperCase()}' : a.ticker.trim().toUpperCase()}',
    };

    final results = _results;
    final available = results.where((c) => !ownedKeys.contains(c.key)).toList();
    final inPortfolio =
        results.where((c) => ownedKeys.contains(c.key)).toList();

    return DefaultTextStyle(
      style: GoogleFonts.dmSans(
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
                    child: Text('Aranıyor…',
                        style: context.t.bodySmall
                            ?.copyWith(color: context.c.text36)),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      if (available.isEmpty && inPortfolio.isEmpty && !_loading)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Text(
                            _q.trim().isEmpty
                                ? 'Aramak için yazmaya başla.'
                                : '"${_q.trim()}" için sonuç yok.',
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
                          'PORTFÖYÜNDE',
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(
          children: [
            SizedBox(
              // Ölçek içi (`SandikSpace`): 36 ölçek dışıydı ve
              // `spacing_scale_test` bunu yakaladı. Dokunma hedefi
              // `height: 44` ile zaten HIG minimumunda.
              width: 32,
              height: 44,
              child: CupertinoButton(
                minimumSize: Size.zero,
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
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: CupertinoTextField(
          controller: _ctrl,
          onChanged: _sorguDegisti,
          placeholder: 'Hisse, fon, endeks, emtia, döviz veya altın ara',
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
            color: context.c.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(color: context.c.hairline),
          ),
        ),
      );

  Widget _tile(BuildContext context, _Candidate c,
      {bool watched = false, bool owned = false}) {
    // Portföydeki varlık pasif: dokunulamaz, soluk, "✓" ile işaretli.
    final disabled = owned || watched;

    return Opacity(
      opacity: owned ? 0.5 : 1.0,
      child: SandikTappable(
        onTap: disabled ? null : () => _add(c),
        semanticLabel: owned
            ? '${c.name}, zaten portföyünde'
            : watched
                ? '${c.name}, zaten takipte'
                : '${c.name} takibe al',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.bodyMedium
                            ?.copyWith(color: context.c.text90)),
                    Text('${c.ticker} · ${c.type.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.bodySmall
                            ?.copyWith(color: context.c.text36, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (owned)
                Icon(Icons.check_rounded, size: 18, color: context.c.text36)
              else if (watched)
                Text('Takipte',
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text36, fontSize: 11))
              else
                Text('+ Takip',
                    style: context.t.titleSmall?.copyWith(
                        color: context.c.amberText,
                        fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _add(_Candidate c) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    try {
      await ref.read(watchlistProvider.notifier).add(WatchlistItem(
            id: '', // sunucuda üretilir
            userId: user.id,
            ticker: c.ticker,
            name: c.name,
            type: c.type,
            subCategory: c.subCategory,
            currency: c.currency,
            addedAt: DateTime.now(),
          ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${c.name} takibe alındı'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on WatchlistLimitException catch (e) {
      if (!mounted) return;
      // Limit hatası ağ hatasından AYRI ele alınır: kullanıcıya neden
      // eklenemediğini ve ÇIKIŞ YOLUNU söylemek gerekir. "Eklenemedi" deyip
      // bırakmak kullanıcıyı çıkışsız bırakırdı.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Ücretsiz planda en fazla ${e.limit} varlık takip edebilirsin.'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Premium',
            onPressed: () =>
                PaywallScreen.show(context, source: 'watchlist_limit'),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      // Sunucudaki unique index çakışması da buraya düşer — kullanıcıya
      // teknik hata değil, ne olduğunu söyle.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Eklenemedi. Zaten takipte olabilir.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.c.loss,
        ),
      );
    }
  }
}
