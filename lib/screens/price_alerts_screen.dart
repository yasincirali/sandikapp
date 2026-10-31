import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/alarm_mesafesi.dart';
import '../models/asset.dart';
import '../models/position.dart';
import '../models/asset_type.dart' show alarmFiyatSimgesi;
import '../models/price_alert.dart';
import '../models/seviye_alarmi.dart';
import '../models/yuzde_alarmi.dart';
import '../providers/portfolio_provider.dart';
import '../providers/price_alert_provider.dart';
import '../providers/seviye_alarmi_provider.dart';
import '../providers/watchlist_provider.dart';
import '../providers/yuzde_alarmi_provider.dart';
import '../services/alarm_onbellegi.dart';
import '../services/analytics_service.dart';
import '../services/cizim_alarmi.dart'
    show cizgiAlarmEtiketi, cizgiEtiketiniAyir, yatayAlarmCizimi;
import '../services/notification_service.dart';
import '../services/crash_reporter.dart';
import '../widgets/cizgi_adi_sayfasi.dart';
import '../utils/sandik_snack.dart';
import '../widgets/bildirim_izni_uyarisi.dart';
import '../widgets/sandik_bos_durum.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../widgets/kapanan_satir.dart';
import '../widgets/alarm_kur_sheet.dart';
import '../widgets/sandik_baglam_menusu.dart';
import '../widgets/sandik_cam.dart';
import '../widgets/tek_dokunus_alarm.dart'
    show tekDokunusYuzdeAlarmiKur, yuzdeAlarmiOnerilsinMi;
import '../widgets/sandik_acilir.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_async_button.dart';
import '../widgets/sandik_skeleton.dart';
import '../utils/tr_format.dart';
import '../widgets/sandik_error_view.dart';
import '../l10n/l10n.dart';

/// Fiyat alarmları — tüm alarmların LİSTESİ.
///
/// **Neden bu ekran değerli:** alarm, kullanıcının KENDİSİNİN istediği tek
/// bildirimdir. Alaka garantili, opt-out riski yok, ve alarm kuran kullanıcı
/// uygulamayı kurulu bırakmak için bir sebep edinir.
///
/// 2026-09-14: asıl kurma yeri varlık ekranındaki zil oldu (alarm varlığa
/// aittir; üç ekran uzaktaki bir listeden kurulmaz). Burası Bildirimler
/// altında yaşayan genel liste; buradan da kurulabilir (sembol seçtirir).
/// Liste durumu `priceAlertsProvider`'da — varlık ekranı ve Portföy
/// kartındaki zil rozeti aynı kaynağı okur.
///
/// **Sembol seçimi arama değil, kendi varlıklarından.** Kullanıcı sahip
/// olduğu ya da izlediği şeye alarm kurar; boş bir arama kutusu hem fazladan
/// bir adım hem de kaynağın tanımadığı bir sembol girme riski demekti.
///
/// 2026-10-27 (0169): günlük yüzde alarmları da bu listede, fiyat
/// alarmlarıyla tek zaman sırasında (en yeni önce). Ayrı bölüm açılmadı:
/// kullanıcı için ikisi de "kurduğum alarm"; satır türünü kendi etiketiyle
/// söyler ("Günlük %2 düşüş").
///
/// 2026-10-29 (0170): gösterge ("EMA50 · yukarı keserse") ve çizgi
/// ("Çizgi alarmı · üstüne çıkınca") alarmları da aynı listede, aynı
/// gerekçeyle. Çizgi alarmı yatay grafikte çizimden kurulur; burada
/// görünür ve silinir.
///
/// 2026-10-29 (yasin: "Çizgi alarmında isim verebilelim. Ve bildirime ve
/// alarma tıkladığımızda çizgiyi izleyebilelim"): çizgi alarmı satırı (ve
/// yatay çizgiye bağlı fiyat alarmı satırı) dokununca çizgiyi yatay
/// grafikte açar ([NotificationService.openCizgi], push'la aynı varış) ve
/// kalem düğmesiyle yeniden adlandırılır. Ad `label`'da "varlık · ad".
/// Listedeki bir satır: tam olarak bir alan dolu.
typedef _Satir = ({
  DateTime t,
  PriceAlert? f,
  YuzdeAlarmi? y,
  GostergeAlarmi? g,
  CizimAlarmi? c,
});

class PriceAlertsScreen extends ConsumerStatefulWidget {
  const PriceAlertsScreen({super.key, this.sembol});

  /// Verilirse liste yalnız bu sembolün alarmlarını gösterir (takip listesi
  /// satırındaki çan, 2026-10-26: "bu varlığın alarmları"). `null` → eski
  /// davranış birebir: tüm alarmlar. Sembol `alarmSembolu` kuralındadır.
  final String? sembol;

  @override
  ConsumerState<PriceAlertsScreen> createState() => _PriceAlertsScreenState();
}

