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
// bant durur ve elle kaydırılır.
//
// ## Etkileşim: uzun bas → tut, kaydır, bırak → akış sürer (2026-09-30)
// İlk sürümde dokunuş bandı durdurup sürdüren bir anahtardı ve elle
// kaydırma yalnızca dururken mümkündü: iki adım (dokun, kaydır, yine dokun)
// ve bant durdurulup unutulunca ana sayfa "donmuş" görünüyordu. Kullanıcı
// istedi: dokunuş değil UZUN BASIŞ bandı tutsun, parmak basılıyken sağa
// sola kaydırılsın, bırakınca akmaya devam etsin. Böylece:
//   · durma geçici — parmak kalkınca bant her zaman akar, unutulmuş durak
//     yok;
//   · kısa dokunuş hiçbir şey yapmaz; sayfayı kaydırmak için bandın
//     üstünden geçen parmak bandı yanlışlıkla durdurmaz;
//   · bırakışta parmağın hızı akışa DEVREDİLİR (apple-design §5): bant
//     parmağın hızıyla başlar, üstel olarak sabit akış hızına iner
//     ([PiyasaSeridi.devirSabiti]). Sert geçiş olsaydı hızlı bir fırlatış
//     parmak kalktığı karede "duvara çarpardı".
// Tutuş anında hafif dokunsal tık (`SandikHaptic.selection`): uzun basış
// görsel olarak hiçbir şey değiştirmediği için "yakaladın" bilgisi oradan
// gelir.
//
// ## Boşta durma: kimse bakmazken akmaz (2026-10-01, CPU/GPU raporu)
// Cihaz ölçümü: Ana ekran boşta dururken bant 58 fps çiziyor ve
// emülatörde bir çekirdeğin %64'ünü tutuyordu; Portföy ve Performans
// sekmeleri boşta sıfırdı. Bant tek başına ekranı ve GPU'yu hiç uyutmuyordu
// (`docs/CPU_GPU_VE_BOYUT_RAPORU_2026_10.md`). Karar: bant iki tur
// ([PiyasaSeridi.bostaSuresi]) dokunulmadan aktıktan sonra YAVAŞLAYARAK
// durur ([PiyasaSeridi.durusSabiti] ile üstel; sert durma 36 pt/sn'de bile
// göze batan bir "takılma" olurdu). Kare hızı DÜŞÜRÜLMEDİ: akarken 60 fps
// kalır, kullanıcı kararı "tüm animasyonlar 60 fps pürüzsüz".
// Yeniden akış: şeride herhangi bir dokunuş (parmak iner inmez, jest
// arenası beklenmez), uygulamanın öne gelmesi, Ana sekmesine dönüş
// (`TickerMode`). Yeni fiyat turu bandı UYANDIRMAZ: nabız 30 sn'de bir
// atıyor, boşta süresi 35 sn — fiyat uyandırsaydı seans boyunca hiç
// durmazdı. Fiyat yerinde güncellenir, faz korunur (aşağıdaki bölüm).
//
// ## Akış: yalnızca boyama, her karede yerleşim YOK (2026-09-21)
// İlk sürüm `ListView.builder` + her karede `jumpTo` idi. Bu, kare başına
// scroll makinesinin tamamını çalıştırıyordu: sliver yerleşimi, üç scroll
// bildirimi, viewport'a giren her öğe için yeni metin yerleşimi. Kullanıcı
// bunu "pürüzsüz kaymıyor" diye bildirdi — kalite algısı için kritik.
// Şimdi bant tek bir Row'u BİR KEZ yerleştirir ve her karede yalnızca
// kaydırma fazına göre yeniden BOYAR (`_RenderBant`); kompozitör düzeyinde
// bir öteleme kadar ucuz. Fiyat güncellenince Row yeniden yerleşir, faz
// korunur, akış kesilmez.
//
// ## Veri
// Fiyat kaynağı sözleşmesi (`services/fiyat_kaynagi.dart`): semboller
// `PriceService.fetchQuotes` üzerinden gelir — kur/altın truncgil'den
// (günlük değişim de AYNI kaynağın `Change` alanından), endeks Yahoo'dan.
// Bant kendi merdivenini kurmaz; değişim bilinmiyorsa yazılmaz.
// Yenileme 30 sn (ön planda; hero kartla aynı ritim). Fiyat servisinin
// 45 sn'lik önbelleği ağa fiilen ~45 sn'de bir çıkarır. Fiyat gelmezse bant
// HİÇ çizilmez (boş kabuk yer işgal etmez).
//
// ## Şerit kartı + "Ara" çipi (kullanıcı kararı, 2026-09-28, seçenek C)
// İlk sürüm (2026-09-28 sabahı) başlığa yapışık 30pt çizgili bant ve sağ
// uçta 18pt soluk bir büyüteçti: "sıfır piksel, dikkat çekmez" diye
// seçilmişti. Kullanıcı iki şey istedi: bant başlıktan ayrılsın, arama
// bulunur olsun ama yeni satır açmasın. Dört seçenekten (daire düğme,
// arama satırı, şerit+çip, önce arama) şerit+çip seçildi:
//   · bant 36pt, `surface1` zeminli bir ŞERİT KARTI (köşe `SandikRadius.md`:
//     alttaki kartlarla aynı; `lg` 36pt'te tam hap oluyordu, kullanıcı
//     "kartlarla aynı olsun" dedi) —
//     çizgiler arasında akan metin değil, kendi nesnesi; başlığın 12pt
//     altında (dolgu ana sayfada);
//   · sağ uçta etiketli çip: büyüteç + "Ara", amber ton. İkona kelime
//     eklemek keşfedilebilirliği çözer, yer maliyeti sıfır;
//   · toplam +18pt (12 boşluk + 6 yükseklik); hero kart neredeyse yerinde.
// Yer seçimi gerekçesi aynı: alt çubuk simetrisi bozulmasın, üst çubuğa
// 5. düğme 320pt'de taşar, ayrı arama satırı 52pt çalardı.
// Fiyat gelmese de çip kalır (tek başına tam yuvarlak) — arama fiyata
// bağlı değil.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import '../services/tazelik_ritmi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../l10n/l10n.dart';
import '../services/crash_reporter.dart';
import '../services/price_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

