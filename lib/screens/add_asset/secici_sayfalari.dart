part of '../add_asset_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Hızlı / Toplu Giriş Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _QuickEntrySheet extends StatefulWidget {
  final TextEditingController ctrl;
  final ParsedEntry? Function(String) parseLine;
  final void Function(ParsedEntry) onConfirmSingle;
  final Future<void> Function(List<ParsedEntry>) onSaveBatch;

  const _QuickEntrySheet({
    required this.ctrl,
    required this.parseLine,
    required this.onConfirmSingle,
    required this.onSaveBatch,
  });

  @override
  State<_QuickEntrySheet> createState() => _QuickEntrySheetState();
}

class _QuickEntrySheetState extends State<_QuickEntrySheet> {
  List<ParsedEntry> _previews = [];

  void _updatePreviews(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty);
    setState(() {
      _previews =
          lines.map(widget.parseLine).whereType<ParsedEntry>().toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMulti = _previews.length > 1;
    return Padding(
      padding: EdgeInsets.only(
        left: SandikSpace.screenH(context),
        right: SandikSpace.screenH(context),
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: context.c.amberText, size: 22),
              const SizedBox(width: 8),
              Text(
                context.l10n.quickEntryTitle,
                style: context.t.headlineSmall?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: context.c.text90,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.quickEntryHelp,
            style: context.t.titleSmall
                ?.copyWith(color: context.c.text58, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: widget.ctrl,
            onTapOutside: _klavyeyiKapat,
            maxLines: 5,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            style: context.t.titleMedium?.copyWith(color: context.c.text90),
            decoration: InputDecoration(
              hintText:
                  context.l10n.quickEntryPlaceholder,
              hintStyle:
                  context.t.bodyMedium?.copyWith(color: context.c.text36),
              // Dolgu/çerçeve temadan (`inputDecorationTheme` = `inputFill` kuralı).
            ),
            onChanged: _updatePreviews,
          ),
          // Önizleme satırları her yazılan satırla uzar; toplu girişte
          // (sayfanın asıl işi) metin + klavye ekranı aşıyordu ve
          // "N varlığı kaydet" klavyenin altında kalıyordu. Liste kalan
          // yükseklikte kayar; alan ve düğme hep görünür (klavye denetimi
          // 2026-10-08).
          if (_previews.isNotEmpty) ...[
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
            ...(_previews.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: e.type.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${e.type.labelOf(context.l10n)}  ·  ${e.qty % 1 == 0 ? e.qty.toInt() : e.qty}'
                          '${e.subCategory != null ? '  ${e.subCategory}' : ''}'
                          '${e.price > 0 ? '  @ ${e.price % 1 == 0 ? e.price.toInt() : e.price} ₺' : '  (fiyat otomatik)'}',
                          style: context.t.titleSmall
                              ?.copyWith(color: context.c.text58),
                        ),
                      ),
                    ],
                  ),
                ))),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: isMulti
                    // Kilit çift kaydı önler; SandikAsyncButton kilidi
                    // `finally`'de açar (eskiden elle yazılmış `_saving` +
                    // tam genişlik döneni; finally'siz sürümde hata verince
                    // buton kalıcı olarak spinner'da kalıyordu).
                    ? SandikAsyncButton.kompakt(
                        onPressed: () => widget.onSaveBatch(_previews),
                        style: FilledButton.styleFrom(
                            backgroundColor: context.c.amberFill,
                            foregroundColor: context.c.onAmber),
                        icon: const Icon(Icons.playlist_add_check_rounded),
                        // Renk açıkça `onAmber` — `_stickyBottomBar` notu.
                        child: Text(context.l10n.saveNAssets(_previews.length),
                            style: context.t.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: context.c.onAmber)),
                      )
                    : FilledButton.icon(
                        onPressed: _previews.isEmpty
                            ? null
                            : () => widget.onConfirmSingle(_previews.first),
                        style: FilledButton.styleFrom(
                            backgroundColor: context.c.amberFill,
                            foregroundColor: context.c.onAmber),
                        icon: const Icon(Icons.check_rounded),
                        // Pasifken (`null`) eski ton kalır: soluk dolguda
                        // koyu `onAmber` okunmazdı.
                        label: Text(context.l10n.fillTheForm,
                            style: context.t.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: _previews.isEmpty
                                    ? null
                                    : context.c.onAmber)),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BIST100 Picker
