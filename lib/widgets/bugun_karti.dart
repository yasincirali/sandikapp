// Ana ekrandaki "Bugün" kartı.
//
// Hesap `services/bugun_service.dart`'ta (saf); burada yalnızca gün içi
// serinin çekimi (kilit ekranı/widget ile ORTAK önbellek — üç yüzey aynı
// rakamı göstermeli), tercihler ve çizim var.
//
// Kendi kapılarını kendi kurar: kendi görünümü + açık pozisyon varken
// çizilir; seri gelmeden de kalan satırları gösterir (boş kart yok).
//
// Düzen (2026-10-09, benchmark revizesi, kullanıcı seçimi): başlık + seans
// durumu; HÜKÜM kelimesi ("Yükseldi / Geriledi / Yerinde saydı") ve dolu
// renkli tutar rozeti; tam genişlik gün içi eğri (açılış seviyesi kesik
// çizgi); dönem çipleri (Özet'e kısayol); oynayanlar sırası (≤3 çip);
// alım gücü kutusu ("Geçen yılki 100 liran bugün 81 lira" + dolu çubuk);
// amber hedef satırı. Gerekçe `_benchmarkDuzeni`. Önceki düzenler: H
// "kıyas öne" (2026-10-04: Getirin/TÜFE çubukları, yüzde rozeti, satır içi
// kıvılcım), D "sakin pano" (2026-10-01), "almanak" (2026-09-21).
import 'dart:async';
import 'dart:math' as math;
import '../services/tazelik_ritmi.dart';
import '../services/price_service.dart';

import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
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
import '../services/en_cok_oynayan.dart';
import '../services/fiyat_kaynagi.dart';
import '../theme/sandik.dart';
import '../utils/piyasa_kapali_etiketi.dart';
import '../utils/pozisyon_etiketi.dart';
import '../utils/tr_format.dart';
import '../utils/tr_iyelik.dart';
import 'aralik_cipi.dart' show AralikMetni;
import 'hedef_sheet.dart';
import 'sandik_skeleton.dart';
import 'sigan_metin.dart';
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
    this.gorunum = '',
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

  /// Kartın gösterildiği ortak seçimi — `GorunumCipi` sözleşmesi: `null`
  /// Birlikte, `''` Ben, uuid o ortak. Karttan açılan Performans bu
  /// seçimle açılır (bayrak `ortak_secimi_tasi`, 2026-10-04): kart
  /// Ayşe'nin gününü anlatıp dokununca senin Özet'ine düşürmemeli.
  final String? gorunum;

  /// Kapsam başına son yükleme önbelleğini boşaltır (testler).
  @visibleForTesting
  static void anliklariTemizle() => _bugunSonYukleme.clear();

  /// Kartın "şimdi"si — üretimde cihaz saati, testte sabit bir hafta içi
  /// gün (2026-10-09). Kart seans saatine göre "Canlı / Piyasa kapalı /
  /// Yükseldi" kararı verir; cihaz saatine bağlı test akşam ve hafta sonu
  /// başka bir kart görüyordu (benchmark testi, 2026-10-09).
  @visibleForTesting
  static DateTime Function() saat = DateTime.now;

  @override
  ConsumerState<BugunKarti> createState() => _BugunKartiState();
}

