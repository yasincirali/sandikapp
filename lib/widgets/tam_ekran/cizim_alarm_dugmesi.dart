import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/demo_modu.dart';
import '../../l10n/l10n.dart';
import '../../models/asset.dart';
import '../../models/grafik_cizimi.dart';
import '../../models/price_alert.dart';
import '../../models/seviye_alarmi.dart';
import '../../providers/auth_provider.dart';
import '../../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../../providers/price_alert_provider.dart';
import '../../providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import '../../providers/seviye_alarmi_provider.dart';
import '../../screens/paywall_screen.dart' show PaywallScreen;
import '../../services/cizim_alarmi.dart';
import '../../services/crash_reporter.dart';
import '../../services/ozellik_olcumu.dart';
import '../../theme/sandik.dart';
import '../../utils/friendly_error.dart' show showAppError;
import '../alarm_kur_sheet.dart';
import '../sandik_async_button.dart';
import 'grafik_olcegi.dart';

/// Yatay grafikte seçili çizimin üstündeki "Alarm kur" düğmesi (0170).
///
/// ## Neden (yasin, 2026-10-29)
/// *"Gösterge ya da çizgiye değdiğinde push gelmesi yapılabilir mi?"* —
/// TradingView'in çizim araç çubuğundaki zil. İki yol:
/// - **Yatay çizgi / yatay ışın → normal fiyat alarmı** (ücretsiz, 20
///   alarm tavanı içinde). Var olan alarm sayfası çizginin fiyatıyla ön
///   dolu açılır ([alarmKurAkisi], `baslangicHedef`); yön güncel fiyattan
///   türer, kullanıcı kaydetmeden önce görür. Alarm sıradan bir fiyat
///   alarmıdır (Alarmlarım'da öyle görünür) ama çizgiye BAĞLIDIR
///   (2026-10-29, uçtan uca test: bağ yokken zil dolmuyor, ikinci dokunuş
///   ikinci alarm açıyor, çizgi silinince alarm ortada kalıyordu). Bağ
///   cihazda tutulur ([yatayAlarmBaglariProvider]): `price_alerts`'e çizim
///   kolonu eklemek eski build'lerin okuduğu tabloyu değiştirmek olurdu,
///   çizim zaten cihazda yaşıyor. Zil trend çizgisindeki gibi durum taşır
///   (ikinci dokunuş kaldırır); çizgi taşınınca hedef, silinince alarm
///   gider, geri al alarmı da geri getirir ([cizimAlarmlariniEsitle]).
/// - **Trend çizgisi / ışın → çizgi alarmı** (Premium, `cizim_alarmlari`).
///   Tek dokunuş kurar, ikinci dokunuş kaldırır (TradingView'deki gibi zil
///   durum taşır). Çizim taşınınca/silinince alarm da taşınır/silinir
///   ([cizimAlarmlariniEsitle]).
///
/// Kutu (dikdörtgen) için alarm yok: "kutuya girince" ayrı bir soru.
///
/// ## Birim
/// Yalnız grafiğin birimi alarmın birimiyle aynıysa ([cizimAlarmSembolu]:
/// TL kote semboller) görünür; değilse düğme hiç çizilmez.
///
/// ## Paylaşım görseli
/// Bu düğme yalnız seçim çubuğunda yaşar; seçim çubuğu paylaşım kipinde
/// çizilmez (`tam_ekran_grafik_paylas_test`). Grafiğe alarm çizgisi
/// çizilmez — kişisel katman eklenmedi.
class CizimAlarmDugmesi extends ConsumerWidget {
  const CizimAlarmDugmesi({
    super.key,
    required this.cizim,
    required this.varlik,
    required this.ad,
    required this.canliBirim,
    required this.olcek,
    required this.kimlikVer,
    required this.bildir,
  });

  final GrafikCizimi cizim;
  final Asset varlik;

  /// Alarmda ve bildirimde okunan ad.
  final String ad;

  /// Grafiğin canlı birim fiyatı (yön ve birim denetimi).
  final double canliBirim;
  final GrafikOlcegi olcek;

  /// Çizimin kimliği yoksa verir, kaydeder ve döndürür.
  final String Function() kimlikVer;

  /// Grafiğin kısa bildirim satırı (yatay ekranda snackbar yerine).
  final void Function(String metin) bildir;

