import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../models/asset.dart';
import '../models/asset_type.dart' show alarmFiyatSimgesi;
import '../models/eurobond.dart' show eurobondOneki;
import '../models/position.dart' show aggregatePositions;
import '../models/price_alert.dart';
import '../models/seviye_alarmi.dart';
import '../models/yuzde_alarmi.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart'
    show premiumKilitliProvider, priceAlertLimitProvider;
import '../providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import '../providers/price_alert_provider.dart';
import '../providers/seviye_alarmi_provider.dart';
import '../providers/yuzde_alarmi_provider.dart';
import '../screens/paywall_screen.dart' show PaywallScreen;
import '../services/analytics_service.dart';
import '../services/crash_reporter.dart';
import '../services/cizim_alarmi.dart'
    show cizgiAlarmEtiketi, kCizgiAdiAzami;
import '../services/fiyat_kaynagi.dart';
import '../services/ozellik_olcumu.dart';
import '../services/review_prompt_service.dart';
import '../theme/sandik.dart';
import 'bildirim_izni_uyarisi.dart';
import 'review_prompt_sheet.dart';
import 'sandik_async_button.dart';
import 'sandik_segment.dart';
import 'sinir_uyarisi.dart';
import 'tur_filtre_cipleri.dart' show SandikFiltreCipi;
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

  /// Son 52 haftanın zirvesi ve dibi, [guncelFiyat] ile AYNI ölçekte
  /// (varlık sayfasının "Aralık" kartındaki 52 hafta satırı, Ar-Ge
  /// 2026-11-11). Verilirse sheet "52 hafta zirvesi / dibi" çiplerini
  /// gösterir. `null`: seri yüklenmedi, bir yıl dolmadı ya da ölçek alarmla
  /// aynı değil — çip çıkmaz, sheet bunun için istek ATMAZ (uydurma yok).
  final ({double zirve, double dip})? yil52;
  const AlarmAdayi(this.sembol, this.ad, this.guncelFiyat,
      {this.maliyet, this.yil52});
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

/// Fiyat kipinin canlı özeti (Ar-Ge 6 Kas 08:45 #1): yüzde kipindeki
/// `alarmYuzdeOzet*` cümlesinin eşi. Kullanıcı yönü kafasında hesaplamasın;
/// hedef yazılınca (ya da çipe basılınca) "THY ₺330,00 seviyesine çıkarsa
/// haber vereceğiz." Tutar varlığın kendi simgesiyle ([alarmFiyatMetni]:
/// ABD hissesinde "$", #293). Yön [PriceAlert.suggestDirection]'dan:
/// kaydedilen yönle aynı kaynak, cümle başka bir şey söyleyemez.
///
/// `null`: hedef yok, güncel fiyat bilinmiyor (yön türetilemez; eski
/// "Fiyat bu seviyeye çıkınca" cümlesi bu durumda da "çıkınca" diyordu)
/// ya da hedef güncel fiyata eşit (orada uyarı satırı konuşur).
String? alarmFiyatOzeti(AppLocalizations l10n, AlarmAdayi aday,
    double? hedef) {
  if (hedef == null || aday.guncelFiyat <= 0) return null;
  if (alarmHedefiGuncelFiyatta(hedef, aday.guncelFiyat)) return null;
  final yon = PriceAlert.suggestDirection(
      currentPrice: aday.guncelFiyat, targetPrice: hedef);
  final tutar = alarmFiyatMetni(hedef, aday.sembol);
  return yon == 'above'
      ? l10n.alarmFiyatOzetYukselis(aday.ad, tutar)
      : l10n.alarmFiyatOzetDusus(aday.ad, tutar);
}

/// Hedefin güncel fiyata uzaklığı, alanın içinde: "+%5,6" / "−%3,2".
/// [alarmFiyatOzeti] ile aynı koşullarda görünür.
String? alarmFiyatUzakligi(AlarmAdayi aday, double? hedef) {
  if (hedef == null || aday.guncelFiyat <= 0) return null;
  if (alarmHedefiGuncelFiyatta(hedef, aday.guncelFiyat)) return null;
  return fmtPctIsaretli((hedef / aday.guncelFiyat - 1) * 100, digits: 1);
}

/// Sheet'in döndürdüğü seçim.
class AlarmKurulumu {
  final AlarmAdayi aday;
  final double hedef;
  final String yon;

  /// Yatay çizgiden kurulurken kullanıcının verdiği ad (boş olabilir);
  /// diğer yollarda `null`. `label`'a [cizgiAlarmEtiketi] ile girer.
  final String? isim;

  /// "Her geçişte haber ver" (0171); varsayılan tek atış.
  final bool tekrar;
  const AlarmKurulumu(this.aday, this.hedef, this.yon,
      {this.isim, this.tekrar = false});
}

/// Sheet'in "Günlük yüzde" kipinde döndürdüğü seçim (0169).
class YuzdeAlarmKurulumu {
  final AlarmAdayi aday;
  final int esik;
  final YuzdeYon yon;
  const YuzdeAlarmKurulumu(this.aday, this.esik, this.yon);
}

/// Sheet'in "Gösterge" kipinde döndürdüğü seçim (0170).
class GostergeAlarmKurulumu {
  final AlarmAdayi aday;
  final GostergeKodu gosterge;
  final SeviyeYon yon;
  const GostergeAlarmKurulumu(this.aday, this.gosterge, this.yon);
}

/// Göstergenin okunan adı: "EMA50", "Bollinger üst bandı".
String gostergeAdi(AppLocalizations l10n, GostergeKodu g) => switch (g) {
      GostergeKodu.bbUst => l10n.gostergeBbUst,
      GostergeKodu.bbAlt => l10n.gostergeBbAlt,
      _ => g.kisaAd,
    };

/// Gösterge alarmının listede okunan adı: "EMA50 · yukarı keserse".
/// Yön metinde yazar (renk körlüğü: yalnız okla anlatılmaz).
String gostergeAlarmEtiketi(
        AppLocalizations l10n, GostergeKodu g, SeviyeYon yon) =>
    switch (yon) {
      SeviyeYon.yukari => l10n.gostergeAlarmEtiketYukari(gostergeAdi(l10n, g)),
      SeviyeYon.asagi => l10n.gostergeAlarmEtiketAsagi(gostergeAdi(l10n, g)),
      SeviyeYon.herIkisi => l10n.gostergeAlarmEtiketIkisi(gostergeAdi(l10n, g)),
    };

