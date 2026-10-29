import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../services/analytics_service.dart';
import '../widgets/bildirim_izni_uyarisi.dart';
import '../widgets/sandik_bos_durum.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../widgets/kapanan_satir.dart';
import '../widgets/alarm_kur_sheet.dart';
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
                : [for (final a in hepsi) if (a.symbol == s) a];
            final yuzdeListe = s == null
                ? yuzdeHepsi
                : [for (final a in yuzdeHepsi) if (a.symbol == s) a];
            // Tek zaman sırası, en yeni önce; eşitlikte fiyat alarmı önde
            // (`List.sort` kararlı değil; liste yenilenince zıplamasın).
            final liste = <({
              DateTime t,
              PriceAlert? f,
              YuzdeAlarmi? y,
              GostergeAlarmi? g,
              CizimAlarmi? c,
            })>[
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
            if (liste.isEmpty) return _bosDurum(c);
            // İzin reddedilmişse listedeki hiçbir alarm haber veremez
            // (Ar-Ge 16:45 #1, 2026-10-21). Liste kaydırılırken satır üstte
            // sabit kalmaz; yalnız listenin başında görünür.
            return Column(
              children: [
                BildirimIzniUyarisi(
                  padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
                      SandikSpace.sm, SandikSpace.screenH(context), 0),
                ),
                Expanded(
                  child: RefreshIndicator.adaptive(
                    color: c.amberText,
                    onRefresh: _yenile,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
                          8, SandikSpace.screenH(context), 96),
                      itemCount: liste.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      // Silinen satır önce kapanır, altındakiler yukarı kayar; sunucu
                      // reddederse geri açılır ve sebep söylenir (animasyon denetimi
                      // 2026-10-01 — eskiden satır tek karede yok oluyor, hata da
                      // yakalanmıyordu).
                      itemBuilder: (_, i) {
                        final seviye = _seviyeSatiri(context, liste[i].g, liste[i].c);
                        if (seviye != null) return seviye;
                        final yuzde = liste[i].y;
                        if (yuzde != null) {
                          return KapananSatir(
                            key: ValueKey('yuzde_${yuzde.id}'),
                            child: Builder(
                              builder: (satirCtx) => _YuzdeAlarmSatiri(
                                alarm: yuzde,
                                onDelete: () async {
                                  SandikHaptic.medium.perform();
                                  try {
                                    await KapananSatir.kapatVeYap(
                                        satirCtx,
                                        () => ref
                                            .read(yuzdeAlarmlariProvider
                                                .notifier)
                                            .delete(yuzde.id));
                                  } catch (e) {
                                    if (context.mounted) {
                                      showAppError(context, e);
                                    }
                                  }
                                },
                              ),
                            ),
                          );
                        }
                        final alarm = liste[i].f!;
                        return KapananSatir(
                        key: ValueKey(alarm.id),
                        child: Builder(
                          builder: (satirCtx) => _AlarmSatiri(
                            alarm: alarm,
                            onDelete: () async {
                              final id = alarm.id;
                              SandikHaptic.medium.perform();
                              try {
                                await KapananSatir.kapatVeYap(
                                    satirCtx,
                                    () => ref
                                        .read(priceAlertsProvider.notifier)
                                        .delete(id));
                              } catch (e) {
                                if (context.mounted) showAppError(context, e);
                              }
                            },
                            // Eskiden hata yakalanmıyordu (sahipsiz Future → zone'a
                            // çökme); düğme artık bekliyor, ret sebebi söylenir.
                            // Eşik geçilmişse ön dolu sayfa, değilse yeniden
                            // kur + onay (`alarmiYenidenKur`, 2026-10-21).
                            onRearm: () {
                              final a = alarm;
                              final aday = _adaylar()
                                      .where((x) => x.sembol == a.symbol)
                                      .firstOrNull ??
                                  AlarmAdayi(a.symbol, a.label, 0);
                              return alarmiYenidenKur(context, ref, a,
                                  aday: aday);
                            },
                          ),
                        ),
                      );
                      },
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

  /// Gösterge ya da çizgi alarmının satırı (0170); ikisi de değilse null.
  Widget? _seviyeSatiri(
      BuildContext context, GostergeAlarmi? g, CizimAlarmi? cz) {
    if (g == null && cz == null) return null;
    final l10n = context.l10n;
    final String etiket;
    final SeviyeYon yon;
    final bool calisti;
    final double? tetik;
    final String anahtar;
    final Future<void> Function() sil;
    String? seviyeMetni;
    if (g != null) {
      etiket = gostergeAlarmEtiketi(l10n, g.gosterge, g.yon);
      yon = g.yon;
      calisti = g.triggeredAt != null;
      tetik = g.tetikFiyat;
      anahtar = 'gosterge_${g.id}';
      sil = () => ref.read(gostergeAlarmlariProvider.notifier).delete(g.id);
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
      // Çizginin bugünkü seviyesi ve (uzamayan parçada) bitişi: "altına
      // inince" tek başına hangi seviye olduğunu söylemiyordu. Çalmış
      // alarmda seviye yazılmaz; durum satırı tetik fiyatını yazar.
      final v = c.isActive ? c.seviye(DateTime.now().millisecondsSinceEpoch) : null;
      if (v != null) {
        final fiyat = fmtFiyat(v, symbol: alarmFiyatSimgesi(c.symbol) ?? '');
        seviyeMetni = c.uzanir
            ? l10n.cizimAlarmSeviyesi(fiyat)
            : l10n.cizimAlarmSeviyesiBitisli(fiyat,
                fmtTarihSaat(DateTime.fromMillisecondsSinceEpoch(c.t2)));
      }
      sil = () => ref.read(cizimAlarmlariProvider.notifier).delete(c.id);
    }
    final sembol = g?.symbol ?? cz!.symbol;
    return KapananSatir(
      key: ValueKey(anahtar),
      child: Builder(
        builder: (satirCtx) => _SeviyeAlarmSatiri(
          ad: g?.label ?? cz!.label,
          etiket: etiket,
          seviye: seviyeMetni,
          yon: yon,
          durum: !calisti
              ? null
              : tetik == null
                  ? l10n.seviyeAlarmCalistiSade
                  : l10n.seviyeAlarmCalisti(
                      fmtFiyat(tetik, symbol: alarmFiyatSimgesi(sembol) ?? '')),
          onDelete: () async {
            SandikHaptic.medium.perform();
            try {
              await KapananSatir.kapatVeYap(satirCtx, sil);
            } catch (e) {
              if (context.mounted) showAppError(context, e);
            }
          },
        ),
      ),
    );
  }

  Widget _bosDurum(SandikPalette c) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bayrak `goz_alici`: kapalı sandık; kapalıyken eski ikon.
              SandikBosIkonu(
                  ikon: Icons.notifications_none_rounded,
                  boyut: 44,
                  renk: c.text36),
              const SizedBox(height: 14),
              Text(
                context.l10n.noAlertsYet,
                style: context.t.headlineSmall?.copyWith(color: c.text90),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.noAlertsBody,
                textAlign: TextAlign.center,
                style: context.t.bodyLarge?.copyWith(color: c.text58),
              ),
            ],
          ),
        ),
      );
}

