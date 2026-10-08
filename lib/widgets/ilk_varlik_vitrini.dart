import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/asset_categories.dart';
import '../models/ilk_varlik_secimi.dart';
import '../providers/add_asset_form_provider.dart' show dovizOptFor;
import '../services/crash_reporter.dart';
import '../services/price_service.dart';
import '../services/tazelik_ritmi.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'sigan_metin.dart';

/// Boş ana ekranın "Canlı fiyat vitrini" (sadeleştirme 2, bayrak
/// `ilk_varlik_kolay`; kullanıcı seçimi 2026-10-04, seçenek 1).
///
/// ## Neden çiplerin yerine
/// Bölüm A'nın ilk sürümü (kumbara + "Henüz varlık eklenmemiş" + beş çip +
/// "Başka bir tür ekle" + ₺0 toplam kartı) emülatörde "çok amatör" bulundu.
/// Sorun çiplerin kendisi değil, ekranın bir BOŞLUĞU anlatmasıydı: ₺0 yazan
/// kart bozuk, kumbara ikonu dekor. Vitrin aynı soruyu ("ne biriktiriyorsun")
/// canlı fiyatla sorar: kullanıcı daha bir şey eklemeden uygulamanın neyi
/// bildiğini görür ("gram altın şu an ₺6.541"), dokununca form o varlıkla
/// hazır açılır ([IlkVarlikSecimi]; kayıt yolu tek, formun).
///
/// ## Fiyat kaynağı (sözleşme `services/fiyat_kaynagi.dart`)
/// Yeni kaynak YOK: piyasa şeridiyle aynı çağrı (`PriceService.fetchQuotes`)
/// ve aynı ritim (`TazelikRitmi.nabiz`; gizli sekmede tur yok). Sembolü
/// vitrin seçmez — formun kaydedeceği sembolü formun tablolarından okur
/// ([fiyatSembolu]: altında `goldTickerMap`, dövizde `dovizOptFor`). Böylece
/// kutuda görülen fiyat, dokununca formun önizlediği ve kaydettiği fiyatla
/// aynı ürünün fiyatıdır (gram altın = 24 ayar, şeritteki de o). Fiyat
/// bilinmiyorsa sayı YAZILMAZ: yüklenirken sabit kısa çubuk, gelmediyse "—".
///
/// ## Hareket (animasyon kararı, skill `animate` + `emil-design-eng`)
/// Ekran ilk açılışta BİR KEZ görülür — "rare/first-time" kademesi, sevinç
/// bütçesi burada. Üç hareket, üçü de bitip DURUR (boşta kare kapısı,
/// `tool/deploy_emulators.sh` "Ana ekran boşta uyuyor"):
///   1. Giriş: başlık, sonra kutular sırayla — saydamlık + 10pt yukarı
///      kayma, `SandikMotion.enter` (ease-out), dilim `surface` (240 ms),
///      kademe ~40 ms, toplam `surface × 2` (480 ms). Yalnız ilk çizimde
///      (controller State'te; yeniden çizim oynatmaz).
///   2. Fiyat değişimi: yalnız SAYI değişince, yönüne göre aşağı/yukarı kısa
///      kayma ([_KayanFiyat], `state` 180 ms). Nabız 30 sn'de bir; aynı
///      değer gelirse hiç oynamaz — saniyelik gürültü yok.
///   3. "Fiyatlar canlı" noktası: fiyat gelince halka yayılıp söner — ilk
///      gelişte iki, sonraki değişimlerde bir kez (`flow` 560 ms). Sonsuz
///      döngü YOK: Apple'ın uyarısı (yavaş salınım vestibüler tetikleyici)
///      ve boşta kare kapısı aynı yöne çıkıyor.
/// "Hareketi azalt" açıkken üçü de yok: giriş son karede başlar, nabız
/// atmaz, fiyat yerinde değişir (`SandikMotion.of` → `Duration.zero`).
/// Basma geri bildirimi `SandikBasma` (ölçek + solma).
class IlkVarlikVitrini extends ConsumerStatefulWidget {
  const IlkVarlikVitrini({
    super.key,
    required this.onSec,
    required this.onDiger,
    required this.onEkstre,
  });

