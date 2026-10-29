import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/demo_modu.dart';
import '../../l10n/l10n.dart';
import '../../models/asset.dart';
import '../../models/grafik_cizimi.dart';
import '../../models/seviye_alarmi.dart';
import '../../providers/auth_provider.dart';
import '../../providers/preferences_provider.dart' show premiumKilitliProvider;
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
///   türer, kullanıcı kaydetmeden önce görür. Alarm bundan sonra sıradan bir
///   fiyat alarmıdır: çizgi silinse de durur (Alarmlarım'dan silinir) —
///   `price_alerts`'e çizim bağı eklemek eski build'lerin okuduğu tabloyu
///   değiştirmek olurdu.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!sunulur(ref, cizim, varlik, canliBirim)) return const SizedBox.shrink();
    final sembol = cizimAlarmSembolu(varlik, canliBirim)!;
    final l10n = context.l10n;
    final c = context.c;
    final yatay = cizim.tur.tekNokta;
    final mevcut = yatay ? null : _mevcut(ref, sembol);
    final kilitli = !yatay && ref.watch(premiumKilitliProvider);
    final etiket = yatay
        ? l10n.tegAlarmKur
        : mevcut != null
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
            ? _yatay(context, ref, sembol)
            : _cizgi(context, ref, sembol, mevcut),
        child: SizedBox(
          width: SandikTouch.min,
          height: SandikTouch.min,
          child: Icon(
            mevcut != null
                ? Icons.notifications_active_rounded
                : kilitli
                    ? Icons.lock_outline_rounded
                    : Icons.add_alert_outlined,
            color: mevcut != null ? c.amberText : c.text90,
          ),
        ),
      ),
    );
  }

  Future<void> _yatay(BuildContext context, WidgetRef ref, String sembol) async {
    final kurulan = await alarmKurAkisi(
      context,
      ref,
      sabit: AlarmAdayi(sembol, ad, canliBirim),
      baslangicHedef: cizim.a.p,
      odakla: false,
    );
    if (kurulan != null) OzellikOlcumu.say(Ozellik.yatayCizgiAlarm);
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

/// Çizimler değişti (taşındı, silindi, geri alındı): bu sembolün çizgi
/// alarmlarını çizimlerle eşitler.
///
/// - Çizimi artık olmayan alarm silinir (kullanıcı çizgiyi sildi).
/// - Çizimi taşınmış etkin alarm yeni doğruya geçer; yeni doğru alarm
///   kuramıyorsa (çizgi geçmişte bitti) silinir ve [bildir] söyler.
/// - Çalmış (kapanmış) alarmın çizimi taşındıysa dokunulmaz: liste geçmişi.
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
}) async {
  final sembol = cizimAlarmSembolu(varlik, canliBirim);
  if (sembol == null) return;
  final alarmlar = [
    for (final a in ref.read(cizimAlarmlariProvider).valueOrNull ?? const <CizimAlarmi>[])
      if (a.symbol == sembol) a,
  ];
  if (alarmlar.isEmpty) return;
  final n = ref.read(cizimAlarmlariProvider.notifier);
  var silinen = 0;
  for (final a in alarmlar) {
    final c = cizimler.where((x) => x.id == a.cizimId).firstOrNull;
    try {
      if (c == null) {
        await n.delete(a.id);
        if (a.isActive) silinen += 1;
        continue;
      }
      if (!a.isActive || olcek == null || cizimImzasi(c) == a.cizimImzasi) {
        continue;
      }
      final simdi = DateTime.now();
      final d = cizimAlarmDogrusu(c,
              indeks: olcek.zamanIndeksi,
              aralikMs: olcek.aralikMs,
              simdiMs: simdi.millisecondsSinceEpoch)
          ?.dogru;
      if (d == null) {
        await n.delete(a.id);
        silinen += 1;
        continue;
      }
      await n.tasi(
        a.id,
        CizimAlarmi(
          id: a.id,
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
          createdAt: a.createdAt,
        ),
      );
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'cizimAlarmi.esitle');
    }
  }
  if (silinen > 0) bildir(l10n.tegAlarmSilindi);
}
