// Ana ekrandaki "Bugün" kartı.
//
// Hesap `services/bugun_service.dart`'ta (saf); burada yalnızca gün içi
// serinin çekimi (kilit ekranı/widget ile ORTAK önbellek — üç yüzey aynı
// rakamı göstermeli), tercihler ve çizim var.
//
// Kendi kapılarını kendi kurar: kendi görünümü + açık pozisyon varken
// çizilir; seri gelmeden de kalan satırları gösterir (boş kart yok).
//
// Düzen (2026-09-21, "almanak"): sol sütunda tarih (büyük gün rakamı),
// sağda günün hareketi; altında `etiket ····· değer` defter satırları, her
// birinin altında kısa açıklama; en altta yaklaşan olay ayak notu. Renk
// yalnızca sayıda, ikon yok — dört eşit ikonlu satır bir menü gibi
// okunuyordu, hiyerarşi yoktu (kullanıcı ekran görüntüsü).
import 'dart:async';
import '../services/tazelik_ritmi.dart';
import '../services/price_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/position.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../screens/portfolio_performance_screen.dart';
import '../services/analytics_service.dart';
import '../services/bist_calendar.dart';
import '../services/bugun_service.dart';
import '../services/bugun_yukleyici.dart';
import '../services/crash_reporter.dart';
import '../services/daily_summary.dart';
import '../theme/sandik.dart';
import '../utils/piyasa_kapali_etiketi.dart';
import '../utils/tr_format.dart';
import '../utils/tr_iyelik.dart';
import 'hedef_sheet.dart';
import 'sandik_skeleton.dart';
import '../services/period_summary_service.dart' show SummaryPeriod;

/// Yüzdeyi TUTARLA AYNI işaret biçimiyle yazar: `+%1,23` / `−%0,06`.
///
/// **Neden (plan F3, 2026-09-29):** kart tutarı "−₺368", yüzdeyi ise
/// `fmtPct(x.abs())` ile "%0,06" yazıyordu; yön yalnız RENKTE kalıyordu.
/// Renk körlüğünde ve ekran okuyucuda yüzde yönsüz okunur, üstelik tutarın
/// yanında işaretsiz duran yüzde "artı" sanılır. Eksi işareti tutardaki
/// gibi U+2212 (−): tire değil, rakam genişliğinde.
///
/// Sıfırda — ya da gösterilen hanelerde sıfıra yuvarlanıyorsa — işaret
/// YOK: "−%0,00" yönü olmayan bir şeye yön yazardı. Hesaba dokunmaz;
/// yalnızca biçim.
///
/// Kural `tr_format.dart` › [fmtPctIsaretli]'de (piyasa şeridi de oradan);
/// bu ad kartın testleri ve çağrı yerleri için korunur.
String isaretliYuzde(double pct, {int digits = 2}) =>
    fmtPctIsaretli(pct, digits: digits);

/// "Enflasyona göre" satırının değeri: `5,2 puan önde` / `20,6 puan geride`.
///
/// **Neden (plan F3):** eskiden `−20,6 puan` yazıyordu — işaretli çıplak
/// "puan" finans jargonu; kullanıcı neyin kaç puan olduğunu satır
/// etiketinden çıkarmak zorundaydı. Etiket "Enflasyona göre" zaten neye
/// göre olduğunu söylüyor; değer yönü KELİMEYLE söyler (işaret gerekmez).
/// Kısa kalması bilinçli: defter satırında değer hiç kırpılmaz, uzun
/// cümle dar ekranda etiketi yok ederdi. Tek ondalığa yuvarlanmış fark
/// sıfırsa "başa baş" — "0,0 puan önde" yön uydururdu.
///
/// [onde] `ReelGetiriSatiri.onde` (fark ≥ 0) — yön kararı hesapta kalır.
String reelFarkMetni(AppLocalizations l10n, {required double fark, required bool onde}) {
  final puan = fmtNum(fark.abs(), digits: 1);
  if (puan == fmtNum(0, digits: 1)) return l10n.todayRealEven;
  return onde ? l10n.todayRealAhead(puan) : l10n.todayRealBehind(puan);
}

class BugunKarti extends ConsumerStatefulWidget {
  const BugunKarti({
    super.key,
    required this.state,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 0),
    this.kisisel = true,
    this.etiket,
    this.hedefKapsami = '',
  });

  /// Kartın anlattığı defter — seçili kapsamın (2026-09-21).
  ///
  /// Eskiden yalnızca giriş yapan kullanıcının defteri veriliyordu ve kart
  /// Birlikte görünümünde de onu anlatıyordu: toplam kartı birleşik defteri
  /// gösterirken Bugün kartı yalnızca senin gününü söylüyordu (kullanıcı
  /// bulgusu). Şimdi kart hangi görünümdeyse o görünümün defterini alır —
  /// şeritlerin 2026-09-17'den beri yaptığı gibi, tek hesap yolu.
  final PortfolioState state;
  final EdgeInsets padding;

  /// Kendi görünümü mü? Aylık özet girişi yalnızca burada; gün içi seri de
  /// yalnızca burada kilit ekranıyla paylaşılan önbellekten okunur (bkz.
  /// `_seriYukle`). Hedef artık her kapsamda — bkz. [hedefKapsami].
  final bool kisisel;

  /// Hedef satırının kapsam anahtarı (`kapsamHedefiProvider`): `''` Ben,
  /// `'birlikte'`, `'ortak_<id>'` (2026-09-30).
  final String hedefKapsami;

  /// Kartın başına yazılan kapsam etiketi ("Ayşe'nin bugünü", "Birlikte").
  /// Kendi görünümünde `null`: kartın kimin olduğu sorusu yalnızca başka
  /// bir defter gösterilirken doğar.
  final String? etiket;

  @override
  ConsumerState<BugunKarti> createState() => _BugunKartiState();
}