class PiyasaSeridi extends StatefulWidget {
  const PiyasaSeridi({super.key, this.padding = EdgeInsets.zero, this.onAra});

  final EdgeInsets padding;

  /// Verilirse bandın sağ ucunda arama büyüteci çizilir.
  final VoidCallback? onAra;

  /// Sırası sabit: en çok bakılan en solda.
  ///
  /// Altın **24 ayar** gram (`ALTIN_GRAM24`), 22 ayar `ALTIN_GRAM` DEĞİL
  /// (emülatör bulgusu #14, 2026-09-29). Bant "Gram altın 5.974" diyordu —
  /// 22 ayar fiyatı — ama aynı kullanıcının portföyündeki "Gram Altın
  /// (24 Ayar)" 6.568/gr, Özet'teki "Gram altın (24 ayar)" de başka bir
  /// yüzde gösteriyordu. İki seçenek vardı: etiketi "Gram altın (22 ayar)"
  /// yapmak ya da fiyatı 24 ayara çekmek. İkincisi seçildi, çünkü:
  ///   * Bandın sorusu "altın ne oldu"; Türkiye'de bankada ve kuyumcuda
  ///     "gram altın" 24 ayar (995) demektir (`GoldSubCategory.gr24`
  ///     açıklaması). Etiketi değiştirmek başlığı doğru ama İLGİSİZ yapardı.
  ///   * Portföydeki 24 ayar gram ile bant aynı sayıyı gösterir; kullanıcı
  ///     iki sayıyı yan yana koyduğunda şaşırmaz.
  /// `ALTIN_GRAM`'ın 22 ayar kalması ayrı ve bilinçli bir karar (sikke
  /// ailesi 22 ayar kote edilir; bkz. `PriceService._truncgilGoldKeys`);
  /// burada yalnızca bandın HANGİ ürünü gösterdiği değişti.
  static const semboller = <String>[
    'USDTRY=X',
    'EURTRY=X',
    altinSembolu,
    'XU100.IS',
  ];

  /// Banttaki "Gram altın" — 24 ayar (bkz. [semboller]).
  static const altinSembolu = 'ALTIN_GRAM24';

  /// Yenileme aralığı — hero kartla aynı ritim (30 sn), seans dışında da
  /// zararsız (ön planda değilken poller durur).
  static const yenilemeAraligi = TazelikRitmi.yuzey;

