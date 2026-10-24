import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../models/asset.dart';
import '../models/eurobond.dart' show eurobondOneki;
import '../models/position.dart' show aggregatePositions;
import '../models/price_alert.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart' show priceAlertLimitProvider;
import '../providers/price_alert_provider.dart';
import '../services/analytics_service.dart';
import '../services/crash_reporter.dart';
import '../services/review_prompt_service.dart';
import '../theme/sandik.dart';
import 'bildirim_izni_uyarisi.dart';
import 'review_prompt_sheet.dart';
import 'sandik_async_button.dart';
import 'sinir_uyarisi.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../l10n/l10n.dart';

/// Alarm kurulabilecek bir sembol: fiyat kaynağının kodu + kullanıcı adı +
/// bilinen güncel fiyat (0 = bilinmiyor).
class AlarmAdayi {
  final String sembol;
  final String ad;
  final double guncelFiyat;

  /// Kullanıcının bu sembolde açık pozisyonunun ortalama alış fiyatı
  /// ([alarmMaliyeti]); takip listesinden ya da ortağın varlığından gelen
  /// adayda `null`. Verilirse sheet "maliyetine göre" çiplerini gösterir.
  final double? maliyet;
  const AlarmAdayi(this.sembol, this.ad, this.guncelFiyat, {this.maliyet});
}

/// Alarm için maliyet: [lots] (kullanıcının KENDİ, bu sembolün lot'ları)
/// içindeki açık pozisyonların miktar ağırlıklı ortalama alış fiyatı.
///
/// Neden (2026-10-23, Ar-Ge): yatırımcının asıl sorusu "güncelin %5
/// altı" değil "maliyetime inerse / maliyetimin %20 üstüne çıkarsa".
/// Rakamı kendisi hesaplamak zorundaydı.
///
/// Uydurma yok: maliyeti bilinmeyen bir lot (`maliyetBilinmiyor`, 0162)
/// ya da farklı para birimli iki pozisyon varsa `null` (çip görünmez).
/// Birim fiyatla aynıdır: alış ve güncel fiyat varlığın kendi para
/// biriminde tutulur (kâr/zarar da bu iki sayıdan hesaplanır).
double? alarmMaliyeti(Iterable<Asset> lots) {
  final pozisyonlar = aggregatePositions(lots.toList());
  if (pozisyonlar.isEmpty) return null;
  final para = pozisyonlar.first.representative.currency;
  var miktar = 0.0, tutar = 0.0;
  for (final p in pozisyonlar) {
    if (p.representative.currency != para) return null;
    if (p.lots.any((l) => l.isBuy && l.maliyetBilinmiyor == true)) return null;
    if (p.totalQuantity <= 0 || p.weightedPurchasePrice <= 0) return null;
    miktar += p.totalQuantity;
    tutar += p.totalQuantity * p.weightedPurchasePrice;
  }
  return miktar > 0 ? tutar / miktar : null;
}

/// Maliyet çiplerinin hedefleri: başa baş, +%20, −%10 (sırayla). Güncel
/// fiyata eşit düşen hedef elenir: alarm hemen çalışırdı
/// ([alarmHedefiGuncelFiyatta]).
List<({int yuzde, double hedef})> maliyetHedefleri(
    double maliyet, double guncel) => [
      for (final y in const [0, 20, -10])
        if (!alarmHedefiGuncelFiyatta(maliyet * (1 + y / 100), guncel))
          (yuzde: y, hedef: maliyet * (1 + y / 100)),
    ];

/// Sheet'in döndürdüğü seçim.
class AlarmKurulumu {
  final AlarmAdayi aday;
  final double hedef;
  final String yon;
  const AlarmKurulumu(this.aday, this.hedef, this.yon);
}