class _BugunKartiState extends ConsumerState<BugunKarti> {
  Map<int, double>? _seri;
  ReelGetiriSatiri? _reel;
  double? _haftalik;
  bool _istendi = false;

  /// Üç yükleme de sonuçlandı mı (başarı ya da hata fark etmez)?
  /// `false` iken kart iskelet çizer — bkz. [_yukle].
  bool _yuklendi = false;

  /// Tek bir yüklemenin üst sınırı. Biri asılı kalırsa kart bu süreden
  /// sonra elindekiyle çizilir; iskelet sonsuza kadar kalmaz.
  static const _yuklemeSuresi = BugunYukleyici.varsayilanButce;

  /// Gün içi seri bundan eskiyse tazelenir — Performans ekranının tick
  /// periyoduyla AYNI (30 sn). İkisi ayrışırsa aynı kapsamda iki farklı
  /// kâr/zarar görünür (bkz. `_seriYukle`).
  static const _seriTazelikPenceresi = TazelikRitmi.yuzey;

  /// Gün içi seriyi Performans ekranıyla AYNI ritimde tazeleyen sayacı.
  ///
  /// ## Neden gerekli (kullanıcı bildirimi, 2026-09-23)
  /// *"Hâlâ zaman zaman fark oluyor, özellikle ana sayfa Bugün ile
  /// Performans günlük arasında, ama ortaklarda fark olmuyor — logged-in
  /// user'ın portföyünde sorun oluyor."*
  ///
  /// İki yüzey aynı hesabı yapıyordu ama serileri FARKLI YAŞTAYDI:
  ///
  ///   * Performans → `Timer.periodic(30 sn)` ile `_intradayKey`'i düşürür,
  ///     `FutureBuilder` seriyi YENİDEN çeker. Yaş her zaman ≤ 30 sn.
  ///   * Bu kart  → `_seri` alanına BİR KEZ yazılıyordu (`_istendi`) ve
  ///     yalnızca defter imzası değişinceyeniden yükleniyordu. Fiyat
  ///     tazelemesi karti yeniden BUILD ediyor ama `_seri` aynı kalıyordu.
  ///
  /// Gün başı (`open`) serinin ilk noktasından gelir. Seri dakikalarca
  /// eskidikçe o nokta Performans'ınkinden ayrışıyor; canlı uç (`last`)
  /// ikisinde de güncel olduğu için **değişim** farklı çıkıyor.
  ///
  /// ### Neden yalnızca "Ben" kapsamında görülüyor
  /// Ortak lot'larının `currentPrice`'ı RLS yüzünden sunucuya yazılamaz;
  /// `refreshPrices` onları ancak bellekte günceller. Ortak görünümünde
  /// canlı uç pek oynamadığı için bayat taban fark yaratmıyor. Kendi
  /// portföyünde ise fiyat her 30 sn'de günelleniyor: uç oynuyor, taban
  /// sabit kalıyor ve makas açılıyor.
  VoidCallback? _nabziBirak;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
    // ORTAK NABIZ — kendi `Timer`'ını KURMAZ.
    //
    // Aynı ritmi kullanmak yetmiyordu: her yüzey sayacını mount anında
    // kuruyor, yani hepsi 30 sn'de bir ama FARKLI FAZDA çalışıyordu.
    // Ana sayfa t=0'da, Performans t=12'de açıldıysa iki yüzey 12 saniye
    // farklı anın verisini gösteriyordu (bkz. `TazelikRitmi.nabiz`).
    _nabziBirak = TazelikRitmi.nabiz.dinle(() {
      if (!mounted) return;
      // Gizli sekmede tazeleme yok (bkz. Performans `_startIntradayTickIfNeeded`,
      // animasyon denetimi 2026-10-01); dönünce en geç bir nabızda tazelenir.
      if (!TickerMode.getValuesNotifier(context).value.enabled) return;
      _seriyiTazele();
    });
  }

  @override
  void dispose() {
    _nabziBirak?.call();
    super.dispose();
  }

  /// Yalnızca GÜN İÇİ seriyi tazeler — diğer iki satıra dokunmaz.
  ///
  /// Reel getiri ve haftalık özet defterden bağımsızdır ve günde bir kez
  /// değişir; onları 30 saniyede bir çekmek boşuna ağ trafiği olurdu
  /// (`_yukle`'nin tek seferlik disiplini onlar için DOĞRU).
  ///
  /// `setState` yalnızca değer GERÇEKTEN değiştiyse çağrılır: her tick'te
  /// kartı yeniden çizmek gereksiz kare üretirdi.
  Future<void> _seriyiTazele() async {
    if (!_yuklendi) return; // ilk yükleme sürüyor, üstüne binme
    // `nabiz: true` — önbellek yaşa bakmadan tazelenir; Performans da bu
    // nabızda koşulsuz çekiyor (bkz. `IntradaySeriesCache.get` [zorla]).
    final yeni = await _seriYukle(nabiz: true);
    if (!mounted || yeni == null) return;
    final eski = _seri;
    if (eski != null &&
        eski.length == yeni.length &&
        eski.entries.every((e) => yeni[e.key] == e.value)) {
      return; // değişmedi
    }
    setState(() => _seri = yeni);
  }

  /// Bütçeyi aşan tur için tek bekleyici var mı? (bkz. [_turBitinceYukle])
  bool _turBekleniyor = false;

  /// Süren fiyat turu bitince (sınırsız değil: seri önbelleği ömrü kadar)
  /// gün içi seriyi kurar — [_seriYukle] bütçesini aşan tur için.
  ///
  /// Nabız her 30 sn'de bunu yeniden isteyebilir; tek bekleyici yeter.
  void _turBitinceYukle(PortfolioNotifier notifier) {
    if (_turBekleniyor) return;
    _turBekleniyor = true;
    CrashReporter.arkaPlan(() async {
      try {
        await notifier.fiyatTurunuVeKareyiBekle(
            enFazla: TazelikRitmi.gunIciSeriOmru);
      } finally {
        _turBekleniyor = false;
      }
      if (!mounted) return;
      final yeni = await _seriYukle(nabiz: true);
      if (!mounted || yeni == null) return;
      setState(() => _seri = yeni);
    }(), reason: 'BugunKarti.turBitinceYukle');
  }

  @override
  void didUpdateWidget(BugunKarti oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Defter mount'ta boşken sonradan dolduysa (ilk varlık eklendi) yükleme
    // hiç istenmemiştir; şimdi iste. Aksi halde `_yuklendi` false kalır.
    if (!_istendi) {
      _yukle();
      return;
    }
    // DEFTER DEĞİŞTİYSE seri yeniden çekilir.
    //
    // ## Neden (kullanıcı bildirimi, 2026-09-22)
    // "10 çeyrek altın ekledim; ana sayfa günlük kartı +311, günlük özet
    // +378 dedi."
    //
    // Seri OTURUMDA BİR KEZ çekiliyordu (`_istendi`) — fiyat satırları
    // (reel getiri, haftalık) için doğru bir disiplin, ama gün içi seri
    // için DEĞİL: o seri DEFTERE bağlıdır. Alımdan sonra kart, YENİ
    // toplamı ESKİ gün başıyla kıyaslıyor ve aradaki farkı "bugünün
    // hareketi" diye yazıyordu.
    //
    // `PortfolioNotifier` mutasyonda `IntradaySeriesCache`'i düşürüyor
    // ama bu kart önbelleğe BİR DAHA SORMUYORDU; elindeki `_seri`
    // alanıyla çizmeye devam ediyordu. Performans ekranı 30 sn'lik
    // tick'iyle kendini toparladığı için iki yüzey ayrışıyordu.
    //
    // Yalnızca MİKTARI değiştiren fark tetikler: fiyat yenilemesi
    // (`refreshPrices`) defteri her 30 sn'de yeniden yayınlıyor ve her
    // yayında ağ isteği atmak boşuna trafik olurdu.
    if (_defterImzasi(oldWidget.state) != _defterImzasi(widget.state)) {
      _istendi = false;
      _yukle();
    }
  }

  /// Defterin MİKTAR imzası — fiyat değişimi bunu değiştirmez.
  ///
  /// Gün içi serinin neye göre çekildiğini özetler: hangi lot, ne kadar.
  /// `currentPrice` BİLEREK dışarı bırakılır — fiyat her tick'te oynar,
  /// seri ise yalnızca defter değişince bayatlar.
  static String _defterImzasi(PortfolioState s) {
    final parcalar = [
      for (final a in s.assets)
        if (a.isActive) '${a.id}:${a.quantity}:${a.kind.name}',
    ]..sort();
    return parcalar.join('|');
  }

  /// Üç yükleme birbirinden bağımsız, PARALEL ve tek seferlik (`_istendi`):
  /// kart her fiyat yenilemesinde yeniden kurulur, ama bu seriler oturumda
  /// bir kez çekilir — eski `RealReturnStrip` / `WeeklySummaryChip` ile aynı
  /// disiplin. Her biri kendi try/catch'inde: biri düşerse diğerleri çizilir.
  ///
  /// **Tek yayın (2026-09-21).** Eskiden her yükleme kendi `setState`'ini
  /// çağırıyordu; satırlar birer birer beliriyor, kart üç kez büyüyordu
  /// ("tek tek load oluyor" — kullanıcı). Şimdi sonuçlar yerelde toplanır
  /// ve kart TEK `setState` ile, tüm veriyle bir kez çizilir; o ana kadar
  /// iskelet durur. Zaman sınırı (`_yuklemeSuresi`) asılı bir çağrının
  /// diğer ikisini rehin almasını önler.
  Future<void> _yukle() async {
    if (_istendi || !mounted || widget.state.assets.isEmpty) return;
    _istendi = true;
    final sonuc = await Future.wait([
      _seriYukle(),
      _reelYukle(),
      _haftalikYukle(),
    ]);
    if (!mounted) return;
    setState(() {
      // `?? _seri`: tur bütçeyi aşmışsa seri buradan null gelir ve
      // `_turBitinceYukle` bu arada yazmış olabilir — ezilmesin.
      _seri = sonuc[0] as Map<int, double>? ?? _seri;
      _reel = sonuc[1] as ReelGetiriSatiri?;
      _haftalik = sonuc[2] as double?;
      _yuklendi = true;
    });
  }

  /// Gün içi seri.
  ///
  /// Kendi görünümünde kilit ekranı ve widget'la ORTAK önbellekten gelir
  /// (üç yüzey aynı rakamı göstermeli). Ortak / Birlikte görünümünde o
  /// önbellek KULLANILMAZ: tek yuvalı ve oturumdaki kullanıcıya damgalı;
  /// başka bir defterle doldurmak kilit ekranını yanlış seriyle beslerdi.
  /// Kapsam serisi doğrudan çekilir — aynı servis, aynı hesap, ayrı yuva.
  Future<Map<int, double>?> _seriYukle({bool nabiz = false}) async {
    try {
      // Süren fiyat turu bitmeden ve turun defteri BU WIDGET'A inmeden
      // seri KURULMAZ (2026-09-24).
      //
      // İki ayak: (1) soğuk açılışta `MainNavigationScreen`'in açılış turu
      // ağdayken seri kurulursa altın/döviz gün başı referansı henüz
      // yoktur, motor eski yola düşer; (2) tur bitse bile `widget.state`
      // yeni defteri ancak bir sonraki karede taşır — hem açılışta hem
      // nabızda seri bir tur önceki fiyatla kalibre ediliyordu. Gerekçe
      // ve ölçümler `TazelikRitmi.turuBekle` / `turuVeKareyiBekle`. Süre
      // kartın kendi yükleme bütçesi: asılı tur iskeleti 30 sn tutmamalı.
      final notifier = ref.read(portfolioProvider.notifier);
      await notifier.fiyatTurunuVeKareyiBekle(enFazla: _yuklemeSuresi);
      if (!mounted) return null;
      // Bütçe doldu ama tur HÂLÂ ağda: eski defterle seri KURULMAZ.
      //
      // Emülatörde ölçüldü (2026-09-24): açılış turu 27 sn sürdü, kart
      // 10 sn'de eldeki (DB'den gelen, saatler önceki) fiyatla seriyi
      // kurdu ve −₺6.317 yazdı; Performans turdan sonra −₺9.711. Bir
      // sonraki nabızda eşitlendi — kullanıcının "kill sonrası farklı,
      // 20-30 sn sonra eşit" bildirimi birebir bu. Eski fiyattan üretilen
      // rakam bir ölçüm değil, uydurma sayıdır: hareket satırı tur bitene
      // kadar BOŞ kalır, kartın kalanı çizilir, tur bitince satır gelir.
      if (notifier.fiyatTuruSuruyor) {
        _turBitinceYukle(notifier);
        return null;
      }
      // Yükleme `BugunYukleyici`'de: splash aynı fonksiyonu ısıtır, kart
      // önbellekten alır ve iskelet çizmez (2026-09-28). Ortak/Birlikte
      // kapsamında seriye YALNIZCA fiyatlanabilir lot'lar girer —
      // Performans ekranıyla AYNI kural (`FiyatKaynagi.seriyeGirer`);
      // eleme eskiden yalnızca Performans'ta vardı ve bu kart ham
      // `activeAssets` gönderiyordu, aynı defterden iki farklı seri
      // çıkıyordu (kullanıcı bildirimi 2026-09-22). Kişisel kapsamda seri
      // kilit ekranı ve widget'la ORTAK önbellekten gelir; ortak kapsamda
      // o önbellek kullanılmaz (tek yuvalı, oturumdaki kullanıcıya damgalı).
      return await BugunYukleyici.seri(
        widget.state,
        kisisel: widget.kisisel,
        azamiYas: _seriTazelikPenceresi,
        zorla: nabiz,
        enFazla: _yuklemeSuresi,
      );
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'BugunKarti.intraday');
      return null;
    }
  }

  /// Yıllık reel getiri — eski `RealReturnStrip` ile AYNI kaynak
  /// (`RealReturnService.yillik`), aynı bayrak. Kapı: bayrak kapalıysa ya da
  /// pencere/seri kurulamıyorsa satır hiç çizilmez (uydurma yok).
  Future<ReelGetiriSatiri?> _reelYukle() =>
      BugunYukleyici.reel(widget.state, enFazla: _yuklemeSuresi);

  /// Son 7 günün (kayan, ucu canlı) piyasa getirisi — eski
  /// `WeeklySummaryChip` ile aynı hesap (`PeriodSummaryService.compute`, 1H
  /// penceresi), aynı bayrak. Etiket "Son 7 gün": gerekçe
  /// `HaftalikOzetSatiri`.
  Future<double?> _haftalikYukle() =>
      BugunYukleyici.haftalik(widget.state, enFazla: _yuklemeSuresi);

  /// Yükleme bitene kadar kartın yerini tutan iskelet — başlık, üç defter
  /// satırı. Kart tek seferde, tüm veriyle gelir; parça parça büyümez.
  Widget _iskelet(BuildContext context) => Padding(
        padding: widget.padding,
        child: SandikCard(
          padding: const EdgeInsets.fromLTRB(SandikSpace.md, SandikSpace.md2,
              SandikSpace.md, SandikSpace.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SandikSkeleton(width: 56, height: 40),
                  const SizedBox(width: SandikSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SandikSkeleton(width: 120, height: 12),
                        SizedBox(height: SandikSpace.xs),
                        SandikSkeleton(width: 180, height: 18),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SandikSpace.smd),
              Divider(height: 1, color: context.c.hairline),
              const SizedBox(height: SandikSpace.xs),
              for (var i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: SandikSpace.sm),
                  child: Row(
                    children: [
                      SandikSkeleton(width: 96, height: 12),
                      Spacer(),
                      SandikSkeleton(width: 64, height: 12),
                    ],
                  ),
                ),
              const SizedBox(height: SandikSpace.xs),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_yuklendi && widget.state.assets.isNotEmpty) return _iskelet(context);
    final now = DateTime.now();
    final seri = _seri;
    final ozet = seri == null
        ? null
        : DailySummary.from(state: widget.state, series: seri, now: now);
    // Sahiplik sınırı korunur: Birlikte görünümünde `state.assets` ben +
    // ortakların BİRLEŞİK defteridir ve `positionKey` sahip taşımaz — tek
    // havuzda toplanırsa iki kişinin aynı hissesi tek pozisyona düşer,
    // birinin satışı diğerinin lotunu düşer (bkz. `aggregatePositionsByOwner`).
    // Kendi görünümünde tek grup çıkar, hesap aynıdır.
    final sahipler = lotlarSahibeGore(widget.state.assets);
    final pozisyonlar = aggregatePositionsByOwner(
        [for (final lots in sahipler) aktifLotlar(lots)]);
    final veri = BugunService.hesapla(
      karZararlar: [for (final p in pozisyonlar) p.gainLoss],
      // `sonFiyat` ŞART — aynı kartın içindeki `ozet` (DailySummary.from)
      // bu düşüşü yapıyor, bu toplam yapmıyordu. Ortak lot'unun fiyatı
      // bayatsa toplam onu saymıyor, kâr/zarar sayıyordu: aynı kartta iki
      // sayı ayrışıyordu (kullanıcı bildirimi 2026-09-22).
      toplamDeger: ownerScopedTotalValue(sahipler,
          toTRY: widget.state.toTRY,
          sonFiyat: PriceService.instance.sonBilinenFiyat),
      ozet: ozet,
      hedefTRY: ref.watch(kapsamHedefiProvider(widget.hedefKapsami)),
      now: now,
      reel: _reel,
      haftalikGetiriPct: _haftalik,
      kisisel: widget.kisisel,
      // "Piyasa kapalı" yalnızca tamamen borsa portföyüne (2026-10-01).
      // Kartın gösterdiği KAPSAMIN defteri — Birlikte'de ortağın altını da
      // rakamı hareket ettirir.
      yalnizcaBorsa: yalnizcaBorsaVarliklardan(widget.state.assets),
    );
    if (veri.bos) return const SizedBox.shrink();
    _gosterimiOlc(veri, now);

    final gizli = ref.watch(balanceHiddenProvider);
    final dil = Localizations.localeOf(context).languageCode == 'en'
        ? 'en_US'
        : 'tr_TR';

    // Almanak düzeni (2026-09-21, kullanıcı seçimi "A"): tarih sütunu +
    // günün hareketi başlıkta; geri kalanı etiket ····· değer biçiminde
    // DEFTER satırları; yaklaşan olay kartın ayak notu. Her satırın altında
    // tek satırlık kısa açıklama — "bu ne demek?" sorusu kartta kalmasın.
    //
    // Sıra: reel (sabit) → haftalık (sabit, Pzt–Sal) → dönüşen içgörüler →
    // aylık özet. Olay defterde değil, ayakta (her gün görünür).
    final defter = <BugunSatiri>[
      if (veri.reel != null) veri.reel!,
      if (veri.haftalik != null) veri.haftalik!,
      ...veri.ikincil,
      if (veri.aylik != null) veri.aylik!,
    ];

    return Padding(
      padding: widget.padding,
      child: SandikCard(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.md, SandikSpace.md2, SandikSpace.md, SandikSpace.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kapsam etiketi (seçenek 3, 2026-09-21): görünüm çipi toplam
            // kartında kimde olduğunu söyler ama bu kart ondan aşağıda,
            // kendi başına okunur — "kimin bugünü" sorusu kartta cevaplanır.
            if (widget.etiket != null)
              Padding(
                padding: const EdgeInsets.only(bottom: SandikSpace.sm),
                child: Text(
                  // Türkçe büyük harf: düz `toUpperCase` "AYŞE'NIN" verir.
                  trBuyukHarf(widget.etiket!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelSmall?.copyWith(
                    color: context.c.text58,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            _Baslik(
              now: now,
              dil: dil,
              birincil: veri.birincil,
              seri: ozet?.sparkline ?? const [],
              gizli: gizli,
              kapaliSoylenir: veri.kapaliSoylenir,
            ),
            if (defter.isNotEmpty) ...[
              const SizedBox(height: SandikSpace.smd),
              Divider(height: 1, color: context.c.hairline),
              const SizedBox(height: SandikSpace.xs),
              for (final s in defter) _defterSatiri(s, gizli),
            ],
            if (veri.olay != null)
              _AyakNotu(olay: veri.olay!, dil: dil)
            else
              const SizedBox(height: SandikSpace.xs),
          ],
        ),
      ),
    );
  }

  /// Defter satırı: etiket ····· değer, altında kısa açıklama.
  Widget _defterSatiri(BugunSatiri s, bool gizli) {
    final l10n = context.l10n;
    final c = context.c;
    switch (s) {
      case ReelGetiriSatiri():
        // Eski şeritle aynı hedef: Performans › Özet › 1Y (reel getiri kartı).
        return _DefterSatiri(
          etiket: l10n.todayRealLabel,
          ipucu: l10n.todayRealHint,
          deger: reelFarkMetni(l10n, fark: s.fark, onde: s.onde),
          renk: s.onde ? c.gain : c.loss,
          onTap: _olcerek(s, () => _ozeteGit(periodIdx: SummaryPeriod.birYil.index)),
        );
      case HaftalikOzetSatiri():
        // Eski çiple aynı hedef: Özet › 1H.
        return _DefterSatiri(
          etiket: l10n.todayWeekLabel,
          ipucu: l10n.todayWeekHint,
          // İşaret zaten vardı ama sıfırda "+%0,00" yazıyordu; ortak biçim.
          deger: isaretliYuzde(s.getiriPct),
          renk: s.getiriPct >= 0 ? c.gain : c.loss,
          onTap: _olcerek(s, () => _ozeteGit(periodIdx: SummaryPeriod.birHafta.index)),
        );
      case HedefSatiri():
        if (s.belirlenmedi) {
          return _DefterSatiri(
            etiket: l10n.todayGoalLabel,
            ipucu: l10n.todayGoalSetShort,
            deger: l10n.todayGoalAction,
            renk: c.amberText,
            onTap: _olcerek(s, () => showHedefSheet(context, ref,
                kapsam: widget.hedefKapsami, etiket: widget.etiket)),
          );
        }
        final hedef = gizli ? '••••' : fmtTRYCompactSade(s.hedefTRY.toDouble());
        if (s.ulasildi) {
          return _DefterSatiri(
            etiket: l10n.todayGoalLabel,
            ipucu: l10n.todayGoalDoneHint(hedef),
            deger: l10n.todayGoalDone,
            renk: c.gain,
            onTap: _olcerek(s, () => showHedefSheet(context, ref,
                kapsam: widget.hedefKapsami, etiket: widget.etiket)),
          );
        }
        return _DefterSatiri(
          etiket: l10n.todayGoalLabel,
          ipucu: l10n.todayGoalLeftHint(hedef),
          deger: l10n.todayGoalValue(
              (s.oran * 100).floor(), gizli ? '••••' : fmtTRYCompactSade(s.kalan)),
          renk: c.amberText,
          cubuk: s.oran,
          onTap: _olcerek(s, () => showHedefSheet(context, ref,
                kapsam: widget.hedefKapsami, etiket: widget.etiket)),
        );
      case YesilOranSatiri():
        return _DefterSatiri(
          etiket: l10n.todayGreenLabel,
          ipucu: l10n.todayGreenHint,
          deger: l10n.todayGreenValue(s.yesil, s.toplam),
          renk: s.yesil * 2 >= s.toplam ? c.gain : c.text90,
        );
      case AylikOzetSatiri():
        return _DefterSatiri(
          etiket: l10n.todayMonthlySummary(DateFormat.MMMM(_dil).format(s.ay)),
          ipucu: l10n.todayMonthlySummaryHint,
          deger: l10n.todayOpenAction,
          renk: c.amberText,
          onTap: _olcerek(
            s,
            () => pushGuarded<void>(
              context,
              adaptiveRoute<void>(
                builder: (_) => const PortfolioPerformanceScreen(
                  showBackButton: true,
                  initialOzet: true,
                  // 1A — geçen ayın özeti; Özet sekmesi TÜFE farkını da taşır.
                  initialPeriodIdx: 2,
                ),
              ),
            ),
          ),
        );
      // Başlıkta ve ayakta çizilirler; defterde yerleri yok.
      case GunlukDegisimSatiri():
      case PiyasaKapaliSatiri():
      case YaklasanOlaySatiri():
        return const SizedBox.shrink();
    }
  }

  String get _dil =>
      Localizations.localeOf(context).languageCode == 'en' ? 'en_US' : 'tr_TR';

  /// Performans › Özet, verilen dönemde ([SummaryPeriod] indeksi — sayı
  /// değil adla verilir; 2026-09-28'de 3A eklenince 6A/1Y kaydı).
  void _ozeteGit({required int periodIdx}) => pushGuarded<void>(
        context,
        adaptiveRoute<void>(
          builder: (_) => PortfolioPerformanceScreen(
            showBackButton: true,
            initialOzet: true,
            initialPeriodIdx: periodIdx,
          ),
        ),
      );

  /// Gösterim ölçümü — gün + satır bileşimi başına BİR olay.
  ///
  /// Kart her fiyat yenilemesinde yeniden kurulur; her build'i saymak
  /// "kaç kez görüldü"yü değil "kaç kez çizildi"yi ölçerdi. Anahtar
  /// uygulama ömrü boyunca statik: aynı gün ikinci açılışta tekrar
  /// sayılmaz, ertesi gün sayılır.
  static String? _sonOlculen;

  void _gosterimiOlc(BugunKartiVerisi veri, DateTime now) {
    final turler = [
      if (veri.birincil != null) _tur(veri.birincil!),
      if (veri.reel != null) _tur(veri.reel!),
      if (veri.haftalik != null) _tur(veri.haftalik!),
      for (final s in veri.ikincil) _tur(s),
      if (veri.aylik != null) _tur(veri.aylik!),
      if (veri.olay != null) _tur(veri.olay!),
    ];
    final anahtar = '${dayKey(now)}|${turler.join(',')}';
    if (_sonOlculen == anahtar) return;
    _sonOlculen = anahtar;
    for (final t in turler) {
      unawaited(AnalyticsService.instance.logTodayRowShown(kind: t));
    }
  }

  static String _tur(BugunSatiri s) => switch (s) {
        GunlukDegisimSatiri() => 'degisim',
        PiyasaKapaliSatiri() => 'kapali',
        YesilOranSatiri() => 'yesil',
        HedefSatiri() => s.belirlenmedi ? 'hedef_yok' : 'hedef',
        ReelGetiriSatiri() => 'reel',
        HaftalikOzetSatiri() => 'haftalik',
        YaklasanOlaySatiri() => switch (s.tur) {
            BugunOlayTuru.tuikAciklamasi => 'olay_tuik',
            BugunOlayTuru.bistTatili => 'olay_tatil',
            BugunOlayTuru.aySonu => 'olay_aysonu',
          },
        AylikOzetSatiri() => 'aylik',
      };

  /// Dokunuş ölçümü — satırın kendi eylemini sarar.
  VoidCallback _olcerek(BugunSatiri s, VoidCallback eylem) => () {
        unawaited(AnalyticsService.instance.logTodayRowTapped(kind: _tur(s)));
        eylem();
      };
}

// ── Başlık: tarih sütunu + günün hareketi ────────────────────────────────────

/// Yaprak takvim: sol sütunda büyük gün rakamı, ay ve gün adı; sağda günün
/// hareketi. Tarih kartın "her gün değişir" hissini biçimle verir, metinle
/// değil. Sütun sabit genişlikte; hero sütunu kalan yeri alır ve 320pt'te
/// sparkline'ı bırakır (`LayoutBuilder`).
class _Baslik extends StatelessWidget {
  const _Baslik({
    required this.now,
    required this.dil,
    required this.birincil,
    required this.seri,
    required this.gizli,
    required this.kapaliSoylenir,
  });

  final DateTime now;
  final String dil;
  final BugunSatiri? birincil;
  final List<double> seri;
  final bool gizli;
  final bool kapaliSoylenir;

  static const double _tarihGenisligi = 60;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Sütunun yüksekliği Column içinde sınırsız; `stretch` sonsuz yükseklik
    // ister. Ayırıcı sabit boyda, satır ortalanır.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _tarihGenisligi,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${now.day}',
                style: context.t.displaySmall?.copyWith(
                  color: c.text90,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: SandikSpace.xs),
              // toUpperCase Türkçe "i"yi bozar (PAZARTESI); başlık hâli kalır.
              Text(
                DateFormat.MMMM(dil).format(now),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelLarge?.copyWith(
                  color: c.text58,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                DateFormat.EEEE(dil).format(now),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelLarge?.copyWith(color: c.text36),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
          child: SizedBox(
            width: 1,
            height: SandikSpace.xxl,
            child: ColoredBox(color: c.hairline),
          ),
        ),
        Expanded(
          child: _Hero(
              now: now,
              dil: dil,
              birincil: birincil,
              seri: seri,
              gizli: gizli,
              kapaliSoylenir: kapaliSoylenir),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.now,
    required this.dil,
    required this.birincil,
    required this.seri,
    required this.gizli,
    required this.kapaliSoylenir,
  });

  final DateTime now;
  final String dil;
  final BugunSatiri? birincil;
  final List<double> seri;
  final bool gizli;

  /// Bkz. `BugunKartiVerisi.kapaliSoylenir`.
  final bool kapaliSoylenir;

  /// Sparkline için hero sütununun en az genişliği (pt). Altında sayı ve
  /// yüzde tek başına kalır; 320pt ekranda buraya ~165pt düşüyor.
  static const double _sparklineEsigi = 200;

  String _saat(DateTime gun, int dk) =>
      DateFormat.Hm().format(dayKey(gun).add(Duration(minutes: dk)));

  /// "Pazartesi 10:00 açılır" / "bugün 10:00 açılır".
  String _acilis(AppLocalizations l10n) {
    final acilis = BugunService.sonrakiAcilis(now);
    final ayniGun = dayKey(acilis) == dayKey(now);
    final ne = ayniGun
        ? l10n.todayAt(DateFormat.Hm().format(acilis))
        : '${DateFormat.EEEE(dil).format(acilis)} ${DateFormat.Hm().format(acilis)}';
    return l10n.todayOpensAt(ne);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final s = birincil;

    String buyuk;
    Color renk;
    String? yuzde;
    String alt;
    var seriCiz = false;
    if (s is GunlukDegisimSatiri) {
      final acik = BugunService.seansAcikMi(now);
      if (s.flat) {
        buyuk = gizli ? '••••' : fmtTRY(0);
        renk = c.text58;
        alt = l10n.todayFlat;
      } else {
        buyuk = gizli
            ? '••••'
            : '${s.changeTRY > 0 ? '+' : '−'}${fmtTRY(s.changeTRY.abs())}';
        renk = context.signColor(s.changeTRY);
        // Tutarla aynı işaret biçimi (F3) — yön yalnız renkte kalmasın.
        yuzde = isaretliYuzde(s.changePct);
        alt = acik
            ? l10n.todaySessionOpen(_saat(
                now,
                BistTakvimi.yarimGunMu(now)
                    ? BistTakvimi.yarimGunKapanisDk
                    : BugunService.seansKapanisDk))
            // Karışık portföy (altın/döviz/kripto): borsa kapalı olsa da
            // rakam işler — "Piyasa kapalı" yanlış olurdu (2026-10-01).
            : kapaliSoylenir
                ? '${l10n.todayClosedWord} · ${_acilis(l10n)}'
                : l10n.todayLiveWord;
      }
      seriCiz = !gizli && seri.length >= 2;
    } else if (s is PiyasaKapaliSatiri) {
      buyuk = l10n.todayClosedWord;
      renk = c.text58;
      alt = _acilis(l10n);
    } else {
      // Seans açık, gün içi seri henüz gelmedi: uydurma sayı yok.
      buyuk = '—';
      renk = c.text36;
      alt = l10n.todayLoading;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.todayTitle,
              style: context.t.labelLarge?.copyWith(
                color: c.amberText,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: Text(
                l10n.todayMarketOnly,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelMedium?.copyWith(color: c.text36),
              ),
            ),
          ],
        ),
        const SizedBox(height: SandikSpace.xs),
        LayoutBuilder(
          builder: (context, k) {
            final sparkOlsun = seriCiz && k.maxWidth >= _sparklineEsigi;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Uzun tutar (−₺2.418.191) dar sütunda küçülür, kırpılmaz.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      buyuk,
                      maxLines: 1,
                      style: context.t.headlineLarge?.copyWith(
                        color: renk,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
                if (yuzde != null) ...[
                  const SizedBox(width: SandikSpace.sm),
                  Padding(
                    padding: const EdgeInsets.only(bottom: SandikSpace.xxs),
                    child: Text(
                      yuzde,
                      style: context.t.bodyMedium?.copyWith(
                        color: c.text58,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (sparkOlsun) ...[
                  const Spacer(),
                  _GunIciCizgi(seri: seri, renk: renk),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: SandikSpace.xxs),
        Text(
          alt,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.t.bodySmall?.copyWith(color: c.text58),
        ),
      ],
    );
  }
}

/// Gün içi eğri — 64×24, tek `drawPath`. Kilit ekranı/widget ile aynı ham
/// seri; burada yalnızca yönü anlatır, eksen yok.
class _GunIciCizgi extends StatelessWidget {
  const _GunIciCizgi({required this.seri, required this.renk});

  final List<double> seri;
  final Color renk;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: const Size(64, 24),
          painter: _GunIciPainter(seri: seri, renk: renk),
        ),
      );
}

class _GunIciPainter extends CustomPainter {
  const _GunIciPainter({required this.seri, required this.renk});

  final List<double> seri;
  final Color renk;

  @override
  void paint(Canvas canvas, Size size) {
    if (seri.length < 2) return;
    var min = seri.first, max = seri.first;
    for (final v in seri) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    // Göreli düz eşik — `DailySummary.isFlat` ile aynı gerekçe: 5 kuruşluk
    // fark tuvale yayılmasın.
    final aralik = max - min;
    final duz = aralik <= max.abs() * 1e-6;
    final yol = Path();
    for (var i = 0; i < seri.length; i++) {
      final x = size.width * i / (seri.length - 1);
      final y = duz
          ? size.height / 2
          : size.height - ((seri[i] - min) / aralik) * (size.height - 2) - 1;
      if (i == 0) {
        yol.moveTo(x, y);
      } else {
        yol.lineTo(x, y);
      }
    }
    final cizgi = Paint()
      ..color = renk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(yol, cizgi);
    final son = yol.computeMetrics().last;
    final uc = son.getTangentForOffset(son.length)?.position;
    if (uc != null) canvas.drawCircle(uc, 2, Paint()..color = renk);
  }

  @override
  bool shouldRepaint(_GunIciPainter old) =>
      old.renk != renk || !identical(old.seri, seri);
}

// ── Defter satırı ────────────────────────────────────────────────────────────

/// `etiket ····· değer ›` ve altında tek satırlık açıklama.
///
/// **Neden ölçüm var:** `Row` içinde `Flexible(etiket)` + `Expanded(kılavuz)`
/// serbest alanı flex oranında böler; etiket payının artığı kılavuza
/// geçmez ve noktalar değere ulaşmaz. Etiket ve değer `TextPainter` ile
/// ölçülür, etikete "değer + ok + en az 24pt kılavuz" dışında kalan yer
/// verilir; dar ekranda önce etiket kısalır (…), değer hiç kırpılmaz.
class _DefterSatiri extends StatelessWidget {
  const _DefterSatiri({
    required this.etiket,
    required this.deger,
    required this.renk,
    this.ipucu,
    this.cubuk,
    this.onTap,
  });

  final String etiket;
  final String? ipucu;
  final String deger;
  final Color renk;

  /// 0..1 ilerleme (hedef) — değerin altında ince çubuk.
  final double? cubuk;
  final VoidCallback? onTap;

  static const double _kilavuzMin = 24;
  static const double _okBoyu = 18;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final etiketStil = context.t.bodyLarge?.copyWith(
      color: c.text90,
      fontWeight: FontWeight.w600,
    );
    final degerStil = context.t.bodyLarge?.copyWith(
      color: renk,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final ust = LayoutBuilder(
      builder: (context, k) {
        final olcek = MediaQuery.textScalerOf(context);
        double genislik(String metin, TextStyle? stil) {
          final tp = TextPainter(
            text: TextSpan(text: metin, style: stil),
            textDirection: Directionality.of(context),
            maxLines: 1,
            textScaler: olcek,
          )..layout();
          final w = tp.width;
          tp.dispose();
          return w;
        }

        final okW = onTap == null ? 0.0 : _okBoyu + SandikSpace.xxs;
        final degerW = genislik(deger, degerStil);
        final etiketMax =
            (k.maxWidth - degerW - okW - _kilavuzMin - 2 * SandikSpace.sm)
                .clamp(0.0, k.maxWidth);
        // +1: alt piksel yuvarlaması etiketi gereksiz yere "…"lemesin.
        final etiketW =
            (genislik(etiket, etiketStil) + 1).clamp(0.0, etiketMax);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: etiketW,
              child: Text(
                etiket,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: etiketStil,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    SandikSpace.sm, 0, SandikSpace.sm, SandikSpace.xs),
                child: _NoktaKilavuz(renk: c.text20),
              ),
            ),
            Text(deger, maxLines: 1, softWrap: false, style: degerStil),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: SandikSpace.xxs),
                child: Icon(Icons.chevron_right_rounded,
                    size: _okBoyu, color: c.text36),
              ),
          ],
        );
      },
    );

    final govde = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ust,
            if (ipucu != null)
              Padding(
                padding: const EdgeInsets.only(top: SandikSpace.xxs),
                child: Text(
                  ipucu!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodySmall?.copyWith(color: c.text58),
                ),
              ),
            if (cubuk != null)
              Padding(
                padding: const EdgeInsets.only(top: SandikSpace.xs2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                  child: SizedBox(
                    height: SandikSpace.xs,
                    child: Stack(
                      children: [
                        Container(color: c.surface2),
                        FractionallySizedBox(
                          widthFactor: cubuk!.clamp(0.02, 1.0),
                          child: Container(color: renk),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (onTap == null) return govde;
    // Şeffaf Material: mürekkep katmanı ata iskeleye bağlı kalmasın
    // (Performans'taki "No Material widget found" dersi, 2026-09-21).
    return Semantics(
      button: true,
      label: '$etiket, $deger. ${ipucu ?? ''}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SandikRadius.sm),
          child: govde,
        ),
      ),
    );
  }
}

/// Noktalı kılavuz — etiket ile değer arasını dolduran nokta dizisi.
class _NoktaKilavuz extends StatelessWidget {
  const _NoktaKilavuz({required this.renk});
  final Color renk;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: SandikSpace.xxs,
        child: CustomPaint(painter: _NoktaPainter(renk)),
      );
}

class _NoktaPainter extends CustomPainter {
  const _NoktaPainter(this.renk);
  final Color renk;

  @override
  void paint(Canvas canvas, Size size) {
    final boya = Paint()..color = renk;
    const adim = 4.0;
    for (var x = 1.0; x < size.width; x += adim) {
      canvas.drawCircle(Offset(x, size.height / 2), 0.8, boya);
    }
  }

  @override
  bool shouldRepaint(_NoktaPainter old) => old.renk != renk;
}

// ── Ayak notu: yaklaşan olay ─────────────────────────────────────────────────

/// "TÜİK enflasyonu · 3 Ekim ······ 13 gün" — kartın altındaki damga.
class _AyakNotu extends StatelessWidget {
  const _AyakNotu({required this.olay, required this.dil});

  final YaklasanOlaySatiri olay;
  final String dil;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final tarih = DateFormat('d MMMM', dil).format(olay.tarih);
    final ne = switch (olay.tur) {
      BugunOlayTuru.tuikAciklamasi => l10n.todayEventCpiShort(tarih),
      BugunOlayTuru.bistTatili => l10n.todayEventHolidayShort(tarih),
      BugunOlayTuru.aySonu => l10n.todayEventMonthEndShort,
    };
    final kalan = switch (olay.gunKaldi) {
      0 => l10n.todayWordToday,
      1 => l10n.todayWordTomorrow,
      _ => l10n.todayDaysShort(olay.gunKaldi),
    };
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: c.hairline),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
            child: Row(
              children: [
                Icon(Icons.event_rounded, size: 14, color: c.text36),
                const SizedBox(width: SandikSpace.xs2),
                Expanded(
                  child: Text(
                    ne,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodySmall?.copyWith(color: c.text58),
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Text(
                  kalan,
                  style: context.t.bodySmall?.copyWith(
                    color: c.amberText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
