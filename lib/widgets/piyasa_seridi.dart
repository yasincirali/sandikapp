// Ana ekranın üstündeki piyasa şeridi — dolar, euro, gram altın, BIST 100.
//
// Neden var (2026-09-20, günlük giriş turu): Türkiye'de bir finans
// uygulamasına her gün girmenin ezici sebebi "dolar/altın ne oldu"; portföyü
// olmayan günde bile buna bakılır. Şerit o soruyu ana ekranın ilk satırında
// cevaplar; kullanıcı portföyüne bakmaya oradan devam eder.
//
// Fiyat kaynağı sözleşmesi (`services/fiyat_kaynagi.dart`): semboller
// `PriceService.fetchQuotes` üzerinden gelir — kur/altın truncgil'den
// (günlük değişim de AYNI kaynağın `Change` alanından), endeks Yahoo'dan.
// Şerit kendi merdivenini kurmaz; değişim yüzdesi bilinmiyorsa yazılmaz.
//
// Çizim kuralı: dört öğe, tek satır, kaydırılabilir; dokunuş yok — şerit
// bir bilgi satırı, gezinme öğesi değil. Fiyat gelmezse şerit HİÇ çizilmez
// (boş kabuk ana ekranda yer işgal etmez).
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/crash_reporter.dart';
import '../services/price_service.dart';
import '../theme/sandik.dart';
import '../utils/polling.dart';
import '../utils/tr_format.dart';

class PiyasaSeridi extends StatefulWidget {
  const PiyasaSeridi({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  /// Sırası sabit: en çok bakılan en solda.
  static const semboller = <String>[
    'USDTRY=X',
    'EURTRY=X',
    'ALTIN_GRAM',
    'XU100.IS',
  ];

  /// Yenileme aralığı — hero kartla aynı ritim (30 sn), seans dışında da
  /// zararsız (ön planda değilken poller durur).
  static const yenilemeAraligi = Duration(seconds: 30);

  @override
  State<PiyasaSeridi> createState() => _PiyasaSeridiState();
}

class _PiyasaSeridiState extends State<PiyasaSeridi> {
  Map<String, YahooQuote> _kotasyon = const {};
  late final ForegroundPoller _poller = ForegroundPoller(
    interval: PiyasaSeridi.yenilemeAraligi,
    onTick: _yukle,
  );

  @override
  void initState() {
    super.initState();
    _poller.start();
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final q = await PriceService.instance.fetchQuotes(PiyasaSeridi.semboller);
      if (!mounted) return;
      setState(() => _kotasyon = q);
    } catch (e, st) {
      // Şerit ikincil: kaynak düşerse son bilinen değer kalır, yoksa hiç
      // çizilmez. Sessiz kalmasın diye non-fatal raporlanır.
      CrashReporter.report(e, st, reason: 'PiyasaSeridi.yukle');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ogeler = <_Oge>[
      for (final s in PiyasaSeridi.semboller)
        if (_kotasyon[s]?.regularMarketPrice case final f? when f > 0)
          _Oge(
            etiket: switch (s) {
              'USDTRY=X' => l10n.marketDollar,
              'EURTRY=X' => l10n.marketEuro,
              'ALTIN_GRAM' => l10n.marketGold,
              _ => l10n.marketBist,
            },
            // Endeks puan, diğerleri ₺: endekste kuruş anlamsız.
            deger: s == 'XU100.IS' ? fmtNum(f, digits: 0) : fmtNum(f, digits: 2),
            degisimPct: _kotasyon[s]?.regularMarketChangePercent,
          ),
    ];
    if (ogeler.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: widget.padding,
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: ogeler.length,
          separatorBuilder: (_, __) => const SizedBox(width: SandikSpace.sm),
          itemBuilder: (context, i) => ogeler[i],
        ),
      ),
    );
  }
}

class _Oge extends StatelessWidget {
  const _Oge({
    required this.etiket,
    required this.deger,
    required this.degisimPct,
  });

  final String etiket;
  final String deger;
  final double? degisimPct;

  @override
  Widget build(BuildContext context) {
    final d = degisimPct;
    final renk = d == null || d == 0 ? context.c.text58 : context.signColor(d);
    return Semantics(
      label: '$etiket $deger${d == null ? '' : ' ${fmtPct(d)}'}',
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.smd, vertical: SandikSpace.xs),
        decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: context.c.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              etiket,
              style: context.t.labelSmall?.copyWith(
                color: context.c.text58,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: SandikSpace.xs),
            Text(
              deger,
              style: context.t.numSmall.copyWith(
                color: context.c.text90,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (d != null) ...[
              const SizedBox(width: SandikSpace.xs),
              Text(
                '${d > 0 ? '+' : ''}${fmtPct(d)}',
                style: context.t.labelSmall?.copyWith(
                  color: renk,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