/// Sheet bu adaya "Gösterge" kipini sunar mı (0170).
///
/// Premium özelliği: [gorunur] `premiumOzellikleriGorunurProvider` (paywall
/// kapalıyken yalnız admin; açıkken herkes, ücretsizde kilitli). Kapsam
/// [FiyatKaynagi.gostergeAlarmiKapsamindaMi] (altın ve TL döviz yok — canlı
/// fiyat ile günlük seri ayrı kaynak). Çalmış fiyat alarmını yeniden
/// kurarken ([baslangicHedef] dolu) sunulmaz — yüzde kipiyle aynı gerekçe.
bool gostergeKipiSunulur(AlarmAdayi aday,
        {required bool gorunur, double? baslangicHedef}) =>
    gorunur &&
    baslangicHedef == null &&
    FiyatKaynagi.gostergeAlarmiKapsamindaMi(aday.sembol);

/// Yüzde alarmının listede ve onayda okunan adı: "Günlük %2 düşüş".
/// Yön metinde de yazar (renk körlüğü: yalnız renkle/okla anlatılmaz).
String yuzdeAlarmEtiketi(AppLocalizations l10n, double esik, YuzdeYon yon) {
  final e = yuzdeEsikMetni(esik);
  return switch (yon) {
    YuzdeYon.dusus => l10n.yuzdeAlarmEtiketDusus(e),
    YuzdeYon.yukselis => l10n.yuzdeAlarmEtiketYukselis(e),
    YuzdeYon.ikisi => l10n.yuzdeAlarmEtiketIkisi(e),
  };
}

/// Sheet bu adaya "Günlük yüzde" kipini sunar mı.
///
/// Kapsam [FiyatKaynagi.yuzdeAlarmiKapsamindaMi]'da (altın, TL döviz,
/// kripto; fon/BIST yok — sunucu onların gün içi yüzdesini ölçmüyor,
/// uydurma yok). Çalmış fiyat alarmını yeniden kurarken ([baslangicHedef]
/// dolu) sunulmaz: o akış eşik düzeltmesidir, kip değiştirmek eski alarmı
/// silip başka türde alarm kurmak olurdu.
bool yuzdeKipiSunulur(AlarmAdayi aday, {double? baslangicHedef}) =>
    baslangicHedef == null && FiyatKaynagi.yuzdeAlarmiKapsamindaMi(aday.sembol);

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

