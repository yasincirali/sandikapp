part of '../asset_detail_screen.dart';

/// Karşılaştırma serisi seçici (katalog + sheet).
/// `asset_detail_screen.dart`'ın part'ı (2026-09-14).
/// Compare picker satır kaynağı — hem portföydeki varlık hem de
/// katalog (BIST100 / döviz / altın) aynı yapıyla temsil edilir.
class _CompareChoice {
  final String ticker;
  final String name;
  final AssetType type;
  final String currency;
  final String source; // 'portfolio' | 'bist' | 'fx' | 'gold'

  const _CompareChoice({
    required this.ticker,
    required this.name,
    required this.type,
    required this.currency,
    required this.source,
  });

  /// HistoryService'in beklediği minimum alanları sağlayan sanal Asset.
  /// Grafik için sadece ticker/type/currency kullanılıyor.
  /// addedDate çok geriye ayarlanır — HistoryService `addedTs > dayTs` ise
  /// quantity=0 döndürüyor, bu compare için tüm dönemde quantity=1 olsun.
  Asset toVirtualAsset() {
    return Asset(
      id: 'compare-$ticker',
      userId: '',
      name: name,
      ticker: ticker,
      type: type,
      quantity: 1,
      purchasePrice: 1,
      currency: currency,
      notes: '',
      addedDate: DateTime(2000, 1, 1),
    );
  }
}

/// Katalog seçenekleri — kullanıcının portföyde tutmadığı varlıklarla
/// da karşılaştırma yapabilsin diye statik olarak sağlanır.
List<_CompareChoice> _catalogChoices() {
  final out = <_CompareChoice>[];
  // BIST100 hisseleri
  bist100StocksMap.forEach((ticker, name) {
    out.add(_CompareChoice(
      ticker: ticker,
      name: name,
      type: AssetType.hisse,
      currency: 'TRY',
      source: 'bist',
    ));
  });
  // Major dövizler
  out.addAll(const [
    _CompareChoice(
        ticker: 'USDTRY=X',
        name: 'ABD Doları',
        type: AssetType.doviz,
        currency: 'USD',
        source: 'fx'),
    _CompareChoice(
        ticker: 'EURTRY=X',
        name: 'Euro',
        type: AssetType.doviz,
        currency: 'EUR',
        source: 'fx'),
    _CompareChoice(
        ticker: 'GBPTRY=X',
        name: 'İngiliz Sterlini',
        type: AssetType.doviz,
        currency: 'GBP',
        source: 'fx'),
  ]);
  // Altın (gram karşılığı, HistoryService altın için USD/gr → TRY dönüşümü yapar)
  out.add(const _CompareChoice(
    ticker: 'XAU',
    name: 'Altın (Gram)',
    type: AssetType.altin,
    currency: 'USD',
    source: 'gold',
  ));
  return out;
}

/// Compare için varlık seçim sheet — iki sekme: Portföyüm + Diğer.
/// Arama kutusu aktif sekmede filtreler.
class _ComparePickerSheet extends StatefulWidget {
  final List<Asset> choices; // portföy varlıkları
  final String? currentSelectionTicker;
  final void Function(_CompareChoice?) onSelected;

  const _ComparePickerSheet({
    required this.choices,
    required this.currentSelectionTicker,
    required this.onSelected,
  });

  @override
  State<_ComparePickerSheet> createState() => _ComparePickerSheetState();
}