// ─────────────────────────────────────────────────────────────────────────────

class _Bist100Picker extends StatefulWidget {
  final String? selected;
  final void Function(String ticker) onSelect;
  const _Bist100Picker({required this.selected, required this.onSelect});

  @override
  State<_Bist100Picker> createState() => _Bist100PickerState();
}

class _Bist100PickerState extends State<_Bist100Picker> {
  final _ctrl = TextEditingController();
  String _q = '';

  // Liste sunucudan tazelenirse (yeni halka arz) açık seçici de güncellenir.
  // Açılışta yüklenmiş olur; burada yalnız bayatsa sorulur (2026-10-10).
  @override
  void initState() {
    super.initState();
    BistHisseKatalogu.instance.addListener(_katalogDegisti);
    CrashReporter.arkaPlan(BistHisseKatalogu.instance.yukle(),
        reason: '_Bist100Picker.yukle');
  }

  void _katalogDegisti() {
    if (mounted) setState(() {});
  }

  List<MapEntry<String, String>> get _filtered {
    final all = BistHisseKatalogu.instance.hisseler.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    if (_q.isEmpty) return all;
    final q = _q.toLowerCase();
    return all
        .where((e) =>
            e.value.toLowerCase().contains(q) ||
            e.key.toLowerCase().contains(q))
        .toList();
  }