class _BugunKartiState extends ConsumerState<BugunKarti> {
  Map<int, double>? _seri;
  ReelGetiriSatiri? _reel;
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
      // animasyon denetimi 2026-10-01); dönünce HEMEN tazelenir
      // ([_gorunurlukDegisti]).
      if (!TickerMode.getValuesNotifier(context).value.enabled) return;
      _seriyiTazele();
    });
    IntradaySeriesCache.instance.surum.addListener(_seriGeldi);
  }

  /// Sekmenin görünürlüğü (`TickerMode`); görünür olunca seri hemen
  /// ortak önbellekten okunur.
  ///
  /// ## Neden (kullanıcı kararı 2026-10-02: "hepsi senkron olmalı")
  /// Gizli sekmede nabız atlanıyor (doğru: boşa kare). Ama Performans'ta
  /// gezip Ana'ya dönen kullanıcı bir nabız boyunca (≤ 30 sn) kartın ESKİ
  /// seriyle hesapladığı rakamı görüyordu; Performans aynı anda taze
  /// seriyi gösteriyordu. Görünür olunca `zorla` ile istenir: aynı nabızda
  /// Performans çekmişse aynı nesne döner (`IntradaySeriesCache.zorlaEsigi`),
  /// yoksa taze çekilir. İki yüzey artık aynı seriyle, aynı anda.
  ValueListenable<TickerModeData>? _gorunurluk;

  void _gorunurlukDegisti() {
    if (!mounted || _gorunurluk?.value.enabled != true) return;
    _seriyiTazele();
  }

  /// Ortak önbelleğe yeni seri yazıldı (başka bir yüzey çekti) — kart
  /// ağa çıkmadan önbellekten okur (`IntradaySeriesCache.surum`).
  void _seriGeldi() {
    if (!mounted) return;
    if (_gorunurluk?.value.enabled == false) return; // görünür olunca okunur
    // Yalnızca kartın kümesinin yuvası (`BugunYukleyici.seri` ile aynı
    // küme: aktif + seriye giren lot'lar).
    final kume =
        widget.state.activeAssets.where(FiyatKaynagi.seriyeGirer).toList();
    if (IntradaySeriesCache.instance.sonGuncellenen !=
        IntradaySeriesCache.anahtar(kume)) {
      return;
    }
    _seriyiTazele(zorla: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final yeni = TickerMode.getValuesNotifier(context);
    if (identical(yeni, _gorunurluk)) return;
    _gorunurluk?.removeListener(_gorunurlukDegisti);
    _gorunurluk = yeni..addListener(_gorunurlukDegisti);
  }

  @override
  void dispose() {
    _gorunurluk?.removeListener(_gorunurlukDegisti);
    IntradaySeriesCache.instance.surum.removeListener(_seriGeldi);
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
  Future<void> _seriyiTazele({bool zorla = true}) async {
    // İlk yükleme sürüyor, üstüne binme. `_yuklendi` tek başına yetmez:
    // kart son yüklemeyle açıldıysa (`_sonYukleme`) yükleme arkada sürer.
    if (!_yuklendi || _yukleniyor) return;
    // `nabiz: true` — önbellek yaşa bakmadan tazelenir; Performans da bu
    // nabızda koşulsuz çekiyor (bkz. `IntradaySeriesCache.get` [zorla]).
    final yeni = await _seriYukle(nabiz: zorla);
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

  /// İki yükleme birbirinden bağımsız, PARALEL ve tek seferlik (`_istendi`):
  /// kart her fiyat yenilemesinde yeniden kurulur, ama bu seriler oturumda
  /// bir kez çekilir — eski `RealReturnStrip` ile aynı disiplin. Her biri
  /// kendi try/catch'inde: biri düşerse diğeri çizilir. (Üçüncüsü, son 7
  /// günün getirisi, 2026-10-08'de kalktı: H düzeni o satırı çizmiyordu,
  /// istek boşa ağa çıkıyordu — `BugunKartiVerisi`.)
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
    ]);
    _yukleniyor = false;
    if (!mounted) return;
    setState(() {
      // `?? _seri`: tur bütçeyi aşmışsa seri buradan null gelir ve
      // `_turBitinceYukle` bu arada yazmış olabilir — ezilmesin.
      _seri = sonuc[0] as Map<int, double>? ?? _seri;
      _reel = sonuc[1] as ReelGetiriSatiri?;
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

  /// Yükleme bitene kadar kartın yerini tutan iskelet — başlık, hüküm +
  /// rozet, eğri, çipler, alım gücü kutusu, hedef satırı. Kart tek seferde,
  /// tüm veriyle gelir; parça parça büyümez. Ölçüler gerçek düzenle aynı ki
  /// yükleme bitince kart zıplamasın.
  Widget _iskelet(BuildContext context) => Padding(
        padding: widget.padding,
        child: SandikCard(
          padding: const EdgeInsets.all(SandikSpace.md),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: SandikSkeleton(width: 160, height: 10)),
                  SizedBox(width: SandikSpace.sm),
                  SandikSkeleton(width: 56, height: 10),
                ],
              ),
              SizedBox(height: SandikSpace.md2),
              Row(
                children: [
                  Flexible(child: SandikSkeleton(width: 150, height: 28)),
                  SizedBox(width: SandikSpace.sm2),
                  Flexible(child: SandikSkeleton(width: 72, height: 24)),
                ],
              ),
              SizedBox(height: SandikSpace.sm2),
              SandikSkeleton(height: _egriYuksekligi),
              SizedBox(height: SandikSpace.sm2),
              Row(
                children: [
                  SandikSkeleton(width: 48, height: 24),
                  SizedBox(width: SandikSpace.xs2),
                  SandikSkeleton(width: 48, height: 24),
                  SizedBox(width: SandikSpace.xs2),
                  SandikSkeleton(width: 40, height: 24),
                  SizedBox(width: SandikSpace.xs2),
                  SandikSkeleton(width: 40, height: 24),
                ],
              ),
              SizedBox(height: SandikSpace.md2),
              SandikSkeleton(height: 112),
              SizedBox(height: SandikSpace.md2),
              SandikSkeleton(height: 56),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_yuklendi && widget.state.assets.isNotEmpty) return _iskelet(context);
    final now = BugunKarti.saat();
    final seri = _seri;
    final ozet = seri == null
        ? null
        : DailySummary.from(state: widget.state, series: seri, now: now);
    // Sahiplik sınırı korunur: Birlikte görünümünde `state.assets` ben +
    // ortakların BİRLEŞİK defteridir; toplam sahip başına kurulur
    // (`ownerScopedTotalValue`). Kendi görünümünde tek grup çıkar.
    final sahipler = lotlarSahibeGore(widget.state.assets);
    final veri = BugunService.hesapla(
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
      // "Piyasa kapalı" yalnızca tamamen borsa portföyüne (2026-10-01).
      // Kartın gösterdiği KAPSAMIN defteri — Birlikte'de ortağın altını da
      // rakamı hareket ettirir.
      yalnizcaBorsa: yalnizcaBorsaVarliklardan(widget.state.assets),
    );
    // En çok oynayan, gün içi seriyle AYNI önbellek nesnesinden — kart
    // seriyi bu kümeyle çekti (`BugunYukleyici.seri`), burada ağa çıkılmaz.
    final kume =
        widget.state.activeAssets.where(FiyatKaynagi.seriyeGirer).toList();
    final bd = IntradaySeriesCache.instance.onbellekte(kume);
    final oynayanlar = bd == null
        ? const <EnCokOynayan>[]
        : enCokOynayanlar(bd, lotlar: kume, now: now);
    _gosterimiOlc(veri, oynayanlar.isNotEmpty, now);

    final gizli = ref.watch(balanceHiddenProvider);
    final dil = _dil;

    // Benchmark düzeni (kullanıcı seçimi 2026-10-09). Düzen H (2026-10-04)
    // ve D "sakin pano" (2026-10-01) bu tarihte kalktı; D'nin satırları
    // zaten 2026-10-05'te silinmişti, hesabı 2026-10-08'de.
    //
    // İskeletten içeriğe geçiş solarak ve hafif yükselerek: kart oturumda
    // bir kez gelir, zıplayarak değil. Hareketi azalt açıkken tek kare.
    return Padding(
      padding: widget.padding,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: SandikMotion.surfaceOf(context),
        curve: SandikMotion.enter,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * SandikSpace.sm),
            child: child,
          ),
        ),
        child: SandikCard(
          padding: const EdgeInsets.all(SandikSpace.md),
          child: _benchmarkDuzeni(veri, ozet, oynayanlar, now, gizli, dil),
        ),
      ),
    );
  }

  /// Başlığın sağındaki durum: "Canlı · 18:10 kapanış" / "Piyasa kapalı ·
  /// Pazartesi 10:00 açılır" / "Canlı" (karışık portföy, borsa kapalı).
  ///
  /// Eski düzende bu metin hareketin ALTINDAYDI; sakin panoda tarih
  /// satırına çıktı ki hareket bloğu yalnızca ölçümü taşısın.
  ///
  /// Uzun → kısa adaylar (`SiganMetin`): "Piyasa kapalı · Pazartesi 10:00
  /// açılır" → "Kapalı · Pzt 10:00" → "Kapalı". Hangisi sığarsa o, tam.
  List<String> _durumMetni(BugunSatiri? s, DateTime now) {
    final l10n = context.l10n;
    if (s is PiyasaKapaliSatiri) {
      final a = BugunService.sonrakiAcilis(now);
      final ayniGun = dayKey(a) == dayKey(now);
      final saat = DateFormat.Hm().format(a);
      final uzun = ayniGun
          ? l10n.todayAt(saat)
          : '${DateFormat.EEEE(_dil).format(a)} $saat';
      final kisa = ayniGun ? saat : '${DateFormat.E(_dil).format(a)} $saat';
      return [
        '${l10n.todayClosedWord} · ${l10n.todayOpensAt(uzun)}',
        '${l10n.todayClosedShort} · $kisa',
        l10n.todayClosedShort,
      ];
    }
    if (s is GunlukDegisimSatiri) {
      if (BugunService.seansAcikMi(now)) {
        final kapanisDk = BistTakvimi.yarimGunMu(now)
            ? BistTakvimi.yarimGunKapanisDk
            : BugunService.seansKapanisDk;
        final kapanis = DateFormat.Hm()
            .format(dayKey(now).add(Duration(minutes: kapanisDk)));
        return [
          '${l10n.todayLiveWord} · ${l10n.todayCloseAt(kapanis)}',
          '${l10n.todayLiveWord} · $kapanis',
          l10n.todayLiveWord,
        ];
      }
      // Karışık portföy (altın/döviz/kripto): borsa kapalı olsa da rakam
      // işler — "Piyasa kapalı" yanlış olurdu (2026-10-01). Yalnızca borsa
      // portföyünde hesap zaten `PiyasaKapaliSatiri` üretir.
      return [l10n.todayLiveWord];
    }
    return [l10n.todayLoading];
  }

  /// Benchmark düzeni (kullanıcı seçimi 2026-10-09): başlık; hüküm kelimesi +
  /// dolu renkli tutar rozeti; tam genişlik gün içi eğri; dönem çipleri;
  /// oynayanlar sırası; alım gücü kutusu ("100 liran bugün kaç lira");
  /// hedef satırı.
  ///
  /// ## Neden bu beş bileşen (benchmark, 2026-10-09)
  /// Sekiz uygulama (Robinhood, Revolut, Trade Republic, Delta, Midas, Apple
  /// Hisse Senetleri, Monzo, Copilot/Monarch) yan yana kondu: büyük tutar +
  /// delta rozeti 8/8, grafik + dönem çipleri 7/8, renk = durum 5/8, hedef
  /// çubuğu 4/8, tek cümle içgörü 3/8, enflasyon/alım gücü 0/8. Kart sektörün
  /// öğrettiği beşini sektör kalıbıyla, altıncıyı (enflasyon — sandık'ın
  /// farkı) kullanıcının diliyle kurar. Finans dışı kullanıcı için kural:
  /// hüküm büyük, sayı küçük; "puan/TÜFE" ikinci satırda gri.
  ///
  /// Kullanıcı şartı (2026-10-04) korunur: en çok oynayan, enflasyon kıyası
  /// ve hedef kartta BULUNUR. Hesap katmanı (`BugunService`, `DailySummary`,
  /// `enCokOynayanlar`) değişmedi; yalnızca çizim.
  Widget _benchmarkDuzeni(BugunKartiVerisi veri, DailySummary? ozet,
      List<EnCokOynayan> oynayanlar, DateTime now, bool gizli, String dil) {
    final reel = veri.reel;
    final birincil = veri.birincil;
    final seri = ozet?.sparkline ?? const <double>[];
    final seriCiz =
        !gizli && birincil is GunlukDegisimSatiri && seri.length >= 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KiyasBaslik(
          now: now,
          dil: dil,
          etiket: widget.etiket,
          durum: _durumMetni(birincil, now),
          acik:
              birincil is GunlukDegisimSatiri && BugunService.seansAcikMi(now),
        ),
        const SizedBox(height: SandikSpace.md2),
        _HukumSatiri(birincil: birincil, gizli: gizli),
        if (seriCiz) ...[
          const SizedBox(height: SandikSpace.sm2),
          _GunIciEgri(
            seri: seri,
            renk: _hareketRengi(context, birincil),
            // Gün değişince eğri yeniden çizilerek gelir; aynı gün içindeki
            // 30 sn'lik tazelemeler yalnız yeni noktayı ekler.
            anahtar: dayKey(now),
          ),
        ],
        const SizedBox(height: SandikSpace.sm2),
        _DonemCipleri(onSec: (p) => _ozeteGit(periodIdx: p.index)),
        if (oynayanlar.isNotEmpty) ...[
          // Başlık satırı 44pt dokunma yüksekliğinde ("Tümü"): üstünde ek
          // boşluk büyük görünüyordu (emülatör, 2026-10-09).
          const SizedBox(height: SandikSpace.xs),
          _OynayanlarSirasi(
            oynayanlar: oynayanlar,
            gizli: gizli,
            onOynayan: () {
              unawaited(
                  AnalyticsService.instance.logTodayRowTapped(kind: 'oynayan'));
              _ozeteGit(periodIdx: SummaryPeriod.gunluk.index);
            },
          ),
        ],
        if (reel != null) ...[
          const SizedBox(height: SandikSpace.md2),
          _AlimGucuKutusu(
            reel: reel,
            pencereMetni: _pencereMetni(reel),
            onTap: _olcerek(
                reel, () => _ozeteGit(periodIdx: SummaryPeriod.birYil.index)),
          ),
        ],
        const SizedBox(height: SandikSpace.md2),
        _hedefKutusu(veri.hedef, gizli),
      ],
    );
  }

  /// Günün rengi: artıda kazanç, ekside kayıp, düz günde sessiz.
  static Color _hareketRengi(BuildContext context, BugunSatiri? s) {
    if (s is GunlukDegisimSatiri && !s.flat) {
      return context.signColor(s.changeTRY);
    }
    return context.c.text58;
  }

  /// Alım gücü kutusunun ölçüm penceresi: ölçülen aylar (Özet'le aynı
  /// biçim; 2026-10-02 müşteri testi "hangi aralık?" sorusu), bilinmiyorsa
  /// "son 12 ay".
  String _pencereMetni(ReelGetiriSatiri r) {
    final l10n = context.l10n;
    final p = r.pencere;
    if (p == null) return l10n.todayLast12Months;
    return AralikMetni.olculenAylar(l10n, context.tarihDili,
        bas: p.seriBaslangici, bitis: p.seriBitisi);
  }

  /// Hedef satırı (amber): ikon + başlık + alt satır; hedef varsa çubuk.
  Widget _hedefKutusu(HedefSatiri s, bool gizli) {
    final l10n = context.l10n;
    final hedefAc = _olcerek(
        s,
        () => showHedefSheet(context, ref,
            kapsam: widget.hedefKapsami, etiket: widget.etiket));
    if (s.belirlenmedi) {
      return _EylemKutusu(
        ikon: Icons.flag_outlined,
        baslik: l10n.todayGoalSetAction,
        alt: [l10n.todayGoalSetSub],
        onTap: hedefAc,
      );
    }
    final hedef = gizli ? '••••' : fmtTRYCompactSade(s.hedefTRY.toDouble());
    if (s.ulasildi) {
      return _EylemKutusu(
        ikon: Icons.flag_rounded,
        baslik: '${l10n.todayGoalLabel} · ${l10n.todayGoalDone}',
        alt: [l10n.todayGoalDoneHint(hedef), l10n.todayGoalNewAction],
        onTap: hedefAc,
      );
    }
    return _EylemKutusu(
      ikon: Icons.flag_outlined,
      baslik: l10n.todayGoalProgressTitle((s.oran * 100).floor()),
      alt: [
        l10n.todayGoalLeftShort(gizli ? '••••' : fmtTRYCompactSade(s.kalan)),
      ],
      oran: s.oran,
      onTap: hedefAc,
    );
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
            initialView: _gecisGorunumu,
          ),
        ),
      );

  /// Karttan açılan ekranın ortak seçimi: kartın gösterildiği seçim — bkz.
  /// [BugunKarti.gorunum] (2026-10-04; bayrak `ortak_secimi_tasi`
  /// 2026-10-05'te kalktı — önceki davranış her zaman "Ben" idi).
  String? get _gecisGorunumu => widget.gorunum;

  /// Gösterim ölçümü — gün + satır bileşimi başına BİR olay.
  ///
  /// Kart her fiyat yenilemesinde yeniden kurulur; her build'i saymak
  /// "kaç kez görüldü"yü değil "kaç kez çizildi"yi ölçerdi. Anahtar
  /// uygulama ömrü boyunca statik: aynı gün ikinci açılışta tekrar
  /// sayılmaz, ertesi gün sayılır.
  ///
  /// YALNIZ ÇİZİLENLER (2026-10-08): eskiden H düzeninin çizmediği
  /// `yesil`/`haftalik`/`aylik`/`olay_*` da sayılıyordu; çizilen en çok
  /// oynayan ise hiç sayılmıyordu (dokunuşu `oynayan` diye ölçülürken).
  /// `today_row_shown` serisi bu tarihte kırılır: o türler biter, `oynayan`
  /// başlar.
  static String? _sonOlculen;

  void _gosterimiOlc(BugunKartiVerisi veri, bool oynayanVar, DateTime now) {
    final turler = [
      if (veri.birincil != null) _tur(veri.birincil!),
      if (veri.reel != null) _tur(veri.reel!),
      if (oynayanVar) 'oynayan',
      _tur(veri.hedef),
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
        HedefSatiri() => s.belirlenmedi ? 'hedef_yok' : 'hedef',
        ReelGetiriSatiri() => 'reel',
      };

  /// Dokunuş ölçümü — satırın kendi eylemini sarar.
  VoidCallback _olcerek(BugunSatiri s, VoidCallback eylem) => () {
        unawaited(AnalyticsService.instance.logTodayRowTapped(kind: _tur(s)));
        eylem();
      };
}