// ── Yüzde alarmı satırı (0169) ───────────────────────────────────────────────

/// Fiyat alarmı satırıyla aynı iskelet. "Yeniden kur" yok: alarm ertesi gün
/// kendiliğinden nöbete döner; bugün çaldıysa alt satır bunu ve çaldığı
/// andaki yüzdeyi (bildirimdeki sayının kendisi) söyler.
class _YuzdeAlarmSatiri extends StatelessWidget {
  final YuzdeAlarmi alarm;
  final VoidCallback onDelete;

  const _YuzdeAlarmSatiri({required this.alarm, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final etiket = yuzdeAlarmEtiketi(l10n, alarm.esikPct, alarm.yon);
    final pct = alarm.sonTetikPct;
    final caldi = alarm.bugunCaldi(DateTime.now()) && pct != null;
    return SandikCard(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.md2, vertical: SandikSpace.smd),
      child: Row(
        children: [
          // Yön RENKLE anlatılmaz — ok her zaman var, etiket de yazar.
          ExcludeSemantics(
            child: Text(
              switch (alarm.yon) {
                YuzdeYon.dusus => '▼',
                YuzdeYon.yukselis => '▲',
                YuzdeYon.ikisi => '▲▼',
              },
              style: context.t.titleMedium?.copyWith(
                color: switch (alarm.yon) {
                  YuzdeYon.dusus => c.loss,
                  YuzdeYon.yukselis => c.gain,
                  YuzdeYon.ikisi => c.text58,
                },
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alarm.label,
                  style: context.t.titleMedium?.copyWith(color: c.text90),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  caldi ? etiket : l10n.yuzdeAlarmHerGun(etiket),
                  style: context.t.bodyMedium?.copyWith(color: c.text58),
                ),
                if (caldi)
                  Text(
                    l10n.yuzdeAlarmBugunCaldi(fmtPctIsaretli(pct, digits: 1)),
                    style: context.t.bodySmall?.copyWith(color: c.text58),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline_rounded, color: c.text36),
            tooltip: l10n.delete,
          ),
        ],
      ),
    );
  }
}

// ── Gösterge / çizgi alarmı satırı (0170) ───────────────────────────────────

/// Yüzde alarmı satırıyla aynı iskelet. "Yeniden kur" yok: gösterge
/// alarmı sayfadan, çizgi alarmı grafikteki zilden yeniden kurulur. Çalmış
/// alarm soluk ok + "Çalıştı · ₺312,40 · tek seferlikti" (bildirimdeki
/// sayı; simge sembolün kendi biriminde).
class _SeviyeAlarmSatiri extends StatelessWidget {
  final String ad;
  final String etiket;