class _PriceAlertsScreenState extends ConsumerState<PriceAlertsScreen> {
  /// Çalanlar grubu kapalı açılır: liste "neyi bekliyorum"u cevaplar.
  bool _calanlarAcik = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView(screenName: 'price_alerts');
  }

  /// Alarm kurulabilecek semboller: portföydeki aktif alımlar + takip listesi.
  List<AlarmAdayi> _adaylar() {
    final out = <String, AlarmAdayi>{};

    // `aktifLotlar`: tamamen satılmış pozisyonlar elenir. Ham `isActive`
    // filtresi yetmiyordu — satılan hissenin alım lot'u defterde durduğu
    // için kullanıcı artık tutmadığı bir sembol için alarm kurabiliyordu.
    final assets = aktifLotlar(
        ref.read(portfolioProvider).valueOrNull?.assets ?? const []);
    final sembolLotlari = <String, List<Asset>>{};
    for (final a in assets) {
      final sembol = alarmSembolu(a.ticker, a.subCategory);
      if (sembol == null) continue;
      (sembolLotlari[sembol] ??= []).add(a);
      if (!a.isBuy) continue;
      out[sembol] = AlarmAdayi(sembol, a.name, a.currentPrice);
    }
    // Portföydeki adayın maliyeti (maliyet çipleri, 2026-10-23); satış
    // lot'ları da girer ki ortalama pozisyonun bugünkü hâlini yazsın.
    for (final e in out.entries.toList()) {
      final a = e.value;
      out[e.key] = AlarmAdayi(a.sembol, a.ad, a.guncelFiyat,
          maliyet: alarmMaliyeti(sembolLotlari[e.key] ?? const []));
    }

    final watch = ref.read(watchlistProvider).valueOrNull ?? const [];
    for (final w in watch) {
      final sembol = alarmSembolu(w.ticker, w.subCategory);
      if (sembol == null) continue;
      out.putIfAbsent(
        sembol,
        () => AlarmAdayi(sembol, w.name, w.currentPrice ?? 0),
      );
    }

    final liste = out.values.toList()
      ..sort((a, b) => a.ad.toLowerCase().compareTo(b.ad.toLowerCase()));
    return liste;
  }

  Future<void> _yenile() => Future.wait([
        ref.read(priceAlertsProvider.notifier).refresh(),
        ref.read(yuzdeAlarmlariProvider.notifier).refresh(),
        ref.read(gostergeAlarmlariProvider.notifier).refresh(),
        ref.read(cizimAlarmlariProvider.notifier).refresh(),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final alarmlar = ref.watch(priceAlertsProvider);
    // Yüzde listesi hata vermez (okuma hatası boş liste, bkz. provider);
    // yüklenirken fiyat alarmları beklemeden görünür.
    final yuzdeHepsi =
        ref.watch(yuzdeAlarmlariProvider).valueOrNull ?? const <YuzdeAlarmi>[];
    // Gösterge ve çizgi alarmları (0170): aynı kural, okuma hatası boş liste.
    final gostergeHepsi = ref.watch(gostergeAlarmlariProvider).valueOrNull ??
        const <GostergeAlarmi>[];
    final cizimHepsi =
        ref.watch(cizimAlarmlariProvider).valueOrNull ?? const <CizimAlarmi>[];
    // Grup başlığındaki güncel fiyat ve satırdaki mesafe portföy/takip
    // listesinin fiyatından ([_adaylar]); fiyat tazelenince liste de.
    ref.watch(portfolioProvider);
    ref.watch(watchlistProvider);
    return Scaffold(
      backgroundColor: c.background,
      appBar: SandikAppBar(
        // "Alarmlarım" (uçtan uca test 2026-10-29): liste artık yalnız fiyat
        // alarmı değil — yüzde, gösterge ve çizgi alarmları da burada.
        // Ana sayfadaki giriş de aynı adı taşır (`myAlarms`).
        title: context.l10n.myAlarms,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.amberFill,
        foregroundColor: c.onAmber,
        // Tema FAB'ı `CircleBorder` yapıyor (main.dart); uzatılmış FAB'a da
        // uygulanınca simge ve yazı dairenin dışına taşıyordu (kullanıcı
        // ekran görüntüsü, 2026-09-21). Uzatılmış biçim stadyum ister.
        shape: const StadiumBorder(),
        extendedPadding:
            const EdgeInsets.symmetric(horizontal: SandikSpace.lgs),
        onPressed: () {
          // Süzülmüş listede yeni alarm o sembol için kurulur; sembol aday
          // değilse (takipten çıkmış) genel seçime düşer.
          final adaylar = _adaylar();
          final sabit = widget.sembol == null
              ? null
              : adaylar.where((a) => a.sembol == widget.sembol).firstOrNull;
          alarmKurAkisi(context, ref, sabit: sabit, adaylar: adaylar);
        },
        icon: const Icon(Icons.add_alert_rounded),
        label: Text(context.l10n.createAlert),
      ),
      body: SandikIcerikGecisi(
        // Yükleme → içerik çapraz solar (2026-10-14).
        tamEkran: true,
        anahtar: SandikIcerikGecisi.hal([alarmlar]),
        child: alarmlar.when(
          error: (e, _) => SandikErrorView(
            error: e,
            onRetry: _yenile,
          ),
          loading: () => const SandikSkeletonList(rows: 5),
          data: (hepsi) {
            final s = widget.sembol;
            final fiyatListe = s == null
                ? hepsi
                : [
                    for (final a in hepsi)
                      if (a.symbol == s) a
                  ];
            final yuzdeListe = s == null
                ? yuzdeHepsi
                : [
                    for (final a in yuzdeHepsi)
                      if (a.symbol == s) a
                  ];
            // Tek zaman sırası, en yeni önce; eşitlikte fiyat alarmı önde
            // (`List.sort` kararlı değil; liste yenilenince zıplamasın).
            final liste = <_Satir>[
              for (final a in fiyatListe)
                (t: a.createdAt, f: a, y: null, g: null, c: null),
              for (final a in yuzdeListe)
                (t: a.createdAt, f: null, y: a, g: null, c: null),
              for (final a in gostergeHepsi)
                if (s == null || a.symbol == s)
                  (t: a.createdAt, f: null, y: null, g: a, c: null),
              for (final a in cizimHepsi)
                if (s == null || a.symbol == s)
                  (t: a.createdAt, f: null, y: null, g: null, c: a),
            ];
            liste.sort((a, b) {
              final z = b.t.compareTo(a.t);
              if (z != 0) return z;
              return (a.f == null ? 1 : 0) - (b.f == null ? 1 : 0);
            });
            if (liste.isEmpty) return _bosDurum(context, yuzdeHepsi);
            // Bekleyenler üstte, çalmışlar altta katlı grupta (Ar-Ge 29 Eki
            // 16:45 #2). Çalmış fiyat/gösterge/çizgi alarmı silinene kadar
            // listede kalıyordu; bir ay sonra bekleyen birkaç alarm onlarca
            // çalmış satırın arasında kayboluyordu. Yüzde alarmı "çalmış"
            // sayılmaz: ertesi gün kendiliğinden nöbette, bekleyenlerde
            // kalır. Çalmış yoksa liste eskisi gibi başlıksız tek grup.
            final bekleyen = [
              for (final r in liste)
                if (_calmaAni(r) == null) r
            ];
            final calan = [
              for (final r in liste)
                if (_calmaAni(r) != null) r
            ]..sort((a, b) => _calmaAni(b)!.compareTo(_calmaAni(a)!));
            final sh = SandikSpace.screenH(context);
            final adaylar = {for (final a in _adaylar()) a.sembol: a};
            final ogeler = <Widget>[
              if (calan.isNotEmpty && bekleyen.isNotEmpty)
                SandikSectionHeader(title: context.l10n.alarmBekleyenler),
              for (final g in _grupla(bekleyen)) _grup(context, g, adaylar),
              if (calan.isNotEmpty) ...[
                _CalanlarBasligi(
                  sayi: calan.length,
                  acik: _calanlarAcik,
                  onTap: () => setState(() => _calanlarAcik = !_calanlarAcik),
                ),
                SandikAcilir(
                  acik: _calanlarAcik,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final g in _grupla(calan)) ...[
                        _grup(context, g, adaylar),
                        const SizedBox(height: 10),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('calanlariTemizle'),
                          style: TextButton.styleFrom(
                            foregroundColor: c.loss,
                            minimumSize: const Size(0, SandikTouch.min),
                          ),
                          onPressed: () => _calanlariTemizle(calan),
                          icon: const Icon(Icons.delete_sweep_rounded),
                          label: Text(context.l10n.alarmCalanlariTemizle),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ];
            // İzin reddedilmişse listedeki hiçbir alarm haber veremez
            // (Ar-Ge 16:45 #1, 2026-10-21). Liste kaydırılırken satır üstte
            // sabit kalmaz; yalnız listenin başında görünür.
            return Column(
              children: [
                BildirimIzniUyarisi(
                  padding: EdgeInsets.fromLTRB(sh, SandikSpace.sm, sh, 0),
                ),
                // Okuma hata verdi, liste cihazdaki son kopya (Ar-Ge 29 Eki
                // 20:45 #3): alarm "kaybolmuş" görünmez ama bayat olduğu da
                // saklanmaz. İkon + cümle; yalnız renkle değil.
                ValueListenableBuilder<bool>(
                  valueListenable: AlarmOnbellegi.bayat,
                  builder: (context, bayat, _) => !bayat
                      ? const SizedBox.shrink()
                      : Padding(
                          key: const ValueKey('alarmlarBayat'),
                          padding:
                              EdgeInsets.fromLTRB(sh, SandikSpace.sm, sh, 0),
                          child: Row(
                            children: [
                              Icon(Icons.cloud_off_rounded,
                                  size: 16, color: c.text58),
                              const SizedBox(width: SandikSpace.sm),
                              Expanded(
                                child: Text(
                                  context.l10n.alarmlarGuncellenemedi,
                                  style: context.t.bodySmall
                                      ?.copyWith(color: c.text58),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                Expanded(
                  child: RefreshIndicator.adaptive(
                    color: c.amberText,
                    onRefresh: _yenile,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(sh, 8, sh, 96),
                      itemCount: ogeler.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => ogeler[i],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Çalmış alarmın çalma anı; bekleyen (ve her zaman yüzde) alarmda null.
  ///
  /// Tekrarlı fiyat alarmı (0171) "çalmış" sayılmaz: çalmış olsa da fiyat
  /// geri dönünce kendiliğinden nöbete girer, yüzde alarmı gibi
  /// Bekleyenler'de kalır. Grup kararı [PriceAlert.sondu]'dan.
  static DateTime? _calmaAni(_Satir r) {
    final f = r.f;
    if (f != null) return f.sondu ? f.triggeredAt : null;
    return r.g?.triggeredAt ?? r.c?.triggeredAt;
  }

  /// Çalmış alarmları toplu siler (kişinin kendi verisi, onayla). Yalnız
  /// [calan] grubundakiler gider; bekleyen alarmlara dokunulmaz. Biri
  /// reddedilirse diyalog açık kalır, sebep söylenir; silinenler gitmiş olur
  /// (sağlayıcı her başarılı silmede listeyi günceller).
  Future<void> _calanlariTemizle(List<_Satir> calan) async {
    final l10n = context.l10n;
    final ok = await showSandikConfirm(
      context: context,
      title: l10n.alarmCalanlariTemizle,
      message: l10n.alarmCalanlariTemizleSoru(calan.length),
      confirmLabel: l10n.delete,
      destructive: true,
      islem: () async {
        for (final r in calan) {
          if (r.f != null) {
            await ref.read(priceAlertsProvider.notifier).delete(r.f!.id);
          } else if (r.g != null) {
            await ref.read(gostergeAlarmlariProvider.notifier).delete(r.g!.id);
          } else if (r.c != null) {
            await ref.read(cizimAlarmlariProvider.notifier).delete(r.c!.id);
          }
        }
      },
    );
    if (ok) {
      SandikHaptic.medium.perform();
      if (mounted) setState(() => _calanlarAcik = false);
    }
  }

  /// Satırın sembolü (tam olarak bir alan dolu).
  static String _sembol(_Satir r) =>
      r.f?.symbol ?? r.y?.symbol ?? r.g?.symbol ?? r.c!.symbol;

  static String _etiket(_Satir r) =>
      r.f?.label ?? r.y?.label ?? r.g?.label ?? r.c!.label;

  /// Aynı varlığın alarmları tek başlık altında (müşteri raporu 31 Eki
  /// 21:15, yasin "yap"). Kişi "altınım" diye düşünür, "yüzde alarmım"
  /// diye değil: eskiden gram altının yüzde alarmı ile fiyat alarmı iki
  /// ayrı karttı. Gruplar listedeki ilk görünüş sırasıyla (en yeni alarmı
  /// olan varlık önde); grup içi sıra listenin kendi sırası.
  static List<List<_Satir>> _grupla(List<_Satir> liste) {
    final gruplar = <String, List<_Satir>>{};
    for (final r in liste) {
      (gruplar[_sembol(r)] ??= []).add(r);
    }
    return gruplar.values.toList();
  }

  /// Bir varlığın grubu: başlıkta ad ve güncel fiyat, altında tek kartta
  /// satırlar (iOS gruplu liste kalıbı). Fiyat bir kez başlıkta yazar;
  /// satırlar yalnız hedefe mesafeyi söyler.
  Widget _grup(BuildContext context, List<_Satir> satirlar,
      Map<String, AlarmAdayi> adaylar) {
    final c = context.c;
    final sembol = _sembol(satirlar.first);
    final aday = adaylar[sembol];
    final ad = aday?.ad ?? cizgiEtiketiniAyir(_etiket(satirlar.first)).varlik;
    final fiyat = (aday?.guncelFiyat ?? 0) > 0
        ? fmtFiyat(aday!.guncelFiyat,
            symbol: alarmFiyatSimgesi(sembol) ?? '')
        : null;
    return Column(
      key: ValueKey('grup_$sembol'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                SandikSpace.xs, SandikSpace.xs, SandikSpace.xs, SandikSpace.xs2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    ad,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.titleMedium?.copyWith(color: c.text90),
                  ),
                ),
                if (fiyat != null) ...[
                  const SizedBox(width: SandikSpace.sm),
                  // Sağa yaslı; büyük yazıda adla yarı yarıya paylaşır,
                  // taşmaz (kısalır).
                  Flexible(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        context.l10n.alarmGrupSimdi(fiyat),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.bodyMedium?.copyWith(
                            color: c.text58,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ]),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        SandikCard(
          padding: EdgeInsets.zero,
          // Kaydırınca beliren kırmızı zemin kartın köşesinden taşmasın.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SandikRadius.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < satirlar.length; i++)
                  _satir(context, satirlar[i], aday: aday, ilk: i == 0),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Silme: satır kapanır, iş koşar, "Alarm silindi · Geri al". Sunucu
  /// reddederse satır geri açılır ve sebep söylenir (animasyon denetimi
  /// 2026-10-01).
  ///
  /// **Neden hemen sil, geri al yeniden kursun** (müşteri raporu 31 Eki
  /// 21:15): silmeyi bildirim kapanana kadar ertelemek ücretsiz alarm
  /// tavanında sayımı karıştırırdı (kişi siler, hemen yenisini kurar, sunucu
  /// eskisini hâlâ sayar). Geri al aynı alarmı yeni kayıtla kurar; çalmış
  /// alarmda geri al yok (yeniden kurmak onu nöbete döndürür, eski hâlini
  /// değil). [geriAl] `null` → eylemsiz bildirim.
  ///
  /// Kaydırma (`Dismissible.confirmDismiss`), bağlam menüsü ve düzenleme
  /// sayfasının "Alarmı sil"i aynı yoldan geçer. Silindiyse `true`.
  Future<bool> _sil(BuildContext satirCtx, Future<void> Function() sil,
      Future<void> Function()? geriAl) async {
    SandikHaptic.medium.perform();
    try {
      await KapananSatir.kapatVeYap(satirCtx, sil);
    } catch (e) {
      if (mounted) showAppError(context, e);
      return false;
    }
    if (!mounted) return true;
    sandikSnack(
      context,
      context.l10n.alarmSilindi,
      onUndo: geriAl == null
          ? null
          : () => CrashReporter.arkaPlan(() async {
                try {
                  await geriAl();
                  SandikHaptic.selection.perform();
                } catch (e) {
                  if (mounted) showAppError(context, e);
                }
              }(), reason: 'alarmlarim.geriAl'),
    );
    return true;
  }

  /// Satırın kabuğu: kapanış (silmede), kaydırarak sil, uzun basınca
  /// bağlam menüsü (iOS sistem menüsü, Android alt sayfa), ekran okuyucuya
  /// aynı eylemler. Satırdaki çöp kutusu kalktı (müşteri raporu 31 Eki
  /// 21:15): tek dokunuş onaysız ve geri alınamaz siliyordu, dört kartta
  /// dört çöp kutusu da listenin en göze batan öğesiydi.
  Widget _kabuk({
    required String anahtar,
    required bool ilk,
    required String menuBasligi,
    required Future<void> Function() sil,
    required Future<void> Function()? geriAl,
    required Widget Function(VoidCallback? duzenleSil) satir,
    Future<void> Function(VoidCallback sil)? duzenle,
  }) {
    final c = context.c;
    final l10n = context.l10n;
    return KapananSatir(
      key: ValueKey(anahtar),
      child: Builder(builder: (satirCtx) {
        void silDokunusu() =>
            CrashReporter.arkaPlan(_sil(satirCtx, sil, geriAl),
                reason: 'alarmlarim.sil');
        final eylemler = [
          if (duzenle != null)
            SandikBaglamEylemi(
              etiket: l10n.alarmiDuzenle,
              ikon: Icons.edit_outlined,
              onSec: () => CrashReporter.arkaPlan(duzenle(silDokunusu),
                  reason: 'alarmlarim.duzenle'),
            ),
          SandikBaglamEylemi(
            etiket: l10n.delete,
            ikon: Icons.delete_outline_rounded,
            yikici: true,
            onSec: silDokunusu,
          ),
        ];
        Widget govde = SandikBaglamMenusu(
          baslik: menuBasligi,
          eylemler: eylemler,
          child: satir(silDokunusu),
        );
        // Bağlam menüsü kapalıyken (bayrak) ekran okuyucu eylemleri yine
        // olsun: kaydırma VoiceOver/TalkBack'te yapılamaz.
        if (!SandikCam.acik) {
          govde = Semantics(
            customSemanticsActions: {
              for (final e in eylemler)
                CustomSemanticsAction(label: e.etiket): e.onSec,
            },
            child: govde,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!ilk)
              Divider(
                  height: 1,
                  thickness: 1,
                  indent: SandikSpace.md2,
                  color: c.hairline),
            Dismissible(
              key: ValueKey('kaydir_$anahtar'),
              direction: DismissDirection.endToStart,
              background: const _SilZemini(),
              // Silme burada koşar: satır önce kapanır, iş biter, sonra
              // kaydırma tamamlanır. Hata olursa satır yerine yaylanır.
              confirmDismiss: (_) => _sil(satirCtx, sil, geriAl),
              child: govde,
            ),
          ],
        );
      }),
    );
  }

  Widget _satir(BuildContext context, _Satir r,
      {required AlarmAdayi? aday, required bool ilk}) {
    final l10n = context.l10n;
    final fiyat = aday?.guncelFiyat ?? 0;
    final g = r.g, cz = r.c, yuzde = r.y;
    if (g != null || cz != null) return _seviyeSatiri(context, g, cz, fiyat, ilk);
    if (yuzde != null) {
      final etiket = yuzdeAlarmEtiketi(l10n, yuzde.esikPct, yuzde.yon);
      final pct = yuzde.sonTetikPct;
      final caldi = yuzde.bugunCaldi(DateTime.now()) && pct != null;
      final n = ref.read(yuzdeAlarmlariProvider.notifier);
      return _kabuk(
        anahtar: 'yuzde_${yuzde.id}',
        ilk: ilk,
        menuBasligi: yuzde.label,
        sil: () => n.delete(yuzde.id),
        geriAl: () => n.create(yuzde),
        satir: (_) => _AlarmSatiri(
          yon: switch (yuzde.yon) {
            YuzdeYon.dusus => _Yon.asagi,
            YuzdeYon.yukselis => _Yon.yukari,
            YuzdeYon.ikisi => _Yon.ikisi,
          },
          baslik: caldi ? etiket : l10n.yuzdeAlarmHerGun(etiket),
          altlar: [
            if (caldi) l10n.yuzdeAlarmBugunCaldi(fmtPctIsaretli(pct, digits: 1)),
          ],
        ),
      );
    }
    final alarm = r.f!;
    // Yatay çizgiye bağlı mı (bağ cihazda): bağlıysa satır çizgiyi açar ve
    // adlandırılır; bağsız fiyat alarmı dokununca düzenlenir.
    final baglar = ref.watch(yatayAlarmBaglariProvider);
    final cizim = yatayAlarmCizimi(baglar, alarm.id);
    final bagFiyati = cizim == null ? null : baglar[cizim]?.fiyat;
    final tetiklendi = alarm.sondu;
    final sonCalis = alarm.tekrar ? alarm.sonCalis : null;
    final hedef = fmtTRYFiyat(alarm.targetPrice);
    final isim = cizim == null ? null : cizgiEtiketiniAyir(alarm.label).isim;
    final mesafe = tetiklendi
        ? null
        : alarmMesafesi(
            fiyat: fiyat, hedef: alarm.targetPrice, yukari: alarm.isAbove);
    final n = ref.read(priceAlertsProvider.notifier);
    final duzenAdayi = aday ??
        AlarmAdayi(alarm.symbol, cizgiEtiketiniAyir(alarm.label).varlik, 0);
    // Düzenleme yalnız nöbetteki, çizgisiz alarmda: çalmış olan "Yeniden
    // kur"la döner; çizgiye bağlı alarmın hedefi çizgiyle taşınır (grafikte).
    final duzenlenir = !tetiklendi && cizim == null;
    Future<void> duzenle(VoidCallback sil) =>
        alarmDuzenleAkisi(context, ref, alarm, aday: duzenAdayi, sil: sil);
    return _kabuk(
      anahtar: alarm.id,
      ilk: ilk,
      menuBasligi: alarm.label,
      sil: () => n.delete(alarm.id),
      geriAl: tetiklendi
          ? null
          : () async {
              final yeni = await n.create(alarm);
              if (cizim != null) {
                ref.read(yatayAlarmBaglariProvider.notifier)
                    .bagla(cizim, yeni.id, bagFiyati ?? alarm.targetPrice);
              }
            },
      duzenle: duzenlenir ? duzenle : null,
      satir: (sil) => _AlarmSatiri(
        yon: alarm.isAbove ? _Yon.yukari : _Yon.asagi,
        sonuk: tetiklendi,
        baslik: tetiklendi
            ? l10n.alarmCalistiFiyat(hedef)
            : alarm.isAbove
                ? l10n.alarmKosulUst(hedef)
                : l10n.alarmKosulAlt(hedef),
        altlar: [
          if (isim != null) '«$isim»',
          if (alarm.tekrar && !tetiklendi) l10n.alarmHerGeciste,
          if (sonCalis != null) l10n.alarmSonCaldi(fmtTarihSaat(sonCalis)),
        ],
        mesafe: mesafe,
        grafikte: cizim != null,
        onTap: cizim != null
            ? () => _cizgiyiAc(alarm.symbol, cizim)
            : duzenlenir
                ? () => CrashReporter.arkaPlan(duzenle(sil!),
                    reason: 'alarmlarim.duzenle')
                : null,
        tapHint: cizim != null
            ? l10n.cizgiyiGrafikteAc
            : duzenlenir
                ? l10n.alarmiDuzenle
                : null,
        onAdlandir: cizim == null
            ? null
            : () => _adlandir(
                alarm.label, (label) => n.etiketiGuncelle(alarm.id, label)),
        // "Yeniden kur" istek atar ve sonucu iyimser değil, sunucu
        // onayından sonra yazar: tek yükleniyor davranışı (2026-10-08).
        // Eşik geçilmişse ön dolu sayfa, değilse yeniden kur + onay
        // (`alarmiYenidenKur`, 2026-10-21).
        onRearm: tetiklendi
            ? () => alarmiYenidenKur(context, ref, alarm, aday: duzenAdayi)
            : null,
      ),
    );
  }

  /// Gösterge ya da çizgi alarmının satırı (0170).
  Widget _seviyeSatiri(BuildContext context, GostergeAlarmi? g,
      CizimAlarmi? cz, double fiyat, bool ilk) {
    final l10n = context.l10n;
    final String etiket;
    final SeviyeYon yon;
    final bool calisti;
    final double? tetik;
    final String anahtar;
    final Future<void> Function() sil;
    final Future<void> Function()? geriAl;
    final altlar = <String>[];
    double? mesafe;
    if (g != null) {
      etiket = gostergeAlarmEtiketi(l10n, g.gosterge, g.yon);
      yon = g.yon;
      calisti = g.triggeredAt != null;
      tetik = g.tetikFiyat;
      anahtar = 'gosterge_${g.id}';
      final n = ref.read(gostergeAlarmlariProvider.notifier);
      sil = () => n.delete(g.id);
      geriAl = calisti ? null : () => n.create(g);
    } else {
      final c = cz!;
      etiket = switch (c.yon) {
        SeviyeYon.yukari => l10n.cizimAlarmEtiketUst,
        SeviyeYon.asagi => l10n.cizimAlarmEtiketAlt,
        SeviyeYon.herIkisi => l10n.cizimAlarmEtiketIkisi,
      };
      yon = c.yon;
      calisti = c.triggeredAt != null;
      tetik = c.tetikFiyat;
      anahtar = 'cizim_${c.id}';
      final isim = cizgiEtiketiniAyir(c.label).isim;
      if (isim != null) altlar.add('«$isim»');
      // Çizginin bugünkü seviyesi ve (uzamayan parçada) bitişi: "altına
      // inince" tek başına hangi seviye olduğunu söylemiyordu. Çalmış
      // alarmda seviye yazılmaz; durum satırı tetik fiyatını yazar.
      final v =
          c.isActive ? c.seviye(DateTime.now().millisecondsSinceEpoch) : null;
      if (v != null) {
        final f = fmtFiyat(v, symbol: alarmFiyatSimgesi(c.symbol) ?? '');
        altlar.add(c.uzanir
            ? l10n.cizimAlarmSeviyesi(f)
            // Bitiş yalnız GÜN: çizginin ucu grafikte serbest bir nokta,
            // saati ("21:42") günlük mumda anlamsız (e2e 2026-10-29).
            : l10n.cizimAlarmSeviyesiBitisli(
                f,
                fmtTarihSaat(
                    dayKey(DateTime.fromMillisecondsSinceEpoch(c.t2)))));
        mesafe = alarmMesafesi(
            fiyat: fiyat,
            hedef: v,
            yukari: switch (c.yon) {
              SeviyeYon.yukari => true,
              SeviyeYon.asagi => false,
              SeviyeYon.herIkisi => null,
            });
      }
      final n = ref.read(cizimAlarmlariProvider.notifier);
      sil = () => n.delete(c.id);
      geriAl = calisti ? null : () => n.create(c);
    }
    final sembol = g?.symbol ?? cz!.symbol;
    if (calisti) {
      altlar.add(tetik == null
          ? l10n.seviyeAlarmCalistiSade
          : l10n.seviyeAlarmCalisti(
              fmtFiyat(tetik, symbol: alarmFiyatSimgesi(sembol) ?? '')));
    }
    return _kabuk(
      anahtar: anahtar,
      ilk: ilk,
      menuBasligi: g?.label ?? cz!.label,
      sil: sil,
      geriAl: geriAl,
      satir: (_) => _AlarmSatiri(
        yon: switch (yon) {
          SeviyeYon.yukari => _Yon.yukari,
          SeviyeYon.asagi => _Yon.asagi,
          SeviyeYon.herIkisi => _Yon.ikisi,
        },
        sonuk: calisti,
        baslik: etiket,
        altlar: altlar,
        mesafe: mesafe,
        grafikte: cz != null,
        onTap: cz == null ? null : () => _cizgiyiAc(cz.symbol, cz.cizimId),
        tapHint: cz == null ? null : l10n.cizgiyiGrafikteAc,
        onAdlandir: cz == null
            ? null
            : () => _adlandir(
                cz.label,
                (label) => ref
                    .read(cizimAlarmlariProvider.notifier)
                    .etiketiGuncelle(cz.id, label)),
      ),
    );
  }
  /// Satırdan çizgiye: push ve çanla aynı varış.
  void _cizgiyiAc(String sembol, String cizimId) {
    SandikHaptic.selection.perform();
    CrashReporter.arkaPlan(
        NotificationService.instance.openCizgi(sembol, cizimId: cizimId),
        reason: 'alarmlarim.cizgiAc');
  }

  /// Çizgi alarmının adı: yalnız "varlık · ad"ın ad kısmı düzenlenir,
  /// varlık adı korunur. Boş bırakmak adı kaldırır (eski biçim).
  Future<void> _adlandir(
      String label, Future<void> Function(String label) yaz) async {
    final l10n = context.l10n;
    final parca = cizgiEtiketiniAyir(label);
    var kaydedildi = false;
    await showCizgiAdiSayfasi(
      context,
      baslik: l10n.cizgiAlarmiAdlandirBaslik,
      dugme: l10n.save,
      baslangic: parca.isim ?? '',
      odakla: true,
      kaydet: (isim) async {
        await yaz(cizgiAlarmEtiketi(parca.varlik, isim));
        kaydedildi = true;
      },
    );
    if (kaydedildi && mounted) {
      SandikHaptic.selection.perform();
      sandikSnack(context, l10n.cizgiAlarmiAdlandi,
          kind: SandikSnackKind.success);
    }
  }

  /// Boş durum: zil ve açıklama, altında portföyündeki kapsam varlıkları
  /// için tek dokunuşla "gün içinde %2 oynarsa" önerisi (müşteri raporu
  /// 31 Eki 21:15, yasin "yap"). Eskiden yalnız "zile dokun" diyordu; ilk
  /// alarmı kurmak bir sonraki adımı bilmeyi istiyordu. Kapsam ve eşik
  /// kayıt anındaki tek dokunuş alarmının kendisi (#260,
  /// [yuzdeAlarmiOnerilsinMi], [tekDokunusYuzdeAlarmiKur]): yeni kural
  /// yazılmadı. En fazla üç öneri; fazlası listeyi kalabalıklaştırır.
  Widget _bosDurum(BuildContext context, List<YuzdeAlarmi> yuzdeHepsi) {
    final c = context.c;
    final s = widget.sembol;
    final oneriler = [
      for (final a in _adaylar())
        if ((s == null || a.sembol == s) &&
            yuzdeAlarmiOnerilsinMi(a, yuzdeHepsi))
          a,
    ].take(3).toList();
    final sh = SandikSpace.screenH(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(sh, SandikSpace.xl, sh, 96),
      children: [
        // Bayrak `goz_alici`: kapalı sandık; kapalıyken eski ikon.
        Center(
          child: SandikBosIkonu(
              ikon: Icons.notifications_none_rounded,
              boyut: 44,
              renk: c.text36),
        ),
        const SizedBox(height: 14),
        Text(
          context.l10n.noAlertsYet,
          textAlign: TextAlign.center,
          style: context.t.headlineSmall?.copyWith(color: c.text90),
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.noAlertsBody,
          textAlign: TextAlign.center,
          style: context.t.bodyLarge?.copyWith(color: c.text58),
        ),
        if (oneriler.isNotEmpty) ...[
          const SizedBox(height: SandikSpace.xl),
          SandikSectionHeader(title: context.l10n.alarmOneriBaslik),
          SandikCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < oneriler.length; i++) ...[
                  if (i > 0)
                    Divider(
                        height: 1,
                        thickness: 1,
                        indent: SandikSpace.md2,
                        color: c.hairline),
                  _OneriSatiri(
                    key: ValueKey('oneri_${oneriler[i].sembol}'),
                    ad: oneriler[i].ad,
                    onKur: () =>
                        tekDokunusYuzdeAlarmiKur(context, ref, oneriler[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Boş durumdaki öneri satırı: ad + "gün içinde %2 oynarsa haber verelim"
/// + "Kur". Kur istek atar, sonucu bekler (tek yükleniyor davranışı).
class _OneriSatiri extends StatelessWidget {
  const _OneriSatiri({super.key, required this.ad, required this.onKur});

  final String ad;
  final Future<void> Function() onKur;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.md2, vertical: SandikSpace.smd),
        child: Row(
          children: [
            Icon(Icons.swap_vert_rounded, size: 20, color: c.text58),
            const SizedBox(width: SandikSpace.smd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.titleMedium?.copyWith(color: c.text90)),
                  Text(context.l10n.alarmOneriAciklama,
                      style: context.t.bodyMedium?.copyWith(color: c.text58)),
                ],
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            SandikAsyncButton.kompakt(
              tur: SandikAsyncTur.metin,
              onPressed: onKur,
              child: Text(context.l10n.tekDokunusYuzdeKur),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Alarm satırı (her tür, 2026-10-31) ──────────────────────────────────────

enum _Yon { yukari, asagi, ikisi }

/// Gruptaki tek satır: yön simgesi, koşul başlığı, alt satırlar, sağda
/// hedefe mesafe ya da "Yeniden kur". Fiyat, yüzde, gösterge ve çizgi
/// alarmı aynı iskeleti paylaşır (eskiden üç ayrı kopyaydı).
///
/// Yön eskiden ▲ ▼ metin karakteriydi: DM Sans'ta yok, platformun yedek
/// fontuyla çiziliyor, kalınlığı ve hizası cihaza göre değişiyordu
/// (müşteri raporu 31 Eki 21:15). Artık simge; yön RENKLE anlatılmaz,
/// başlık da yazar ("Üstüne çıkınca").
class _AlarmSatiri extends StatelessWidget {
  const _AlarmSatiri({
    required this.yon,
    required this.baslik,
    this.altlar = const [],
    this.sonuk = false,
    this.mesafe,
    this.grafikte = false,
    this.onTap,
    this.tapHint,
    this.onAdlandir,
    this.onRearm,
  });

  final _Yon yon;
  final String baslik;
  final List<String> altlar;

  /// Çalmış (tek atışlık) alarm: simge soluk.
  final bool sonuk;

  /// Hedefe kalan yüzde ([alarmMesafesi]); bilinmiyorsa null, yazılmaz.
  final double? mesafe;

  /// Çizgi alarmı: "Grafikte aç ›" ipucu satırı.
  final bool grafikte;
  final VoidCallback? onTap;
  final String? tapHint;
  final VoidCallback? onAdlandir;
  final Future<void> Function()? onRearm;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final renk = sonuk
        ? c.text36
        : switch (yon) {
            _Yon.yukari => c.gain,
            _Yon.asagi => c.loss,
            _Yon.ikisi => c.text58,
          };
    final m = mesafe;
    final mesafeMetni =
        m == null ? null : fmtPct(m, digits: alarmMesafesiHanesi(m));
    // Büyük yazıda (1,5× üstü) mesafe sağ sütundan başlığın altına iner:
    // dar satırda başlığı tek harfe sıkıştırmasın (Dynamic Type).
    final buyukYazi = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final mesafeYazisi = mesafeMetni == null
        ? null
        : Semantics(
            label: l10n.alarmKaldiSemantik(mesafeMetni),
            excludeSemantics: true,
            child: Text(
              l10n.alarmKaldi(mesafeMetni),
              key: const ValueKey('alarmMesafe'),
              style: context.t.labelLarge?.copyWith(
                  color: c.text90,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          );
    final govde = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.md2, vertical: SandikSpace.smd),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                switch (yon) {
                  _Yon.yukari => Icons.arrow_upward_rounded,
                  _Yon.asagi => Icons.arrow_downward_rounded,
                  _Yon.ikisi => Icons.swap_vert_rounded,
                },
                size: 20,
                color: renk,
              ),
            ),
            const SizedBox(width: SandikSpace.smd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    baslik,
                    style: context.t.titleMedium?.copyWith(color: c.text90),
                  ),
                  for (final a in altlar)
                    Text(
                      a,
                      style: context.t.bodySmall?.copyWith(color: c.text58),
                    ),
                  if (buyukYazi && mesafeYazisi != null) mesafeYazisi,
                  if (grafikte) const _GrafikteAcSatiri(),
                ],
              ),
            ),
            if (!buyukYazi && mesafeYazisi != null) ...[
              const SizedBox(width: SandikSpace.sm),
              mesafeYazisi,
            ],
            if (onRearm != null)
              SandikAsyncButton.kompakt(
                tur: SandikAsyncTur.metin,
                onPressed: onRearm!,
                child: Text(l10n.recreateAlert),
              ),
            if (onAdlandir != null) _AdlandirDugmesi(onPressed: onAdlandir!),
            // Dokunulabilir satır görünür ipucu taşır (yalnız basma
            // tepkisine bırakılmaz); çizgi satırının ipucu "Grafikte aç".
            if (onTap != null && !grafikte)
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(left: SandikSpace.xs),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 20, color: c.text36),
                ),
              ),
          ],
        ),
      ),
    );
    if (onTap == null) return govde;
    return Semantics(
      button: true,
      onTapHint: tapHint,
      child: SandikTappable(onTap: onTap, child: govde),
    );
  }
}

/// Sola kaydırınca beliren zemin: NE olacağını söyler ("Sil" + simge),
/// yalnız renk değil.
class _SilZemini extends StatelessWidget {
  const _SilZemini();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      color: c.loss,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: SandikSpace.lgs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.delete,
            style: context.t.labelLarge?.copyWith(color: c.onStatus),
          ),
          const SizedBox(width: SandikSpace.xs2),
          Icon(Icons.delete_outline_rounded, color: c.onStatus, size: 20),
        ],
      ),
    );
  }
}
/// "Grafikte aç ›" — satırın dokunulabilir olduğunu yalnız kart
/// gölgesine bırakmayan görünür ipucu (metin + ok; yalnız renk değil).
class _GrafikteAcSatiri extends StatelessWidget {
  const _GrafikteAcSatiri();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.xxs),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart_rounded, size: 16, color: c.amberText),
            const SizedBox(width: SandikSpace.xs),
            Flexible(
              child: Text(
                context.l10n.cizgiyiGrafikteAc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelMedium?.copyWith(color: c.amberText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kalem: çizgi alarmının adını değiştirir (IconButton, 48 pt).
class _AdlandirDugmesi extends StatelessWidget {
  const _AdlandirDugmesi({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        key: const ValueKey('cizgiAlarmiAdlandir'),
        onPressed: onPressed,
        icon: Icon(Icons.edit_outlined, color: context.c.text36),
        tooltip: context.l10n.cizgiAlarmiAdlandir,
      );
}

// ── Çalanlar grubu başlığı (Ar-Ge 29 Eki 16:45 #2) ─────────────────────────

/// "Çalanlar (N)" — dokununca grup açılır/kapanır. Tüm satır dokunma alanı
/// (≥44 pt); açık/kapalı durumu ok yönüyle ve erişilebilirlikte `expanded`
/// ile söylenir, yalnız hareketle değil.
class _CalanlarBasligi extends StatelessWidget {
  const _CalanlarBasligi({
    required this.sayi,
    required this.acik,
    required this.onTap,
  });

  final int sayi;
  final bool acik;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      expanded: acik,
      child: SandikTappable(
        key: const ValueKey('calanlarBasligi'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.alarmCalanlar(sayi),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: c.text58,
                  ),
                ),
              ),
              SandikAcilirOk(
                acik: acik,
                child:
                    Icon(Icons.expand_more_rounded, size: 20, color: c.text58),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