/// Alarmda yazan fiyat: varlığın kendi simgesiyle (müşteri raporu 5 Kas
/// 09:15). Liste satırı, kurma sayfasının "Şu an" satırı ve "alarm kuruldu"
/// onayı her sembolde lira biçimleyicisini kullanıyordu; ABD hissesinde grup
/// başlığı "$228,52" derken satır "₺240,00" diyordu ve kişi lira mı dolar mı
/// kurduğunu bilemiyordu. Push, çan ve grup başlığı zaten
/// [alarmFiyatSimgesi]'ni kullanıyor; simgesi belirsiz sembolde (endeks)
/// sayı simgesiz yazılır, yanlış simge simgesiz sayıdan kötüdür.
String alarmFiyatMetni(double fiyat, String sembol) =>
    fmtFiyat(fiyat, symbol: alarmFiyatSimgesi(sembol) ?? '');

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
  bool? odakla,
  bool cizgiAdi = false,
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
  YuzdeAlarmi? yuzdeKayit;
  GostergeAlarmi? gostergeKayit;
  final sonuc = await showSandikSheet<Object>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => AlarmKurSheet(
      adaylar: liste,
      sabit: sabit != null,
      baslangicHedef: baslangicHedef,
      odakla: odakla,
      cizgiAdi: cizgiAdi,
      // Gösterge kipi (0170, Premium): görünürlük ve kilit ƒx ile aynı
      // kapı; kilitliyken sekmeye dokunmak paywall'u açar.
      gostergeGorunur: ref.read(premiumOzellikleriGorunurProvider),
      gostergeKilitli: ref.read(premiumKilitliProvider),
      onGostergeKilitli: (ctx) =>
          PaywallScreen.show(ctx, source: 'gosterge_alarmi'),
      kurGosterge: (k) async {
        final me = ref.read(authProvider).valueOrNull;
        if (me == null) return;
        gostergeKayit = await ref
            .read(gostergeAlarmlariProvider.notifier)
            .create(GostergeAlarmi(
              id: '',
              userId: me.id,
              symbol: k.aday.sembol,
              label: k.aday.ad,
              gosterge: k.gosterge,
              yon: k.yon,
              createdAt: DateTime.now(),
            ));
      },
      kur: (k) async {
        final me = ref.read(authProvider).valueOrNull;
        if (me == null) return;
        kayit = await ref.read(priceAlertsProvider.notifier).create(PriceAlert(
          id: '',
          userId: me.id,
          symbol: k.aday.sembol,
          // Yatay çizgiden: "varlık · ad" (ad yoksa yalnız varlık, eskisi).
          label: cizgiAdi ? cizgiAlarmEtiketi(k.aday.ad, k.isim) : k.aday.ad,
          targetPrice: k.hedef,
          direction: k.yon,
          enabled: true,
          createdAt: DateTime.now(),
          tekrar: k.tekrar,
        ));
      },
      kurYuzde: (k) async {
        final me = ref.read(authProvider).valueOrNull;
        if (me == null) return;
        yuzdeKayit =
            await ref.read(yuzdeAlarmlariProvider.notifier).create(YuzdeAlarmi(
          id: '',
          userId: me.id,
          symbol: k.aday.sembol,
          label: k.aday.ad,
          esikPct: k.esik.toDouble(),
          yon: k.yon,
          createdAt: DateTime.now(),
        ));
      },
    ),
  );
  if (sonuc is GostergeAlarmKurulumu && gostergeKayit != null) {
    OzellikOlcumu.say(Ozellik.gostergeAlarm);
    if (context.mounted) {
      sandikSnack(
        context,
        context.l10n.gostergeAlarmKuruldu(sonuc.aday.ad,
            gostergeAlarmEtiketi(context.l10n, sonuc.gosterge, sonuc.yon)),
        kind: SandikSnackKind.success,
      );
    }
    // Fiyat alarmı kurulmadı (yüzde kipiyle aynı sözleşme).
    return null;
  }
  if (sonuc is YuzdeAlarmKurulumu && yuzdeKayit != null) {
    OzellikOlcumu.say(Ozellik.yuzdeAlarm);
    if (context.mounted) {
      sandikSnack(
        context,
        context.l10n.yuzdeAlarmKuruldu(sonuc.aday.ad,
            yuzdeAlarmEtiketi(context.l10n, sonuc.esik.toDouble(), sonuc.yon)),
        kind: SandikSnackKind.success,
      );
      CrashReporter.arkaPlan(
          ReviewPromptSheet.belkiGoster(context, ReviewAni.alarmKuruldu),
          reason: 'alarmKur.degerlendirmeIstemi');
    }
    // Dönüş tipi fiyat alarmı: çağıranlar (varlık ekranı, yeniden kur)
    // yalnız fiyat alarmının kaydıyla iş yapar; yüzde alarmı onlar için
    // "fiyat alarmı kurulmadı" demektir.
    return null;
  }
  final kurulan = kayit;
  if (sonuc is! AlarmKurulumu || kurulan == null) return null;
  unawaited(AnalyticsService.instance
      .logScreenView(screenName: 'price_alert_created'));
  if (context.mounted) {
    // Yatay çizgiye ad verildiyse onay adı söyler ("«Destek» için alarm
    // kuruldu", e2e 2026-10-29); adsızda varlığın adı, eskisi gibi.
    final isim = (sonuc.isim ?? '').trim();
    final ad = isim.isEmpty ? sonuc.aday.ad : '«$isim»';
    sandikSnack(
      context,
      sonuc.yon == 'above'
          ? context.l10n.alertSetAbove(
              ad, alarmFiyatMetni(sonuc.hedef, sonuc.aday.sembol))
          : context.l10n.alertSetBelow(
              ad, alarmFiyatMetni(sonuc.hedef, sonuc.aday.sembol)),
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
    final fiyat = alarmFiyatMetni(alarm.targetPrice, alarm.symbol);
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

/// Nöbetteki fiyat alarmını düzenler (müşteri raporu 31 Eki 21:15, yasin
/// "yap"). Altın yükseldikçe hedefi yukarı çekmek en sık alarm işi; eskiden
/// sil + yeniden kur iki adımdı ve arada alarm kayboluyordu.
///
/// Sayfa kurma sayfasının kendisi, ön dolu: hedef, "her geçişte". Yön yine
/// güncel fiyattan türetilir (kurmadaki kural). Kayıt aynı satırı günceller
/// ([PriceAlertsNotifier.duzenle]); tavana ikinci kez sayılmaz, bu yüzden
/// sınır denetimi yok. [sil] verilirse sayfanın altında "Alarmı sil" durur;
/// sayfa önce kapanır, silme (ve "Geri al") listenin kendi yolundan koşar.
/// Kaydedilirse `true`.
Future<bool> alarmDuzenleAkisi(
  BuildContext context,
  WidgetRef ref,
  PriceAlert alarm, {
  required AlarmAdayi aday,
  VoidCallback? sil,
}) async {
  if (DemoModu.yazmaKapisi('alarm')) return false;
  var silinsin = false;
  final sonuc = await showSandikSheet<Object>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sayfa) => AlarmKurSheet(
      adaylar: [aday],
      sabit: true,
      duzenle: true,
      // Hedef zaten yazılı; klavye açılışta sayfayı örtmesin.
      odakla: false,
      baslangicHedef: alarm.targetPrice,
      baslangicTekrar: alarm.tekrar,
      onSil: sil == null
          ? null
          : () {
              silinsin = true;
              Navigator.of(sayfa).pop();
            },
      // Güncel fiyat bilinmiyorsa yön türetilemez: alarmın kendi yönü
      // korunur (yoksa "altına inince" sessizce "üstüne çıkınca" olurdu).
      kur: (k) => ref.read(priceAlertsProvider.notifier).duzenle(alarm.id,
          hedef: k.hedef,
          yon: aday.guncelFiyat > 0 ? k.yon : alarm.direction,
          tekrar: k.tekrar),
    ),
  );
  if (silinsin) {
    sil!();
    return false;
  }
  // "Alarm güncellendi" snack'ı kalktı (Ar-Ge 11 Kas 19:04 #6): yeni hedef
  // alarm satırında/şeridinde hemen görünür, geri alınacak bir şey yok.
  // Onay sayfanın Kaydet düğmesinde ✓ + başarı titreşimi (yazma `kur:`
  // ile sayfanın içinde koşar).
  if (sonuc is! AlarmKurulumu) return false;
  return true;
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

  /// "Günlük yüzde" kipinin yazması ([kur] ile aynı sözleşme). `null` →
  /// sayfa kurulumu hemen döndürür (widget testleri).
  final Future<void> Function(YuzdeAlarmKurulumu kurulum)? kurYuzde;

  /// Alanın ön değeri: çalmış alarmı yeniden kurarken eski eşik
  /// ([alarmiYenidenKur]) ya da yatay grafikteki çizginin fiyatı;
  /// kullanıcı değiştirebilir.
  final double? baslangicHedef;

  /// Hedef alanı açılışta klavyeyi açsın mı; `null` → [sabit] (eski
  /// davranış). Yatay grafikten açılınca kapalı: telefon yan dururken
  /// klavye sayfanın neredeyse tamamını örter, hedef zaten ön dolu.
  final bool? odakla;

  /// Yatay grafikteki çizgiden açıldı: hedefin altında isteğe bağlı "Çizginin
  /// adı" alanı (yasin 2026-10-29). Varsayılan kapalı: sayfa birebir eski.
  final bool cizgiAdi;

  /// "Gösterge" kipi (0170, Premium) görünür mü — `premiumOzellikleriGorunur`.
  /// Varsayılan kapalı: bugünkü sayfa birebir.
  final bool gostergeGorunur;

  /// Görünür ama kilitli (paywall açık, Premium değil): sekme kilit
  /// simgesiyle durur, dokunuş [onGostergeKilitli]'yı çağırır.
  final bool gostergeKilitli;
  final void Function(BuildContext context)? onGostergeKilitli;

  /// "Gösterge" kipinin yazması ([kur] ile aynı sözleşme).
  final Future<void> Function(GostergeAlarmKurulumu kurulum)? kurGosterge;

  /// Var olan alarmı düzenleme kipi ([alarmDuzenleAkisi]): başlık "Alarmı
  /// düzenle", düğme "Kaydet". Varsayılan kapalı: sayfa birebir eskisi.
  final bool duzenle;

  /// "Her geçişte" anahtarının ön değeri (düzenlenen alarmın kendisi).
  final bool baslangicTekrar;

  /// Düzenlemede sayfanın altındaki "Alarmı sil": kaydırarak silme tek yol
  /// kalırsa bulunamaz; görünür yol burada (müşteri raporu 31 Eki 21:15).
  final VoidCallback? onSil;

  const AlarmKurSheet(
      {super.key,
      required this.adaylar,
      this.sabit = false,
      this.kur,
      this.kurYuzde,
      this.baslangicHedef,
      this.odakla,
      this.cizgiAdi = false,
      this.gostergeGorunur = false,
      this.gostergeKilitli = false,
      this.onGostergeKilitli,
      this.kurGosterge,
      this.duzenle = false,
      this.baslangicTekrar = false,
      this.onSil});

  @override
  State<AlarmKurSheet> createState() => _AlarmKurSheetState();
}

