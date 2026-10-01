// Ana ekrandaki "Bugün" kartı.
//
// Hesap `services/bugun_service.dart`'ta (saf); burada yalnızca gün içi
// serinin çekimi (kilit ekranı/widget ile ORTAK önbellek — üç yüzey aynı
// rakamı göstermeli), tercihler ve çizim var.
//
// Kendi kapılarını kendi kurar: kendi görünümü + açık pozisyon varken
// çizilir; seri gelmeden de kalan satırları gösterir (boş kart yok).
//
// Düzen (2026-10-01, "sakin pano", kullanıcı seçimi D): üstte takvim
// yaprağı + gün + seans durumu; altında ölçüm bloğu (tutar, yüzde rozeti,
// tam genişlik gün içi eğri, açılış seviyesi kesik çizgi); sonra iki
// sütunlu BİLGİ kutuları (enflasyona göre + TÜFE çubuğu, son 7 gün,
// artıdaki varlık) ve amber EYLEM kutuları (hedef, aylık özet); en altta
// yaklaşan olay ayak notu. Önceki "almanak" (2026-09-21) beş satırı aynı
// ağırlıkta alt alta diziyordu; ölçüm / bağlam / eylem ayrımı yoktu.
import 'dart:async';
import '../services/tazelik_ritmi.dart';
import '../services/price_service.dart';

import 'package:flutter/foundation.dart' show listEquals;
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
String reelFarkMetni(AppLocalizations l10n,
    {required double fark, required bool onde}) {
  final puan = fmtNum(fark.abs(), digits: 1);
  if (puan == fmtNum(0, digits: 1)) return l10n.todayRealEven;
  return onde ? l10n.todayRealAhead(puan) : l10n.todayRealBehind(puan);
}

/// Bkz. `_BugunKartiState._sonYukleme`.
typedef _BugunAnligi = ({
  String imza,
  DateTime at,
  Map<int, double>? seri,
  ReelGetiriSatiri? reel,
  double? haftalik,
});
final Map<String, _BugunAnligi> _bugunSonYukleme = {};

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

  /// Kapsam başına son yükleme önbelleğini boşaltır (testler).
  @visibleForTesting
  static void anliklariTemizle() => _bugunSonYukleme.clear();

  @override
  ConsumerState<BugunKarti> createState() => _BugunKartiState();
}

class _BugunKartiState extends ConsumerState<BugunKarti> {
  Map<int, double>? _seri;
  ReelGetiriSatiri? _reel;
  double? _haftalik;
  bool _istendi = false;

  /// [_yukle] ağda mı — bkz. [_seriyiTazele].
  bool _yukleniyor = false;

  /// Üç yükleme de sonuçlandı mı (başarı ya da hata fark etmez)?
  /// `false` iken kart iskelet çizer — bkz. [_yukle].
  bool _yuklendi = false;

  /// Kapsam başına son yükleme (2026-10-01).
  ///
  /// Kart görünüm başına anahtarlı (`bugun-<görünüm>`): Ben → Ayşe → Ben
  /// kaydırmasında her dönüşte SIFIRDAN kuruluyor ve az önce gösterdiği
  /// sonucu yeniden yüklerken iskelet çiziyordu (kullanıcı: "günlük veri
  /// kartı yüklenmeden kaydırma olmuyor"). Şimdi kart, aynı defter için
  /// [_seriTazelikPenceresi] içinde yüklenmiş sonucu varsa onunla açılır;
  /// yükleme yine arkada koşar ve sonucu yazar. Pencere kartın kendi
  /// tazelik penceresidir: o yaştaki seri zaten "taze" sayılıyor, ikinci bir
  /// bayatlık kuralı yok. Defter imzası tutmazsa (alım/satım) kullanılmaz.
  static Map<String, _BugunAnligi> get _sonYukleme => _bugunSonYukleme;

  String get _anlikAnahtari => '${widget.kisisel}|${widget.hedefKapsami}';