  /// Kutuya dokunuş — form bu seçimle açılır. Gezinmeyi çağıran yapar;
  /// bileşen rota bilmez, testte rota kurmadan sınanır.
  final ValueChanged<IlkVarlikSecimi> onSec;

  /// "Kripto, emtia, mevduat, BES ve diğerleri" — ön seçimsiz form.
  final VoidCallback onDiger;

  /// "Ekstreden aktar" satırı.
  final VoidCallback onEkstre;

  /// Izgara sırası (2 sütun, soldan sağa): seçilen tasarımdaki sıra.
  static const siralama = <IlkVarlikSecimi>[
    IlkVarlikSecimi.gramAltin,
    IlkVarlikSecimi.dolar,
    IlkVarlikSecimi.euro,
    IlkVarlikSecimi.ceyrekAltin,
    IlkVarlikSecimi.fon,
    IlkVarlikSecimi.hisse,
  ];

  /// Kutunun canlı fiyatının sembolü — formun KAYDEDECEĞİ sembol; fon ve
  /// hisse (varlık seçilmemiş) için `null`.
  static String? fiyatSembolu(IlkVarlikSecimi s) {
    if (s.altinAltTuru case final g?) return goldTickerMap[g.label];
    if (s.dovizEtiketi case final e?) return dovizOptFor(e).ticker;
    return null;
  }

  /// Vitrin açıkken toplam kartı (₺0) çizilmez mi?
  ///
  /// Yalnız kendi defteri boş ve ORTAK YOKKEN (bayrak `ilk_varlik_kolay`
  /// 2026-10-05'te kalktı; vitrin kalıcı). Ortak varsa
  /// kart kalır: görünüm çipi (Ben / ortak / Birlikte) ve kaydırarak geçiş
  /// o kartın üstünde; kartı gizlemek ortağın toplamına giden yolu da
  /// gizlerdi. Tur da aynı kuralı sorar (`onboarding_screen` 'hero' ve
  /// 'vitrin' adımları) — iki kopya olmasın diye burada.
  static bool toplamKartiYerine({
    required bool bosKendi,
    required bool ortakVar,
  }) =>
      bosKendi && !ortakVar;

  @override
  ConsumerState<IlkVarlikVitrini> createState() => _IlkVarlikVitriniState();
}

/// Kotasyon yükleyici — üretimde piyasa şeridiyle aynı çağrı. Testte ve
/// görsel önizlemede sabit fiyat verilsin diye sağlayıcı; ikinci bir fiyat
/// yolu DEĞİL (varsayılanı `PriceService.fetchQuotes`).
typedef VitrinKotasyonYukleyici = Future<Map<String, YahooQuote>> Function(
    List<String> semboller);

final vitrinKotasyonYukleyiciProvider = Provider<VitrinKotasyonYukleyici>(
  (ref) => (semboller) => PriceService.instance.fetchQuotes(semboller),
);