/// Fiyat kaynağının anladığı sembol.
///
/// Altında alt kategori (ALTIN_GRAM…) sembolün kendisidir; hissede ticker.
/// Manuel fiyatlı ya da kodu olmayan varlık alarm kuramaz — sunucu onun
/// fiyatını çekemez ve alarm hiç çalışmazdı.
///
/// **Eurobond alarm kuramaz (seri denetimi, 2026-10-08).** Kural yalnız
/// ekleme formundaydı (`add_asset_screen`, "Eurobond alarmı yok"); varlık
/// ekranının zili ve Fiyat Alarmları adayları aynı sembolü bu fonksiyondan
/// aldığı için tahvilde zil görünüyor ve kurulan alarm hiç tetiklenmiyordu
/// (o tarihteki sunucu `EUROBOND:` sembolünü Yahoo'ya soruyordu; fiyat
/// birim değerdir, kirli/100 — kullanıcının "hedef fiyat" diye yazacağı
/// temiz % ile aynı ölçek değil). Sunucu artık tahvili fiyatlayabiliyor
/// (`live_prices.ts` › eurobond kovası) ama alarm ölçek sorusu çözülene
/// dek KAPALI kalır. Kapı tek yerde: her çağıran `null`'u "alarm yok"
/// diye okur.
String? alarmSembolu(String ticker, String? subCategory) {
  final sub = subCategory?.trim() ?? '';
  if (sub.startsWith('ALTIN_')) return sub;
  final t = ticker.trim();
  if (t.toUpperCase().startsWith(eurobondOneki)) return null;
  return t.isEmpty ? null : t;
}

/// Hedef, kullanıcının GÖRDÜĞÜ güncel fiyata eşit mi.
///
/// Yön güncel fiyattan türetildiği için "yönüne göre zaten geçmiş" hedef
/// kurulamaz; kalan tek boş alarm EŞİT hedeftir: sunucu `price >= target`
/// ile tetikler (`check-price-alerts` `isTriggered`), yani alarm ilk
/// kontrolde, fiyat hiç kıpırdamadan çalışır (emülatör testi #24,
/// 2026-09-29: TUPRS 383,25'e 383,25 hedef kabul edildi). Karşılaştırma
/// ekrandaki hassasiyette ([fmtTRYFiyat]) yapılır: kullanıcının "aynı"
/// gördüğü iki sayı aynı sayılır, ham çiftin son hanesi değil. Fiyat
/// bilinmiyorsa (0) karar verilemez → `false`.
bool alarmHedefiGuncelFiyatta(double hedef, double guncelFiyat) =>
    guncelFiyat > 0 && fmtTRYFiyat(hedef) == fmtTRYFiyat(guncelFiyat);

/// Alarm kurma akışı — limit denetimi, sheet, sunucuya yazma, geri bildirim.
///
/// 2026-09-14: bu akış yalnızca Fiyat Alarmları ekranındaydı; alarm artık
/// varlık ekranındaki zilden de kurulur. [sabit] verilirse sheet sembol
/// seçtirmez (varlık ekranı: "bu varlık için"); [adaylar] verilirse liste
/// sunar (alarmlar ekranı). Başarıda kurulan alarm döner, iptalde `null`.
Future<PriceAlert?> alarmKurAkisi(
  BuildContext context,
  WidgetRef ref, {
  AlarmAdayi? sabit,
  List<AlarmAdayi> adaylar = const [],
  double? baslangicHedef,
}) async {
  if (DemoModu.yazmaKapisi('alarm')) return null; // Demo: alarm hesap ister (F1).
  final liste = sabit != null ? [sabit] : adaylar;
  if (liste.isEmpty) {
    sandikSnack(context, context.l10n.addAssetFirst,
        kind: SandikSnackKind.warning);
    return null;
  }

  if (alarmSiniriDoluysaUyar(context, ref)) return null;

  // Sunucuya yazma sayfanın "Alarm kur" düğmesinin İÇİNDE koşar (tek
  // yükleniyor davranışı, 2026-10-08): eskiden sayfa kapanıyor, `create`
  // ardından göstergesiz sürüyordu. Sayfa yalnızca kayıt başarılıysa
  // kapanır; hata olursa açık kalır, girilen hedef kaybolmaz ve hata alanın
  // altında (eski snackbar'ın önekiyle) yazar.
  PriceAlert? kayit;
  final sonuc = await showSandikSheet<AlarmKurulumu>(
    context: context,
    backgroundColor: context.c.surface1,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => AlarmKurSheet(
      adaylar: liste,
      sabit: sabit != null,
      baslangicHedef: baslangicHedef,
      kur: (k) async {
        final me = ref.read(authProvider).valueOrNull;
        if (me == null) return;
        kayit = await ref.read(priceAlertsProvider.notifier).create(PriceAlert(
          id: '',
          userId: me.id,
          symbol: k.aday.sembol,
          label: k.aday.ad,
          targetPrice: k.hedef,
          direction: k.yon,
          enabled: true,
          createdAt: DateTime.now(),
        ));
      },
    ),
  );
  final kurulan = kayit;
  if (sonuc == null || kurulan == null) return null;
  unawaited(AnalyticsService.instance
      .logScreenView(screenName: 'price_alert_created'));
  if (context.mounted) {
    sandikSnack(
      context,
      sonuc.yon == 'above'
          ? context.l10n.alertSetAbove(sonuc.aday.ad, fmtTRYFiyat(sonuc.hedef))
          : context.l10n.alertSetBelow(sonuc.aday.ad, fmtTRYFiyat(sonuc.hedef)),
      kind: SandikSnackKind.success,
    );
    // Alarm kuruldu — kullanıcı istediğini yaptı. İstem beklenmez:
    // çağıran (varlık ekranı zili) sonucu hemen alsın.
    // Hata yutulmaz: Crashlytics'e gider (arka_plan_hata_yutma_test).
    CrashReporter.arkaPlan(
        ReviewPromptSheet.belkiGoster(context, ReviewAni.alarmKuruldu),
        reason: 'alarmKur.degerlendirmeIstemi');
  }
  return kurulan;
}