// ── Başlık ───────────────────────────────────────────────────────────────────

/// Tek satır başlık: "BUGÜN · CUMA 3 EKİM" solda, seans durumu sağda.
/// Takvim yaprağı yok: hüküm ve eğri ağırlığı taşıyor, başlık yalnız yer ve
/// zaman söyler.
class _KiyasBaslik extends StatelessWidget {
  const _KiyasBaslik({
    required this.now,
    required this.dil,
    required this.etiket,
    required this.durum,
    required this.acik,
  });

  final DateTime now;
  final String dil;
  final String? etiket;
  final List<String> durum;
  final bool acik;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bas = etiket ?? context.l10n.todayTitle;
    final tarih = DateFormat('EEEE d MMMM', dil).format(now);
    final durumStil = context.t.labelMedium?.copyWith(
      color: c.text58,
      fontWeight: FontWeight.w600,
    );
    // Durum metni DOĞAL genişliğini alır (en fazla satırın %45'i), başlık
    // kalanı. İkisi de esnek olunca satır yarı yarıya bölünüyor ve "Canlı"
    // gibi kısa bir durumda bile tarih sığmayıp düşüyordu (önizleme PNG'si,
    // 2026-10-04).
    return LayoutBuilder(builder: (context, k) {
      final tp = TextPainter(
        text: TextSpan(text: durum.first, style: durumStil),
        textDirection: Directionality.of(context),
        maxLines: 1,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final durumW = math.min(tp.width + 1, k.maxWidth * 0.45);
      tp.dispose();
      return Row(
        children: [
          Expanded(
            child: SiganMetin(
              [trBuyukHarf('$bas · $tarih'), trBuyukHarf(bas)],
              style: context.t.labelSmall?.copyWith(
                color: c.text58,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          // Canlı noktası: seans açıkken kazanç renginde ve yumuşak bir
          // nabız (opaklık), kapalıyken sabit gri. Nabız yalnız renk/opaklık;
          // konum oynamaz (günde onlarca kez görülen yüzey).
          _CanliNokta(acik: acik),
          const SizedBox(width: SandikSpace.xs2),
          SizedBox(
            width: durumW,
            child:
                SiganMetin(durum, textAlign: TextAlign.end, style: durumStil),
          ),
        ],
      );
    });
  }
}

/// Seans açıkken yavaşça nefes alan nokta.
class _CanliNokta extends StatefulWidget {
  const _CanliNokta({required this.acik});

  final bool acik;

  @override
  State<_CanliNokta> createState() => _CanliNoktaState();
}

class _CanliNoktaState extends State<_CanliNokta>
    with SingleTickerProviderStateMixin {
  // Nefes süresi [SandikMotion.flow]×3: hızlı yanıp sönme "uyarı" okunur,
  // bu nokta yalnız "canlı" der.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SandikMotion.flow * 3,
  );

  // `_ayarla` MediaQuery okur: initState'te değil, didChangeDependencies'te
  // (ilk kez initState'ten hemen sonra çağrılır) ve widget değişince.
  @override
  void didUpdateWidget(covariant _CanliNokta old) {
    super.didUpdateWidget(old);
    if (old.acik != widget.acik) _ayarla();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ayarla();
  }

  void _ayarla() {
    // Hareketi azalt açıkken ve kapalı seansta nokta sabit durur.
    final dur = !widget.acik || MediaQuery.disableAnimationsOf(context);
    if (dur) {
      _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final renk = widget.acik ? c.gain : c.text36;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1)
          .animate(CurvedAnimation(parent: _c, curve: SandikMotion.move)),
      child: Container(
        width: SandikSpace.xs2,
        height: SandikSpace.xs2,
        decoration: BoxDecoration(shape: BoxShape.circle, color: renk),
      ),
    );
  }
}

// ── Hüküm satırı: kelime + dolu renkli tutar rozeti ─────────────────────────

/// "Yükseldi / Geriledi / Yerinde saydı" büyük, tutar yanında dolu rozette.
///
/// Apple Hisse Senetleri'nin dolu rozeti (benchmark 8/8 "büyük tutar +
/// delta"): yön hem kelimede hem rengin kendisinde; yüzde rozeti yok,
/// yüzde ekran okuyucuya gider. Seans kapalıyken "Piyasa kapalı", seri
/// henüz yokken "Gün içi veri geliyor" — uydurma sayı yok.
class _HukumSatiri extends StatelessWidget {
  const _HukumSatiri({required this.birincil, required this.gizli});