class _AlarmKurSheetState extends State<AlarmKurSheet> {
  /// Kaydet düğmesinin ✓ anı (Ar-Ge 11 Kas 19:04 #3); yalnız yazma
  /// sayfanın içinde koştuğunda ([AlarmKurSheet.kur] verildiyse).
  final _basari = SandikBasariSinyali();

  late AlarmAdayi _secili = widget.adaylar.first;
  final _controller = TextEditingController();
  final _isim = TextEditingController();
  String? _hata;

  /// Seçili kip (0169 yüzde, 0170 gösterge). Varsayılan Fiyat: bugünkü
  /// davranış birebir; diğer kipler yalnız kapsamdaki adayda sunulur.
  _AlarmKipi _kip = _AlarmKipi.fiyat;
  int _esik = 2;
  // Varsayılan "İkisi de" (müşteri raporu 27 Eki 09:15): "bugün sert
  // oynarsa haber ver" yönsüz bir istek; kullanıcı yön seçmekle uğraşmasın.
  YuzdeYon _yuzdeYon = YuzdeYon.ikisi;

  GostergeKodu _gosterge = GostergeKodu.ema50;
  // "Keserse haber ver" yönsüz bir istek (yüzde kipindeki karar, müşteri
  // raporu 27 Eki 09:15): varsayılan iki yön.
  SeviyeYon _gostergeYon = SeviyeYon.herIkisi;

  /// "Her geçişte haber ver" (0171, Ar-Ge 29 Eki 20:45 #1). Varsayılan
  /// kapalı: bugünkü tek atış alarm birebir. Ücretsiz (alarm temel değer);
  /// tavana yine tek alarm olarak sayılır.
  late bool _tekrar = widget.baslangicTekrar;

  bool get _yuzdeSunulur =>
      yuzdeKipiSunulur(_secili, baslangicHedef: widget.baslangicHedef);

  bool get _gostergeSunulur => gostergeKipiSunulur(_secili,
      gorunur: widget.gostergeGorunur, baslangicHedef: widget.baslangicHedef);

  /// Bu adayda sunulan kipler, segmentteki sırayla.
  List<_AlarmKipi> get _kipler => [
        _AlarmKipi.fiyat,
        if (_yuzdeSunulur) _AlarmKipi.yuzde,
        if (_gostergeSunulur) _AlarmKipi.gosterge,
      ];

  /// Seçici kapsam dışı bir adaya geçerse kip kendiliğinden Fiyat'a döner.
  _AlarmKipi get _etkinKip => _kipler.contains(_kip) ? _kip : _AlarmKipi.fiyat;