/// Aynı eşikle yeniden kurulan alarm ilk kontrolde çalar mı: fiyat eşiğin
/// hâlâ ötesinde (sunucu `price >= target` / `<=`). Fiyat bilinmiyorsa
/// (0) `false`.
bool alarmHemenCalarMi(PriceAlert alarm, double guncelFiyat) =>
    guncelFiyat > 0 &&
    (alarm.isAbove
        ? guncelFiyat >= alarm.targetPrice
        : guncelFiyat <= alarm.targetPrice);

/// Çalmış alarmı yeniden kurar (Ar-Ge 21 Eki 12:45 #2; yasin "şerh
/// düştüklerim dışında yap", 2026-10-21).
///
/// Alarm bildirimine dokunmak varlık ekranını açar; çalmış alarm orada
/// şeritte durur ve tek dokunuşla yeniden kurulur. İki eksik vardı (müşteri
/// raporu 21 Eki 13:15):
/// - Fiyat eşiğin hâlâ ötesindeyse aynı eşikle kurulan alarm ilk kontrolde
///   yeniden çalar. Bu durumda eşik ÖN DOLU ve düzenlenebilir sayfa açılır;
///   yeni alarm kurulunca çalmış olanı silinir (liste ikilenmesin).
/// - Kurulunca hiçbir şey olmuyordu: artık titreşim + onay satırı.
///
/// Güncel fiyat bilinmiyorsa (0) karar verilemez: eski davranış (doğrudan
/// yeniden kur).
Future<void> alarmiYenidenKur(
  BuildContext context,
  WidgetRef ref,
  PriceAlert alarm, {
  required AlarmAdayi aday,
}) async {
  final hemenCalar = alarmHemenCalarMi(alarm, aday.guncelFiyat);
  final n = ref.read(priceAlertsProvider.notifier);
  try {
    if (hemenCalar) {
      final yeni = await alarmKurAkisi(context, ref,
          sabit: aday, baslangicHedef: alarm.targetPrice);
      if (yeni != null) await n.delete(alarm.id);
      return;
    }
    if (alarmSiniriDoluysaUyar(context, ref)) return;
    await n.rearm(alarm.id);
    SandikHaptic.selection.perform();
    if (!context.mounted) return;
    final fiyat = fmtTRYFiyat(alarm.targetPrice);
    sandikSnack(
      context,
      alarm.isAbove
          ? context.l10n.alertSetAbove(aday.ad, fiyat)
          : context.l10n.alertSetBelow(aday.ad, fiyat),
      kind: SandikSnackKind.success,
    );
  } catch (e) {
    if (context.mounted) showAppError(context, e);
  }
}