  /// Akış hızı (pt/sn). Bir tur (dört öğe ≈ 600pt) ~17 sn sürer: okumaya
  /// yetecek kadar yavaş, "canlı" hissettirecek kadar hızlı.
  static const hiz = 36.0;

  /// Bırakıştan sonra parmak hızının akış hızına inme zaman sabiti (sn).
  /// 0,35 sn: fırlatış ~1 sn içinde akışa karışır — momentum hissedilir ama
  /// bant ekranda "uçup gitmez".
  static const devirSabiti = 0.35;

  /// Devredilen hızın üst sınırı (pt/sn). Sert bir fırlatış bandı
  /// okunamayacak hızda döndürmesin; sınır tur başına ~0,4 sn.
  static const azamiDevirHizi = 1500.0;

  /// Dokunuşsuz akış süresi; dolunca bant yavaşlayıp durur (bkz. dosya başı
  /// "Boşta durma"). İki tur: ilk turda dört değer okunur, ikincisi "canlı"
  /// hissini verir; üçüncü turu kimse izlemez. 30 sn'lik fiyat nabzından
  /// uzun olması bilinçli — nabız bandı uyandırmaz ama zamanlama çakışmasın.
  static const bostaSuresi = Duration(seconds: 35);

  /// Boşta durma yavaşlamasının zaman sabiti (sn). 0,6 sn: bant ~2 sn'de
  /// (≈ 3 zaman sabiti) görünür biçimde durur, "fren" değil "sönme".
  static const durusSabiti = 0.6;

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

  /// Ekran okuyucu ve test için düz metin: "Dolar 48,79 +%0,08".
  ///
  /// Yön [fmtPctIsaretli] ile (2026-09-29): eskiden eksi "%-0,23" diye
  /// sayının içine giriyordu; uygulamanın geri kalanı "−%0,23" yazıyor.
  String get metin =>
      '$etiket $deger${degisimPct == null ? '' : ' ${fmtPctIsaretli(degisimPct!)}'}';
}

class _PiyasaSeridiState extends State<PiyasaSeridi> {
  Map<String, YahooQuote> _kotasyon = const {};

  /// ORTAK NABIZ dinleyicisi — kendi sayacını KURMAZ (2026-09-23).
  ///
  /// Eskiden `ForegroundPoller` ile kendi 30 sn'lik turunu atıyordu. Aynı
  /// ritim yetmiyordu: sayac mount anında kurulduğu için bant, Bugün kartı
  /// ve Performans FARKLI FAZDA tazeleniyordu — bant "USD 48,79" derken
  /// portföy toplamı henüz bir önceki kotasyondan hesaplanmış olabiliyordu
  /// (bkz. `TazelikRitmi.nabiz`).
  ///
  /// Yaşam döngüsü korunur: nabız arka planda durur, öne gelince hemen
  /// bir tur atar — `ForegroundPoller`'ın yaptığının aynısı.
  VoidCallback? _nabziBirak;

  @override
  void initState() {
    super.initState();
    // İlk turu HEMEN at: nabız ilk tick'ini bir aralık sonra atar ve
    // bant o süre boyunca boş kalırdı.
    _yukle();
    _nabziBirak = TazelikRitmi.nabiz.dinle(() {
      // Gizli sekmede kotasyon turu yok (animasyon denetimi 2026-10-01).
      if (!mounted || !TickerMode.getValuesNotifier(context).value.enabled) {
        return;
      }
      _yukle();
    });
  }

  @override
  void dispose() {
    _nabziBirak?.call();
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
              PiyasaSeridi.altinSembolu => l10n.marketGold,
              _ => l10n.marketBist,
            },
            // Endeks puan, diğerleri ₺: endekste kuruş anlamsız.
            deger:
                s == 'XU100.IS' ? fmtNum(f, digits: 0) : fmtNum(f, digits: 2),
            degisimPct: _kotasyon[s]?.regularMarketChangePercent,
          ),
    ];
    final ara = widget.onAra;
    if (ogeler.isEmpty) {
      if (ara == null) return const SizedBox.shrink();
      return Padding(
        padding: widget.padding,
        child: Align(
          alignment: Alignment.centerRight,
          child: PiyasaAramaDugmesi(onTap: ara, cerceveli: false),
        ),
      );
    }

    // Şerit kartı: bant sol yarıyı (köşeleri solda yuvarlak), çip sağ
    // ucu (köşeleri sağda yuvarlak) çizer; ikisi 44pt'lik ortak kutuda
    // ortalanır, görünen şerit 36pt. Kart tek Container olsaydı çipin
    // 44pt dokunma alanı 36pt'lik klibin dışında kalırdı (HIG #37).
    return Padding(
      padding: widget.padding,
      child: Row(
        children: [
          Expanded(child: KayanBant(ogeler: ogeler, sagKose: ara == null)),
          if (ara != null) PiyasaAramaDugmesi(onTap: ara),
        ],
      ),
    );
  }
}