  /// Çizgi alarmında bugünkü seviye (ve bitiş); gösterge alarmında null.
  final String? seviye;
  final SeviyeYon yon;

  /// Çalmışsa durum satırı; nöbetteyse null.
  final String? durum;
  final VoidCallback onDelete;

  const _SeviyeAlarmSatiri({
    required this.ad,
    required this.etiket,
    this.seviye,
    required this.yon,
    required this.durum,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final calisti = durum != null;
    return SandikCard(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.md2, vertical: SandikSpace.smd),
      child: Row(
        children: [
          // Yön RENKLE anlatılmaz — ok her zaman var, etiket de yazar.
          ExcludeSemantics(
            child: Text(
              switch (yon) {
                SeviyeYon.yukari => '▲',
                SeviyeYon.asagi => '▼',
                SeviyeYon.herIkisi => '▲▼',
              },
              style: context.t.titleMedium?.copyWith(
                color: calisti
                    ? c.text36
                    : switch (yon) {
                        SeviyeYon.yukari => c.gain,
                        SeviyeYon.asagi => c.loss,
                        SeviyeYon.herIkisi => c.text58,
                      },
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: SandikSpace.smd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad,
                  style: context.t.titleMedium?.copyWith(color: c.text90),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  etiket,
                  style: context.t.bodyMedium?.copyWith(color: c.text58),
                ),
                if (seviye != null)
                  Text(
                    seviye!,
                    style: context.t.bodySmall?.copyWith(color: c.text58),
                  ),
                if (durum != null)
                  Text(
                    durum!,
                    style: context.t.bodySmall?.copyWith(color: c.text58),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline_rounded, color: c.text36),
            tooltip: context.l10n.delete,
          ),
        ],
      ),
    );
  }
}

// ── Alarm satırı ─────────────────────────────────────────────────────────────

class _AlarmSatiri extends StatelessWidget {
  final PriceAlert alarm;
  final VoidCallback onDelete;
  final Future<void> Function() onRearm;

  const _AlarmSatiri({
    required this.alarm,
    required this.onDelete,
    required this.onRearm,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tetiklendi = alarm.triggeredAt != null;
    // Düz kart: kenar `text20 %22` idi, kartlar arası tek kenar dili
    // saç teli olsun diye `SandikCard`'a geçti (SandikCard 2. tur, 2026-10-08).
    return SandikCard(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.md2, vertical: SandikSpace.smd),
      child: Row(
        children: [
          // Yön RENKLE anlatılmaz — ok her zaman var.
          Text(
            alarm.isAbove ? '▲' : '▼',
            style: context.t.titleMedium?.copyWith(
              color: tetiklendi ? c.text36 : (alarm.isAbove ? c.gain : c.loss),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alarm.label,
                  style: context.t.titleMedium?.copyWith(color: c.text90),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  tetiklendi
                      ? 'Çalıştı · ${fmtTRYFiyat(alarm.targetPrice)}'
                      : '${alarm.isAbove ? "Üstüne çıkınca" : "Altına inince"}'
                          ' · ${fmtTRYFiyat(alarm.targetPrice)}',
                  style: context.t.bodyMedium?.copyWith(color: c.text58),
                ),
              ],
            ),
          ),
          // "Yeniden kur" istek atar ve sonucu iyimser değil, sunucu
          // onayından sonra yazar: tek yükleniyor davranışı (2026-10-08).
          // Sil iyimser kalır (KapananSatir satırı önce kapatır).
          if (tetiklendi)
            SandikAsyncButton.kompakt(
              tur: SandikAsyncTur.metin,
              onPressed: onRearm,
              child: Text(context.l10n.recreateAlert),
            ),
          IconButton(
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline_rounded, color: c.text36),
            tooltip: 'Sil',
          ),
        ],
      ),
    );
  }
}