  /// Bu çizimde düğme görünür mü (seçim çubuğunun genişliği için de).
  static bool sunulur(WidgetRef ref, GrafikCizimi c, Asset varlik,
      double canliBirim) {
    if (cizimAlarmSembolu(varlik, canliBirim) == null) return false;
    if (c.tur.tekNokta) return true;
    if (c.tur == CizimTuru.trend || c.tur == CizimTuru.isin) {
      return ref.watch(premiumOzellikleriGorunurProvider);
    }
    return false;
  }

  CizimAlarmi? _mevcut(WidgetRef ref, String sembol) {
    final id = cizim.id;
    if (id == null) return null;
    return (ref.watch(cizimAlarmlariProvider).valueOrNull ?? const [])
        .where((a) => a.symbol == sembol && a.cizimId == id && a.isActive)
        .firstOrNull;
  }

  /// Yatay çizginin bağlı, hâlâ nöbetteki fiyat alarmı. Çalmış alarm
  /// zili doldurmaz: dokunuş yeni alarm kurar, bağ yenisine geçer.
  PriceAlert? _yatayMevcut(WidgetRef ref) {
    final id = cizim.id;
    if (id == null) return null;
    final bag = ref.watch(yatayAlarmBaglariProvider)[id];
    if (bag == null) return null;
    return (ref.watch(priceAlertsProvider).valueOrNull ?? const [])
        .where((a) => a.id == bag.alarmId && a.isActive)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!sunulur(ref, cizim, varlik, canliBirim)) return const SizedBox.shrink();
    final sembol = cizimAlarmSembolu(varlik, canliBirim)!;
    final l10n = context.l10n;
    final c = context.c;
    final yatay = cizim.tur.tekNokta;
    final mevcut = yatay ? null : _mevcut(ref, sembol);
    final yatayMevcut = yatay ? _yatayMevcut(ref) : null;
    final aktif = mevcut != null || yatayMevcut != null;
    final kilitli = !yatay && ref.watch(premiumKilitliProvider);
    final etiket = aktif
        ? l10n.tegAlarmKaldir
        : kilitli
            ? l10n.tegAlarmKurPremium
            : l10n.tegAlarmKur;
    return Tooltip(
      message: etiket,
      child: SandikAsyncTap(
        key: const ValueKey('tamEkranCizimAlarmi'),
        semanticLabel: etiket,
        onTap: () => yatay
            ? _yatay(context, ref, sembol, yatayMevcut)
            : _cizgi(context, ref, sembol, mevcut),
        child: SizedBox(
          width: SandikTouch.min,
          height: SandikTouch.min,
          child: Icon(
            aktif
                ? Icons.notifications_active_rounded
                : kilitli
                    ? Icons.lock_outline_rounded
                    : Icons.add_alert_outlined,
            color: aktif ? c.amberText : c.text90,
          ),
        ),
      ),
    );
  }

  Future<void> _yatay(BuildContext context, WidgetRef ref, String sembol,
      PriceAlert? mevcut) async {
    final l10n = context.l10n;
    final baglar = ref.read(yatayAlarmBaglariProvider.notifier);
    if (mevcut != null) {
      // Zil durum taşır (trend çizgisiyle aynı): ikinci dokunuş kaldırır.
      // Hedefi değiştirmek çizgiyi sürüklemektir; ayrı düzenleme sayfası
      // aynı işi ikinci yoldan yapardı.
      if (DemoModu.yazmaKapisi('alarm')) return;
      try {
        await ref.read(priceAlertsProvider.notifier).delete(mevcut.id);
        final id = cizim.id;
        if (id != null) baglar.coz(id);
        bildir(l10n.tegAlarmKaldirildi);
      } catch (e) {
        if (context.mounted) showAppError(context, e);
      }
      return;
    }
    // Kimlik sayfa açılmadan verilir: sayfa modal, kapanınca seçim aynı
    // çizimde ama `kimlikVer` seçili çizime bakar — beklemeden almak
    // güvenli. Vazgeçilirse kimlik yine de kalır; zararsız.
    final id = cizim.id ?? kimlikVer();
    final kurulan = await alarmKurAkisi(
      context,
      ref,
      sabit: AlarmAdayi(sembol, ad, canliBirim),
      baslangicHedef: cizim.a.p,
      odakla: false,
    );
    if (kurulan == null) return;
    baglar.bagla(id, kurulan.id, cizim.a.p);
    OzellikOlcumu.say(Ozellik.yatayCizgiAlarm);
  }

  Future<void> _cizgi(BuildContext context, WidgetRef ref, String sembol,
      CizimAlarmi? mevcut) async {
    final l10n = context.l10n;
    if (DemoModu.yazmaKapisi('alarm')) return;
    final n = ref.read(cizimAlarmlariProvider.notifier);
    try {
      if (mevcut != null) {
        // Zil durum taşır: ikinci dokunuş kaldırır.
        await n.delete(mevcut.id);
        bildir(l10n.tegAlarmKaldirildi);
        return;
      }
      if (ref.read(premiumKilitliProvider)) {
        await PaywallScreen.show(context, source: 'cizim_alarmi');
        return;
      }
      if (alarmSiniriDoluysaUyar(context, ref)) return;
      final simdi = DateTime.now();
      final sonuc = cizimAlarmDogrusu(cizim,
          indeks: olcek.zamanIndeksi,
          aralikMs: olcek.aralikMs,
          simdiMs: simdi.millisecondsSinceEpoch);
      final d = sonuc?.dogru;
      if (d == null) {
        bildir(switch (sonuc?.engel) {
          CizimAlarmEngeli.bitti => l10n.tegAlarmBitti,
          CizimAlarmEngeli.gecersiz => l10n.tegAlarmGecersiz,
          _ => l10n.tegAlarmYonsuz,
        });
        return;
      }
      final me = ref.read(authProvider).valueOrNull;
      if (me == null) return;
      final id = cizim.id ?? kimlikVer();
      final yon = SeviyeYon.fiyattan(guncel: canliBirim, seviye: d.p1);
      await n.create(CizimAlarmi(
        id: '',
        userId: me.id,
        symbol: sembol,
        label: ad,
        cizimId: id,
        cizimImzasi: cizimImzasi(cizim),
        t1: d.t1,
        p1: d.p1,
        t2: d.t2,
        p2: d.p2,
        uzanir: d.uzanir,
        yon: yon,
        createdAt: simdi,
      ));
      OzellikOlcumu.say(Ozellik.cizimAlarm);
      bildir(switch (yon) {
        SeviyeYon.yukari => l10n.tegAlarmKurulduUst,
        SeviyeYon.asagi => l10n.tegAlarmKurulduAlt,
        SeviyeYon.herIkisi => l10n.tegAlarmKurulduIkisi,
      });
    } catch (e) {
      if (context.mounted) showAppError(context, e);
    }
  }
}