/// Şeridin sağ ucundaki "Ara" çipi.
///
/// Dokunma alanı 44pt (HIG); görünen çip şeritle aynı 36pt, ortalı.
/// Amber ton dolgu (`amberFill`, zemin — `amberText` zemin olamaz), amber
/// metin + büyüteç. [cerceveli] `true` iken şeridin devamıdır: sol kenar
/// ayraç, sağ köşeler yuvarlak. `false` iken (fiyat yok, ortak görünüm)
/// tek başına dört köşesi yuvarlak kart.
class PiyasaAramaDugmesi extends StatelessWidget {
  const PiyasaAramaDugmesi(
      {super.key, required this.onTap, this.cerceveli = true});

  final VoidCallback onTap;
  final bool cerceveli;

  @override
  Widget build(BuildContext context) => SandikTappable(
        onTap: onTap,
        semanticLabel: context.l10n.searchAssetsSemantics,
        child: Container(
          height: SandikTouch.min,
          constraints: const BoxConstraints(minWidth: SandikTouch.min),
          alignment: Alignment.center,
          child: _AramaCipi(cerceveli: cerceveli),
        ),
      );
}

class _AramaCipi extends StatelessWidget {
  const _AramaCipi({required this.cerceveli});
  final bool cerceveli;

  @override
  Widget build(BuildContext context) {
    final cizgi = BorderSide(color: context.c.hairline);
    const kose = Radius.circular(SandikRadius.md);
    return Container(
      height: KayanBant.seritYuksekligi,
      padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md2),
      decoration: BoxDecoration(
        color: context.c.amberFill.withValues(alpha: 0.12),
        borderRadius: cerceveli
            ? const BorderRadius.horizontal(right: kose)
            : const BorderRadius.all(kose),
        border: cerceveli
            ? Border(top: cizgi, right: cizgi, bottom: cizgi, left: cizgi)
            : Border.fromBorderSide(cizgi),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded, size: 16, color: context.c.amberText),
          const SizedBox(width: SandikSpace.xs2),
          Text(
            context.l10n.searchChip,
            style: context.t.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: context.c.amberText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sonsuz kayan bant. Öğeler döngüsel tekrarlanır; uzun basış tutar.
///
/// Öğeler tek bir Row olarak BİR KEZ yerleşir; her karede yalnızca kaydırma
/// fazı değişir ve bant yeniden boyanır (bkz. dosya başı "Akış"). Kayma
/// değeri bir [ValueNotifier]'da yaşar: kare başına `setState` yok, widget
/// ağacı hiç yeniden kurulmaz.
class KayanBant extends StatefulWidget {
  const KayanBant({super.key, required this.ogeler, this.sagKose = true});

  final List<PiyasaOgesi> ogeler;

  /// Sağ köşeler de yuvarlak mı. Yanında "Ara" çipi varken `false`: şerit
  /// çipe düz kenarla bitişir, yuvarlağı çip tamamlar.
  final bool sagKose;

  /// Görünen şerit yüksekliği (pt). 30'dan 36'ya (2026-09-28): köşeli bir
  /// kartın yazıya nefes payı bırakması için; dokunma kutusu yine 44.
  static const double seritYuksekligi = 36;

  @override
  State<KayanBant> createState() => KayanBantState();
}

/// Bant durumu — testler kayma ve akış durumunu buradan okur.
class KayanBantState extends State<KayanBant>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_kare);

  /// Toplam kayma (pt). Bant fazı bunun içerik genişliğine bölümünden
  /// kalanıdır; sınırsız büyür, saatlerce açık kalsa da taşmaz (double).
  final _kaydirma = ValueNotifier<double>(0);

  /// Fazın başladığı andaki kayma — tutuş sonrası akış kaldığı yerden
  /// devam eder, sıçramaz.
  double _taban = 0;

  /// Faz başında devredilen hız (pt/sn). Normal akışta [PiyasaSeridi.hiz];
  /// bırakıştan sonra parmağın hızı; boşta durmaya girerken o anki hız.
  double _baslangicHizi = PiyasaSeridi.hiz;

  /// Fazın yöneldiği hız (pt/sn): akışta [PiyasaSeridi.hiz], boşta durmada 0.
  double _hedefHiz = PiyasaSeridi.hiz;

  /// Fazın ticker zamanındaki başlangıcı. Faz değişimi ticker'ı yeniden
  /// başlatmaz (tik içinde stop/start yok); süre buradan ölçülür.
  Duration _fazT0 = Duration.zero;

  /// Son karedeki anlık hız — dışarıdan uyandırırken (dokunuş, öne geliş)
  /// akış bu hızdan sürer, sıçramaz.
  double _sonHiz = 0;

  /// Bant boşta süresi dolduğu için durdu mu (hareketi azalt ya da tutuş
  /// değil). Test ve teşhis için.
  bool _bostaDurdu = false;

  /// Son bilinen `TickerMode` — gizli sekmeden dönüşü yakalamak için.
  bool _tickerModuAcik = true;

  /// Parmak bandı tutuyor mu (uzun basış sürüyor).
  bool _tutuluyor = false;

  /// Tutuş sırasında parmağın son yatay konumu — kare başına fark.
  double _sonX = 0;

  /// Bant şu an kendiliğinden akıyor mu?
  @visibleForTesting
  bool get akiyor => _ticker.isActive;

  /// Boşta süresi dolduğu için durdu mu — test için.
  @visibleForTesting
  bool get bostaDurdu => _bostaDurdu && !_ticker.isActive;

  /// Parmak bandı tutuyor mu — test için.
  @visibleForTesting
  bool get tutuluyor => _tutuluyor;

  /// Toplam kayma (pt) — test için.
  @visibleForTesting
  double get kaydirma => _kaydirma.value;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hareketi azalt: bant durur, elle kaydırılır (iOS HIG: Motion).
    final dur = MediaQuery.disableAnimationsOf(context);
    if (dur && _ticker.isActive) _ticker.stop();
    // Gizli sekmede ticker susturulur ama `isActive` kalır; sekmeye dönünce
    // ticker'ın saati sıçrar ve boşta süresi dolmuş görünür. Dönüş bir
    // "dokunuş" sayılır: saat sıfırlanır, bant akar.
    final acik = TickerMode.valuesOf(context).enabled;
    final sekmeyeDonus = acik && !_tickerModuAcik;
    _tickerModuAcik = acik;
    if (dur || _tutuluyor) return;
    if (!_ticker.isActive || sekmeyeDonus) _uyandir();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Öne geliş: arka planda kare yoktu, ticker saati sıçradı; boşta
    // durmuşsa da kullanıcı yeni geldi — her iki durumda yeniden akar.
    if (state == AppLifecycleState.resumed) _uyandir();
  }