  bool get _yuzdeAcik => _etkinKip == _AlarmKipi.yuzde;
  bool get _gostergeAcik => _etkinKip == _AlarmKipi.gosterge;

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
    _isim.dispose();
    super.dispose();
  }

  double? get _hedef {
    final v = parseTrNumber(_controller.text);
    return (v == null || v <= 0) ? null : v;
  }

  void _hedefYaz(double f) {
    // 1 ₺ altı (SHIB) 2 haneye yuvarlanınca hedef 0 olurdu.
    _controller.text = f >= 1 ? fmtNum(f, digits: 2) : fmtInputTr(f);
    setState(() => _hata = null);
  }

  /// Hızlı doldurma çipleri: TEK, yatay kayan satır (Ar-Ge 6 Kas 08:45 #3).
  ///
  /// Neden: güncel fiyatın ±%'si köşeli/renkli yazılı bir `Wrap`'te,
  /// maliyet çipleri ayrı başlıklı ikinci bir satırdaydı; hedef sayfasının
  /// çipleri ise pill. Aynı iş üç görünümdeydi (TASARIM_DILI §6.4). Artık
  /// ortak seçilebilir çip ([SandikFiltreCipi]: pill, 44 pt, seçiliyken
  /// amber + onay işareti) ve tek satır: sayfa bir satır kısalır, yatay
  /// grafikten (390 pt) açılınca da satır kırılmaz (2026-10-29 e2e kaydı:
  /// alt alta dizilen çipler "Alarm kur"u ekran dışına itiyordu).
  ///
  /// Güncelin ±%'si duruyor: kullanıcı çoğu zaman "biraz yükselince /
  /// düşünce" der, rakam hesaplamak istemez.
  ///
  /// Sıra kullanıcının sorusuna göre: önce "maliyetime dönerse", sonra
  /// yükseliş (güncelin +%5/+%10'u, maliyetin +%20'si), sonra düşüş, en
  /// sonda 52 hafta zirvesi/dibi (yalnız [AlarmAdayi.yil52] varsa). Yön
  /// yalnız renkle verilmez: işaret (+/−), ok ikonu ve alttaki cümle.
  /// Alandaki hedefe eşit çip SEÇİLİ görünür; eşitlik ekrandaki
  /// hassasiyette ([fmtTRYFiyat]), [alarmHedefiGuncelFiyatta] ile aynı kural.
  Widget _hizliCipler(
      SandikPalette c, List<({int yuzde, double hedef})> maliyetCipleri) {
    final l10n = context.l10n;
    final g = _secili.guncelFiyat;
    final yazilan = _hedef;
    String? isaret(int y) => y == 0 ? null : (y > 0 ? '+' : '−');
    ({String ad, String semantik, int yon, double hedef})? maliyet(int y) {
      for (final h in maliyetCipleri) {
        if (h.yuzde != y) continue;
        return (
          ad: y == 0
              ? l10n.alertCostBreakEven
              : l10n.alertCostPct('${isaret(y)}%${y.abs()}'),
          semantik: y == 0
              ? l10n.alertCostBreakEvenSemantics
              : l10n.alertCostPctSemantics(
                  y > 0 ? l10n.plusWord : l10n.minusWord, y.abs()),
          yon: y.sign,
          hedef: h.hedef,
        );
      }
      return null;
    }

    ({String ad, String semantik, int yon, double hedef}) guncel(int y) => (
          ad: '${isaret(y)}%${y.abs()}',
          semantik: l10n.targetPctSemantics(
              y > 0 ? l10n.plusWord : l10n.minusWord, y.abs()),
          yon: y.sign,
          hedef: g * (1 + y / 100),
        );
    // 52 hafta zirvesi/dibi (Ar-Ge 2026-11-11, ücretsiz): satırın SONUNDA;
    // yüzdeler kullanıcının kendi sorusu, bunlar piyasanın verdiği eşik.
    // Zirve yalnız güncelin ÜSTÜNDE, dip yalnız ALTINDA çıkar: yön hedeften
    // türetildiği için ([PriceAlert.suggestDirection]) aksi hâlde "zirve"
    // çipi aşağı alarm kurardı; bugün yeni zirvedeyse hedef güncele eşittir
    // ve alarm hemen çalardı ([alarmHedefiGuncelFiyatta]) — o çip hiç yok.
    ({String ad, String semantik, int yon, double hedef})? yil52(int yon) {
      final y = _secili.yil52;
      if (y == null || g <= 0) return null;
      final hedef = yon > 0 ? y.zirve : y.dip;
      if (!hedef.isFinite || hedef <= 0) return null;
      if (alarmHedefiGuncelFiyatta(hedef, g)) return null;
      if (yon > 0 ? hedef <= g : hedef >= g) return null;
      final tutar = alarmFiyatMetni(hedef, _secili.sembol);
      return (
        ad: yon > 0 ? l10n.alertYil52Zirve(tutar) : l10n.alertYil52Dip(tutar),
        semantik: yon > 0
            ? l10n.alertYil52ZirveSemantics(tutar)
            : l10n.alertYil52DipSemantics(tutar),
        yon: yon,
        hedef: hedef,
      );
    }

    final cipler = [
      maliyet(0),
      guncel(5),
      guncel(10),
      maliyet(20),
      guncel(-5),
      guncel(-10),
      maliyet(-10),
      yil52(1),
      yil52(-1),
    ].whereType<({String ad, String semantik, int yon, double hedef})>();
    return SingleChildScrollView(
      key: const ValueKey('alarmHizliCipler'),
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final (i, cip) in cipler.indexed) ...[
            if (i > 0) const SizedBox(width: SandikSpace.xs2),
            // Yatay kaydırmada genişlik sınırsız; ortak çipin içindeki
            // `Flexible` sınır ister. Çip yazısı kısa, tavan yalnız güvenlik.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: SandikFiltreCipi(
                ad: cip.ad,
                semantik: cip.semantik,
                secili: yazilan != null &&
                    fmtTRYFiyat(yazilan) == fmtTRYFiyat(cip.hedef),
                ikon: switch (cip.yon) {
                  > 0 => Icons.arrow_upward_rounded,
                  < 0 => Icons.arrow_downward_rounded,
                  _ => null,
                },
                ikonRengi: cip.yon > 0 ? c.gain : c.loss,
                onTap: () => _hedefYaz(cip.hedef),
              ),
            ),
          ],
        ],
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
    final kurulum = AlarmKurulumu(_secili, hedef, yon,
        isim: widget.cizgiAdi ? _isim.text.trim() : null, tekrar: _tekrar);
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
      // Yazma bitti: düğmede ✓, sonra kapanış. `kur` yoksa kaydı çağıran
      // sayfa kapandıktan SONRA yapar (başarısı burada bilinmez) → ✓ yok.
      await _basari.goster();
      if (!mounted) return;
    }
    Navigator.of(context).pop(kurulum);
  }

  Future<void> _kaydetGosterge() async {
    if (widget.gostergeKilitli) {
      widget.onGostergeKilitli?.call(context);
      return;
    }
    final kurulum = GostergeAlarmKurulumu(_secili, _gosterge, _gostergeYon);
    final kur = widget.kurGosterge;
    if (kur != null) {
      final l10n = context.l10n;
      try {
        await kur(kurulum);
      } catch (e) {
        if (!mounted) return;
        setState(() => _hata = '${l10n.alertSetFailed}. ${friendlyError(e)}');
        return;
      }
      if (!mounted) return;
      // Yazma bitti: düğmede ✓, sonra kapanış. `kur` yoksa kaydı çağıran
      // sayfa kapandıktan SONRA yapar (başarısı burada bilinmez) → ✓ yok.
      await _basari.goster();
      if (!mounted) return;
    }
    Navigator.of(context).pop(kurulum);
  }

  String _seviyeYonAdi(SeviyeYon y) => switch (y) {
        SeviyeYon.yukari => context.l10n.gostergeYonYukari,
        SeviyeYon.asagi => context.l10n.gostergeYonAsagi,
        SeviyeYon.herIkisi => context.l10n.alarmYonIkisi,
      };

  /// "Gösterge" kipinin gövdesi (0170): gösterge çipleri, yön çipleri,
  /// özet ve hesap notu. Yüzde kipiyle aynı bileşenler (tek seçim çipi
  /// `SandikFiltreCipi`); yön ok ikonu + fiil + özet cümlesiyle okunur.
  List<Widget> _gostergeBolumu(SandikPalette c) {
    final l10n = context.l10n;
    final ad = gostergeAdi(l10n, _gosterge);
    final ozet = switch (_gostergeYon) {
      SeviyeYon.yukari => l10n.gostergeOzetYukari(_secili.ad, ad),
      SeviyeYon.asagi => l10n.gostergeOzetAsagi(_secili.ad, ad),
      SeviyeYon.herIkisi => l10n.gostergeOzetIkisi(_secili.ad, ad),
    };
    return [
      Text(l10n.gostergeBaslik,
          style: context.t.labelMedium?.copyWith(color: c.text58)),
      const SizedBox(height: SandikSpace.xs),
      Wrap(
        spacing: SandikSpace.xs2,
        runSpacing: SandikSpace.xs2,
        children: [
          for (final g in GostergeKodu.values)
            SandikFiltreCipi(
              key: ValueKey('gostergeCipi_${g.kod}'),
              ad: gostergeAdi(l10n, g),
              secili: _gosterge == g,
              onTap: () => setState(() {
                _gosterge = g;
                _hata = null;
              }),
            ),
        ],
      ),
      const SizedBox(height: SandikSpace.smd),
      Text(l10n.alarmYuzdeYonBaslik,
          style: context.t.labelMedium?.copyWith(color: c.text58)),
      const SizedBox(height: SandikSpace.xs),
      Wrap(
        spacing: SandikSpace.xs2,
        runSpacing: SandikSpace.xs2,
        children: [
          for (final y in SeviyeYon.values)
            SandikFiltreCipi(
              ad: _seviyeYonAdi(y),
              ikon: switch (y) {
                SeviyeYon.yukari => Icons.arrow_upward_rounded,
                SeviyeYon.asagi => Icons.arrow_downward_rounded,
                SeviyeYon.herIkisi => Icons.swap_vert_rounded,
              },
              ikonRengi: switch (y) {
                SeviyeYon.yukari => c.gain,
                SeviyeYon.asagi => c.loss,
                SeviyeYon.herIkisi => null,
              },
              secili: _gostergeYon == y,
              onTap: () => setState(() {
                _gostergeYon = y;
                _hata = null;
              }),
            ),
        ],
      ),
      const SizedBox(height: SandikSpace.smd),
      Text(ozet, style: context.t.bodyMedium?.copyWith(color: c.amberText)),
      const SizedBox(height: SandikSpace.xs),
      Text(l10n.gostergeNot,
          style: context.t.bodySmall?.copyWith(color: c.text58)),
      if (_hata != null) ...[
        const SizedBox(height: SandikSpace.xs),
        Text(_hata!, style: context.t.bodyMedium?.copyWith(color: c.danger)),
      ],
    ];
  }

  /// "Her geçişte haber ver" anahtarı (0171). Bütün satır dokunma alanı
  /// (≥44 pt); ekran okuyucu satırı tek öğe okur (başlık + açıklama +
  /// anahtar durumu). Açık/kapalı yalnız renkle değil, anahtarın konumuyla
  /// da okunur (sistem kontrolü, `Switch.adaptive`).
  Widget _tekrarSatiri(SandikPalette c) {
    final l10n = context.l10n;
    void degistir(bool v) {
      SandikHaptic.selection.perform();
      setState(() => _tekrar = v);
    }

    return MergeSemantics(
      child: SandikTappable(
        key: const ValueKey('alarmTekrarSatiri'),
        onTap: () => degistir(!_tekrar),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.alarmTekrarAnahtar,
                      style: context.t.bodyMedium?.copyWith(
                          color: c.text90, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: SandikSpace.xxs),
                    // Tek satır (Ar-Ge 6 Kas, tasarım 4): yalnız sınır. Sınır
                    // sunucuda `GUNLUK_TAVAN = 3` (_shared/fiyat_alarmi_tekrar.ts);
                    // "geri dönüp yeniden geçerse" ayrıntısı alarm satırında.
                    Text(
                      l10n.alarmTekrarAciklama,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall?.copyWith(color: c.text58),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SandikSpace.sm),
              Switch.adaptive(
                key: const ValueKey('alarmTekrarAnahtari'),
                value: _tekrar,
                // TRACK rengi: iOS'ta `CupertinoSwitch` açık rengi track'te
                // taşır (bkz. sinyal ayarları anahtarı).
                activeTrackColor: c.amberText,
                onChanged: degistir,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Segmentteki kip etiketi; kilitli gösterge sekmesi kilit simgesi taşır
  /// (ƒx çipiyle aynı dil: görünür, dokununca Premium).
  Widget _kipEtiketi(_AlarmKipi k) {
    final l10n = context.l10n;
    final metin = Text(
      switch (k) {
        _AlarmKipi.fiyat => l10n.alarmModFiyat,
        _AlarmKipi.yuzde => l10n.alarmModYuzde,
        _AlarmKipi.gosterge => l10n.alarmModGosterge,
      },
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (k != _AlarmKipi.gosterge || !widget.gostergeKilitli) return metin;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline_rounded,
            size: SandikSpace.md, semanticLabel: l10n.alarmPremiumGerekli),
        const SizedBox(width: SandikSpace.xs),
        Flexible(child: metin),
      ],
    );
  }

  Future<void> _kaydetYuzde() async {
    final kurulum = YuzdeAlarmKurulumu(_secili, _esik, _yuzdeYon);
    final kur = widget.kurYuzde;
    if (kur != null) {
      final l10n = context.l10n;
      try {
        await kur(kurulum);
      } catch (e) {
        if (!mounted) return;
        setState(() => _hata = '${l10n.alertSetFailed}. ${friendlyError(e)}');
        return;
      }
      if (!mounted) return;
      // Yazma bitti: düğmede ✓, sonra kapanış. `kur` yoksa kaydı çağıran
      // sayfa kapandıktan SONRA yapar (başarısı burada bilinmez) → ✓ yok.
      await _basari.goster();
      if (!mounted) return;
    }
    Navigator.of(context).pop(kurulum);
  }

  String _yonAdi(YuzdeYon y) => switch (y) {
        YuzdeYon.dusus => context.l10n.alarmYonDusus,
        YuzdeYon.yukselis => context.l10n.alarmYonYukselis,
        YuzdeYon.ikisi => context.l10n.alarmYonIkisi,
      };

  /// "Günlük yüzde" kipinin gövdesi: eşik çipleri, yön çipleri, özet.
  /// Seçim çipi `SandikFiltreCipi` (tam yuvarlak, 44 pt, seçiliyken amber +
  /// onay işareti — tasarım dili "tek seçim"). Yön üç yoldan okunur: ok
  /// ikonu, fiil ("Düşerse") ve özet cümlesi; renk yalnız ikonda, ek bilgi.
  List<Widget> _yuzdeBolumu(SandikPalette c) {
    final l10n = context.l10n;
    final ozet = switch (_yuzdeYon) {
      YuzdeYon.dusus => l10n.alarmYuzdeOzetDusus(_secili.ad, _esik),
      YuzdeYon.yukselis => l10n.alarmYuzdeOzetYukselis(_secili.ad, _esik),
      YuzdeYon.ikisi => l10n.alarmYuzdeOzetIkisi(_secili.ad, _esik),
    };
    return [
      Text(l10n.alarmYuzdeEsikBaslik,
          style: context.t.labelMedium?.copyWith(color: c.text58)),
      const SizedBox(height: SandikSpace.xs),
      Wrap(
        spacing: SandikSpace.xs2,
        runSpacing: SandikSpace.xs2,
        children: [
          for (final e in YuzdeAlarmi.esikler)
            SandikFiltreCipi(
              ad: '±%$e',
              semantik: l10n.alarmYuzdeEsikSemantik(e),
              secili: _esik == e,
              onTap: () => setState(() {
                _esik = e;
                _hata = null;
              }),
            ),
        ],
      ),
      const SizedBox(height: SandikSpace.smd),
      Text(l10n.alarmYuzdeYonBaslik,
          style: context.t.labelMedium?.copyWith(color: c.text58)),
      const SizedBox(height: SandikSpace.xs),
      Wrap(
        spacing: SandikSpace.xs2,
        runSpacing: SandikSpace.xs2,
        children: [
          for (final y in YuzdeYon.values)
            SandikFiltreCipi(
              ad: _yonAdi(y),
              ikon: switch (y) {
                YuzdeYon.dusus => Icons.arrow_downward_rounded,
                YuzdeYon.yukselis => Icons.arrow_upward_rounded,
                YuzdeYon.ikisi => Icons.swap_vert_rounded,
              },
              ikonRengi: switch (y) {
                YuzdeYon.dusus => c.loss,
                YuzdeYon.yukselis => c.gain,
                YuzdeYon.ikisi => null,
              },
              secili: _yuzdeYon == y,
              onTap: () => setState(() {
                _yuzdeYon = y;
                _hata = null;
              }),
            ),
        ],
      ),
      const SizedBox(height: SandikSpace.smd),
      Text(ozet, style: context.t.bodyMedium?.copyWith(color: c.amberText)),
      const SizedBox(height: SandikSpace.xs),
      Text(l10n.alarmYuzdeGundeBir,
          style: context.t.bodySmall?.copyWith(color: c.text58)),
      if (_hata != null) ...[
        const SizedBox(height: SandikSpace.xs),
        Text(_hata!, style: context.t.bodyMedium?.copyWith(color: c.danger)),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hedef = _hedef;
    final ozet = alarmFiyatOzeti(context.l10n, _secili, hedef);
    final uzaklik = alarmFiyatUzakligi(_secili, hedef);
    final yukari = hedef != null && hedef > _secili.guncelFiyat;
    final fiyatVar = _secili.guncelFiyat > 0;
    final maliyet = _secili.maliyet;
    final maliyetCipleri = maliyet == null || maliyet <= 0 || !fiyatVar
        ? const <({int yuzde, double hedef})>[]
        : maliyetHedefleri(maliyet, _secili.guncelFiyat);
    final esit =
        hedef != null && alarmHedefiGuncelFiyatta(hedef, _secili.guncelFiyat);

    final kisa = MediaQuery.sizeOf(context).height < 480;
    // Klavye payı `showSandikSheet` kabuğunda (sheet standardı 2026-11-06);
    // yatay pay standart ekran kenarı: hedef sayfasıyla aynı (Ar-Ge 6 Kas
    // #2: alarm sabit 24, hedef `screenH` kullanıyordu).
    final kenar = SandikSpace.screenH(context);
    return Padding(
        padding: EdgeInsets.fromLTRB(
            kenar, SandikSpace.sm, kenar, SandikSpace.lg),
        // Kaydırılabilir: büyük yazıda (3,1×) form sayfa yüksekliğini aşıyor,
        // "Alarm kur" düğmesi ekranın altında kesiliyordu (büyük yazı
        // taraması 2026-10-12). Sığınca kaydırma yok, düzen aynı.
        // Düğme kaydırmanın DIŞINDA, altta sabit: yatay grafikten (390 pt
        // yükseklik) çizgi adıyla açılınca form sığmıyor, düğme kaydırmadan
        // görünmüyordu (e2e 2026-10-29). Kaydırılan yalnız form.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık seçilen varlıkla değiştiği için kabuğun `baslik:`'ı
                // değil, aynı stil bileşeni burada (sheet standardı).
                SandikSheetBasligi(widget.duzenle
                    ? context.l10n.alarmiDuzenle
                    : widget.sabit
                        ? context.l10n.alertForAsset(_secili.ad)
                        : 'Alarm kur'),
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
                // Maliyet bu satırda (tek çip satırı, 6 Kas): eskiden ikinci
                // çip satırının başlığıydı ("Maliyetine göre · ₺200,00").
                Text(
                  fiyatVar
                      ? [
                          context.l10n.currentlyPrice(alarmFiyatMetni(
                              _secili.guncelFiyat, _secili.sembol)),
                          if (maliyetCipleri.isNotEmpty)
                            context.l10n.alarmMaliyetin(
                                alarmFiyatMetni(maliyet!, _secili.sembol)),
                        ].join(' · ')
                      : context.l10n.currentPriceUnknown,
                  style: context.t.bodyMedium?.copyWith(color: c.text58),
                ),
                const SizedBox(height: SandikSpace.md),
                // Kip seçici (0169): yalnız günlük yüzdesi sunucuda ölçülen
                // adayda. Kayan segment = "mod değiştiren seçici" (tasarım dili);
                // hareketi azalt açıkken zemin anında yerine oturur.
                // 0170: üçüncü kip "Gösterge" (Premium); kilitliyse sekme
                // seçilmez, paywall açılır.
                if (_kipler.length > 1) ...[
                  SandikSegment(
                    key: const ValueKey('alarmKipSegmenti'),
                    adet: _kipler.length,
                    secili: _kipler.indexOf(_etkinKip),
                    onSec: (i) {
                      final k = _kipler[i];
                      if (k == _AlarmKipi.gosterge && widget.gostergeKilitli) {
                        widget.onGostergeKilitli?.call(context);
                        return;
                      }
                      // Çipli kiplerde klavye açık kalırsa çipleri örter.
                      if (k != _AlarmKipi.fiyat) FocusScope.of(context).unfocus();
                      setState(() {
                        _kip = k;
                        _hata = null;
                      });
                    },
                    oge: (_, i, __) => _kipEtiketi(_kipler[i]),
                  ),
                  const SizedBox(height: SandikSpace.md),
                ],
                if (_yuzdeAcik)
                  ..._yuzdeBolumu(c)
                else if (_gostergeAcik)
                  ..._gostergeBolumu(c)
                else ...[
                TextField(
                  controller: _controller,
                  autofocus: widget.odakla ?? widget.sabit,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Hedef fiyat',
                    errorText: _hata,
                    suffixText: uzaklik,
                    suffixStyle: context.t.titleSmall?.copyWith(
                      color: yukari ? c.gain : c.loss,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onChanged: (_) => setState(() => _hata = null),
                ),
                if (fiyatVar) ...[
                  const SizedBox(height: SandikSpace.smd),
                  _hizliCipler(c, maliyetCipleri),
                ],
                const SizedBox(height: SandikSpace.smd),
                // Eşit hedef: "çıkınca haber vereceğiz" demek yalan olurdu —
                // alarm hemen çalışır. Yön cümlesinin yerine uyarı (#24).
                if (esit && _hata == null)
                  Text(
                    context.l10n.alertTargetAtCurrent,
                    style: context.t.bodyMedium?.copyWith(color: c.danger),
                  )
                else if (ozet != null)
                  Text(
                    ozet,
                    key: const ValueKey('alarmFiyatOzeti'),
                    style: context.t.bodyMedium?.copyWith(color: c.amberText),
                  ),
                const SizedBox(height: SandikSpace.sm),
                _tekrarSatiri(c),
                if (widget.cizgiAdi) ...[
                  const SizedBox(height: SandikSpace.md),
                  // Ad isteğe bağlı; boşsa alarm varlığın adıyla kurulur.
                  TextField(
                    key: const ValueKey('cizgiAdiAlani'),
                    controller: _isim,
                    maxLength: kCizgiAdiAzami,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: context.l10n.cizgiAdiEtiket,
                      hintText: context.l10n.cizgiAdiIpucu,
                      // Kısa ekranda (yatay) açıklama ve sayaç yer kaplamasın;
                      // ipucu metni aynı şeyi söylüyor.
                      helperText: kisa ? null : context.l10n.cizgiAdiAciklama,
                      helperMaxLines: 2,
                      counterText: kisa ? '' : null,
                    ),
                  ),
                ],
                ],
                SizedBox(height: kisa ? SandikSpace.md : SandikSpace.lg),
                // İzin reddedilmişse alarm kurulur ama çalınca haber gelmez;
                // bunu kurarken söylemek (Ar-Ge 16:45 #1, 2026-10-21).
                const BildirimIzniUyarisi(
                    padding: EdgeInsets.only(bottom: SandikSpace.md)),
              ],
            ),
            ),
            ),
            SizedBox(
              width: double.infinity,
              child: SandikAsyncButton.kompakt(
                basari: _basari,
                style: FilledButton.styleFrom(
                  backgroundColor: c.amberFill,
                  foregroundColor: c.onAmber,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _yuzdeAcik
                    ? _kaydetYuzde
                    : _gostergeAcik
                        ? _kaydetGosterge
                        : _kaydet,
                child: Text(widget.duzenle
                    ? context.l10n.save
                    : context.l10n.setAlert),
              ),
            ),
            if (widget.onSil != null)
              TextButton.icon(
                key: const ValueKey('alarmiSil'),
                style: TextButton.styleFrom(
                  foregroundColor: c.danger,
                  minimumSize: const Size(0, SandikTouch.min),
                ),
                onPressed: widget.onSil,
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(context.l10n.alarmiSil),
              ),
          ],
        ),
    );
  }
}