  @override
  void dispose() {
    BistHisseKatalogu.instance.removeListener(_katalogDegisti);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;
    return _PickerShell(
      title: context.l10n.bistStocks,
      count: filtered.length,
      color: AssetType.hisse.color,
      searchCtrl: _ctrl,
      onSearch: (v) => setState(() => _q = v),
      query: _q,
      cs: cs,
      child: filtered.isEmpty
          ? _emptySearch(context, _q, cs)
          : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final e = filtered[i];
                final isSelected = e.key == widget.selected;
                final ticker = e.key.replaceAll('.IS', '');
                return _PickerRow(
                  badgeText:
                      ticker.length > 5 ? ticker.substring(0, 4) : ticker,
                  title: e.value,
                  subtitle: e.key,
                  isSelected: isSelected,
                  color: AssetType.hisse.color,
                  cs: cs,
                  onTap: () => widget.onSelect(e.key),
                  kimlik: VarlikKimligi.hisse(e.key, e.value),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ABD hisse seçici (bayrak `abd_hisse`) — BIST seçicisinin eşi
// ─────────────────────────────────────────────────────────────────────────────

class _AbdPicker extends StatefulWidget {
  final String? selected;
  final void Function(String ticker) onSelect;
  const _AbdPicker({required this.selected, required this.onSelect});

  @override
  State<_AbdPicker> createState() => _AbdPickerState();
}

class _AbdPickerState extends State<_AbdPicker> {
  final _ctrl = TextEditingController();
  String _q = '';

  /// BIST seçicisiyle aynı kural (ad sırası, ad/sembol içinde arama). Sembol
  /// sorgusu da Yahoo biçimine çevrilir: "brk.b" `BRK-B`'yi bulur.
  List<MapEntry<String, String>> get _filtered {
    final all = abdHisseleri.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    if (_q.isEmpty) return all;
    final q = _q.toLowerCase();
    final sembol = abdSembolu(_q).toLowerCase();
    return all
        .where((e) =>
            e.value.toLowerCase().contains(q) ||
            e.key.toLowerCase().contains(sembol))
        .toList();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;
    return _PickerShell(
      title: context.l10n.usStocks,
      count: filtered.length,
      color: AssetType.hisse.color,
      searchCtrl: _ctrl,
      onSearch: (v) => setState(() => _q = v),
      query: _q,
      cs: cs,
      child: filtered.isEmpty
          ? _emptySearch(context, _q, cs)
          : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final e = filtered[i];
                return _PickerRow(
                  badgeText: e.key.length > 5 ? e.key.substring(0, 4) : e.key,
                  title: e.value,
                  subtitle: e.key,
                  isSelected: e.key == widget.selected,
                  color: AssetType.hisse.color,
                  cs: cs,
                  onTap: () => widget.onSelect(e.key),
                  kimlik: VarlikKimligi.abdHisse(e.key, e.value),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Altın türü seçici — tüm türler, gruplu ve aramalı
// ─────────────────────────────────────────────────────────────────────────────

class _GoldPicker extends StatefulWidget {
  final GoldSubCategory? selected;
  final String Function(GoldSubCategory) birim;
  final void Function(GoldSubCategory) onSelect;
  const _GoldPicker(
      {required this.selected, required this.birim, required this.onSelect});

  @override
  State<_GoldPicker> createState() => _GoldPickerState();
}

class _GoldPickerState extends State<_GoldPicker> {
  final _ctrl = TextEditingController();
  String _q = '';

  String _grupAdi(AltinGrubu g) => switch (g) {
        AltinGrubu.gram => context.l10n.goldGroupGram,
        AltinGrubu.ziynet => context.l10n.goldGroupZiynet,
        AltinGrubu.sikke => context.l10n.goldGroupSikke,
        AltinGrubu.ons => context.l10n.goldGroupOns,
      };

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final eslesen = altinTurleriniAra(_q);
    // Grup başlığı + satırlar düz listeye açılır; boş grup başlığı çizilmez.
    final ogeler = <Object>[
      for (final grup in AltinGrubu.values)
        if (eslesen.any((g) => g.grup == grup)) ...[
          grup,
          ...eslesen.where((g) => g.grup == grup),
        ],
    ];
    return _PickerShell(
      title: context.l10n.goldTypes,
      searchHint: context.l10n.goldSearchHint,
      count: eslesen.length,
      color: AssetType.altin.color,
      searchCtrl: _ctrl,
      onSearch: (v) => setState(() => _q = v),
      query: _q,
      cs: cs,
      child: eslesen.isEmpty
          ? _emptySearch(context, _q, cs)
          : ListView.builder(
              itemCount: ogeler.length,
              itemBuilder: (_, i) {
                final o = ogeler[i];
                if (o is AltinGrubu) {
                  // HIG gruplu liste başlığı: satır metniyle aynı sol
                  // hizada, ikincil renkte, üstünde grup ayıracı boşluk.
                  final yatay = SandikSpace.screenH(context);
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                        yatay, i == 0 ? SandikSpace.md : SandikSpace.lg,
                        yatay, SandikSpace.xs),
                    child: Semantics(
                      header: true,
                      child: Text(_grupAdi(o),
                          style: context.t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.c.text58)),
                    ),
                  );
                }
                final g = o as GoldSubCategory;
                return _PickerRow(
                  badgeText: widget.birim(g),
                  title: g.label,
                  subtitle: g.description,
                  isSelected: g == widget.selected,
                  color: AssetType.altin.color,
                  cs: cs,
                  onTap: () => widget.onSelect(g),
                  kimlik: VarlikKimligi.fromGold(g),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TEFAS Picker
// ─────────────────────────────────────────────────────────────────────────────

class _TefasPicker extends StatefulWidget {
  final String? selected;
  final void Function(TefasFund fund) onSelect;
  const _TefasPicker({required this.selected, required this.onSelect});

  @override
  State<_TefasPicker> createState() => _TefasPickerState();
}

class _TefasPickerState extends State<_TefasPicker> {
  final _ctrl = TextEditingController();
  String _q = '';
  List<TefasFund>? _funds;
  String? _error;

  // TEFAS liste API'sinde olmayan ama fiyat API'sinde bulunan
  // (kurucu-only) fonlar için lookup sonucu. Kullanıcı örn. "ALE" ya da
  // "YLB" yazdığında liste boş çıkarsa, arka planda tek-fon sorgusu
  // gönderilir ve sonuç buraya konur — kullanıcı "para piyasası fonu"
  // gibi görünmeyen fonları da bulabilsin.
  final Map<String, TefasFund?> _lookupCache = {};
  final Set<String> _lookupInFlight = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _tryLookup(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.length < 2 || code.length > 6) return;
    if (_lookupCache.containsKey(code)) return;
    if (_lookupInFlight.contains(code)) return;
    _lookupInFlight.add(code);
    try {
      final fund = await TefasService.instance.lookupFund(code);
      if (!mounted) return;
      setState(() {
        _lookupCache[code] = fund;
        if (fund != null && _funds != null) {
          // Cache'e yansı — bir sonraki filtreleme direkt bulur.
          if (!_funds!.any((f) => f.code == fund.code)) {
            _funds = [..._funds!, fund]
              ..sort((a, b) => a.name.compareTo(b.name));
          }
        }
      });
    } finally {
      _lookupInFlight.remove(code);
    }
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _funds = null;
    });
    try {
      final funds = await TefasService.instance.fetchAllFunds();
      if (mounted) {
        // Always succeed - funds will never be null
        if (funds.isNotEmpty) {
          setState(() => _funds = funds);
        } else {
          // Yedek katalog da boş geldiyse. Eskiden kullanıcıya geliştirici
          // notu ("fallback kullanılıyor") gösteriliyordu (2026-10-20).
          setState(() => _error = context.l10n.fundsEmptyRetry);
        }
      }
    } catch (e) {
      // This should never happen, but keep for safety
      if (mounted) {
        // Elle string eşleme yerine ortak çevirici — ağ/timeout/HTTP
        // ayrımını zaten yapıyor, ham metin sızdırmıyor.
        setState(() => _error = friendlyError(e));
      }
    }
  }

  List<TefasFund> get _filtered {
    final all = _funds ?? [];
    if (_q.isEmpty) return all;
    final q = _q.toLowerCase();
    return all
        .where((f) =>
            f.name.toLowerCase().contains(q) ||
            f.code.toLowerCase().contains(q))
        .toList();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;
    final fmt = qtyFormatter(maxDigits: 6);

    return _PickerShell(
      title: context.l10n.tefasFunds,
      count: filtered.length,
      color: AssetType.fon.color,
      searchCtrl: _ctrl,
      onSearch: (v) {
        setState(() => _q = v);
        // TEFAS liste API'sinde olmayan (kurucu-only) fon kodları için —
        // örn. ALE, YLB gibi para piyasası fonları — arama filtresi boş
        // çıkarsa arka planda tek-fon lookup gönder. Bulunursa cache'e
        // eklenip filtreye dâhil olur.
        final code = v.trim().toUpperCase();
        if (code.length >= 3 && code.length <= 6) {
          final already = (_funds ?? []).any((f) => f.code == code);
          if (!already) _tryLookup(code);
        }
      },
      query: _q,
      cs: cs,
      // Yükleniyor/hata görünümü kripto ve eurobond seçicileriyle aynı
      // (token'lı renk/tipografi, l10n "Tekrar Dene"); 2026-10-20'ye kadar bu
      // seçici Material renkleri ve ham `fontSize` taşıyordu.
      child: _funds == null && _error == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CustomLoadingIndicator(),
                  const SizedBox(height: SandikSpace.smd),
                  Text(context.l10n.fundsLoading,
                      style: context.t.bodyMedium
                          ?.copyWith(color: context.c.text58)),
                  const SizedBox(height: SandikSpace.xs),
                  Text(
                    context.l10n.pleaseWait,
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58),
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(SandikSpace.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded,
                            color: context.c.loss, size: 40),
                        const SizedBox(height: SandikSpace.smd),
                        Text(context.l10n.fundsLoadFailed,
                            style: context.t.titleSmall),
                        const SizedBox(height: SandikSpace.xs),
                        Text(
                          _error!,
                          style: context.t.bodySmall
                              ?.copyWith(color: context.c.text58),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: SandikSpace.md),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(context.l10n.retry),
                        ),
                      ],
                    ),
                  ),
                )
              : filtered.isEmpty
                  ? _emptySearch(context, _q, cs)
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final f = filtered[i];
                        final isSelected = f.code == widget.selected;
                        return _PickerRow(
                          badgeText: f.code,
                          title: f.name,
                          subtitle: f.price > 0
                              ? '₺ ${fmt.format(f.price)}'
                              : context.l10n.priceNotAvailable,
                          isSelected: isSelected,
                          color: AssetType.fon.color,
                          cs: cs,
                          onTap: () => widget.onSelect(f),
                          kimlik: VarlikKimligi.fon(f.code, f.name),
                        );
                      },
                    ),
    );
  }
}