/// Hedef fiyat girişi. Yön SEÇTİRİLMEZ, güncel fiyata göre türetilir ve
/// kaydetmeden önce GÖSTERİLİR (kullanıcı ne kurduğunu görsün).
class AlarmKurSheet extends StatefulWidget {
  final List<AlarmAdayi> adaylar;

  /// `true` → tek aday, seçici çizilmez; başlıkta varlığın adı yazar.
  final bool sabit;

  /// Verilirse "Alarm kur" düğmesi bu yazmayı bekler (düğmede gösterge);
  /// başarıda sayfa kurulumla kapanır, hata olursa açık kalır. `null` →
  /// sayfa kurulumu hemen döndürür (widget testleri).
  final Future<void> Function(AlarmKurulumu kurulum)? kur;

  /// Alanın ön değeri: çalmış alarmı yeniden kurarken eski eşik
  /// ([alarmiYenidenKur]); kullanıcı değiştirebilir.
  final double? baslangicHedef;
  const AlarmKurSheet(
      {super.key,
      required this.adaylar,
      this.sabit = false,
      this.kur,
      this.baslangicHedef});

  @override
  State<AlarmKurSheet> createState() => _AlarmKurSheetState();
}

class _AlarmKurSheetState extends State<AlarmKurSheet> {
  late AlarmAdayi _secili = widget.adaylar.first;
  final _controller = TextEditingController();
  String? _hata;

  /// Hızlı hedefler: güncel fiyatın ±%'si. Kullanıcı çoğu zaman "biraz
  /// yükselince / düşünce" der, rakam hesaplamak istemez.
  static const _hizliYuzdeler = [-10, -5, 5, 10];