  final BugunSatiri? birincil;
  final bool gizli;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final s = birincil;

    String hukum;
    Color renk;
    String? tutar;
    String? yuzde;
    if (s is GunlukDegisimSatiri) {
      if (s.flat) {
        hukum = l10n.todayVerdictFlat;
        renk = c.text58;
        tutar = gizli ? '••••' : fmtTRY(0);
      } else {
        hukum = s.changeTRY > 0 ? l10n.todayVerdictUp : l10n.todayVerdictDown;
        renk = context.signColor(s.changeTRY);
        tutar = gizli
            ? '••••'
            : '${s.changeTRY > 0 ? '+' : '−'}${fmtTRY(s.changeTRY.abs())}';
        yuzde = isaretliYuzde(s.changePct);
      }
    } else if (s is PiyasaKapaliSatiri) {
      hukum = l10n.todayClosedWord;
      renk = c.text58;
    } else {
      hukum = l10n.todayLoading;
      renk = c.text36;
    }

    final hukumStil = context.t.headlineSmall?.copyWith(
      color: c.text90,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      height: 1.1,
    );

    return Semantics(
      label: [hukum, if (tutar != null) tutar, if (yuzde != null) yuzde]
          .join(', '),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            flex: 3,
            // Hüküm değişince (seri geldi, gün döndü) kelime solarak değişir;
            // sayı rozetin içinde sessizce güncellenir — günde onlarca kez
            // görülen yüzeyde konum oynamaz.
            child: AnimatedSwitcher(
              duration: SandikMotion.stateOf(context),
              switchInCurve: SandikMotion.enter,
              switchOutCurve: SandikMotion.exit,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, if (current != null) current],
              ),
              child: FittedBox(
                key: ValueKey(hukum),
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(hukum, maxLines: 1, style: hukumStil),
              ),
            ),
          ),
          if (tutar != null) ...[
            const SizedBox(width: SandikSpace.sm2),
            // Rozet de kalan yere sığar: 280pt ve büyük yazı ölçeğinde
            // KÜÇÜLÜR, taşmaz (uç durum testi, 2026-10-09).
            Flexible(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _DeltaRozeti(
                    metin: tutar,
                    renk: renk,
                    dolu: s is GunlukDegisimSatiri && !s.flat),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dolu renkli tutar rozeti: "+₺1.840" kazanç zemininde, "−₺368" kayıp
/// zemininde, düz günde sessiz zemin. Zemin rengi yön değişince süzülür.
class _DeltaRozeti extends StatelessWidget {
  const _DeltaRozeti({
    required this.metin,
    required this.renk,
    required this.dolu,
  });

  final String metin;
  final Color renk;

  /// Dolu zemin (yönlü gün) mü, sessiz zemin (düz gün) mi?
  final bool dolu;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final zemin = dolu ? renk : c.surface2;
    final yazi = dolu ? c.onStatus : c.text58;
    return AnimatedContainer(
      duration: SandikMotion.stateOf(context),
      curve: SandikMotion.move,
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.sm2, vertical: SandikSpace.xs2),
      decoration: BoxDecoration(
        color: zemin,
        borderRadius: BorderRadius.circular(SandikRadius.sm),
      ),
      child: AnimatedDefaultTextStyle(
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.move,
        style: (context.t.labelLarge ?? const TextStyle()).copyWith(
          color: yazi,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        child: Text(metin, maxLines: 1),
      ),
    );
  }
}

// ── Tam genişlik gün içi eğri ───────────────────────────────────────────────

/// Eğrinin yüksekliği: tek satır hükmün ağırlığını dengeler, kartın üçte
/// birini almaz (D düzeninin 56pt + eksen satırı eleştirisi; eksen yok).
const double _egriYuksekligi = 56;

/// Tam genişlik gün içi eğri — altı renkten şeffafa inen dolgu, gün başı
/// seviyesi kesik çizgi, uçta nokta.
///
/// İlk çizim soldan sağa AKARAK gelir ([SandikMotion.flow] + [glide]):
/// kullanıcı günün nereden geldiğini izler. Aynı gün içindeki tazelemeler
/// (30 sn) eğriyi yeniden akıtmaz — yalnız yeni nokta eklenir; akış gün
/// değişince ([anahtar]) bir daha oynar. Hareketi azalt açıkken tek karede
/// tam çizilir (`SandikMotion.of` sıfır süre).
class _GunIciEgri extends StatelessWidget {
  const _GunIciEgri({
    required this.seri,
    required this.renk,
    required this.anahtar,
  });

  final List<double> seri;
  final Color renk;
  final Object anahtar;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox(
          height: _egriYuksekligi,
          width: double.infinity,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(anahtar),
            tween: Tween<double>(begin: 0, end: 1),
            duration: SandikMotion.flowOf(context),
            curve: SandikMotion.glide,
            builder: (context, ilerleme, _) => CustomPaint(
              painter: _GunIciPainter(
                seri: seri,
                renk: renk,
                tabanRenk: context.c.text36,
                ilerleme: ilerleme,
              ),
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
    this.ilerleme = 1,
  });

  final List<double> seri;
  final Color renk;
  final Color tabanRenk;

  /// 0..1 — eğrinin soldan sağa ne kadarının çizildiği (giriş akışı).
  final double ilerleme;

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
    const kenar = 3.0;
    double y(double v) => duz
        ? size.height / 2
        : size.height -
            ((v - min) / aralik) * (size.height - 2 * kenar) -
            kenar;

    final tam = Path();
    for (var i = 0; i < seri.length; i++) {
      final x = size.width * i / (seri.length - 1);
      if (i == 0) {
        tam.moveTo(x, y(seri[i]));
      } else {
        tam.lineTo(x, y(seri[i]));
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

    // Giriş akışı: yolun ilk `ilerleme` kadarı. Tam çizimde kopyasız.
    final t = ilerleme.clamp(0.0, 1.0);
    if (t <= 0) return;
    Path yol = tam;
    if (t < 1) {
      yol = Path();
      for (final m in tam.computeMetrics()) {
        yol.addPath(m.extractPath(0, m.length * t), Offset.zero);
      }
    }
    final son = yol.computeMetrics().lastOrNull;
    final uc = son?.getTangentForOffset(son.length)?.position;
    if (uc == null) return;

    // Eğrinin altı: renkten şeffafa inen gölge — çizilen kısım kadar.
    final dolgu = Path.from(yol)
      ..lineTo(uc.dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      dolgu,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [renk.withValues(alpha: 0.18), renk.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      yol,
      Paint()
        ..color = renk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(uc, 4, Paint()..color = renk);
  }

  // DEĞER karşılaştırması (animasyon denetimi 2026-10-01): seri her
  // kurulumda `DailySummary.from`'dan YENİ liste olarak geliyor; kimlik
  // karşılaştırması her fiyat tikinde — değer aynıyken de — yeniden
  // boyatıyordu. Seri gün içi (≤ ~100 nokta), karşılaştırma boyamaktan ucuz.
  @override
  bool shouldRepaint(_GunIciPainter old) =>
      old.renk != renk ||
      old.tabanRenk != tabanRenk ||
      old.ilerleme != ilerleme ||
      !listEquals(old.seri, seri);
}

// ── Dönem çipleri ───────────────────────────────────────────────────────────

/// "Bugün · Hafta · Ay · Yıl" — Bugün seçili (bu kartın serisi); diğerleri
/// Özet'in o dönemine götürür. Kart YENİ SERİ ÇEKMEZ: gün içi seri her
/// yüzeyde tek kaynaktan gelir (kullanıcı kuralı 2026-10-02); dönem çipi
/// burada bir gezinti kısayoludur, ikinci bir seri motoru değil.
///
/// Sağ uçta "sadece fiyat etkisi" notu: büyük rakamın yatırdığın parayı
/// saymadığı (2026-10-04 müşteri testi) kartta yazılı kalmalı.
class _DonemCipleri extends StatelessWidget {
  const _DonemCipleri({required this.onSec});

  final void Function(SummaryPeriod) onSec;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final cipler = <(String, SummaryPeriod)>[
      (l10n.todayWord, SummaryPeriod.gunluk),
      (l10n.todayChipWeek, SummaryPeriod.birHafta),
      (l10n.todayChipMonth, SummaryPeriod.birAy),
      (l10n.todayChipYear, SummaryPeriod.birYil),
    ];
    // Çipler ve not tek `Row`da sabit sığmıyordu: 320pt'te ve büyük yazı
    // ölçeğinde taşıyordu (uç durum testi, 2026-10-09). Şimdi çipler kendi
    // içinde KÜÇÜLEN bir grup (`FittedBox`), "sadece fiyat etkisi" notu
    // aynı satıra sığmazsa ALT SATIRA düşer (`Wrap`); geniş ekranda not
    // sağ uçta durur (`spaceBetween`).
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: SandikSpace.xs2,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (ad, donem) in cipler)
                Padding(
                  padding: const EdgeInsets.only(right: SandikSpace.xs2),
                  child: _DonemCipi(
                    ad: ad,
                    secili: donem == SummaryPeriod.gunluk,
                    onTap: () => onSec(donem),
                  ),
                ),
            ],
          ),
        ),
        Text(
          l10n.todayMarketOnly,
          maxLines: 1,
          style: context.t.labelSmall?.copyWith(color: c.text36),
        ),
      ],
    );
  }
}