class _KriptoPicker extends ConsumerStatefulWidget {
  final String? selected;
  final void Function(KriptoKatalogOgesi o) onSelect;
  const _KriptoPicker({required this.selected, required this.onSelect});

  @override
  ConsumerState<_KriptoPicker> createState() => _KriptoPickerState();
}

class _KriptoPickerState extends ConsumerState<_KriptoPicker> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final katalog = ref.watch(kriptoKatalogProvider);
    final liste = kriptoAra(katalog.valueOrNull ?? const [], _q);
    final renk = AssetType.kripto.color;
    final simdi = DateTime.now();

    return _PickerShell(
      title: context.l10n.cryptoPickerTitle,
      count: liste.length,
      color: renk,
      searchCtrl: _ctrl,
      searchHint: context.l10n.cryptoSearchHint,
      onSearch: (v) => setState(() => _q = v),
      query: _q,
      cs: cs,
      child: katalog.when(
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CustomLoadingIndicator(),
              const SizedBox(height: SandikSpace.smd),
              Text(context.l10n.cryptoLoading,
                  style: context.t.bodyMedium
                      ?.copyWith(color: context.c.text58)),
            ],
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(SandikSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, color: context.c.loss, size: 40),
                const SizedBox(height: SandikSpace.smd),
                Text(context.l10n.cryptoLoadFailed,
                    style: context.t.titleSmall),
                const SizedBox(height: SandikSpace.xs),
                Text(friendlyError(e),
                    textAlign: TextAlign.center,
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58)),
                const SizedBox(height: SandikSpace.md),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(kriptoKatalogProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
        data: (_) => Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
                  SandikSpace.sm, SandikSpace.screenH(context), SandikSpace.xs),
              child: Text(context.l10n.cryptoSourceNote,
                  style:
                      context.t.bodySmall?.copyWith(color: context.c.text36)),
            ),
            Expanded(
              child: liste.isEmpty
                  ? _emptySearch(context, _q, cs)
                  : ListView.builder(
                      itemCount: liste.length,
                      itemBuilder: (_, i) {
                        final o = liste[i];
                        final f = o.fiyat;
                        return _PickerRow(
                          badgeText: o.kod,
                          logoUrl: o.logoUrl,
                          title: o.gorunenAd,
                          subtitle: f == null
                              ? context.l10n.priceNotAvailable
                              : [
                                  o.kod,
                                  fmtTRYFiyat(f.fiyatTry),
                                  if (f.bayatMi(simdi))
                                    context.l10n.priceDelayed,
                                ].join(' · '),
                          isSelected: o.kod == widget.selected,
                          color: renk,
                          cs: cs,
                          onTap: () => widget.onSelect(o),
                          kimlik: VarlikKimligi.kripto(o.kod, o.gorunenAd),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eurobond seçici — katalogdaki USD tahviller (`eklenebilirEurobondlar`;
/// EUR'nun neden dışarıda olduğu orada). Arama ad ya da ISIN alır; tam bir
/// ISIN yazıldığında kontrol hanesi ve katalog üyeliği satır içinde söylenir
/// (`isinAramaSonucu`) — "sonuç yok" yerine nedeni.
class _EurobondPicker extends ConsumerStatefulWidget {
  final String? selected;
  final void Function((EurobondSozlesmesi, EurobondFiyati?) o) onSelect;
  const _EurobondPicker({required this.selected, required this.onSelect});

  @override
  ConsumerState<_EurobondPicker> createState() => _EurobondPickerState();
}

class _EurobondPickerState extends ConsumerState<_EurobondPicker> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Satır alt başlığı: ISIN · vade · temiz fiyat · getiri. Fiyat yoksa
  /// getiri de yok — uydurulmaz.
  String _altBaslik((EurobondSozlesmesi, EurobondFiyati?) o, DateTime simdi) {
    final (s, f) = o;
    final l = context.l10n;
    final temiz = f?.temizFiyat;
    final getiri = temiz == null ? null : s.vadeyeGetiri(temiz, simdi);
    return [
      s.isin,
      l.eurobondMaturityShort(fmtTarihSaat(dayKey(s.vade))),
      if (temiz != null) fmtNum(temiz),
      if (getiri != null) l.eurobondYieldShort(fmtPct(getiri * 100)),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final katalog = ref.watch(eurobondKatalogProvider);
    final simdi = DateTime.now();
    final eklenebilir = eklenebilirEurobondlar(
        katalog.valueOrNull ?? const [],
        simdi: simdi);
    final liste = eurobondAra(eklenebilir, _q);
    final isinDurumu = isinAramaSonucu(_q, eklenebilir);
    final renk = AssetType.eurobond.color;
    final yatay = SandikSpace.screenH(context);

    return _PickerShell(
      title: context.l10n.eurobondPickerTitle,
      count: liste.length,
      color: renk,
      searchCtrl: _ctrl,
      searchHint: context.l10n.tickerHintEurobond,
      onSearch: (v) => setState(() => _q = v),
      query: _q,
      cs: cs,
      child: katalog.when(
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CustomLoadingIndicator(),
              const SizedBox(height: SandikSpace.smd),
              Text(context.l10n.eurobondLoading,
                  style: context.t.bodyMedium
                      ?.copyWith(color: context.c.text58)),
            ],
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(SandikSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, color: context.c.loss, size: 40),
                const SizedBox(height: SandikSpace.smd),
                Text(context.l10n.eurobondLoadFailed,
                    style: context.t.titleSmall),
                const SizedBox(height: SandikSpace.xs),
                Text(friendlyError(e),
                    textAlign: TextAlign.center,
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58)),
                const SizedBox(height: SandikSpace.md),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(eurobondKatalogProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
        data: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  yatay, SandikSpace.sm, yatay, SandikSpace.xs),
              child: Text(context.l10n.eurobondSourceNote,
                  style:
                      context.t.bodySmall?.copyWith(color: context.c.text36)),
            ),
            if (isinDurumu == IsinAramaSonucu.gecersiz ||
                isinDurumu == IsinAramaSonucu.katalogdaYok)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    yatay, SandikSpace.xs, yatay, SandikSpace.xs),
                child: Text(
                  isinDurumu == IsinAramaSonucu.gecersiz
                      ? context.l10n.eurobondIsinInvalid
                      : context.l10n.eurobondIsinNotListed,
                  style: context.t.bodySmall?.copyWith(color: context.c.loss),
                ),
              ),
            Expanded(
              child: liste.isEmpty
                  ? _emptySearch(context, _q, cs)
                  : ListView.builder(
                      itemCount: liste.length,
                      itemBuilder: (_, i) {
                        final o = liste[i];
                        return _PickerRow(
                          badgeText: '${o.$1.vade.year}',
                          title: o.$1.ad,
                          subtitle: _altBaslik(o, simdi),
                          isSelected: o.$1.isin == widget.selected,
                          color: renk,
                          cs: cs,
                          onTap: () => widget.onSelect(o),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared picker shell & row widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PickerShell extends StatefulWidget {
  final String title;
  final int count;
  final Color color;
  final TextEditingController searchCtrl;
  final void Function(String) onSearch;
  final String query;
  final ColorScheme cs;
  final Widget child;
  /// Arama kutusunun ipucu; verilmezse genel "Ara…".
  final String? searchHint;

  const _PickerShell({
    required this.title,
    required this.count,
    required this.color,
    required this.searchCtrl,
    required this.onSearch,
    required this.query,
    required this.cs,
    required this.child,
    this.searchHint,
  });

  @override
  State<_PickerShell> createState() => _PickerShellState();
}

// Hisse, fon ve altın seçicilerinin ortak kabuğu.
//
// 2026-09-25 ("liste uygulama ve HIG standartlarına uygun olmalı",
// kullanıcı): kabuk ham `TextStyle(fontSize:)` ve Material `cs.*` tonlarıyla
// yazılmıştı; uygulamanın geri kalanından farklı font boyutu/rengi
// taşıyordu. Artık tipografi `context.t`, renk `context.c`, boşluk
// `SandikSpace` — aynı liste her yerde aynı görünür. HIG: arama alanı 44pt,
// temizle düğmesi 44pt dokunma hedefi, başlık büyük ve kalın.
class _PickerShellState extends State<_PickerShell> {
  @override
  Widget build(BuildContext context) {
    final yatay = SandikSpace.screenH(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, sc) => Column(
        children: [
          // Ortak tutamaç (HIG denetimi 2026-10-10; elle çizilmiş kopyaydı).
          const Padding(
            padding: EdgeInsets.symmetric(vertical: SandikSpace.sm2),
            child: SandikTutamac(),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(yatay, 0, yatay, SandikSpace.smd),
            child: Row(
              children: [
                Flexible(
                  child: Semantics(
                    header: true,
                    child: Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.sm, vertical: SandikSpace.xxs),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                  child: Text('${widget.count}',
                      style: context.t.labelLarge
                          ?.copyWith(color: widget.color.metinTonu(context))),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(yatay, 0, yatay, SandikSpace.smd),
            child: Container(
              constraints: const BoxConstraints(minHeight: SandikTouch.min),
              decoration: BoxDecoration(
                // `background` idi: beyaz alt sayfa üstünde krem kutu
                // (kullanıcı, 2026-09-25). Dolgu artık tema kuralından.
                color: context.inputFill,
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(color: context.c.hairline),
              ),
              child: Row(
                children: [
                  const SizedBox(width: SandikSpace.smd),
                  Icon(Icons.search_rounded,
                      size: 18, color: context.c.text58),
                  const SizedBox(width: SandikSpace.sm),
                  Expanded(
                    child: TextField(
                      controller: widget.searchCtrl,
                      onTapOutside: _klavyeyiKapat,
                      style: context.t.bodyLarge,
                      decoration: InputDecoration(
                        hintText:
                            widget.searchHint ?? context.l10n.searchEllipsis,
                        hintStyle: context.t.bodyLarge
                            ?.copyWith(color: context.c.text36),
                        // Dolgu ve çerçeve dıştaki Container'da. Tema
                        // `filled: true` verir; kapatılmazsa metin alanı
                        // kutunun içinde ikinci bir dolgu dikdörtgeni çizer
                        // (ikonun sağında farklı renk şerit).
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: widget.onSearch,
                    ),
                  ),
                  if (widget.query.isNotEmpty)
                    Semantics(
                      button: true,
                      label: context.l10n.clearSearch,
                      child: SandikBasma(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          widget.searchCtrl.clear();
                          widget.onSearch('');
                        },
                        child: SizedBox.fromSize(
                          size: SandikTouch.minSize,
                          child: Icon(Icons.cancel_rounded,
                              size: 18, color: context.c.text36),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: context.c.hairline),
          // DraggableScrollableSheet klavyeyle küçülmez: sonuç listesinin
          // alt ~300px'i ve ortalanmış "sonuç yok" metni klavyenin altında
          // kalıyordu. Liste klavyenin üstünde biter; sürüklemek klavyeyi
          // kapatır (listelerde `onDrag`). Klavye denetimi 2026-10-08.
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final String badgeText;
  /// Verilirse rozetin yerine logo; yüklenemezse rozet metnine düşer.
  final String? logoUrl;
  final String title;
  final String subtitle;
  final bool isSelected;
  final Color color;
  final ColorScheme cs;
  final VoidCallback onTap;

  /// Verilirse satırın sağında "grafiği gör" düğmesi çıkar ve varlık sayfasını
  /// açar (kullanıcı isteği, 2026-09-28: "varlık ekle kısmında da varlığın
  /// detayını izlemek isteyecekler"). Satırın kendisi SEÇMEYE devam eder —
  /// seçim listesinin HIG sözleşmesi bozulmaz; sayfanın birincil eylemi de
  /// "Bunu seç" olur, akış aynı yere çıkar.
  final VarlikKimligi? kimlik;

  const _PickerRow({
    required this.badgeText,
    this.logoUrl,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.color,
    required this.cs,
    required this.onTap,
    this.kimlik,
  });

  // HIG seçim listesi: seçili satırda onay işareti, diğerlerinde HİÇBİR
  // işaret yok. Eski `chevron_right` "yeni sayfaya gider" demekti (HIG'de
  // ok = disclosure); burada dokunuş seçer ve sayfayı kapatır.
  @override
  Widget build(BuildContext context) {
    final yatay = SandikSpace.screenH(context);
    final rozet = Text(
      badgeText.length > 5 ? badgeText.substring(0, 4) : badgeText,
      maxLines: 1,
      style: context.t.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: isSelected ? color.metinTonu(context) : context.c.text90,
      ),
    );
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: yatay, vertical: SandikSpace.sm2),
          child: Row(
            children: [
              Container(
                width: SandikTouch.min,
                height: SandikTouch.min,
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.16)
                      : context.c.surface2,
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: isSelected
                      ? Border.all(color: color.withValues(alpha: 0.5))
                      : null,
                ),
                alignment: Alignment.center,
                child: logoUrl == null
                    ? rozet
                    : Padding(
                        padding: const EdgeInsets.all(SandikSpace.sm),
                        child: Image.network(
                          logoUrl!,
                          // Logo süs; ekran okuyucu satır başlığını okur.
                          excludeFromSemantics: true,
                          cacheWidth: 96,
                          errorBuilder: (_, __, ___) => rozet,
                        ),
                      ),
              ),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: context.t.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: SandikSpace.xxs),
                      Text(subtitle,
                          style: context.t.bodyMedium
                              ?.copyWith(color: context.c.text58),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (kimlik case final k?)
                IconButton(
                  tooltip: context.l10n.vsOpenDetailSemantics(title),
                  onPressed: () => showVarlikSayfasi(context, k, onSec: onTap),
                  icon: Icon(Icons.insights_rounded,
                      size: 20, color: context.c.text58),
                  constraints: const BoxConstraints(
                      minWidth: SandikTouch.min, minHeight: SandikTouch.min),
                ),
              if (isSelected) ...[
                const SizedBox(width: SandikSpace.sm),
                Icon(Icons.check_rounded,
                    size: 22, color: color.metinTonu(context)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Widget _emptySearch(BuildContext context, String q, ColorScheme cs) => Center(
      child: Padding(
        padding: const EdgeInsets.all(SandikSpace.lg),
        child: Text(
            q.isEmpty ? context.l10n.noResults : context.l10n.noResultsFor(q),
            textAlign: TextAlign.center,
            style: context.t.bodyLarge?.copyWith(color: context.c.text58)),
      ),
    );
