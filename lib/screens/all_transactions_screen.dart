import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import '../widgets/modern_tab_selector.dart';
import '../widgets/h_scroll_with_fade.dart';
import '../widgets/transaction_row.dart';

/// Portföy hareketleri — tam liste.
///
/// Ana sayfadaki "PORTFÖY HAREKETLERİ" bölümü yalnızca son 3 kaydı gösterir;
/// "Tümünü Gör" buraya getirir. Bu ekran bir LOG'dur: her Al/Sat/Temettü ve
/// her silme işlemi ayrı satırdır, dolayısıyla kayıt sayısı zamanla büyür.
/// Bu yüzden üç şey gerekiyor:
///
///   1. **Sayfalama** — hepsini birden kurmak uzun listede kare düşürür.
///      `ListView.builder` zaten tembel çalışır ama satır sayısı arttıkça
///      filtre/sıralama maliyeti de büyüdüğü için [_pageSize]'lık parçalar
///      hâlinde büyütüyoruz.
///   2. **Tarih aralığı** — "geçen ay ne yaptım" sorusu.
///   3. **Metin araması** — varlık adı / ticker üzerinde.
///
/// Ana sayfadan farklı olarak burada AGGREGATE YOK: liste ham ledger'dır.
class AllTransactionsScreen extends ConsumerStatefulWidget {
  final Map<String, List<Asset>> allPartnerAssets;
  final List<AppUser> partners;

  /// Ana sayfadaki sahiplik sekmesi ('' = Ben, null = Birlikte, id = ortak).
  final String? initialView;
  final AssetType? initialTypeFilter;

  const AllTransactionsScreen({
    super.key,
    required this.allPartnerAssets,
    required this.partners,
    this.initialView,
    this.initialTypeFilter,
  });

  @override
  ConsumerState<AllTransactionsScreen> createState() =>
      _AllTransactionsScreenState();
}

/// Tarih aralığı ön ayarları — mutlak tarih seçtirmek yerine yaygın
/// pencereleri tek dokunuşla veriyoruz; "Özel" takvim açar.
enum _DateRange { all, days7, days30, days90, thisYear, custom }

extension _DateRangeLabel on _DateRange {
  String get label {
    switch (this) {
      case _DateRange.all:
        return 'Tüm zamanlar';
      case _DateRange.days7:
        return 'Son 7 gün';
      case _DateRange.days30:
        return 'Son 30 gün';
      case _DateRange.days90:
        return 'Son 90 gün';
      case _DateRange.thisYear:
        return 'Bu yıl';
      case _DateRange.custom:
        return 'Özel';
    }
  }
}

class _AllTransactionsScreenState extends ConsumerState<AllTransactionsScreen> {
  static const int _pageSize = 25;

  late String? _view;
  AssetType? _typeFilter;
  _DateRange _range = _DateRange.all;
  DateTimeRange? _customRange;
  String _query = '';