class _DonemCipi extends StatelessWidget {
  const _DonemCipi({
    required this.ad,
    required this.secili,
    required this.onTap,
  });

  final String ad;
  final bool secili;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Seçili çip amber (markanın "aktif durum" rengi), diğerleri sessiz.
    // Görsel yükseklik küçük, dokunma alanı 44pt (`SandikTouch.min`).
    // Ekran okuyucu etiketi `semanticLabel`; çocuk metni ayrıca okunmasın
    // ("Hafta Hafta" — emülatör arayüz ağacı, 2026-10-09).
    return SandikTappable(
      onTap: onTap,
      selected: secili,
      semanticLabel: ad,
      child: ExcludeSemantics(
          child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        child: Center(
          child: AnimatedContainer(
            duration: SandikMotion.stateOf(context),
            curve: SandikMotion.move,
            padding: const EdgeInsets.symmetric(
                horizontal: SandikSpace.sm2, vertical: SandikSpace.xs),
            decoration: BoxDecoration(
              color: secili
                  ? c.amberFill.withValues(alpha: 0.18)
                  : c.amberFill.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(SandikRadius.sm),
            ),
            child: Text(
              ad,
              style: context.t.labelMedium?.copyWith(
                color: secili ? c.amberText : c.text58,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      )),
    );
  }
}

// ── Oynayanlar sırası ───────────────────────────────────────────────────────

/// Delta'nın "Daily Movers" satırı: bölüm başlığı + sağında "Tümü ›", altında
/// en fazla üç çip ikişerli ızgarada. Çip: yön halkası + ad + tutar. Yön hem
/// okta hem renkte (renk körlüğü, ekran okuyucu).
///
/// ## Neden ızgara, neden başlıkta "Tümü" (emülatör, 2026-10-09)
/// İlk sürümde "Tümü ›" çiplerle aynı akıştaydı: çipler iki satıra kırılınca
/// tek başına üçüncü bir satır kaplıyor, kartı uzatıyordu. İki karar:
///  1. "Tümü ›" bölüm başlığının sağına çıktı (bölüm eylemi başlıkta durur,
///     her fintech listesinin kalıbı): ayrı satır yok, yer kazanıldı.
///  2. Çipler `Wrap` yerine ikişerli ızgara; tek kalan çip satırı doldurur
///     (ragged kenar ve yetim çip yok). Ad `FittedBox(scaleDown)` içinde:
///     dar ekranda ve büyük yazı ölçeğinde KÜÇÜLÜR, kırpılmaz ve taşmaz.
class _OynayanlarSirasi extends StatelessWidget {
  const _OynayanlarSirasi({
    required this.oynayanlar,
    required this.gizli,
    required this.onOynayan,
  });

  final List<EnCokOynayan> oynayanlar;
  final bool gizli;
  final VoidCallback onOynayan;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final satirlar = <Widget>[];
    for (var i = 0; i < oynayanlar.length; i += 2) {
      if (i > 0) satirlar.add(const SizedBox(height: SandikSpace.sm));
      final tek = i + 1 >= oynayanlar.length;
      satirlar.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _OynayanCipi(
                oynayan: oynayanlar[i],
                gizli: gizli,
                sira: i,
                onTap: onOynayan,
              ),
            ),
            if (!tek) ...[
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                child: _OynayanCipi(
                  oynayan: oynayanlar[i + 1],
                  gizli: gizli,
                  sira: i + 1,
                  onTap: onOynayan,
                ),
              ),
            ],
          ],
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SiganMetin(
                [l10n.todayMoversTitle, l10n.todayTopMoverLabel],
                style: context.t.labelMedium?.copyWith(
                  color: c.text58,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            SandikTappable(
              onTap: onOynayan,
              semanticLabel: l10n.todayMoversAll,
              child: ExcludeSemantics(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: SandikTouch.min),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.todayMoversAll,
                      style: context.t.labelLarge?.copyWith(
                        color: c.text58,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: c.text36),
                  ],
                ),
              )),
            ),
          ],
        ),
        ...satirlar,
      ],
    );
  }
}