/// Çizimle birlikte silinen alarmların geri al için saklandığı yer —
/// yatay grafik ekranı açık kaldıkça yaşar (ekranın geri al geçmişi de öyle).
///
/// ## Neden (uçtan uca test, 2026-10-29)
/// "Bu grafikteki tüm çizimleri sil" çizgi alarmını da siliyordu (doğru)
/// ama "Geri al" yalnız çizimleri getiriyordu; bildirim "geri al ile geri
/// getirebilirsin" diyordu. Silinen satır burada çizim kimliğiyle durur;
/// çizim geri gelince ([cizimAlarmlariniEsitle]) alarm yeniden kurulur.
/// Geri al çizimi aynı kimlikle döndürdüğü için eşleme kimlik üzerinden.
///
/// Yalnız NÖBETTEKİ alarm geri gelir: çalmış satır geçmiştir, yeniden
/// kurmak kullanıcının istemediği bir nöbet açardı.
class CizimAlarmCopu {
  /// Trend/ışın alarmları (`cizim_alarmlari`), çizim kimliğine göre.
  final Map<String, CizimAlarmi> cizgi = {};

  /// Yatay çizgi fiyat alarmları (`price_alerts`), çizim kimliğine göre.
  final Map<String, PriceAlert> yatay = {};

  /// Eşitlemeler sırayla koşar: "sil" ardından hızlı "geri al" iki eşitlemeyi
  /// üst üste başlatır; ikincisi birincinin silmesini görmeden bakarsa alarm
  /// ne silinmiş ne geri gelmiş sayılır ve kaybolurdu.
  Future<void> _sira = Future.value();

  Future<void> sirala(Future<void> Function() isle) {
    final f = _sira.then((_) => isle());
    _sira = f.catchError((_) {});
    return f;
  }
}