class _IlkVarlikVitriniState extends ConsumerState<IlkVarlikVitrini>
    with TickerProviderStateMixin {
  static final _semboller = <String>[
    for (final s in IlkVarlikVitrini.siralama)
      if (IlkVarlikVitrini.fiyatSembolu(s) case final sembol?) sembol,
  ];

  Map<String, YahooQuote> _kotasyon = const {};

  /// İlk tur bitti mi (başarılı ya da değil)? Bitmeden kutu "yükleniyor"
  /// çubuğunu, bittikten sonra fiyat yoksa "—" gösterir.
  bool _yuklendi = false;
  VoidCallback? _nabziBirak;

  /// Kademeli giriş — tek controller, öğeler dilimlerini [_kademe] ile alır.
  late final AnimationController _giris = AnimationController(
    vsync: this,
    duration: SandikMotion.surface * 2,
  );

  /// "Fiyatlar canlı" halkası.
  late final AnimationController _halka = AnimationController(
    vsync: this,
    duration: SandikMotion.flow,
  );
  bool _girisKuruldu = false;

  @override
  void initState() {
    super.initState();
    _yukle();
    // Şeritle AYNI nabız: kendi sayacını kurmaz, fiyatlar şeritle aynı fazda
    // tazelenir (bkz. `TazelikRitmi.nabiz`).
    _nabziBirak = TazelikRitmi.nabiz.dinle(() {
      if (!mounted || !TickerMode.getValuesNotifier(context).value.enabled) {
        return;
      }
      _yukle();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_girisKuruldu) return;
    _girisKuruldu = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _giris.value = 1;
    } else {
      _giris.forward();
    }
  }

  @override
  void dispose() {
    _nabziBirak?.call();
    _giris.dispose();
    _halka.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final q = await ref.read(vitrinKotasyonYukleyiciProvider)(_semboller);
      if (!mounted) return;
      final ilk = _kotasyon.isEmpty;
      final degisti = _semboller.any(
          (s) => q[s]?.regularMarketPrice != _kotasyon[s]?.regularMarketPrice);
      setState(() {
        _kotasyon = q;
        _yuklendi = true;
      });
      if (degisti && _fiyatVar) {
        CrashReporter.arkaPlan(_nabizAt(ilk ? 2 : 1),
            reason: 'IlkVarlikVitrini.nabiz');
      }
    } catch (e, st) {
      // Vitrin fiyatsız da çalışır (kutular dokunulabilir); sessiz kalmasın.
      CrashReporter.report(e, st, reason: 'IlkVarlikVitrini.yukle');
      if (mounted) setState(() => _yuklendi = true);
    }
  }

  bool get _fiyatVar => _semboller.any((s) => _fiyat(s) != null);

  double? _fiyat(String sembol) {
    final f = _kotasyon[sembol]?.regularMarketPrice;
    return f != null && f > 0 ? f : null;
  }

  Future<void> _nabizAt(int kez) async {
    if (MediaQuery.disableAnimationsOf(context)) return;
    try {
      for (var i = 0; i < kez && mounted; i++) {
        await _halka.forward(from: 0).orCancel;
      }
    } on TickerCanceled {
      // Ekran kapandı ya da yeni nabız eskisini kesti — beklenen.
    }
    if (mounted) _halka.value = 0;
  }

  /// [sira]'daki öğenin giriş dilimi: başlangıç `sira × kademe`, uzunluk
  /// controller'ın yarısı (240 ms). Eğri ease-out — kullanıcının en dikkatli
  /// baktığı ilk anda hareket zaten olmuş olur.
  Widget _kademe(int sira, Widget child) {
    const dilim = 0.5;
    const adim = dilim / 6;
    final bas = (sira * adim).clamp(0.0, 1 - dilim);
    return AnimatedBuilder(
      animation: _giris,
      child: child,
      builder: (context, c) {
        final t = SandikMotion.enter
            .transform(((_giris.value - bas) / dilim).clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * SandikSpace.sm2),
            child: c,
          ),
        );
      },
    );
  }

  String _ad(IlkVarlikSecimi s) {
    final l10n = context.l10n;
    return switch (s) {
      IlkVarlikSecimi.gramAltin => l10n.firstAssetGoldGram,
      IlkVarlikSecimi.ceyrekAltin => l10n.vitrinQuarterGold,
      IlkVarlikSecimi.dolar => l10n.firstAssetUsd,
      IlkVarlikSecimi.euro => l10n.firstAssetEur,
      IlkVarlikSecimi.fon => l10n.assetTypeFund,
      IlkVarlikSecimi.hisse => l10n.assetTypeStock,
    };
  }

  IconData _ikon(IlkVarlikSecimi s) => switch (s) {
        IlkVarlikSecimi.ceyrekAltin => Icons.toll_rounded,
        IlkVarlikSecimi.euro => Icons.euro_rounded,
        _ => s.tur.icon,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kutular = [
      for (final (i, s) in IlkVarlikVitrini.siralama.indexed)
        _kademe(
          1 + i,
          _VitrinKutusu(
            ad: _ad(s),
            ikon: _ikon(s),
            renk: s.tur.color,
            ikonRengi: s.tur.onSurface(context),
            fiyatli: IlkVarlikVitrini.fiyatSembolu(s) != null,
            fiyat: switch (IlkVarlikVitrini.fiyatSembolu(s)) {
              final sembol? => _fiyat(sembol),
              null => null,
            },
            degisim: switch (IlkVarlikVitrini.fiyatSembolu(s)) {
              final sembol? => _kotasyon[sembol]?.regularMarketChangePercent,
              null => null,
            },
            yuklendi: _yuklendi,
            aciklama: switch (s) {
              IlkVarlikSecimi.fon => l10n.vitrinFundHint,
              IlkVarlikSecimi.hisse => l10n.vitrinStockHint,
              _ => null,
            },
            onTap: () => widget.onSec(s),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kademe(0, _baslik(context)),
        const SizedBox(height: SandikSpace.md),
        for (var r = 0; r < kutular.length; r += 2) ...[
          if (r > 0) const SizedBox(height: SandikSpace.sm2),
          // IntrinsicHeight: aynı satırdaki iki kutu eşit boyda — fiyat
          // satırı dar ekranda alta kırılınca komşu kutu kısa kalmasın.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: kutular[r]),
                const SizedBox(width: SandikSpace.sm2),
                Expanded(child: kutular[r + 1]),
              ],
            ),
          ),
        ],
        const SizedBox(height: SandikSpace.xs),
        _kademe(6, _digerBaglantisi(context)),
        const SizedBox(height: SandikSpace.xs),
        _kademe(6, _ekstreSatiri(context)),
      ],
    );
  }

  Widget _baslik(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.vitrinWelcome,
                style: context.t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600, color: context.c.text58),
              ),
            ),
            // Fiyat gelmeden "canlı" demek yanlış olurdu.
            if (_fiyatVar) _CanliEtiketi(halka: _halka),
          ],
        ),
        const SizedBox(height: SandikSpace.xs),
        Text(
          l10n.vitrinTitle,
          style: context.t.headlineLarge
              ?.copyWith(fontWeight: FontWeight.w700, color: context.c.text90),
        ),
        const SizedBox(height: SandikSpace.xs2),
        Text(
          l10n.vitrinHint,
          style: context.t.bodyMedium?.copyWith(color: context.c.text58),
        ),
      ],
    );
  }

  Widget _digerBaglantisi(BuildContext context) {
    final l10n = context.l10n;
    final stil = context.t.bodyMedium
        ?.copyWith(fontWeight: FontWeight.w600, color: context.c.amberText);
    return Semantics(
      button: true,
      label: l10n.vitrinOtherTypes,
      excludeSemantics: true,
      child: SandikBasma(
        onTap: widget.onDiger,
        child: ConstrainedBox(
          // 44pt dokunma yüksekliği (HIG); metin ortada.
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: SiganMetin(
                  [l10n.vitrinOtherTypes, l10n.vitrinOtherTypesShort],
                  style: stil,
                  textAlign: TextAlign.center,
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: context.c.amberText),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ekstreSatiri(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: '${l10n.importFromStatement}. ${l10n.vitrinStatementHint}',
      excludeSemantics: true,
      // Kabuk `SandikCard` (2. tur, 2026-10-08) — piksel aynı: surface2 +
      // saç teli + tema gölgesi, basma geri bildirimi `SandikBasma`.
      child: SandikCard(
        onTap: widget.onEkstre,
        elevated: true,
        shadowed: true,
        padding: const EdgeInsets.all(SandikSpace.smd),
        child: Row(
          children: [
            _IkonKutusu(
              ikon: Icons.content_paste_go_rounded,
              zemin: context.c.amberFill.withValues(alpha: 0.16),
              renk: context.c.amberText,
            ),
            const SizedBox(width: SandikSpace.smd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.importFromStatement,
                    style: context.t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: context.c.text90),
                  ),
                  const SizedBox(height: SandikSpace.xxs),
                  SiganMetin(
                    // Tek satır tercih; 320pt'te kısa yazım, o da
                    // sığmazsa (büyük yazı) iki satıra kırılır.
                    [l10n.vitrinStatementHint, l10n.vitrinStatementHintShort],
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58),
                  ),
                ],
              ),
            ),
            const SizedBox(width: SandikSpace.xs),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: context.c.text36),
          ],
        ),
      ),
    );
  }
}