class _OynayanCipi extends StatelessWidget {
  const _OynayanCipi({
    required this.oynayan,
    required this.gizli,
    required this.sira,
    required this.onTap,
  });

  final EnCokOynayan oynayan;
  final bool gizli;

  /// Sıradaki yeri — giriş kademesi (30-80 ms arası, burada 60).
  final int sira;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final o = oynayan;
    final renk = o.artida ? c.gain : c.loss;
    final ad = pozisyonEtiketi(o.positionKey, o.tur, l10n);
    final tutar = gizli
        ? '••••'
        : '${o.degisimTRY >= 0 ? '+' : '−'}${fmtTRY(o.degisimTRY.abs())}';
    final yuzde = isaretliYuzde(o.degisimPct);
    // Kademeli giriş: her çip bir öncekinden biraz sonra belirir (opaklık +
    // hafif yükselme). Kademe [SandikMotion.state]'in üçte biri (60 ms;
    // 30-80 ms bandı). Dekoratif; dokunmayı engellemez, hareketi azalt
    // açıkken tek karede gelir.
    final gecikme = SandikMotion.of(context, SandikMotion.state ~/ 3 * sira);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: SandikMotion.surfaceOf(context) + gecikme,
      curve: Interval(
        gecikme.inMilliseconds /
            math.max(
                1, (SandikMotion.surfaceOf(context) + gecikme).inMilliseconds),
        1,
        curve: SandikMotion.enter,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * SandikSpace.xs2),
          child: child,
        ),
      ),
      child: SandikTappable(
        onTap: onTap,
        semanticLabel: '$ad, $tutar, $yuzde',
        child: ExcludeSemantics(
            child: Container(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.sm2, vertical: SandikSpace.sm),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(color: c.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: SandikSpace.lg,
                height: SandikSpace.lg,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: renk.withValues(alpha: 0.14),
                ),
                child: Icon(
                  o.artida
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 16,
                  color: renk,
                ),
              ),
              const SizedBox(width: SandikSpace.sm),
              // Ad ve tutar kalan yere sığar; sığmazsa KÜÇÜLÜR (kırpılmaz,
              // taşmaz): "Cumhuriyet altını" 320pt'te de tam okunur.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ad,
                        maxLines: 1,
                        style: context.t.titleSmall?.copyWith(
                          color: c.text90,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        tutar,
                        maxLines: 1,
                        style: context.t.labelMedium?.copyWith(
                          color: renk,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        )),
      ),
    );
  }
}