  int _visible = _pageSize;

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _view = widget.initialView ?? '';
    _typeFilter = widget.initialTypeFilter;
    // Kullanıcı listenin sonuna yaklaşınca sessizce büyüt — "daha fazla
    // yükle" düğmesi log okumada akışı bölerdi.
    _scrollCtrl.addListener(_maybeGrow);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_maybeGrow);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _maybeGrow() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      final total = _filtered.length;
      if (_visible < total) {
        setState(() => _visible = (_visible + _pageSize).clamp(0, total));
      }
    }
  }

  /// Filtre değişince sayfalama başa sarmalı; aksi halde kullanıcı dar bir
  /// sonuç kümesinde "zaten hepsi yüklü" sanır ya da tersi.
  void _resetPaging() => _visible = _pageSize;

  /// Sahiplik sekmesine göre ham ledger.
  List<Asset> get _ledger {
    final myAssets = ref.read(portfolioProvider).valueOrNull?.assets ?? const [];
    if (_view == '') return myAssets;
    if (_view != null && _view!.isNotEmpty) {
      return widget.allPartnerAssets[_view!] ?? const [];
    }
    return [
      ...myAssets,
      for (final list in widget.allPartnerAssets.values) ...list,
    ];
  }

  (DateTime?, DateTime?) get _rangeBounds {
    final now = DateTime.now();
    switch (_range) {
      case _DateRange.all:
        return (null, null);
      case _DateRange.days7:
        return (now.subtract(const Duration(days: 7)), null);
      case _DateRange.days30:
        return (now.subtract(const Duration(days: 30)), null);
      case _DateRange.days90:
        return (now.subtract(const Duration(days: 90)), null);
      case _DateRange.thisYear:
        return (DateTime(now.year), null);
      case _DateRange.custom:
        final r = _customRange;
        if (r == null) return (null, null);
        // Bitiş günü DAHİL olmalı: kullanıcı 5 Mart seçtiyse o günün
        // işlemleri de listeye girsin.
        return (
          DateTime(r.start.year, r.start.month, r.start.day),
          DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59),
        );
    }
  }

  List<Asset> get _filtered {
    final (from, to) = _rangeBounds;
    final q = _query.trim().toLowerCase();

    final out = <Asset>[];
    for (final a in _ledger) {
      if (_typeFilter != null && a.type != _typeFilter) continue;
      if (from != null && a.addedDate.isBefore(from)) continue;
      if (to != null && a.addedDate.isAfter(to)) continue;
      if (q.isNotEmpty) {
        final name = a.name.toLowerCase();
        final ticker = a.ticker.toLowerCase();
        final sub = (a.subCategory ?? '').toLowerCase();
        if (!name.contains(q) && !ticker.contains(q) && !sub.contains(q)) {
          continue;
        }
      }
      out.add(a);
    }
    out.sort((a, b) => b.addedDate.compareTo(a.addedDate));
    return out;
  }

  bool get _hasActiveFilter =>
      _typeFilter != null || _range != _DateRange.all || _query.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final activePartners = ref.watch(activePartnersProvider);
    final pState = ref.watch(portfolioProvider).valueOrNull;
    final hideBalance = ref.watch(balanceHiddenProvider);

    final rows = _filtered;
    final shown = _visible.clamp(0, rows.length);

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: context.c.text90),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Portföy Hareketleri',
          style: context.t.headlineMedium?.copyWith(color: context.c.text90),
        ),
      ),
      body: Column(
        children: [
          if (activePartners.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: ModernTabSelector(
                partners: activePartners,
                selectedId: _view,
                onChanged: (v) => setState(() {
                  _view = v;
                  _resetPaging();
                }),
              ),
            ),

          // ── Arama ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() {
                _query = v;
                _resetPaging();
              }),
              style: context.t.bodyMedium?.copyWith(color: context.c.text90),
              decoration: context.inputDecoration(
                'Varlık adı veya sembol ara',
                prefixIcon:
                    Icon(Icons.search_rounded, size: 20, color: context.c.text36),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close_rounded,
                            size: 18, color: context.c.text36),
                        onPressed: () => setState(() {
                          _searchCtrl.clear();
                          _query = '';
                          _resetPaging();
                        }),
                      ),
              ),
            ),
          ),

          // ── Tarih aralığı ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: HScrollWithFade(
              child: Row(
                children: [
                  for (final r in _DateRange.values) _rangeChip(r),
                ],
              ),
            ),
          ),

          // ── Varlık türü ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: HScrollWithFade(
              child: Row(
                children: [
                  _typeChip(null, 'Tümü'),
                  for (final t in RemoteConfigService.instance.visibleAssetTypes)
                    _typeChip(t, t.label),
                ],
              ),
            ),
          ),

          // ── Sonuç sayacı ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Text(
                  rows.isEmpty
                      ? 'Kayıt yok'
                      : '${rows.length} kayıt'
                          '${shown < rows.length ? ' · $shown gösteriliyor' : ''}',
                  style: context.t.bodySmall?.copyWith(color: context.c.text36),
                ),
                const Spacer(),
                if (_hasActiveFilter)
                  SandikTappable(
                    semanticLabel: 'Filtreleri temizle',
                    onTap: () => setState(() {
                      _typeFilter = null;
                      _range = _DateRange.all;
                      _customRange = null;
                      _query = '';
                      _searchCtrl.clear();
                      _resetPaging();
                    }),
                    child: Text(
                      'Filtreleri temizle',
                      style: context.t.bodySmall?.copyWith(
                          color: context.c.amberText,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          Divider(color: context.c.hairline, height: 1),

          // ── Liste ────────────────────────────────────────────────────
          Expanded(
            child: rows.isEmpty
                ? _empty()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    // +1: son satırda "yükleniyor" göstergesi (daha var ise).
                    itemCount: shown + (shown < rows.length ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i >= shown) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'Yükleniyor…',
                              style: context.t.bodySmall
                                  ?.copyWith(color: context.c.text36),
                            ),
                          ),
                        );
                      }
                      return TransactionRow(
                        asset: rows[i],
                        portfolioState: pState ?? const PortfolioState(),
                        hideBalance: hideBalance,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 52, color: context.c.text36),
            const SizedBox(height: 12),
            Text(
              _hasActiveFilter ? 'Filtreye uyan kayıt yok' : 'Henüz işlem yok',
              style: context.t.titleMedium?.copyWith(color: context.c.text36),
            ),
            if (_hasActiveFilter) ...[
              const SizedBox(height: 8),
              Text(
                'Tarih aralığını genişletmeyi veya aramayı temizlemeyi dene.',
                textAlign: TextAlign.center,
                style: context.t.bodySmall?.copyWith(color: context.c.text36),
              ),
            ],
          ],
        ),
      );

  Widget _rangeChip(_DateRange r) {
    final selected = _range == r;
    // "Özel" seçiliyse etiket seçilen aralığı göstersin — yoksa kullanıcı
    // hangi aralıkta olduğunu chip'ten okuyamaz.
    final label = r == _DateRange.custom && _customRange != null
        ? '${DateFormat('d MMM', 'tr_TR').format(_customRange!.start)}'
            ' – ${DateFormat('d MMM', 'tr_TR').format(_customRange!.end)}'
        : r.label;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SandikTappable(
        semanticLabel: label,
        onTap: () async {
          if (r == _DateRange.custom) {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2000),
              lastDate: DateTime.now(),
              // Locale MaterialApp'ten gelir (tr_TR) — burada tekrar
              // vermek gereksiz ve iki yerde sürüklenmesi gereken bir
              // sabit yaratırdı.
              initialDateRange: _customRange,
            );
            if (picked == null) return;
            if (!mounted) return;
            setState(() {
              _customRange = picked;
              _range = _DateRange.custom;
              _resetPaging();
            });
            return;
          }
          setState(() {
            _range = r;
            _resetPaging();
          });
        },
        child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.md, vertical: SandikSpace.sm),
          decoration: context.chip(selected: selected, radius: SandikRadius.lg),
          child: Text(
            label,
            style: context.t.titleSmall?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? context.c.amberText : context.c.text58,
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeChip(AssetType? type, String label) {
    final selected = _typeFilter == type;
    final color = type?.color ?? context.c.amberText;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SandikTappable(
        semanticLabel: label,
        onTap: () => setState(() {
          _typeFilter = type;
          _resetPaging();
        }),
        child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.md, vertical: SandikSpace.sm),
          decoration: context.chip(
              selected: selected, accent: color, radius: SandikRadius.lg),
          child: Text(
            label,
            style: context.t.titleSmall?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? color : context.c.text58,
            ),
          ),
        ),
      ),
    );
  }
}