  /// Dokunuş / öne geliş / sekmeye dönüş: boşta saatini sıfırlar, bant
  /// durmuşsa o anki hızdan (durmuşsa 0'dan yumuşak kalkışla) yeniden akar.
  void _uyandir() {
    if (!mounted || _tutuluyor || MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final v = _ticker.isActive ? _sonHiz : 0.0;
    _ticker.stop();
    _baslat(hiz: v);
  }

  /// Ticker'ı durmuş hâlden başlatır; [hiz] devredilen hız, hedef akış hızı.
  void _baslat({double hiz = PiyasaSeridi.hiz}) {
    _taban = _kaydirma.value;
    _baslangicHizi = hiz;
    _hedefHiz = PiyasaSeridi.hiz;
    _fazT0 = Duration.zero;
    _bostaDurdu = false;
    _ticker.start();
  }

  /// Tik içinde faz değişimi: ticker sürer, saat [simdi]'den ölçülür.
  void _fazaGec(Duration simdi, {required double hiz, required double hedef}) {
    _taban = _kaydirma.value;
    _baslangicHizi = hiz;
    _hedefHiz = hedef;
    _fazT0 = simdi;
  }

  /// Kare: kayma = taban + ∫ v(t) dt, v(t) = hedef + (v₀ − hedef)·e^(−t/τ).
  /// Normal akışta v₀ = hedef = hız ve ifade `taban + hız × t`'ye iner.
  /// Zamana bağlı (kare farkına değil): düşen bir kare bandı yavaşlatmaz,
  /// sonraki kare doğru konuma oturur. Boşta durma aynı formülün hedef = 0
  /// hâli: hız üstel söner, kayma asimptotik yerleşir, ticker durur.
  void _kare(Duration gecen) {
    final hedef = _hedefHiz;
    final tau = hedef == 0 ? PiyasaSeridi.durusSabiti : PiyasaSeridi.devirSabiti;
    final t = (gecen - _fazT0).inMicroseconds / 1e6;
    final sonum = math.exp(-t / tau);
    _sonHiz = hedef + (_baslangicHizi - hedef) * sonum;
    _kaydirma.value =
        _taban + hedef * t + (_baslangicHizi - hedef) * tau * (1 - sonum);
    if (hedef == 0) {
      // Altı zaman sabiti: kalan hız binde üçün altında, göz ayırt etmez.
      if (t >= 6 * tau) {
        _sonHiz = 0;
        _bostaDurdu = true;
        _ticker.stop();
      }
      return;
    }
    if (gecen - _fazT0 >= PiyasaSeridi.bostaSuresi) {
      _fazaGec(gecen, hiz: _sonHiz, hedef: 0);
    }
  }

  /// Uzun basış: bant parmağa yapışır. Akış durur, faz olduğu yerde kalır.
  void _tut(LongPressStartDetails d) {
    _ticker.stop();
    _sonX = d.localPosition.dx;
    setState(() => _tutuluyor = true);
    SandikHaptic.selection.perform();
  }

  /// Tutarken sürükleme 1:1: parmak sola giderse içerik ileri akar; sınır
  /// yok, döngüsel.
  void _tutarkenKaydir(LongPressMoveUpdateDetails d) {
    final x = d.localPosition.dx;
    _kaydirma.value -= x - _sonX;
    _sonX = x;
  }

  /// Bırakış: parmağın hızı akışa devredilir (bkz. dosya başı
  /// "Etkileşim"). Hareketi azalt açıksa bant durur kalır.
  void _birak(LongPressEndDetails d) {
    setState(() => _tutuluyor = false);
    if (MediaQuery.disableAnimationsOf(context)) return;
    final v = (-d.velocity.pixelsPerSecond.dx).clamp(
        -PiyasaSeridi.azamiDevirHizi, PiyasaSeridi.azamiDevirHizi);
    _baslat(hiz: v.toDouble());
  }

  /// Hareketi azalt açıkken bant hiç akmaz; uzun basış beklemeden doğrudan
  /// sürüklenir.
  void _surukle(DragUpdateDetails d) {
    _kaydirma.value -= d.delta.dx;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _kaydirma.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ogeler = widget.ogeler;
    final hareketiAzalt = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: ogeler.map((o) => o.metin).join(', '),
      // Listener, GestureDetector'ın DIŞINDA: parmak iner inmez uyandırır,
      // jest arenasının (uzun basış mı, sayfa kaydırma mı) kararını
      // beklemez. Sayfayı kaydırırken bandın üstünden geçen parmak da
      // bandı uyandırır — kullanıcı ekranda, akış yerinde.
      child: Listener(
        onPointerDown: (_) => _uyandir(),
        child: GestureDetector(
        onLongPressStart: _tut,
        onLongPressMoveUpdate: _tutarkenKaydir,
        onLongPressEnd: _birak,
        onHorizontalDragUpdate: hareketiAzalt ? _surukle : null,
        behavior: HitTestBehavior.opaque,
        // Dokunma alanı 44pt (HIG); görünen şerit 36pt, kutuda ortalı —
        // 4pt'lik dikey tamponlar ana sayfa dolgusuyla birlikte 12pt üst
        // boşluğu verir (seçenek C, 2026-09-28). Önceki sürüm 30pt bandı
        // kutunun üstüne yaslıyordu; şerit kartı artık başlıktan ayrı
        // durduğu için ortalama doğru.
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Container(
            height: KayanBant.seritYuksekligi,
            // Şerit kartı: surface1 zemin, saç teli kenar, sol köşeler
            // yuvarlak; sağ köşeler çip yoksa. Metin kenardan taşmasın
            // diye klip — akan öğe köşeden çıkarken kırpılır.
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.c.surface1,
              borderRadius: widget.sagKose
                  ? BorderRadius.circular(SandikRadius.md)
                  : const BorderRadius.horizontal(
                      left: Radius.circular(SandikRadius.md)),
              border: widget.sagKose
                  ? Border.all(color: context.c.hairline)
                  : Border(
                      left: BorderSide(color: context.c.hairline),
                      top: BorderSide(color: context.c.hairline),
                      bottom: BorderSide(color: context.c.hairline),
                    ),
            ),
            // RepaintBoundary: bant her karede boyanır; sınır olmadan hero
            // kart ve üst çubuk da her karede yeniden boyanırdı (GPU).
            child: RepaintBoundary(
              child: ExcludeSemantics(
                child: _Bant(
                  kaydirma: _kaydirma,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [for (final o in ogeler) _Oge(oge: o)],
                  ),
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Çocuğunu (öğe satırı) sınırsız genişlikte BİR KEZ yerleştirir, her
/// karede kaydırma fazına göre yan yana tekrar boyar.
class _Bant extends SingleChildRenderObjectWidget {
  const _Bant({required this.kaydirma, required Widget child})
      : super(child: child);

  final ValueListenable<double> kaydirma;

  @override
  _RenderBant createRenderObject(BuildContext context) => _RenderBant(kaydirma);

  @override
  void updateRenderObject(BuildContext context, _RenderBant renderObject) {
    renderObject.kaydirma = kaydirma;
  }
}

/// Bant çizicisi.
///
/// Kayma değiştiğinde yalnızca `markNeedsPaint` — yerleşim yok, widget
/// yeniden kurulumu yok. Çocuk viewport'u dolduracak kadar yan yana
/// boyanır (`periyot` = çocuğun genişliği).
///
/// **Değişmez:** çocuk ağacı kendi katmanını açan bir düğüm içermemeli
/// (`RepaintBoundary`, `Opacity`, `ClipPath` gibi). Aynı çocuğu birden çok
/// konumda boyamak ancak katmansız çizimde geçerlidir; katmanlı bir çocuk
/// ikinci konumda bağlı katmanı yeniden eklemeye çalışır. Öğeler düz
/// metindir, bu koşul bugün sağlanıyor — öğe yapısını değiştirirken korun.
class _RenderBant extends RenderBox with RenderObjectWithChildMixin<RenderBox> {
  _RenderBant(this._kaydirma);

  ValueListenable<double> _kaydirma;
  set kaydirma(ValueListenable<double> v) {
    if (identical(v, _kaydirma)) return;
    if (attached) _kaydirma.removeListener(markNeedsPaint);
    _kaydirma = v;
    if (attached) _kaydirma.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _kaydirma.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _kaydirma.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    // Genişlik sınırsız: satır kendi doğal genişliğine yerleşir; bant
    // viewport'u ondan bağımsız doldurur.
    c.layout(
      BoxConstraints(
        minHeight: constraints.minHeight,
        maxHeight: constraints.maxHeight,
      ),
      parentUsesSize: true,
    );
    final w = constraints.hasBoundedWidth ? constraints.maxWidth : c.size.width;
    size = constraints.constrain(Size(w, c.size.height));
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    final periyot = c.size.width;
    if (periyot <= 0 || size.width <= 0) return;
    // Faz 0 ≤ x0 < periyot; ilk kopya −x0'dan başlar, viewport dolana
    // kadar periyot adımıyla tekrar eder. Dart'ta `%` negatif kaymada da
    // pozitif kalan verir (elle sağa kaydırma).
    final x0 = -(_kaydirma.value % periyot);
    context.pushClipRect(needsCompositing, offset, Offset.zero & size,
        (ctx, off) {
      for (var x = x0; x < size.width; x += periyot) {
        ctx.paintChild(c, off + Offset(x, 0));
      }
    });
  }

  // Öğeler etkileşimsiz; dokunuşu üstteki GestureDetector alır.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;
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