// ── Alım gücü kutusu ─────────────────────────────────────────────────────────

/// "Paran fiyatlara yetişiyor mu?" — "Geçen yılki 100 liran bugün 81 lira",
/// altında dolu çubuk (100 çizgisi sağ uç), yanında hüküm rozeti ("Fiyatlar
/// önde" / "Sen öndesin" / "başa baş"), en altta iki yüzde gri.
///
/// Sayı `ReelGetiriSatiri.yuzLiraBugun` (saf; Performans'taki bileşik reel
/// ile aynı formül). "Puan"/"TÜFE" kelimeleri ana satırda yok: finans dışı
/// kullanıcı için soru ve cevap kelimeyle (benchmark revizesi 2026-10-09).
class _AlimGucuKutusu extends StatelessWidget {
  const _AlimGucuKutusu({
    required this.reel,
    required this.pencereMetni,
    required this.onTap,
  });

  final ReelGetiriSatiri reel;
  final String pencereMetni;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final yuz = reel.yuzLiraBugun;
    final onde = reel.onde;
    final basaBas = fmtNum(reel.fark.abs(), digits: 1) == fmtNum(0, digits: 1);
    final renk = basaBas ? c.text58 : (onde ? c.gain : c.loss);
    final hukum = basaBas
        ? l10n.todayRealEven
        : (onde ? l10n.todayYouAhead : l10n.todayPricesAhead);
    // 100 lira cümlesi TAM SAYI (okunurluk: "81 lira"); iki yüzde ise iki
    // ondalıkla, yuvarlanmadan — TÜİK rakamıyla karşılaştırılabilmeli ve
    // yuvarlama bir arızayı gizlemişti (`inflation_display_precision_test`).
    final yuzMetni = '${yuz.round()}';
    final ayrinti = l10n.todayPurchasingDetail(
        fmtPct(reel.nominal), fmtPct(reel.inflation));
    // Çubuk: 100 lira = tam boy; 81 → %81 dolu. Öndeyken tam dolu, sayı
    // 100'ü aşar (çubuk taşmaz, kelime söyler).
    final oran = (yuz / 100).clamp(0.0, 1.0);