class _ComparePickerSheetState extends State<_ComparePickerSheet>
    with SingleTickerProviderStateMixin {
  String _query = '';
  late TabController _tabController;
  late List<_CompareChoice> _catalog = _catalogChoices();
  late final List<_CompareChoice> _portfolio = widget.choices
      .map((a) => _CompareChoice(
            ticker: a.ticker,
            name: a.name,
            type: a.type,
            currency: a.currency,
            source: 'portfolio',
          ))
      .toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _appendTefas();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// TEFAS fonlarını katalog listesine ekle. Uygulama açılışında disk
  /// cache'ten hazır geldiği için pratikte anında döner; spinner gösterme.
  Future<void> _appendTefas() async {
    try {
      final funds = await TefasService.instance.fetchAllFunds();
      if (!mounted || funds.isEmpty) return;
      final extra = funds.map((f) => _CompareChoice(
            ticker: 'TEFAS:${f.code}',
            name: f.name,
            type: AssetType.fon,
            currency: 'TRY',
            source: 'tefas',
          ));
      setState(() {
        _catalog = [..._catalog, ...extra];
      });
    } catch (_) {
      // Cache yoksa TEFAS sekmesi olmadan devam et.
    }
  }

  // TEFAS liste API'sinde olmayan (kurucu-only) fonlar için tek-fon
  // lookup — kullanıcı ALE / YLB gibi bir kod yazınca arka planda çağrılır.
  final Set<String> _lookupInFlight = {};
  final Set<String> _lookupTried = {};

  Future<void> _tryLookupTefas(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.length < 3 || code.length > 6) return;
    if (_lookupTried.contains(code)) return;
    if (_lookupInFlight.contains(code)) return;
    if (_catalog.any((c) => c.ticker == 'TEFAS:$code')) return;
    _lookupInFlight.add(code);
    try {
      final fund = await TefasService.instance.lookupFund(code);
      _lookupTried.add(code);
      if (!mounted || fund == null) return;
      setState(() {
        _catalog = [
          ..._catalog,
          _CompareChoice(
            ticker: 'TEFAS:${fund.code}',
            name: fund.name,
            type: AssetType.fon,
            currency: 'TRY',
            source: 'tefas',
          ),
        ];
      });
    } catch (_) {
      _lookupTried.add(code); // spam engelle
    } finally {
      _lookupInFlight.remove(code);
    }
  }

  List<_CompareChoice> _filter(List<_CompareChoice> src) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return src;
    return src.where((c) {
      return c.ticker.toLowerCase().contains(q) ||
          c.name.toLowerCase().contains(q);
    }).toList();
  }

  Widget _list(List<_CompareChoice> items) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Sonuç yok.',
          style: context.t.bodyMedium?.copyWith(color: context.c.text58),
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) {
        final c = items[i];
        final selected = widget.currentSelectionTicker == c.ticker;
        return ListTile(
          leading: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c.type.color,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(
            c.ticker,
            style: context.t.titleMedium?.copyWith(
              color: context.c.text90,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            c.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
          trailing: selected
              ? Icon(Icons.check_rounded, color: context.c.amberText)
              : null,
          onTap: () => widget.onSelected(c),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.78,
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.c.overlay,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    Text(
                      'Karşılaştır',
                      style: context.t.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: context.c.text90,
                      ),
                    ),
                    const Spacer(),
                    if (widget.currentSelectionTicker != null)
                      TextButton(
                        onPressed: () => widget.onSelected(null),
                        child: const Text('Temizle'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  autofocus: false,
                  style: TextStyle(color: context.c.text90),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded,
                        color: context.c.text58),
                    hintText: 'Ticker veya isim ara…',
                    hintStyle:
                        TextStyle(color: context.c.text36, fontSize: 13),
                    filled: true,
                    fillColor: context.c.overlay,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SandikRadius.md),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (v) {
                    setState(() => _query = v);
                    // Kurucu-only TEFAS fonları (ör. ALE, YLB) fetchAllFunds
                    // içinde yok — kullanıcı kısa bir kod yazınca arka
                    // planda lookup yap, bulunursa katalog liste güncellenir.
                    _tryLookupTefas(v);
                  },
                ),
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabController,
                indicatorColor: context.c.amberText,
                labelColor: context.c.amberText,
                unselectedLabelColor: context.c.text58,
                labelStyle: context.t.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                tabs: const [
                  Tab(text: 'Portföyüm'),
                  Tab(text: 'Diğer'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _list(_filter(_portfolio)),
                    _list(_filter(_catalog)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const Color _kCompareColor = Sandik.info;
