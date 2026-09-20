// Ana ekranın üstündeki piyasa bandı — dolar, euro, gram altın, BIST 100.
//
// Neden var (2026-09-20, günlük giriş turu): Türkiye'de bir finans
// uygulamasına her gün girmenin ezici sebebi "dolar/altın ne oldu"; portföyü
// olmayan günde bile buna bakılır. Bant o soruyu ana ekranın ilk satırında
// cevaplar; kullanıcı portföyüne bakmaya oradan devam eder.
//
// ## Biçim: kayan bant (kullanıcı kararı, 2026-09-20)
// Dört seçenek arasından (çip sırası, sparkline kartları, kayan bant, 2×2
// kart) aracı kurum bandı seçildi: en az yer (30pt), "canlı piyasa" hissi
// en güçlü. Dört değer sabit ve sıralı olduğu için erişilebilirlik sorunu
// yok: ekran okuyucu bandı TEK cümle olarak okur, "hareketi azalt" açıkken
// bant durur ve elle kaydırılır, dokunuş durdurur/sürdürür.
//
// ## Veri
// Fiyat kaynağı sözleşmesi (`services/fiyat_kaynagi.dart`): semboller
// `PriceService.fetchQuotes` üzerinden gelir — kur/altın truncgil'den
// (günlük değişim de AYNI kaynağın `Change` alanından), endeks Yahoo'dan.
// Bant kendi merdivenini kurmaz; değişim bilinmiyorsa yazılmaz.
// Yenileme 30 sn (ön planda; hero kartla aynı ritim). Fiyat servisinin
// 45 sn'lik önbelleği ağa fiilen ~45 sn'de bir çıkarır. Fiyat gelmezse bant
// HİÇ çizilmez (boş kabuk yer işgal etmez).
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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

  /// Akış hızı (pt/sn). Bir tur (dört öğe ≈ 600pt) ~17 sn sürer: okumaya
  /// yetecek kadar yavaş, "canlı" hissettirecek kadar hızlı.
  static const hiz = 36.0;

  @override
  State<PiyasaSeridi> createState() => _PiyasaSeridiState();
}

/// Banttaki tek öğe — çizimden bağımsız veri.
class PiyasaOgesi {
  const PiyasaOgesi({
    required this.etiket,
    required this.deger,
    required this.degisimPct,
  });

  final String etiket;
  final String deger;
  final double? degisimPct;

  /// Ekran okuyucu ve test için düz metin: "Dolar 48,79 artı %0,08".
  String get metin =>
      '$etiket $deger${degisimPct == null ? '' : ' ${degisimPct! >= 0 ? '+' : ''}${fmtPct(degisimPct!)}'}';
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
      // Bant ikincil: kaynak düşerse son bilinen değer kalır, yoksa hiç
      // çizilmez. Sessiz kalmasın diye non-fatal raporlanır.
      CrashReporter.report(e, st, reason: 'PiyasaSeridi.yukle');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ogeler = <PiyasaOgesi>[
      for (final s in PiyasaSeridi.semboller)
        if (_kotasyon[s]?.regularMarketPrice case final f? when f > 0)
          PiyasaOgesi(
            etiket: switch (s) {
              'USDTRY=X' => l10n.marketDollar,
              'EURTRY=X' => l10n.marketEuro,
              'ALTIN_GRAM' => l10n.marketGold,
              _ => l10n.marketBist,
            },
            // Endeks puan, diğerleri ₺: endekste kuruş anlamsız.
            deger:
                s == 'XU100.IS' ? fmtNum(f, digits: 0) : fmtNum(f, digits: 2),
            degisimPct: _kotasyon[s]?.regularMarketChangePercent,
          ),
    ];
    if (ogeler.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: widget.padding,
      child: KayanBant(ogeler: ogeler),
    );
  }
}

/// Sonsuz kayan bant. Öğeler döngüsel tekrarlanır; dokunuş durdurur.
///
/// Ölçüm gerektirmez: `ListView.builder` sınırsız öğeyle döner, ticker her
/// karede kaydırma konumunu ilerletir. Fiyat güncellenince öğeler yerinde
/// değişir, akış kesilmez.
class KayanBant extends StatefulWidget {
  const KayanBant({super.key, required this.ogeler});

  final List<PiyasaOgesi> ogeler;

  @override
  State<KayanBant> createState() => _KayanBantState();
}

class _KayanBantState extends State<KayanBant>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final Ticker _ticker = createTicker(_kare);
  Duration _onceki = Duration.zero;
  bool _duraklatildi = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hareketi azalt: bant durur, elle kaydırılır (iOS HIG: Motion).
    final dur = MediaQuery.disableAnimationsOf(context);
    if (dur && _ticker.isActive) _ticker.stop();
    if (!dur && !_ticker.isActive && !_duraklatildi) _baslat();
  }

  void _baslat() {
    _onceki = Duration.zero;
    _ticker.start();
  }

  void _kare(Duration gecen) {
    if (!_scroll.hasClients) return;
    final dt = (gecen - _onceki).inMicroseconds / 1e6;
    _onceki = gecen;
    // Kare süresi sıçrarsa (arka plandan dönüş) tek adımda uzağa atlama.
    if (dt <= 0 || dt > 0.25) return;
    _scroll.jumpTo(_scroll.offset + PiyasaSeridi.hiz * dt);
  }

  void _dokunus() {
    setState(() => _duraklatildi = !_duraklatildi);
    if (_duraklatildi) {
      _ticker.stop();
    } else if (!MediaQuery.disableAnimationsOf(context)) {
      _baslat();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ogeler = widget.ogeler;
    final akiyor = _ticker.isActive;
    return Semantics(
      label: ogeler.map((o) => o.metin).join(', '),
      button: true,
      child: GestureDetector(
        onTap: _dokunus,
        behavior: HitTestBehavior.opaque,
        // Dokunma alanı 44pt (HIG); görünen bant 30pt, dikey 7pt'lik
        // tampon ana ekranın satır boşluğunu doldurur — ek yer yok.
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Container(
            height: 30,
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: context.c.hairline),
              ),
            ),
            child: ExcludeSemantics(
              child: ListView.builder(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                // Akarken parmakla kaydırma yok (ticker ile çatışır); durunca
                // ve hareketi azaltta serbest.
                physics: akiyor
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                itemBuilder: (context, i) =>
                    _Oge(oge: ogeler[i % ogeler.length]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Oge extends StatelessWidget {
  const _Oge({required this.oge});

  final PiyasaOgesi oge;

  @override
  Widget build(BuildContext context) {
    final d = oge.degisimPct;
    final renk = d == null || d == 0 ? context.c.text58 : context.signColor(d);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            oge.etiket,
            style: context.t.labelSmall?.copyWith(
              color: context.c.text58,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: SandikSpace.xs),
          Text(
            oge.deger,
            style: context.t.numSmall.copyWith(
              color: context.c.text90,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (d != null) ...[
            const SizedBox(width: SandikSpace.xs),
            Text(
              '${d > 0 ? '▲' : (d < 0 ? '▼' : '')} ${fmtPct(d.abs())}',
              style: context.t.labelSmall?.copyWith(
                color: renk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(width: SandikSpace.md2),
          Text('·',
              style: context.t.labelSmall?.copyWith(color: context.c.text36)),
        ],
      ),
    );
  }
}