/// Çizimler değişti (taşındı, silindi, geri alındı): bu sembolün çizgi
/// alarmlarını ve yatay çizgi fiyat alarmlarını çizimlerle eşitler.
///
/// - Çizimi artık olmayan alarm silinir (kullanıcı çizgiyi sildi); nöbetteyse
///   [cop]'a konur.
/// - [cop]'taki alarmın çizimi geri geldiyse (geri al) alarm yeniden kurulur.
/// - Çizimi taşınmış etkin alarm yeni doğruya geçer; yeni doğru alarm
///   kuramıyorsa (çizgi geçmişte bitti) silinir ve [bildir] söyler. Yatay
///   çizgide hedef çizginin yeni fiyatına, yön güncel fiyata göre geçer.
/// - Çalmış (kapanmış) alarmın çizimi taşındıysa dokunulmaz: liste geçmişi.
///
/// Notifier'lar çağrı anında alınır: sıradaki eşitleme ekran kapandıktan
/// sonra koşabilir, o zaman `ref` artık okunamaz.
///
/// Arka planda koşar; hata Crashlytics'e gider, çizim kaydını durdurmaz.
Future<void> cizimAlarmlariniEsitle(
  WidgetRef ref, {
  required Asset varlik,
  required double canliBirim,
  required List<GrafikCizimi> cizimler,
  required GrafikOlcegi? olcek,
  required void Function(String metin) bildir,
  required AppLocalizations l10n,
  CizimAlarmCopu? cop,
}) {
  final sembol = cizimAlarmSembolu(varlik, canliBirim);
  if (sembol == null) return Future.value();
  final cizgiN = ref.read(cizimAlarmlariProvider.notifier);
  final fiyatN = ref.read(priceAlertsProvider.notifier);
  final bagN = ref.read(yatayAlarmBaglariProvider.notifier);
  Future<void> isle() => _esitle(
        sembol: sembol,
        canliBirim: canliBirim,
        cizimler: cizimler,
        olcek: olcek,
        bildir: bildir,
        l10n: l10n,
        cop: cop,
        cizgiN: cizgiN,
        fiyatN: fiyatN,
        bagN: bagN,
      );
  return cop == null ? isle() : cop.sirala(isle);
}