  void _anligiKaydet() => _sonYukleme[_anlikAnahtari] = (
        imza: _defterImzasi(widget.state),
        at: DateTime.now(),
        seri: _seri,
        reel: _reel,
        haftalik: _haftalik,
      );

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
    final son = _sonYukleme[_anlikAnahtari];
    if (son != null &&
        son.imza == _defterImzasi(widget.state) &&
        DateTime.now().difference(son.at) <= _seriTazelikPenceresi) {
      _seri = son.seri;
      _reel = son.reel;
      _haftalik = son.haftalik;
      _yuklendi = true;
    }
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
    // İlk yükleme sürüyor, üstüne binme. `_yuklendi` tek başına yetmez:
    // kart son yüklemeyle açıldıysa (`_sonYukleme`) yükleme arkada sürer.
    if (!_yuklendi || _yukleniyor) return;
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
    _anligiKaydet();
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
      _anligiKaydet();
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
    _yukleniyor = true;
    final sonuc = await Future.wait([
      _seriYukle(),
      _reelYukle(),
      _haftalikYukle(),
    ]);
    _yukleniyor = false;
    if (!mounted) return;
    setState(() {
      // `?? _seri`: tur bütçeyi aşmışsa seri buradan null gelir ve
      // `_turBitinceYukle` bu arada yazmış olabilir — ezilmesin.
      _seri = sonuc[0] as Map<int, double>? ?? _seri;
      _reel = sonuc[1] as ReelGetiriSatiri?;
      _haftalik = sonuc[2] as double?;
      _yuklendi = true;
    });
    _anligiKaydet();
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