/// Sheet'in kipleri: sabit hedef, günlük yüzde (0169), gösterge (0170).
enum _AlarmKipi { fiyat, yuzde, gosterge }

/// Bir alarm daha AKTİF olursa (yeni kurma ya da tetiklenmişi yeniden kurma)
/// sınır aşılır mı; aşılırsa uyarıyı gösterip true döner. Paywall açıkken
/// sınır satış kapısıdır: Premium yolu da gösterilir.
///
/// Neden ortak (paywall kapıları incelemesi, 2026-10-11): sınır yalnız bu
/// sayfada denetleniyordu; Alarmlar ekranı ve alarm şeridindeki "yeniden
/// kur" tetiklenmiş alarmları aktife döndürerek 20 sınırını aşıyordu.
///
/// Yüzde alarmı (0169) aynı tavana sayılır: kullanıcı için ikisi de "bir
/// alarm"; açık yüzde alarmı her gün nöbettedir, yani hep aktiftir.
/// Gösterge ve çizgi alarmı (0170) da sayılır: Premium'a özgü olsalar da
/// paywall kapalıyken (admin) ya da abonelik bitince tavan yine geçerli.
bool alarmSiniriDoluysaUyar(BuildContext context, WidgetRef ref) {
  final limit = ref.read(priceAlertLimitProvider);
  if (etkinAlarmSayisi(ref) < limit) return false;
  alarmSiniriUyarisi(context, ref, limit);
  return true;
}

/// Tavana sayılan alarm sayısı: aktif fiyat alarmları + açık yüzde
/// alarmları. Yüklenmemiş liste 0 sayılır (bilinmeyen sayı yüzünden
/// kimseyi durdurmayız — `ortakSiniriDoluProvider` ile aynı kural).
int etkinAlarmSayisi(WidgetRef ref) {
  final fiyat = ref.read(priceAlertsProvider).valueOrNull ?? const [];
  final yuzde = ref.read(yuzdeAlarmlariProvider).valueOrNull ?? const [];
  final gosterge = ref.read(gostergeAlarmlariProvider).valueOrNull ?? const [];
  final cizim = ref.read(cizimAlarmlariProvider).valueOrNull ?? const [];
  return fiyat.where((a) => a.isActive).length +
      yuzde.where((a) => a.isActive).length +
      gosterge.where((a) => a.isActive).length +
      cizim.where((a) => a.isActive).length;
}