/// Türün renginde yumuşak zeminli 32pt ikon kutusu.
class _IkonKutusu extends StatelessWidget {
  const _IkonKutusu(
      {required this.ikon, required this.zemin, required this.renk});

  final IconData ikon;
  final Color zemin;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: SandikSpace.xl,
      height: SandikSpace.xl,
      decoration: BoxDecoration(color: zemin, borderRadius: SandikRadius.smAll),
      child: Icon(ikon, size: 18, color: renk),
    );
  }
}

class _VitrinKutusu extends StatelessWidget {
  const _VitrinKutusu({
    required this.ad,
    required this.ikon,
    required this.renk,
    required this.ikonRengi,
    required this.fiyatli,
    required this.fiyat,
    required this.degisim,
    required this.yuklendi,
    required this.aciklama,
    required this.onTap,
  });

  final String ad;
  final IconData ikon;

  /// Tür rengi — DOLGU için (düşük alfa).
  final Color renk;

  /// Tür rengi — ikon olarak, açık temada okunur tonu (`onSurface`).
  final Color ikonRengi;

  /// Kutu canlı fiyat gösterir mi (altın/döviz)? Değilse [aciklama].
  final bool fiyatli;
  final double? fiyat;
  final double? degisim;
  final bool yuklendi;
  final String? aciklama;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final f = fiyat;
    final d = degisim;
    final fiyatMetni = f == null ? null : fmtTRYFiyat(f);
    final degisimMetni = d == null ? null : fmtPctIsaretli(d);
    final etiket = [
      ad,
      if (fiyatli) fiyatMetni ?? l10n.vitrinPriceUnknown,
      if (fiyatli && degisimMetni != null) degisimMetni,
      if (aciklama != null) aciklama!,
    ].join(', ');