  /// Yükleme bitene kadar kartın yerini tutan iskelet — başlık, hareket
  /// bloğu, iki kutu. Kart tek seferde, tüm veriyle gelir; parça parça
  /// büyümez. Ölçüler gerçek düzenle aynı ki yükleme bitince kart zıplamasın.
  Widget _iskelet(BuildContext context) => Padding(
        padding: widget.padding,
        child: SandikCard(
          padding: const EdgeInsets.all(SandikSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SandikSkeleton(
                      width: _TarihKutusu.genislik, height: 46),
                  const SizedBox(width: SandikSpace.smd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SandikSkeleton(width: 56, height: 10),
                        SizedBox(height: SandikSpace.xs),
                        SandikSkeleton(width: 96, height: 16),
                      ],
                    ),
                  ),
                  const SandikSkeleton(width: 96, height: 12),
                ],
              ),
              const SizedBox(height: SandikSpace.md2),
              const SandikSkeleton(width: 140, height: 12),
              const SizedBox(height: SandikSpace.sm),
              const SandikSkeleton(width: 180, height: 36),
              const SizedBox(height: SandikSpace.sm),
              const SandikSkeleton(
                  width: double.infinity, height: _GunIciGrafik.yukseklik),
              const SizedBox(height: SandikSpace.md2),
              Divider(height: 1, color: context.c.hairline),
              const SizedBox(height: SandikSpace.md2),
              Row(
                children: const [
                  Expanded(child: SandikSkeleton(height: 84)),
                  SizedBox(width: SandikSpace.sm),
                  Expanded(child: SandikSkeleton(height: 84)),
                ],
              ),
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
    final dil = _dil;

    // Sakin pano düzeni (2026-10-01, kullanıcı seçimi "D"): hesap aynı,
    // satırlar KUTULARA ayrıldı. Eski almanakta beş defter satırı aynı
    // ağırlıkta alt alta duruyordu; "ne kadar", "neye göre" ve "ne yapmalı"
    // birbirine karışıyordu. Şimdi üç kat: ölçüm (hareket + gün içi eğri),
    // bağlam (enflasyon / son 7 gün / artıdaki varlık — bilgi kutuları),
    // eylem (hedef / aylık özet — amber kutular); olay yine ayakta.
    //
    // Kutular hesabın verdiği satırlardan türetilir; hangi satırın geldiği
    // (`BugunService.hesapla`: sabit reel + haftalık, dönen havuz, hedef
    // her gün) burada DEĞİŞMEZ — yalnızca nereye çizildiği.
    final bilgi = <BugunSatiri>[
      if (veri.reel != null) veri.reel!,
      if (veri.haftalik != null) veri.haftalik!,
      ...veri.ikincil.where((s) => s is! HedefSatiri),
    ];
    final eylem = <BugunSatiri>[
      ...veri.ikincil.whereType<HedefSatiri>(),
      if (veri.aylik != null) veri.aylik!,
    ];

    return Padding(
      padding: widget.padding,
      child: SandikCard(
        padding: const EdgeInsets.all(SandikSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Baslik(
              now: now,
              dil: dil,
              etiket: widget.etiket,
              durum: _durumMetni(veri.birincil, now),
              acik: veri.birincil is GunlukDegisimSatiri &&
                  BugunService.seansAcikMi(now),
            ),
            const SizedBox(height: SandikSpace.md2),
            _Hareket(
              birincil: veri.birincil,
              seri: ozet?.sparkline ?? const [],
              gizli: gizli,
            ),
            if (bilgi.isNotEmpty) ...[
              const SizedBox(height: SandikSpace.md2),
              Divider(height: 1, color: context.c.hairline),
              const SizedBox(height: SandikSpace.md2),
              _Izgara(
                  children: [for (final s in bilgi) _bilgiKutusu(s, gizli)]),
            ],
            if (eylem.isNotEmpty) ...[
              const SizedBox(height: SandikSpace.sm),
              _Izgara(
                  children: [for (final s in eylem) _eylemKutusu(s, gizli)]),
            ],
            if (veri.olay != null) ...[
              const SizedBox(height: SandikSpace.smd),
              _AyakNotu(olay: veri.olay!, dil: dil),
            ],
          ],
        ),
      ),
    );
  }

  /// Başlığın sağındaki durum: "Canlı · 18:10 kapanış" / "Piyasa kapalı ·
  /// Pazartesi 10:00 açılır" / "Canlı" (karışık portföy, borsa kapalı).
  ///
  /// Eski düzende bu metin hareketin ALTINDAYDI; sakin panoda tarih
  /// satırına çıktı ki hareket bloğu yalnızca ölçümü taşısın.
  String _durumMetni(BugunSatiri? s, DateTime now) {
    final l10n = context.l10n;
    String acilis() {
      final a = BugunService.sonrakiAcilis(now);
      final ayniGun = dayKey(a) == dayKey(now);
      final ne = ayniGun
          ? l10n.todayAt(DateFormat.Hm().format(a))
          : '${DateFormat.EEEE(_dil).format(a)} ${DateFormat.Hm().format(a)}';
      return l10n.todayOpensAt(ne);
    }

    if (s is PiyasaKapaliSatiri) return '${l10n.todayClosedWord} · ${acilis()}';
    if (s is GunlukDegisimSatiri) {
      if (BugunService.seansAcikMi(now)) {
        final kapanisDk = BistTakvimi.yarimGunMu(now)
            ? BistTakvimi.yarimGunKapanisDk
            : BugunService.seansKapanisDk;
        final kapanis = DateFormat.Hm()
            .format(dayKey(now).add(Duration(minutes: kapanisDk)));
        return '${l10n.todayLiveWord} · ${l10n.todayCloseAt(kapanis)}';
      }
      // Karışık portföy (altın/döviz/kripto): borsa kapalı olsa da rakam
      // işler — "Piyasa kapalı" yanlış olurdu (2026-10-01). Yalnızca borsa
      // portföyünde hesap zaten `PiyasaKapaliSatiri` üretir.
      return l10n.todayLiveWord;
    }
    return l10n.todayLoading;
  }

  /// Bilgi kutusu: etiket › / değer / açıklama (+ enflasyon çubuğu).
  Widget _bilgiKutusu(BugunSatiri s, bool gizli) {
    final l10n = context.l10n;
    final c = context.c;
    switch (s) {
      case ReelGetiriSatiri():
        // Eski şeritle aynı hedef: Performans › Özet › 1Y (reel getiri kartı).
        return _BilgiKutusu(
          etiket: '${l10n.todayRealLabel} · ${l10n.todayRealYearly}',
          deger: reelFarkMetni(l10n, fark: s.fark, onde: s.onde),
          renk: s.onde ? c.gain : c.loss,
          yon: s.onde,
          cubuk: _EnflasyonCubugu(nominal: s.nominal, tufe: s.inflation),
          altMetin:
              '${l10n.todayYourReturn(fmtPct(s.nominal))} · ${l10n.todayCpiShort(fmtPct(s.inflation))}',
          onTap: _olcerek(
              s, () => _ozeteGit(periodIdx: SummaryPeriod.birYil.index)),
        );
      case HaftalikOzetSatiri():
        // Eski çiple aynı hedef: Özet › 1H. Yön kelimeyle (F3): "%2,89 düşüş".
        final yuzde = fmtPct(s.getiriPct.abs());
        final sifir = s.getiriPct.abs() < 0.005;
        return _BilgiKutusu(
          etiket: l10n.todayWeekLabel,
          deger: sifir
              ? isaretliYuzde(0)
              : s.getiriPct > 0
                  ? l10n.todayWeekUp(yuzde)
                  : l10n.todayWeekDown(yuzde),
          renk: s.getiriPct >= 0 ? c.gain : c.loss,
          yon: sifir ? null : s.getiriPct > 0,
          altMetin: l10n.todayWeekHintShort,
          rozet: l10n.todayWeekReady,
          onTap: _olcerek(
              s, () => _ozeteGit(periodIdx: SummaryPeriod.birHafta.index)),
        );
      case YesilOranSatiri():
        return _BilgiKutusu(
          etiket: l10n.todayGreenLabel,
          deger: l10n.todayGreenValue(s.yesil, s.toplam),
          renk: s.yesil * 2 >= s.toplam ? c.gain : c.text90,
          altMetin: l10n.todayGreenHint,
        );
      // Eylem kutusunda ya da başlık/ayakta çizilirler.
      case HedefSatiri():
      case AylikOzetSatiri():
      case GunlukDegisimSatiri():
      case PiyasaKapaliSatiri():
      case YaklasanOlaySatiri():
        return const SizedBox.shrink();
    }
  }

  /// Eylem kutusu (amber zemin): ikon + başlık + alt satır.
  Widget _eylemKutusu(BugunSatiri s, bool gizli) {
    final l10n = context.l10n;
    switch (s) {
      case HedefSatiri():
        final hedefAc = _olcerek(
            s,
            () => showHedefSheet(context, ref,
                kapsam: widget.hedefKapsami, etiket: widget.etiket));
        if (s.belirlenmedi) {
          return _EylemKutusu(
            ikon: Icons.flag_outlined,
            baslik: l10n.todayGoalSetAction,
            alt: l10n.todayGoalSetSub,
            onTap: hedefAc,
          );
        }
        final hedef = gizli ? '••••' : fmtTRYCompactSade(s.hedefTRY.toDouble());
        if (s.ulasildi) {
          return _EylemKutusu(
            ikon: Icons.flag_rounded,
            baslik: '${l10n.todayGoalLabel} · ${l10n.todayGoalDone}',
            alt: l10n.todayGoalDoneHint(hedef),
            onTap: hedefAc,
          );
        }
        return _EylemKutusu(
          ikon: Icons.flag_outlined,
          baslik: l10n.todayGoalProgressTitle((s.oran * 100).floor()),
          alt: l10n
              .todayGoalLeftShort(gizli ? '••••' : fmtTRYCompactSade(s.kalan)),
          oran: s.oran,
          onTap: hedefAc,
        );
      case AylikOzetSatiri():
        return _EylemKutusu(
          ikon: Icons.menu_book_outlined,
          baslik: l10n.todayMonthlyTile(DateFormat.MMMM(_dil).format(s.ay)),
          alt: l10n.todayMonthlyTileSub,
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
      case ReelGetiriSatiri():
      case HaftalikOzetSatiri():
      case YesilOranSatiri():
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

// ── Başlık: tarih kutusu + gün + durum ───────────────────────────────────────

/// Yaprak takvim kutusu (amber ay bandı + gün rakamı), yanında "BUGÜN" /
/// gün adı, sağda seans durumu. Tarih kartın "her gün değişir" hissini
/// biçimle verir, metinle değil.
class _Baslik extends StatelessWidget {
  const _Baslik({
    required this.now,
    required this.dil,
    required this.etiket,
    required this.durum,
    required this.acik,
  });

  final DateTime now;
  final String dil;

  /// Kapsam etiketi ("Ayşe'nin bugünü", "Birlikte") — kendi görünümünde
  /// `null`, o zaman "BUGÜN" yazar. Görünüm çipi toplam kartında kimde
  /// olduğunu söyler ama bu kart ondan aşağıda, kendi başına okunur.
  final String? etiket;
  final String durum;

  /// Seans açık mı — durum noktasının rengi.
  final bool acik;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _TarihKutusu(now: now, dil: dil),
        const SizedBox(width: SandikSpace.smd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // Türkçe büyük harf: düz `toUpperCase` "AYŞE'NIN" verir.
                trBuyukHarf(etiket ?? context.l10n.todayTitle),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelSmall?.copyWith(
                  color: c.amberText,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                // toUpperCase Türkçe "i"yi bozar (PAZARTESI); başlık hâli kalır.
                DateFormat.EEEE(dil).format(now),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.titleMedium?.copyWith(
                  color: c.text90,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: SandikSpace.sm),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: SandikSpace.xs2,
                height: SandikSpace.xs2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: acik ? c.gain : c.text36,
                ),
              ),
              const SizedBox(width: SandikSpace.xs2),
              Flexible(
                child: Text(
                  durum,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: context.t.labelMedium?.copyWith(
                    color: c.text58,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Amber ay bandı üstte, büyük gün rakamı altta — 46pt'lik takvim yaprağı.
class _TarihKutusu extends StatelessWidget {
  const _TarihKutusu({required this.now, required this.dil});

  final DateTime now;
  final String dil;

  static const double genislik = 46;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: genislik,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            color: c.amberFill,
            padding: const EdgeInsets.symmetric(vertical: SandikSpace.xxs),
            child: Text(
              // "Eki" → "EKİ": Türkçe büyük harf (noktalı İ) için trBuyukHarf.
              trBuyukHarf(DateFormat.MMM(dil).format(now).replaceAll('.', '')),
              textAlign: TextAlign.center,
              maxLines: 1,
              style: context.t.labelSmall?.copyWith(
                color: c.onAmber,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                0, SandikSpace.xs2, 0, SandikSpace.xs2),
            child: Text(
              '${now.day}',
              style: context.t.titleLarge?.copyWith(
                color: c.text90,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hareket bloğu: etiket, tutar + yüzde rozeti, gün içi grafik ──────────────

class _Hareket extends StatelessWidget {
  const _Hareket({
    required this.birincil,
    required this.seri,
    required this.gizli,
  });

  final BugunSatiri? birincil;
  final List<double> seri;
  final bool gizli;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final s = birincil;

    String buyuk;
    Color renk;
    String? yuzde;
    bool? yon;
    var seriCiz = false;
    if (s is GunlukDegisimSatiri) {
      if (s.flat) {
        buyuk = gizli ? '••••' : fmtTRY(0);
        renk = c.text58;
      } else {
        buyuk = gizli
            ? '••••'
            : '${s.changeTRY > 0 ? '+' : '−'}${fmtTRY(s.changeTRY.abs())}';
        renk = context.signColor(s.changeTRY);
        // Rozet yönü OK ile söyler, yüzde işaretsiz: "▼ %0,18". Yön hem
        // okta hem renkte — renk körlüğünde ve ekran okuyucuda kaybolmaz (F3).
        yuzde = fmtPct(s.changePct.abs());
        yon = s.changeTRY > 0;
      }
      seriCiz = !gizli && seri.length >= 2;
    } else if (s is PiyasaKapaliSatiri) {
      buyuk = l10n.todayClosedWord;
      renk = c.text58;
    } else {
      // Seans açık, gün içi seri henüz gelmedi: uydurma sayı yok.
      buyuk = '—';
      renk = c.text36;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: l10n.todayMoveLabel,
            style: context.t.labelMedium?.copyWith(
              color: c.text58,
              fontWeight: FontWeight.w600,
            ),
            children: [
              TextSpan(
                text: ' · ${l10n.todayMarketOnly}',
                style: context.t.labelMedium?.copyWith(color: c.text36),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: SandikSpace.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Uzun tutar (−₺2.418.191) dar sütunda küçülür, kırpılmaz.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  buyuk,
                  maxLines: 1,
                  style: context.t.displaySmall?.copyWith(
                    color: c.text90,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: -1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            if (yuzde != null) ...[
              const SizedBox(width: SandikSpace.sm2),
              _YuzdeRozeti(metin: yuzde, renk: renk, yon: yon),
            ],
          ],
        ),
        if (seriCiz) ...[
          const SizedBox(height: SandikSpace.sm),
          _GunIciGrafik(seri: seri, renk: renk),
          const SizedBox(height: SandikSpace.xxs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.todayAxisOpen,
                  style: context.t.labelSmall?.copyWith(color: c.text36)),
              Text(l10n.todayAxisNow,
                  style: context.t.labelSmall?.copyWith(color: c.text36)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Renkli zeminli yüzde rozeti: "▼ %0,18".
class _YuzdeRozeti extends StatelessWidget {
  const _YuzdeRozeti({required this.metin, required this.renk, this.yon});

  final String metin;
  final Color renk;

  /// `true` yukarı, `false` aşağı, `null` oksuz.
  final bool? yon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.xs2, SandikSpace.xs, SandikSpace.sm, SandikSpace.xs),
        decoration: BoxDecoration(
          color: renk.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(SandikRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (yon != null)
              Icon(
                yon!
                    ? Icons.arrow_drop_up_rounded
                    : Icons.arrow_drop_down_rounded,
                size: 18,
                color: renk,
              ),
            Text(
              metin,
              style: context.t.labelLarge?.copyWith(
                color: renk,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
}

/// Gün içi eğri — tam genişlik, altı renk gölgeli, gün başı kesik çizgi.
///
/// Eski 64×24 kıvılcımın yerine (sakin pano): eğri artık yalnızca yönü
/// değil "gün başına göre neredeyim"i de anlatır — kesik çizgi açılış
/// seviyesidir; eğri onun altındaysa gün ekside. Kilit ekranı/widget ile
/// aynı ham seri; eksen yok, zaman etiketleri altındaki satırda.
class _GunIciGrafik extends StatelessWidget {
  const _GunIciGrafik({required this.seri, required this.renk});

  final List<double> seri;
  final Color renk;

  static const double yukseklik = 56;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox(
          height: yukseklik,
          width: double.infinity,
          child: CustomPaint(
            painter: _GunIciPainter(
              seri: seri,
              renk: renk,
              tabanRenk: context.c.text36,
            ),
          ),
        ),
      );
}

class _GunIciPainter extends CustomPainter {
  const _GunIciPainter({
    required this.seri,
    required this.renk,
    required this.tabanRenk,
  });

  final List<double> seri;
  final Color renk;
  final Color tabanRenk;

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
    const kenar = 2.0;
    double y(double v) => duz
        ? size.height / 2
        : size.height -
            ((v - min) / aralik) * (size.height - 2 * kenar) -
            kenar;

    final yol = Path();
    for (var i = 0; i < seri.length; i++) {
      final x = size.width * i / (seri.length - 1);
      if (i == 0) {
        yol.moveTo(x, y(seri[i]));
      } else {
        yol.lineTo(x, y(seri[i]));
      }
    }

    // Gün başı seviyesi: kesik yatay çizgi. Serinin ilk noktası = açılış
    // (DailySummary da değişimi oradan ölçer).
    final tabanY = y(seri.first);
    final taban = Paint()
      ..color = tabanRenk.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    const cizgi = 3.0, bosluk = 3.0;
    for (var x = 0.0; x < size.width; x += cizgi + bosluk) {
      canvas.drawLine(Offset(x, tabanY),
          Offset((x + cizgi).clamp(0, size.width), tabanY), taban);
    }

    // Eğrinin altı: renkten şeffafa inen gölge.
    final dolgu = Path.from(yol)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      dolgu,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [renk.withValues(alpha: 0.16), renk.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      yol,
      Paint()
        ..color = renk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final son = yol.computeMetrics().last;
    final uc = son.getTangentForOffset(son.length)?.position;
    if (uc != null) canvas.drawCircle(uc, 2.5, Paint()..color = renk);
  }

  // DEĞER karşılaştırması (animasyon denetimi 2026-10-01): seri her
  // kurulumda `DailySummary.from`'dan YENİ liste olarak geliyor; kimlik
  // karşılaştırması her fiyat tikinde — değer aynıyken de — yeniden
  // boyatıyordu. Seri gün içi (≤ ~100 nokta), karşılaştırma boyamaktan ucuz.
  @override
  bool shouldRepaint(_GunIciPainter old) =>
      old.renk != renk ||
      old.tabanRenk != tabanRenk ||
      !listEquals(old.seri, seri);
}

// ── Izgara: iki sütun, tek kalan tam genişlik ───────────────────────────────

/// Kutuları ikişer ikişer dizer; tek kalan son kutu satırı tek başına
/// doldurur (yarım satırda boşluk bırakmaz). Satırdaki iki kutu aynı boyda
/// (`IntrinsicHeight`) — kısa kutunun altı boş kalınca ızgara dişli görünür.
class _Izgara extends StatelessWidget {
  const _Izgara({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final satirlar = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      if (i > 0) satirlar.add(const SizedBox(height: SandikSpace.sm));
      final tek = i + 1 >= children.length;
      satirlar.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: children[i]),
            if (!tek) ...[
              const SizedBox(width: SandikSpace.sm),
              Expanded(child: children[i + 1]),
            ],
          ],
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: satirlar,
    );
  }
}

// ── Bilgi kutusu ─────────────────────────────────────────────────────────────

/// Beyaz kutu: `etiket ›` / `▲ değer` / çubuk / açıklama / rozet.
class _BilgiKutusu extends StatelessWidget {
  const _BilgiKutusu({
    required this.etiket,
    required this.deger,
    required this.renk,
    this.yon,
    this.cubuk,
    this.altMetin,
    this.rozet,
    this.onTap,
  });

  final String etiket;
  final String deger;
  final Color renk;

  /// `true` yukarı ok, `false` aşağı, `null` oksuz.
  final bool? yon;
  final Widget? cubuk;
  final String? altMetin;
  final String? rozet;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final govde = Padding(
      padding: const EdgeInsets.all(SandikSpace.smd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  etiket,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelMedium?.copyWith(
                    color: c.text58,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, size: 16, color: c.text36),
            ],
          ),
          const SizedBox(height: SandikSpace.xs2),
          Row(
            children: [
              if (yon != null)
                Padding(
                  padding: const EdgeInsets.only(right: SandikSpace.xxs),
                  child: Icon(
                    yon!
                        ? Icons.arrow_drop_up_rounded
                        : Icons.arrow_drop_down_rounded,
                    size: 18,
                    color: renk,
                  ),
                ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    deger,
                    maxLines: 1,
                    style: context.t.titleMedium?.copyWith(
                      color: c.text90,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (cubuk != null)
            Padding(
              padding: const EdgeInsets.only(top: SandikSpace.xs2),
              child: cubuk,
            ),
          if (altMetin != null)
            Padding(
              padding: const EdgeInsets.only(top: SandikSpace.xs2),
              child: Text(
                altMetin!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelSmall?.copyWith(color: c.text58),
              ),
            ),
          if (rozet != null) ...[
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(top: SandikSpace.xs2),
              child: _Rozet(metin: rozet!),
            ),
          ],
        ],
      ),
    );
    final kutu = DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: c.hairline),
      ),
      child: onTap == null
          ? govde
          // Şeffaf Material: mürekkep katmanı ata iskeleye bağlı kalmasın
          // (Performans'taki "No Material widget found" dersi, 2026-09-21).
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(SandikRadius.md),
                child: govde,
              ),
            ),
    );
    return Semantics(
      button: onTap != null,
      label: '$etiket, $deger. ${altMetin ?? ''}',
      excludeSemantics: true,
      child: kutu,
    );
  }
}

/// Amber zeminli küçük hap: "Haftalık özet hazır", "2 gün".
class _Rozet extends StatelessWidget {
  const _Rozet({required this.metin});
  final String metin;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.sm, vertical: SandikSpace.xxs),
      decoration: BoxDecoration(
        color: c.amberFill.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(SandikRadius.lg),
      ),
      child: Text(
        metin,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.t.labelSmall?.copyWith(
          color: c.amberText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Getiri çubuğu + TÜFE imleci: "getirin nereye kadar, enflasyon nerede".
///
/// Ölçek ikisinin büyüğünün 1,25 katı — büyük olan çubuğun %80'ine gelir,
/// imleç çubuğun içinde kalır. Negatif getiri çubuğu sıfıra çeker (uydurma
/// uzunluk yok); fark zaten değer satırında kelimeyle söylenir.
class _EnflasyonCubugu extends StatelessWidget {
  const _EnflasyonCubugu({required this.nominal, required this.tufe});

  final double nominal;
  final double tufe;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final buyuk = nominal > tufe ? nominal : tufe;
    final olcek = buyuk <= 0 ? 1.0 : buyuk * 1.25;
    final dolu = (nominal / olcek).clamp(0.0, 1.0);
    final imlec = (tufe / olcek).clamp(0.0, 1.0);
    return SizedBox(
      height: SandikSpace.smd,
      child: LayoutBuilder(
        builder: (context, k) => Stack(
          alignment: Alignment.centerLeft,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(SandikRadius.sm),
              child: SizedBox(
                height: SandikSpace.xs2,
                width: double.infinity,
                child: Stack(
                  children: [
                    ColoredBox(
                        color: c.surface2, child: const SizedBox.expand()),
                    FractionallySizedBox(
                      widthFactor: dolu,
                      child: ColoredBox(
                          color: nominal >= tufe ? c.gain : c.loss,
                          child: const SizedBox.expand()),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: (k.maxWidth * imlec - 1).clamp(0.0, k.maxWidth - 2),
              child: Container(
                width: 2,
                height: SandikSpace.smd,
                decoration: BoxDecoration(
                  color: c.text90,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Eylem kutusu (amber) ─────────────────────────────────────────────────────

/// `[ikon] başlık / alt` — amber zemin; dokununca hedef sayfası ya da özet.
class _EylemKutusu extends StatelessWidget {
  const _EylemKutusu({
    required this.ikon,
    required this.baslik,
    required this.alt,
    required this.onTap,
    this.oran,
  });

  final IconData ikon;
  final String baslik;
  final String alt;
  final VoidCallback onTap;

  /// 0..1 hedef ilerlemesi — alt satırın altında ince çubuk.
  final double? oran;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: '$baslik. $alt',
      excludeSemantics: true,
      child: Material(
        color: c.amberFill.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: SandikSpace.smd, vertical: SandikSpace.sm2),
              child: Row(
                children: [
                  Icon(ikon, size: 20, color: c.amberText),
                  const SizedBox(width: SandikSpace.sm2),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          baslik,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.labelLarge?.copyWith(
                            color: c.amberText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          alt,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              context.t.labelSmall?.copyWith(color: c.text58),
                        ),
                        if (oran != null)
                          Padding(
                            padding:
                                const EdgeInsets.only(top: SandikSpace.xs2),
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(SandikRadius.sm),
                              child: SizedBox(
                                height: SandikSpace.xs,
                                child: Stack(
                                  children: [
                                    ColoredBox(
                                        color: c.surface2,
                                        child: const SizedBox.expand()),
                                    FractionallySizedBox(
                                      widthFactor: oran!.clamp(0.02, 1.0),
                                      child: ColoredBox(
                                          color: c.amberFill,
                                          child: const SizedBox.expand()),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Ayak notu: yaklaşan olay ─────────────────────────────────────────────────

/// "📅 TÜİK enflasyonu · 3 Ekim ········ [2 gün]" — kartın altındaki damga;
/// kalan gün amber hapta.
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
    return Row(
      children: [
        Icon(Icons.event_rounded, size: 16, color: c.text36),
        const SizedBox(width: SandikSpace.sm),
        Expanded(
          child: Text(
            ne,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.bodySmall?.copyWith(color: c.text58),
          ),
        ),
        const SizedBox(width: SandikSpace.sm),
        _Rozet(metin: kalan),
      ],
    );
  }
}