    final govde = Padding(
      padding: const EdgeInsets.all(SandikSpace.md2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.todayPurchasingQuestion,
            style: context.t.labelMedium?.copyWith(
              color: c.text58,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SandikSpace.xs2),
          Text.rich(
            TextSpan(
              style: context.t.titleMedium?.copyWith(
                color: c.text90,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
              children: [
                TextSpan(text: l10n.todayHundredBefore),
                TextSpan(
                  text: l10n.todayHundredAmount(yuzMetni),
                  style: TextStyle(
                    color: renk,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SandikSpace.sm2),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _DoluCubuk(oran: oran, renk: renk),
              ),
              const SizedBox(width: SandikSpace.sm2),
              // Hüküm rozeti kalan payına sığar, sığmazsa küçülür (taşmaz).
              Flexible(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: SandikSpace.sm, vertical: SandikSpace.xs),
                    decoration: BoxDecoration(
                      color: renk.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                    ),
                    child: Text(
                      hukum,
                      maxLines: 1,
                      style: context.t.labelMedium?.copyWith(
                        color: renk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(
            '$ayrinti · $pencereMetni',
            style: context.t.labelSmall?.copyWith(color: c.text36),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      // `excludeSemantics` içteki InkWell'in eylemini de gizler; dokunma
      // eylemi burada verilmezse ekran okuyucu kutuyu açamaz (2026-10-09).
      onTap: onTap,
      label: '${l10n.todayPurchasingQuestion} ${l10n.todayHundredBefore}'
          '${l10n.todayHundredAmount(yuzMetni)}. '
          '$hukum. $ayrinti, $pencereMetni',
      excludeSemantics: true,
      // Kabuk `SandikCard` — piksel aynı. Dokunma `InkWell`: kartın hedef
      // kutusu ripple kullanıyor; aynı panoda iki basma dili olmasın.
      child: SandikCard(
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            child: govde,
          ),
        ),
      ),
    );
  }
}

/// Dolu çubuk: sağ uçta ince "100" işareti; dolgu 0'dan hedefe AKAR
/// ([flow] + [glide]) — gözün ne kadarının kaldığını izlemesi için.
/// Değer değişince (pencere döndü) yeni değere süzülür.
class _DoluCubuk extends StatelessWidget {
  const _DoluCubuk({required this.oran, required this.renk});

  final double oran;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      height: SandikSpace.smd,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: oran),
        duration: SandikMotion.flowOf(context),
        curve: SandikMotion.glide,
        builder: (context, t, _) => Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.hairline,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
              ),
            ),
            FractionallySizedBox(
              widthFactor: t.clamp(0.0, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: renk,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
              ),
            ),
            // 100 lira çizgisi: sağ uç.
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Container(width: SandikSpace.xxs, color: c.text36),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hedef satırı (amber) ────────────────────────────────────────────────────

/// `[ikon] başlık / alt` — amber zemin; dokununca hedef sayfası. Hedef
/// varsa altta ilerleme çubuğu (Monzo Pots kalıbı; benchmark 4/8).
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

  /// Uzun → kısa yazımlar; sığan ilki tam yazılır.
  final List<String> alt;
  final VoidCallback onTap;

  /// 0..1 hedef ilerlemesi — alt satırın altında ince çubuk.
  final double? oran;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      onTap: onTap,
      label: '$baslik. ${alt.first}',
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
                        SiganMetin(
                          [baslik],
                          style: context.t.labelLarge?.copyWith(
                            color: c.amberText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SiganMetin(
                          alt,
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
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                      begin: 0, end: oran!.clamp(0.02, 1.0)),
                                  duration: SandikMotion.flowOf(context),
                                  curve: SandikMotion.glide,
                                  builder: (context, t, _) => Stack(
                                    children: [
                                      ColoredBox(
                                          color: c.surface2,
                                          child: const SizedBox.expand()),
                                      FractionallySizedBox(
                                        widthFactor: t,
                                        child: ColoredBox(
                                            color: c.amberFill,
                                            child: const SizedBox.expand()),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: c.amberText.withValues(alpha: 0.7)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