Future<void> _esitle({
  required String sembol,
  required double canliBirim,
  required List<GrafikCizimi> cizimler,
  required GrafikOlcegi? olcek,
  required void Function(String metin) bildir,
  required AppLocalizations l10n,
  required CizimAlarmCopu? cop,
  required CizimAlarmlariNotifier cizgiN,
  required PriceAlertsNotifier fiyatN,
  required YatayAlarmBaglariNotifier bagN,
}) async {
  final cizimIle = {
    for (final c in cizimler)
      if (c.id != null) c.id!: c,
  };
  var silinen = 0;
  var gelen = 0;

  CizimDogrusu? dogru(GrafikCizimi c) => olcek == null
      ? null
      : cizimAlarmDogrusu(c,
              indeks: olcek.zamanIndeksi,
              aralikMs: olcek.aralikMs,
              simdiMs: DateTime.now().millisecondsSinceEpoch)
          ?.dogru;

  // ── Trend / ışın alarmları ──────────────────────────────────────────
  for (final a in [
    for (final x in cizgiN.liste)
      if (x.symbol == sembol) x,
  ]) {
    final c = cizimIle[a.cizimId];
    try {
      if (c == null) {
        await cizgiN.delete(a.id);
        if (a.isActive) {
          silinen += 1;
          cop?.cizgi[a.cizimId] = a;
        }
        continue;
      }
      if (!a.isActive || olcek == null || cizimImzasi(c) == a.cizimImzasi) {
        continue;
      }
      final d = dogru(c);
      if (d == null) {
        await cizgiN.delete(a.id);
        silinen += 1;
        continue;
      }
      await cizgiN.tasi(a.id, _cizgiAlarmi(a, c, d, canliBirim));
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'cizimAlarmi.esitle');
    }
  }
  // Geri al: çizimi dönen alarm yeniden kurulur. Ölçek yoksa (grafik
  // yüklenmedi) silinen doğru aynen yazılır — çizim aynı çizim.
  if (cop != null) {
    for (final e in cop.cizgi.entries.toList()) {
      final c = cizimIle[e.key];
      if (c == null) continue;
      cop.cizgi.remove(e.key);
      if (cizgiN.liste.any((x) => x.symbol == sembol && x.cizimId == e.key)) {
        continue;
      }
      final eski = e.value;
      final d = olcek == null
          ? (t1: eski.t1, p1: eski.p1, t2: eski.t2, p2: eski.p2, uzanir: eski.uzanir)
          : dogru(c);
      if (d == null) continue; // Çizgi bu arada geçmişte bitti.
      try {
        await cizgiN.create(_cizgiAlarmi(eski, c, d, canliBirim,
            id: '', createdAt: DateTime.now()));
        gelen += 1;
      } catch (e, st) {
        CrashReporter.report(e, st, reason: 'cizimAlarmi.geriAl');
      }
    }
  }

  // ── Yatay çizgi fiyat alarmları ─────────────────────────────────────
  await bagN.yuklendi;
  // Liste gelmeden "alarm yok" denmez: bağ yanlışlıkla çözülür, geri al
  // eşleşmesi kaybolurdu.
  if (fiyatN.yuklendi) {
    for (final e in bagN.baglar.entries.toList()) {
      final alarm =
          fiyatN.liste.where((a) => a.id == e.value.alarmId).firstOrNull;
      if (alarm == null) {
        // Alarmlarım'dan silinmiş: bağ da gider (zil boşalır).
        bagN.coz(e.key);
        continue;
      }
      if (alarm.symbol != sembol) continue;
      final c = cizimIle[e.key];
      try {
        if (c == null) {
          await fiyatN.delete(alarm.id);
          bagN.coz(e.key);
          if (alarm.isActive) {
            silinen += 1;
            cop?.yatay[e.key] = alarm;
          }
          continue;
        }
        if (!alarm.isActive || c.a.p == e.value.fiyat) continue;
        // Çizgi taşındı: alarm aynı satırda yeni seviyeye geçer.
        await fiyatN.hedefiGuncelle(
            alarm.id,
            c.a.p,
            PriceAlert.suggestDirection(
                currentPrice: canliBirim, targetPrice: c.a.p));
        bagN.bagla(e.key, alarm.id, c.a.p);
      } catch (e, st) {
        CrashReporter.report(e, st, reason: 'cizimAlarmi.yatayEsitle');
      }
    }
    if (cop != null) {
      for (final e in cop.yatay.entries.toList()) {
        final c = cizimIle[e.key];
        if (c == null) continue;
        cop.yatay.remove(e.key);
        if (bagN.baglar.containsKey(e.key)) continue;
        final eski = e.value;
        try {
          // Tavan denetlenmez: alarm az önce aynı eylemle silindi, geri al
          // tavanı aşmaz (arada başka alarm kurulduysa sunucu yine karar
          // verir).
          final yeni = await fiyatN.create(PriceAlert(
            id: '',
            userId: eski.userId,
            symbol: eski.symbol,
            label: eski.label,
            targetPrice: c.a.p,
            direction: PriceAlert.suggestDirection(
                currentPrice: canliBirim, targetPrice: c.a.p),
            enabled: true,
            createdAt: DateTime.now(),
          ));
          bagN.bagla(e.key, yeni.id, c.a.p);
          gelen += 1;
        } catch (e, st) {
          CrashReporter.report(e, st, reason: 'cizimAlarmi.yatayGeriAl');
        }
      }
    }
  }
  if (silinen > 0) bildir(l10n.tegAlarmSilindi);
  if (gelen > 0) bildir(l10n.tegAlarmGeriGeldi);
}

CizimAlarmi _cizgiAlarmi(
        CizimAlarmi a, GrafikCizimi c, CizimDogrusu d, double canliBirim,
        {String? id, DateTime? createdAt}) =>
    CizimAlarmi(
      id: id ?? a.id,
      userId: a.userId,
      symbol: a.symbol,
      label: a.label,
      cizimId: a.cizimId,
      cizimImzasi: cizimImzasi(c),
      t1: d.t1,
      p1: d.p1,
      t2: d.t2,
      p2: d.p2,
      uzanir: d.uzanir,
      yon: SeviyeYon.fiyattan(guncel: canliBirim, seviye: d.p1),
      createdAt: createdAt ?? a.createdAt,
    );