  @override
  void initState() {
    super.initState();
    final h = widget.baslangicHedef;
    if (h != null && h > 0) {
      _controller.text = h >= 1 ? fmtNum(h, digits: 2) : fmtInputTr(h);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _hedef {
    final v = parseTrNumber(_controller.text);
    return (v == null || v <= 0) ? null : v;
  }

  void _hizli(int yuzde) => _hedefYaz(_secili.guncelFiyat * (1 + yuzde / 100));

  void _hedefYaz(double f) {
    // 1 ₺ altı (SHIB) 2 haneye yuvarlanınca hedef 0 olurdu.
    _controller.text = f >= 1 ? fmtNum(f, digits: 2) : fmtInputTr(f);
    setState(() => _hata = null);
  }

  /// Hızlı hedef çipi — güncel ve maliyet satırının ortak kabuğu.
  Widget _cip({
    required String metin,
    required String semantik,
    required Color renk,
    required VoidCallback onTap,
  }) {
    final c = context.c;
    return Semantics(
      button: true,
      label: semantik,
      excludeSemantics: true,
      child: SandikTappable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(SandikRadius.sm),
            border: Border.all(color: c.hairline),
          ),
          child: Text(
            metin,
            style: context.t.labelLarge?.copyWith(
              color: renk,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _kaydet() async {
    final hedef = _hedef;
    if (hedef == null) {
      setState(() => _hata = context.l10n.enterValidPrice);
      return;
    }
    // Girdi kuralı istemcide, basmadan ÖNCE de görünür (aşağıdaki uyarı
    // satırı); burada yalnız kaydı durdurur.
    if (alarmHedefiGuncelFiyatta(hedef, _secili.guncelFiyat)) {
      setState(() => _hata = context.l10n.alertTargetAtCurrent);
      return;
    }
    // Yön otomatik: güncel fiyatın üstündeki hedef "yükselince", altındaki
    // "düşünce" demektir. Kullanıcıya ayrıca sormak, yanlış seçimde alarmın
    // hiç çalışmaması ve sebebinin anlaşılmaması riskini getirirdi.
    final yon = PriceAlert.suggestDirection(
      currentPrice: _secili.guncelFiyat,
      targetPrice: hedef,
    );
    final kurulum = AlarmKurulumu(_secili, hedef, yon);
    final kur = widget.kur;
    if (kur != null) {
      final l10n = context.l10n;
      try {
        await kur(kurulum);
      } catch (e) {
        if (!mounted) return;
        // Snackbar modal sayfanın altında kalırdı; hata alanın altında.
        setState(() => _hata = '${l10n.alertSetFailed}. ${friendlyError(e)}');
        return;
      }
      if (!mounted) return;
    }
    Navigator.of(context).pop(kurulum);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hedef = _hedef;
    final yon = hedef == null
        ? null
        : PriceAlert.suggestDirection(
            currentPrice: _secili.guncelFiyat, targetPrice: hedef);
    final fiyatVar = _secili.guncelFiyat > 0;
    final maliyet = _secili.maliyet;
    final maliyetCipleri = maliyet == null || maliyet <= 0 || !fiyatVar
        ? const <({int yuzde, double hedef})>[]
        : maliyetHedefleri(maliyet, _secili.guncelFiyat);
    final esit =
        hedef != null && alarmHedefiGuncelFiyatta(hedef, _secili.guncelFiyat);

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.lg, SandikSpace.sm2, SandikSpace.lg, SandikSpace.lg),
        // Kaydırılabilir: büyük yazıda (3,1×) form sayfa yüksekliğini aşıyor,
        // "Alarm kur" düğmesi ekranın altında kesiliyordu (büyük yazı
        // taraması 2026-10-12). Sığınca kaydırma yok, düzen aynı.
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tutamaç (HIG denetimi 2026-10-10): aşağı kaydırarak kapandığı görünsün.
            const Center(child: SandikTutamac()),
            const SizedBox(height: SandikSpace.sm),
            Text(widget.sabit ? context.l10n.alertForAsset(_secili.ad) : 'Alarm kur',
                style: context.t.headlineSmall?.copyWith(color: c.text90),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: SandikSpace.md),
            if (!widget.sabit) ...[
              // `DropdownButton` + `value`: projede kararlı kalıp
              // (bkz. add_asset_screen).
              Container(
                padding: const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
                decoration: BoxDecoration(
                  // Altındaki hedef fiyat alanıyla aynı dolgu kuralı;
                  // sabit `surface2` alt sayfa zemini değişirse ayrışırdı.
                  color: context.inputFill,
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(color: c.hairline),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AlarmAdayi>(
                    value: _secili,
                    isExpanded: true,
                    // null: satır yüksekliği yazıyla büyür (en az 48).
                    // Varsayılan sabit 48'de büyük yazıda (2×+) varlık adı
                    // dikeyde kesiliyordu (büyük yazı taraması 2026-10-12).
                    itemHeight: null,
                    dropdownColor: c.surface2,
                    style: context.t.titleMedium?.copyWith(color: c.text90),
                    icon: Icon(Icons.arrow_drop_down_rounded, color: c.amberText),
                    items: [
                      for (final a in widget.adaylar)
                        DropdownMenuItem(
                          value: a,
                          child: Text(a.ad, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _secili = v ?? _secili),
                  ),
                ),
              ),
              const SizedBox(height: SandikSpace.xs2),
            ],
            Text(
              fiyatVar
                  ? context.l10n.currentlyPrice(fmtTRYFiyat(_secili.guncelFiyat))
                  : context.l10n.currentPriceUnknown,
              style: context.t.bodyMedium?.copyWith(color: c.text58),
            ),
            const SizedBox(height: SandikSpace.md),
            TextField(
              controller: _controller,
              autofocus: widget.sabit,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Hedef fiyat',
                errorText: _hata,
              ),
              onChanged: (_) => setState(() => _hata = null),
            ),
            if (fiyatVar) ...[
              const SizedBox(height: SandikSpace.smd),
              Wrap(
                spacing: SandikSpace.xs2,
                runSpacing: SandikSpace.xs2,
                children: [
                  for (final y in _hizliYuzdeler)
                    _cip(
                      metin: '${y > 0 ? '+' : '−'}%${y.abs()}',
                      semantik: context.l10n.targetPctSemantics(
                          y > 0 ? context.l10n.plusWord : context.l10n.minusWord,
                          y.abs()),
                      renk: y > 0 ? c.gain : c.loss,
                      onTap: () => _hizli(y),
                    ),
                ],
              ),
            ],
            if (maliyetCipleri.isNotEmpty) ...[
              const SizedBox(height: SandikSpace.smd),
              // Maliyetine göre (2026-10-23): yüzde güncelden değil kendi
              // alış fiyatından. Renk yönü söyler, metin de söyler (renk
              // körlüğü): "Maliyetim", "Maliyet +%20".
              Text(
                context.l10n.alertCostRow(fmtTRYFiyat(maliyet!)),
                style: context.t.labelMedium?.copyWith(color: c.text58),
              ),
              const SizedBox(height: SandikSpace.xs),
              Wrap(
                spacing: SandikSpace.xs2,
                runSpacing: SandikSpace.xs2,
                children: [
                  for (final h in maliyetCipleri)
                    _cip(
                      metin: h.yuzde == 0
                          ? context.l10n.alertCostBreakEven
                          : context.l10n.alertCostPct(
                              '${h.yuzde > 0 ? '+' : '−'}%${h.yuzde.abs()}'),
                      semantik: h.yuzde == 0
                          ? context.l10n.alertCostBreakEvenSemantics
                          : context.l10n.alertCostPctSemantics(
                              h.yuzde > 0
                                  ? context.l10n.plusWord
                                  : context.l10n.minusWord,
                              h.yuzde.abs()),
                      renk: h.yuzde == 0
                          ? c.text90
                          : h.yuzde > 0
                              ? c.gain
                              : c.loss,
                      onTap: () => _hedefYaz(h.hedef),
                    ),
                ],
              ),
            ],
            const SizedBox(height: SandikSpace.smd),
            // Eşit hedef: "çıkınca haber vereceğiz" demek yalan olurdu —
            // alarm hemen çalışır. Yön cümlesinin yerine uyarı (#24).
            if (esit && _hata == null)
              Text(
                context.l10n.alertTargetAtCurrent,
                style: context.t.bodyMedium?.copyWith(color: c.danger),
              )
            else if (yon != null && !esit)
              Text(
                yon == 'above'
                    ? context.l10n.notifyWhenAbove
                    : context.l10n.notifyWhenBelow,
                style: context.t.bodyMedium?.copyWith(color: c.amberText),
              ),
            const SizedBox(height: SandikSpace.lg),
            // İzin reddedilmişse alarm kurulur ama çalınca haber gelmez;
            // bunu kurarken söylemek (Ar-Ge 16:45 #1, 2026-10-21).
            const BildirimIzniUyarisi(
                padding: EdgeInsets.only(bottom: SandikSpace.md)),
            SizedBox(
              width: double.infinity,
              child: SandikAsyncButton.kompakt(
                style: FilledButton.styleFrom(
                  backgroundColor: c.amberFill,
                  foregroundColor: c.onAmber,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _kaydet,
                child: Text(context.l10n.setAlert),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Bir alarm daha AKTİF olursa (yeni kurma ya da tetiklenmişi yeniden kurma)
/// sınır aşılır mı; aşılırsa uyarıyı gösterip true döner. Paywall açıkken
/// sınır satış kapısıdır: Premium yolu da gösterilir.
///
/// Neden ortak (paywall kapıları incelemesi, 2026-10-11): sınır yalnız bu
/// sayfada denetleniyordu; Alarmlar ekranı ve alarm şeridindeki "yeniden
/// kur" tetiklenmiş alarmları aktife döndürerek 20 sınırını aşıyordu.
bool alarmSiniriDoluysaUyar(BuildContext context, WidgetRef ref) {
  final mevcut = ref.read(priceAlertsProvider).valueOrNull ?? const [];
  final limit = ref.read(priceAlertLimitProvider);
  if (mevcut.where((a) => a.isActive).length < limit) return false;
  alarmSiniriUyarisi(context, ref, limit);
  return true;
}