    return Semantics(
      button: true,
      label: etiket,
      hint: l10n.vitrinTapToAdd,
      excludeSemantics: true,
      // Kabuk `SandikCard` (2. tur, 2026-10-08) — piksel aynı; 112pt alt
      // sınır kartın dışından verilir (eski `Container.constraints`).
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 112),
        child: SandikCard(
          onTap: onTap,
          elevated: true,
          shadowed: true,
          padding: const EdgeInsets.all(SandikSpace.smd),
          // Üstten akar (spaceBetween DEĞİL): dar ekranda bir kutunun
          // fiyat satırı alta kırılırsa komşu kutuların adları yine aynı
          // hizada kalır; artan boy kutunun altında boşluk olur.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IkonKutusu(
                    ikon: ikon,
                    zemin: renk.withValues(alpha: 0.16),
                    renk: ikonRengi,
                  ),
                  const Spacer(),
                  // "+" — kutunun EKLEME yolu olduğunu söyler; fiyat
                  // kartı gibi okunup "ayrıntı açar" sanılmasın.
                  Icon(Icons.add_rounded, size: 20, color: context.c.text36),
                ],
              ),
              const SizedBox(height: SandikSpace.smd),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ad,
                    style: context.t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: context.c.text90),
                  ),
                  const SizedBox(height: SandikSpace.xxs),
                  if (fiyatli)
                    _fiyatSatiri(context, fiyatMetni, d)
                  else
                    Text(
                      aciklama ?? '',
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fiyatSatiri(BuildContext context, String? fiyatMetni, double? d) {
    if (fiyatMetni == null) {
      // Uydurma sayı yok (fiyat sözleşmesi madde 3): yüklenirken sabit kısa
      // çubuk — nabız atan iskelet DEĞİL, fiyat hiç gelmezse sonsuza dek
      // kare çizerdi; gelmediyse "—".
      if (!yuklendi) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
          child: Container(
            width: SandikSpace.xxl + SandikSpace.md,
            height: SandikSpace.sm2,
            decoration: BoxDecoration(
              color: context.c.hairline,
              borderRadius: SandikRadius.smAll,
            ),
          ),
        );
      }
      return Text('—',
          style: context.t.numSmall.copyWith(color: context.c.text36));
    }
    final renk = d == null || d == 0 ? context.c.text58 : context.signColor(d);
    return Wrap(
      spacing: SandikSpace.xs2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _KayanFiyat(
          metin: fiyatMetni,
          yukari: (d ?? 0) >= 0,
          style: context.t.numSmall.copyWith(color: context.c.text90),
        ),
        if (d != null)
          // Şeritle aynı dil: ▲/▼ + mutlak yüzde.
          Text(
            '${d > 0 ? '▲' : (d < 0 ? '▼' : '')} ${fmtPct(d.abs())}'.trim(),
            style: context.t.labelMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: renk),
          ),
      ],
    );
  }
}

/// Fiyat metni değişince eskisi kayarak çıkar, yenisi yönünden girer.
///
/// Yalnız METİN değişince oynar (anahtar metnin kendisi): 30 sn'lik nabız
/// aynı değeri getirirse hiçbir şey kıpırdamaz. Kayma 6pt — "sayı döndü"
/// hissi, dikkat çeken bir sıçrama değil.
class _KayanFiyat extends StatelessWidget {
  const _KayanFiyat(
      {required this.metin, required this.yukari, required this.style});

  final String metin;
  final bool yukari;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: SandikMotion.stateOf(context),
      switchInCurve: SandikMotion.enter,
      switchOutCurve: SandikMotion.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, anim) {
        final giren = child.key == ValueKey(metin);
        // Yükselişte yeni sayı aşağıdan gelir (yukarı iter), düşüşte üstten.
        final yon = (yukari ? 1.0 : -1.0) * (giren ? 1 : -1);
        return AnimatedBuilder(
          animation: anim,
          child: child,
          builder: (_, c) => Opacity(
            opacity: anim.value,
            child: Transform.translate(
              offset: Offset(0, (1 - anim.value) * SandikSpace.xs2 * yon),
              child: c,
            ),
          ),
        );
      },
      child: Text(metin, key: ValueKey(metin), style: style),
    );
  }
}

/// Nabız atan yeşil nokta + "Fiyatlar canlı".
class _CanliEtiketi extends StatelessWidget {
  const _CanliEtiketi({required this.halka});

  final Animation<double> halka;

  @override
  Widget build(BuildContext context) {
    final renk = context.c.gain;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: SandikSpace.smd,
          height: SandikSpace.smd,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Halka: noktadan yayılıp söner; controller durunca 0'da
              // (görünmez) kalır — boşta kare yok.
              AnimatedBuilder(
                animation: halka,
                builder: (_, __) {
                  final t = SandikMotion.glide.transform(halka.value);
                  if (t == 0) return const SizedBox.shrink();
                  return Transform.scale(
                    scale: 1 + t * 1.6,
                    child: Container(
                      width: SandikSpace.sm,
                      height: SandikSpace.sm,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: renk.withValues(alpha: 0.6 * (1 - t))),
                      ),
                    ),
                  );
                },
              ),
              Container(
                width: SandikSpace.sm,
                height: SandikSpace.sm,
                decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
              ),
            ],
          ),
        ),
        const SizedBox(width: SandikSpace.xs2),
        Text(
          context.l10n.vitrinLive,
          style: context.t.bodySmall
              ?.copyWith(fontWeight: FontWeight.w600, color: context.c.text58),
        ),
      ],
    );
  }
}
