import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../models/varlik_kimligi.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart'
    show SinyalYuzeyi, sinyalYuzeyiProvider;
import '../providers/secili_donem_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/crash_reporter.dart';
import '../services/history_service.dart';
import '../services/period_summary_service.dart' show SummaryPeriod;
import '../services/remote_config_service.dart';
import '../services/son_bakilanlar.dart';
import '../services/varlik_istatistik.dart';
import '../theme/sandik.dart';
import '../utils/acilis_kapisi.dart';
import '../utils/tr_format.dart';
import '../widgets/sandik_async_button.dart';
import '../widgets/analiz_notu_kutusu.dart';
import '../widgets/bozdur_al_satiri.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/donem_istatistik.dart';
import '../widgets/donem_secici.dart';
import '../widgets/katmanli_fiyat_grafigi.dart';
import '../widgets/fon_karnesi_karti.dart';
import '../widgets/para_akisi_karti.dart';
import '../widgets/hacim_radari_karti.dart';
import '../widgets/grafik_stili.dart';
import '../widgets/sandik_skeleton.dart';
import '../widgets/seri_son_guncelleme.dart';
import '../widgets/takip_yildizi.dart';
import '../widgets/varlik_iskeleti.dart';
import '../widgets/varlik_ozeti.dart';
import 'asset_detail_screen.dart'
    show TechnicalSignalPanel;
import '../services/technical_analysis_service.dart'
    show kSinyalCozunurlugu, kSinyalPenceresiGun;
import 'pozisyona_git.dart';
import '../widgets/fon_fiyat_gunu_etiketi.dart';
import '../widgets/sandik_ikon_gecisi.dart';

/// Varlık sayfası — bir varlığı portföye EKLEMEDEN incelemek.
///
/// ## Karar (kullanıcı, 2026-09-28)
/// "Herhangi bir varlığın bireysel istatistik ve zaman aralığına göre
/// grafiklerini portföyüme eklemeden izlemek isterim, oradan direkt
/// portföyüme ya da takip listesine eklenebilir." Üç tasarım seçeneğinden
/// **C (büyüyen sayfa)** seçildi: alttan yarım açılır, yukarı çekince tam
/// sayfa olur; alt çubuk iki hâlde de aynı yerde durur. Ardından: "karşılaştır
/// menüsü, takibe alınanlar ve varlık ekle kısımlarında da varlıklar var; o
/// adımlarda da varlığın detayını izlemek isteyecekler." Dört giriş noktası:
///   · Takip listesi satırı (tam hâlde açılır; eski `WatchlistDetailScreen`'in
///     yerini aldı — ikinci bir detay ekranı ayrışırdı),
///   · Takibe al araması (satıra dokunmak önizler, "+" hemen ekler),
///   · Karşılaştır seçim satırı,
///   · Varlık ekleme seçicileri (hisse, fon, altın, kripto) — orada birincil
///     eylem "Bunu seç" olur, akış bozulmaz.
///
/// ## Sahiplik yok
/// Bu dosya `Asset` tipini bilmez, sahte bir `Asset` üretmez ve sahiplik
/// ekranını açmaz; portföyde olan bir varlık için geçiş `pozisyona_git.dart`
/// üzerinden yapılır (`varlik_sayfasi_test` kilitler). Buradaki hiçbir değer
/// portföy toplamına girmez.
///
/// ## Tek kaynak
/// Fiyat serisi `HistoryService.getSymbolHistory` — takip listesi satırıyla
/// AYNI kaynak; başlıktaki fiyat serinin son noktası, ayrı bir canlı fiyat
/// çağrısı yapılmaz (iki kaynak = ayrışan iki sayı). İstatistikler
/// [DonemIstatistigi]'nde, `build()` dışında, seri gelince bir kez hesaplanır.
///
/// ## Performans
///   · Sayfa grafik beklemeden açılır; grafik yeri aynı yükseklikte iskeletle
///     ayrılır, yerleşim zıplamaz.
///   · Altı dönemin serisi AYNI ANDA istenir; seçili dönem kendi yanıtı
///     gelince ötekileri beklemeden çizilir. Dönem değiştirmek çoğu zaman
///     bekleme göstermez; bekletirse eski çizgi soluk kalır, dönen tekerlek
///     gösterilmez.
///   · Çip altındaki getiriler o dönemin KENDİ serisinden gelir — başka bir
///     seriden türetilseydi çip ile başlık aynı dönem için iki sayı yazardı.
///   · Önce eski seri, sonra taze (2026-10-24, Ar-Ge raporu §1): bellekte
///     seri yoksa diskteki son ölçülmüş seri ([EldekiSeriYukleyici]) hemen
///     SOLUK çizilir, taze seri gelince netleşir; istatistikler ve grafik
///     göstergeleri taze seriden yeniden hesaplanır. Taze çekim düşerse eski
///     seri net kalır, altında "Son güncelleme: …" ([SeriSonGuncelleme]).
Future<void> showVarlikSayfasi(
  BuildContext context,
  VarlikKimligi kimlik, {
  bool tamAcilis = false,
  int? baslangicDonemGun,
  VoidCallback? onSec,
}) async {
  // Satıra hızlı iki dokunuş iki sayfa açmasın (`pushGuarded`'ın gerekçesi).
  if (_acik) return;
  _acik = true;
  try {
    await showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Zemin `background` — varlık detayıyla AYNI katman sırası.
      // `colorScheme.surface` (= surface2) iken sayfa, kartlarından ve
      // dönem seçicinin kabuğundan (surface1) daha AÇIKTI: kabuk zeminde
      // kayboluyor, seçili segment (surface2) zeminle aynı tona düşüyor,
      // istatistik kartları çukur gibi duruyordu. Aynı düzeni paylaşan iki
      // ekran iki farklı yükseklik hiyerarşisi çiziyordu (kullanıcı
      // bildirimi 2026-09-28). Sayfa tam yükseklikte açıldığı için sheet
      // yükselti ipucu kaybolmaz: köşe yuvarlağı ve karartma yeter.
      backgroundColor: context.c.background,
      shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
      builder: (_) => VarlikSayfasi(
        kimlik: kimlik,
        anaBaglam: context,
        tamAcilis: tamAcilis,
        baslangicDonemGun: baslangicDonemGun,
        onSec: onSec,
      ),
    );
  } finally {
    _acik = false;
  }
}

bool _acik = false;

/// Sayfanın dönemleri (gün). `1` = GÜNLÜK (takvim günü, 5 dakikalık seri).
///
/// Uygulamanın tek dönem kümesinden ([SummaryPeriod]) türetilir
/// (2026-09-28): önceden burada 3A yoktu, Performans'ta 5Y yoktu; seçiciler
/// artık her ekranda birebir aynı. Servis `3mo`/`5y` aralıklarını zaten
/// destekliyor (`HistoryService.rangeForPeriod`).
final varlikSayfasiDonemleri = <int>[
  for (final p in SummaryPeriod.values) p.sembolGunu,
];

/// Seri yükleyici — testte ağ yerine sahte seri verilir.
typedef SeriYukleyici = Future<Map<int, double>> Function(
    String ticker, int periodDays);

/// Taze seri + tazeliği: `bayatZaman` doluysa ağ düştü ve seri son iyi
/// kopyadan geldi (`HistoryService.getSymbolHistoryTazelikli`).
typedef TazeSeriYukleyici
    = Future<({Map<int, double> seri, DateTime? bayatZaman})> Function(
        String ticker, int periodDays);

/// Ağa çıkmadan eldeki (disk) son iyi seri; yoksa ya da çok eskiyse `null`
/// (`HistoryService.getSymbolHistoryEldeki`).
typedef EldekiSeriYukleyici
    = Future<({Map<int, double> seri, DateTime zaman})?> Function(
        String ticker, int periodDays);

class VarlikSayfasi extends ConsumerStatefulWidget {
  const VarlikSayfasi({
    super.key,
    required this.kimlik,
    this.anaBaglam,
    this.tamAcilis = false,
    this.baslangicDonemGun,
    this.onSec,
    this.seriYukleyici,
    this.tazeYukleyici,
    this.eldekiYukleyici,
  });

  final VarlikKimligi kimlik;

  /// Sayfanın ALTINDAKİ ekranın bağlamı. Sayfa kapandıktan sonra "Portföye
  /// ekle" / "Pozisyonuma git" rotası buradan itilir; sayfanın kendi bağlamı
  /// kapanınca geçersizleşir.
  final BuildContext? anaBaglam;

  /// Takip listesinden açılınca tam hâlde başlar: kullanıcı zaten o varlığa
  /// "bakmaya" gelmiştir. Aramadan açılınca yarım hâlde başlar; liste arkada
  /// görünür kalır.
  final bool tamAcilis;

  final int? baslangicDonemGun;

  /// Verilirse (varlık ekleme seçicisi) birincil eylem "Bunu seç" olur.
  final VoidCallback? onSec;

  final SeriYukleyici? seriYukleyici;

  /// Testte tazelik bilgisiyle sahte seri ([seriYukleyici]'nin yerine).
  final TazeSeriYukleyici? tazeYukleyici;

  /// Testte sahte eldeki seri. Verilmezse ve iki yükleyici de yoksa disk.
  final EldekiSeriYukleyici? eldekiYukleyici;

  @override
  ConsumerState<VarlikSayfasi> createState() => _VarlikSayfasiState();
}

class _VarlikSayfasiState extends ConsumerState<VarlikSayfasi> {
  static const _yarim = 0.7;
  static const _tam = 0.94;

  /// Sayfanın inebileceği en alt oran. Tutamaç sürüklemesi de, içerik
  /// fırlatması da buraya kadar parmağı izler; altı kapatmaya sayılır.
  static const _enAlt = 0.5;
  /// Grafik kartının dış yüksekliği — ortak grafik stilinden (Performans
  /// stili, 2026-09-28); yükleme/hata kutuları da aynı yükseklikte.
  static const _grafikYuksekligi = GrafikStili.kartYuksekligi;

  final _sayfa = DraggableScrollableController();

  late int _gun = varlikSayfasiDonemleri.contains(widget.baslangicDonemGun)
      ? widget.baslangicDonemGun!
      // Tek dönem hafızası: istek yoksa uygulamanın ortak dönemi
      // (Sadeleştirme 2; bayrak `donem_hafizasi` 2026-10-20'de emekliye
      // ayrıldı, eski 1Y varsayılanı kalktı). Sayfa her dönemi
      // gösterebildiği için en yakına düşme gerekmez.
      : ref.read(seciliDonemProvider).sembolGunu;

  /// Grafikte ŞU AN çizilen dönem. Yeni dönem yüklenirken eski çizgi soluk
  /// kalır — boş kutu ya da dönen tekerlek yerine bağlam.
  int? _cizilen;

  final Map<int, Map<int, double>> _seriler = {};
  final Map<int, DonemIstatistigi?> _istatistik = {};
  final Set<int> _yukleniyor = {};
  final Set<int> _hatali = {};

  /// Dönemin ekrandaki serisi ESKİ bir kopyadan: o kopyanın ölçüldüğü an.
  /// Taze seri gelince silinir; taze çekim düştüyse kalır ve grafiğin altına
  /// "Son güncelleme" yazılır.
  final Map<int, DateTime> _eskiZaman = {};

  /// Eski seri çiziliyor, taze çekim sürüyor → grafik soluk.
  final Set<int> _tazesiYolda = {};

  bool get _agsizTest =>
      widget.seriYukleyici != null || widget.tazeYukleyici != null;

  TazeSeriYukleyici get _tazeYukleyici {
    final t = widget.tazeYukleyici;
    if (t != null) return t;
    final s = widget.seriYukleyici;
    if (s != null) {
      return (tk, d) async => (seri: await s(tk, d), bayatZaman: null);
    }
    return (tk, d) => HistoryService.instance
        .getSymbolHistoryTazelikli(tk, periodDays: d);
  }

  EldekiSeriYukleyici? get _eldekiYukleyici =>
      widget.eldekiYukleyici ??
      (_agsizTest
          ? null
          : (tk, d) => HistoryService.instance
              .getSymbolHistoryEldeki(tk, periodDays: d));

  /// Açılış kapısı açıldı mı (bkz. `utils/acilis_kapisi.dart`): altı dönem
  /// ve sinyal serisi geldi ya da süre doldu. Bir kez `true` olur.
  bool _acildi = false;

  @override
  void initState() {
    super.initState();
    // Tek dönem hafızası: açılışta istenen dönem (Takip satırı, derin bağlantı)
    // ortak döneme de yazılır. Sağlayıcı kurulum sırasında değiştirilemez;
    // kareden sonra yazılır.
    final istenen = widget.baslangicDonemGun;
    if (varlikSayfasiDonemleri.contains(istenen)) {
      Future.microtask(() {
        if (!mounted) return;
        ref.read(seciliDonemProvider.notifier).state =
            SummaryPeriod.values[varlikSayfasiDonemleri.indexOf(istenen!)];
      });
    }
    CrashReporter.arkaPlan(_ilkYukleme(), reason: 'VarlikSayfasi.ilkYukleme');
    // Arama ekranının "Son baktıkların" şeridi — hangi girişten açıldıysa
    // (arama, takip, karşılaştır, ekleme seçicisi) bakılan varlık odur.
    final uid = ref.read(authProvider).valueOrNull?.id;
    // Demo (F1): "son bakılanlar" diske yazılır ve gerçek hesapta görünürdü.
    if (uid != null && !DemoModu.aktif) {
      CrashReporter.arkaPlan(
          SonBakilanlar.instance.kaydet(uid, widget.kimlik),
          reason: 'VarlikSayfasi.sonBakilan');
    }
  }

  /// Grafikteki imlecin `(fiyat, tarih)`ı — büyük fiyat parmağı izlesin
  /// diye (bayrak `goz_alici`; kapalıyken kimse dinlemez, yazılmaz).
  final _imlec = ValueNotifier<(String, String)?>(null);

  @override
  void dispose() {
    _sayfa.dispose();
    _imlec.dispose();
    super.dispose();
  }

  Future<void> _ilkYukleme() async {
    // Altı dönem AYNI ANDA istenir (kullanıcı kararı 2026-09-28: "tüm
    // varlıklar için paralel çağrı"). İlk sürüm seçili dönemi tek başına,
    // kalanları ikişer ikişer çekiyordu — dört dalga ardı ardına bekliyordu
    // ve son çip getirisi ancak dördüncü yanıttan sonra doluyordu.
    //
    // Seçili dönem yine ÖNCE başlatılır ve kendi yanıtı gelir gelmez
    // çizilir (`_yukle` her dönemi bağımsız `setState` eder); ötekileri
    // beklemez. Aşırı yük kaygısı yok: `HistoryService` aynı anahtardaki
    // uçuşan isteği tekilleştirir, önbellekte olan dönem ağa hiç çıkmaz.
    //
    // Açılış kapısı (kullanıcı kararı 2026-09-28): dönemler ve sinyal
    // panelinin serisi aynı anda istenir, sayfa hepsi gelince BİRLİKTE
    // dolar — çipler birer birer, panel en son dolmaz. Panel aynı seriyi
    // `HistoryService` önbelleğinden alır. Testte yükleyici verilmişse
    // (ağsız) sinyal serisi burada istenmez.
    await acilisKapisi([
      _yukle(_gun),
      for (final g in varlikSayfasiDonemleri)
        if (g != _gun) _yukle(g),
      // Panel seviye kapısının arkasında (Başlangıç'ta yok) — çizilmeyecek
      // panelin serisi de istenmez (varlık detayıyla aynı).
      if (!_agsizTest &&
          widget.kimlik.ticker.isNotEmpty &&
          ref.read(sinyalYuzeyiProvider) == SinyalYuzeyi.acik)
        _sinyalKapisi(),
    ]);
    if (!mounted) return;
    await rotaGecisiniBekle(context);
    if (mounted) setState(() => _acildi = true);
  }

  /// Sinyal panelinin serisi açılış kapısında. Eldeki kopyası varsa kapı
  /// tazeyi BEKLEMEZ (önce-eski-seri): sayfa diskteki serilerle hemen açılır,
  /// panel aynı serinin taze çekimini kendi yerinde bekler (uçuşan istek
  /// tekilleştirilir). Kopya yoksa eskisi gibi tazeyi bekler.
  Future<Object?> _sinyalKapisi() {
    Future<Map<int, double>> seri() =>
        HistoryService.instance.getSymbolHistory(widget.kimlik.ticker,
            periodDays: kSinyalPenceresiGun, cozunurluk: kSinyalCozunurlugu);
    final taze = seri();
    final eldeki = HistoryService.eldekiSeriyle(seri);
    return Future.any<Object?>([
      taze,
      eldeki.then<Object?>((e) => e == null ? taze : null),
    ]);
  }

  /// Dönemi yükler. Dönen future dönem İLK KEZ çizilebilir olunca biter
  /// (eski kopya ya da taze seri) — açılış kapısı tazeyi beklemesin; taze
  /// çekim arkada sürer.
  Future<void> _yukle(int gun) {
    final elde = _seriler[gun]?.isNotEmpty ?? false;
    // Boş gelen dönem yeniden denenir: tek bir boş yanıt (TEFAS sınırı,
    // kesinti) dönemi sayfa kapanana kadar boş bırakıyordu (2026-10-23).
    // Taze çekimi düşüp eski seriyle kalan dönem de seçilince yeniden dener.
    if ((elde && !_eskiZaman.containsKey(gun)) || _yukleniyor.contains(gun)) {
      return Future.value();
    }
    setState(() {
      _yukleniyor.add(gun);
      _hatali.remove(gun);
    });
    final ilk = Completer<void>();
    void cizilebilir() {
      if (!ilk.isCompleted) ilk.complete();
    }

    final eldeki = _eldekiYukleyici;
    if (!elde && eldeki != null) {
      eldeki(widget.kimlik.ticker, gun).then((e) {
        // Taze seri önce geldiyse eski kopya yok sayılır.
        if (e == null ||
            !mounted ||
            !_yukleniyor.contains(gun) ||
            (_seriler[gun]?.isNotEmpty ?? false)) {
          return;
        }
        setState(() {
          _seriKoy(gun, e.seri);
          _eskiZaman[gun] = e.zaman;
          _tazesiYolda.add(gun);
        });
        cizilebilir();
      }, onError: (Object e, StackTrace st) {
        CrashReporter.report(e, st, reason: 'VarlikSayfasi.eldekiSeri');
      });
    }
    CrashReporter.arkaPlan(_tazeYukle(gun).whenComplete(cizilebilir),
        reason: 'VarlikSayfasi.tazeSeri');
    return ilk.future;
  }

  Future<void> _tazeYukle(int gun) async {
    try {
      final r = await _tazeYukleyici(widget.kimlik.ticker, gun);
      if (!mounted) return;
      setState(() {
        _yukleniyor.remove(gun);
        _tazesiYolda.remove(gun);
        final eskiCiziliyor = _seriler[gun]?.isNotEmpty ?? false;
        // Ağ boş döndü ve ekranda eski seri var: o kalır, "son güncelleme"
        // yazılır. Boş seri eski ölçümü silmez.
        if (r.seri.isNotEmpty || !eskiCiziliyor) {
          // Yeni seri → istatistik ve grafik göstergeleri yeniden hesaplanır
          // (`_seriKoy`; grafik katmanları `seri`'den çizer).
          _seriKoy(gun, r.seri);
          final z = r.bayatZaman;
          if (z == null) {
            _eskiZaman.remove(gun);
          } else {
            _eskiZaman[gun] = z;
          }
        }
        if (gun == _gun) _cizilen = gun;
      });
    } catch (e, st) {
      // Ağ hatası kullanıcıya dönem kutusunda söylenir; sessiz kalmasın diye
      // Crashlytics'e de non-fatal gider (CLAUDE.md "Hata gösterimi").
      CrashReporter.report(e, st, reason: 'VarlikSayfasi._yukle');
      if (!mounted) return;
      setState(() {
        _yukleniyor.remove(gun);
        _tazesiYolda.remove(gun);
        _hatali.add(gun);
      });
    }
  }

  /// Dönem serisini yazar ve istatistiği BİR KEZ hesaplar (build'de değil).
  void _seriKoy(int gun, Map<int, double> seri) {
    _seriler[gun] = seri;
    _istatistik[gun] =
        DonemIstatistigi.hesapla(seri, periodDays: gun, simdi: DateTime.now());
    if (gun == _gun) _cizilen = gun;
  }

  void _donemSec(int gun) {
    setState(() {
      _gun = gun;
      if (_seriler.containsKey(gun)) _cizilen = gun;
    });
    // Hatalı dönem yeniden seçilince yeniden dener — çıkış yolu açık.
    CrashReporter.arkaPlan(_yukle(gun), reason: 'VarlikSayfasi.donemSec');
  }

  /// Seçiciden dönem seçimi (tek dönem hafızası). Ortak döneme yazma
  /// `_gun` güncellendikten SONRA: [build]'deki dinleyici değişikliği kendi
  /// seçimimiz olarak tanır, ikinci kez yüklemez.
  void _ortakDonemSec(int i) {
    _donemSec(varlikSayfasiDonemleri[i]);
    ref.read(seciliDonemProvider.notifier).state = SummaryPeriod.values[i];
  }

  void _boyutuDegistir() {
    if (!_sayfa.isAttached) return;
    final hedef = _sayfa.size < (_yarim + _tam) / 2 ? _tam : _yarim;
    final sure = SandikMotion.of(context, SandikMotion.surface);
    if (sure == Duration.zero) {
      _sayfa.jumpTo(hedef);
    } else {
      _sayfa.animateTo(hedef, duration: sure, curve: SandikMotion.enter);
    }
  }

  /// Tutamaçtan sürükleme: parmağın dikey hareketi sayfa oranına çevrilir.
  /// [_enAlt]'ın altına inen çekiş kapatmaya sayılır (modalın kendi
  /// jestiyle aynı his).
  ///
  /// Animasyon denetimi 2026-10-01: sayfa eskiden [_yarim]'da (0,7) DONUP
  /// parmak aşağı giderken yerinde duruyordu; içerik fırlatması ise 0,5'e
  /// kadar inebildiği için oradan tutamaca dokununca sayfa 0,7'ye
  /// zıplıyordu. Artık tutamaç da [_enAlt]'a kadar parmağı izler; altı
  /// kapatma sayılır. Bırakınca hedefe parmağın hızıyla gider
  /// ([_hizliSure]).
  double _asagiTasma = 0;

  void _surukle(DragUpdateDetails d) {
    if (!_sayfa.isAttached) return;
    final h = MediaQuery.sizeOf(context).height;
    if (h <= 0) return;
    final yeni = _sayfa.size - d.delta.dy / h;
    if (yeni < _enAlt) {
      _asagiTasma += d.delta.dy;
      _sayfa.jumpTo(_enAlt);
      return;
    }
    _asagiTasma = 0;
    _sayfa.jumpTo(yeni.clamp(_enAlt, _tam));
  }

  void _birak(DragEndDetails d) {
    if (!_sayfa.isAttached) return;
    final hiz = d.primaryVelocity ?? 0; // + aşağı
    final tasma = _asagiTasma;
    _asagiTasma = 0;
    final boy = _sayfa.size;
    // Kapatma: en alta dayanıp çekmeye devam ettiyse ya da yarım boyun
    // altından aşağı fırlattıysa.
    if ((boy <= _enAlt + 0.01 && tasma > SandikTouch.min) ||
        (boy < _yarim - 0.01 && hiz > 700) ||
        (boy <= _yarim + 0.01 && hiz > 1200)) {
      Navigator.of(context).maybePop();
      return;
    }
    final hedef = hiz < -300
        ? _tam
        : hiz > 300
            ? _yarim
            : (boy < (_yarim + _tam) / 2 ? _yarim : _tam);
    final sure = _hizliSure(hedef, hiz);
    if (sure == Duration.zero) {
      _sayfa.jumpTo(hedef);
    } else {
      _sayfa.animateTo(hedef, duration: sure, curve: SandikMotion.enter);
    }
  }

  /// Parmak hızını taşıyan süre: `easeOutCubic` başlangıç eğimi 3'tür, yani
  /// ilk hız = 3 × mesafe / süre. Süreyi buna göre seçmek, bırakma anında
  /// sayfanın parmakla AYNI hızda devam etmesini sağlar (eskiden hız ne
  /// olursa olsun sabit 240 ms'ydi — hızlı fiskede sayfa bir an
  /// yavaşlıyordu). Yavaş bırakışta [SandikMotion.surface]'i aşmaz, çok
  /// hızlıda 120 ms'nin altına inmez.
  Duration _hizliSure(double hedef, double hiz) {
    final tavan = SandikMotion.of(context, SandikMotion.surface);
    if (tavan == Duration.zero) return Duration.zero;
    final h = MediaQuery.sizeOf(context).height;
    final mesafe = (hedef - _sayfa.size).abs() * h;
    if (hiz.abs() < 50 || mesafe <= 0) return tavan;
    final ms = (3 * mesafe / hiz.abs() * 1000).clamp(120.0, tavan.inMilliseconds.toDouble());
    return Duration(microseconds: (ms * 1000).round());
  }

  String _donemEtiketi(int gun) => donemEtiketi(
      context.l10n,
      SummaryPeriod.values[varlikSayfasiDonemleri.indexOf(gun).clamp(
              0, SummaryPeriod.values.length - 1)]
          .label);

  @override
  Widget build(BuildContext context) {
    final k = widget.kimlik;
    // Tek dönem hafızası: ortak dönem başka yüzeyde değişirse sayfa da geçer.
    ref.listen<SummaryPeriod>(seciliDonemProvider, (_, yeni) {
      final gun = yeni.sembolGunu;
      if (gun != _gun) _donemSec(gun);
    });
    return Semantics(
      label: context.l10n.vsSheetSemantics(k.name),
      container: true,
      child: DraggableScrollableSheet(
        controller: _sayfa,
        expand: false,
        initialChildSize: widget.tamAcilis ? _tam : _yarim,
        minChildSize: _enAlt,
        maxChildSize: _tam,
        snap: true,
        snapSizes: const [_yarim],
        builder: (ctx, sc) => Stack(
          children: [
            Column(
              children: [
                // Tutamaç + başlık sayfayı İKİ YÖNE de sürükler (kullanıcı
                // bildirimi 2026-09-28): `DraggableScrollableSheet` yalnızca
                // kendi kaydırma denetleyicisine bağlı listeden büyür;
                // liste dışındaki tutamaçta aşağı çekmek modalın kapatma
                // jestine düşüyor, yukarı çekmek hiçbir şey yapmıyordu.
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: _surukle,
                  onVerticalDragEnd: _birak,
                  child: Column(children: [_tutamac(), _baslik()]),
                ),
                Expanded(
                  child: ListView(
                    controller: sc,
                    padding: EdgeInsets.fromLTRB(
                      SandikSpace.screenH(context),
                      SandikSpace.xs,
                      SandikSpace.screenH(context),
                      // Alt çubuğun altında içerik kalmasın.
                      96 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    children: _govde(),
                  ),
                ),
              ],
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: _altCubuk()),
          ],
        ),
      ),
    );
  }

  // ── Üst kısım ─────────────────────────────────────────────────────────────

  /// Tutamaç — sürüklenir; dokununca yarım ↔ tam arasında geçer (sürükleme
  /// jestini bilmeyen kullanıcı için ikinci yol).
  Widget _tutamac() => SandikTappable(
        onTap: _boyutuDegistir,
        semanticLabel: context.l10n.vsSheetSemantics(widget.kimlik.name),
        child: const SizedBox(
          width: 120,
          height: SandikTouch.min,
          child: Center(child: _TutamacCizgisi()),
        ),
      );

  Widget _baslik() {
    final k = widget.kimlik;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          SandikSpace.screenH(context), 0, SandikSpace.xs, SandikSpace.xs),
      child: Row(
        children: [
          // Başlık portföy varlık detayıyla ORTAK parça (Sadeleştirme 2
          // madde 6); burada yalnız kapatma düğmesi yanına eklenir.
          Expanded(child: VarlikBasligi(kimlik: k)),
          IconButton(
            tooltip: context.l10n.close,
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: context.c.text58),
            constraints: const BoxConstraints(
                minWidth: SandikTouch.min, minHeight: SandikTouch.min),
          ),
        ],
      ),
    );
  }

  // ── Gövde ─────────────────────────────────────────────────────────────────

  /// İskelet → sayfa çapraz solar, boy farkı akar
  /// (2026-10-14; gerekçe [SandikYuklemeGecisi]). `stretch`: liste
  /// öğeleri eskiden ListView'dan sıkı genişlik alıyordu, aynısı korunur.
  List<Widget> _govde() => [
        SandikYuklemeGecisi(
          yukleniyor: !_acildi,
          iskelet: const VarlikIskeleti(grafikYuksekligi: _grafikYuksekligi),
          icerik: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: _govdeIcerik(),
          ),
        ),
      ];

  List<Widget> _govdeIcerik() {
    final k = widget.kimlik;
    final cizilen = _cizilen;
    final ist = cizilen == null ? null : _istatistik[cizilen];
    // Sayılar sembol serisinden (`getSymbolHistory`) ve o seri her sembolde
    // TL: simge ₺ ([sembolSerisiSimgesi], seri denetimi 2026-10-08). Eskiden
    // kotasyonun para biriminden seçiliyordu; ABD hissesi/eurobond/emtia
    // TL sayıyı "$" ile yazıyordu. Dolar kuru "₺49,00" (2026-09-29
    // emülatör testi #13) bu kuralın özel hâli.
    //
    // Ondalık [fiyatBicimi]'nden (2026-10-10): sabit 2 hane SHIB'i ₺0,00,
    // BES fonunu ₺0,18 yazıyordu; `goz_alici` açıkken kaynak hassasiyeti.
    final bicim = fiyatBicimi(ist?.son ?? 0,
        azami: k.type.fiyatHassasiyeti, symbol: sembolSerisiSimgesi);
    // Soluk: başka dönemin çizgisi (yeni dönem yolda) ya da eski kopya
    // (taze seri yolda).
    final bayat = cizilen != null &&
        (cizilen != _gun || _tazesiYolda.contains(cizilen));
    final sonGuncelleme = cizilen == null || _tazesiYolda.contains(cizilen)
        ? null
        : _eskiZaman[cizilen];

    return [
      _fiyatBlogu(ist, bicim, cizilen),
      // Altın/döviz: "Bozdurursan · Alırsan · fark" (2026-10-25). Büyük
      // fiyat serinin son noktası (alış) olarak kalır; satır ise iki sayıyı
      // da AYNI kotasyon kaydından yazar. Kapı reddederse satır yok.
      BozdurAlSatiri(ticker: k.ticker, paraBirimi: k.currency),
      const SizedBox(height: SandikSpace.smd),
      // Seçici grafiğin ÜSTÜNDE — Performans ve varlık detayıyla aynı sıra
      // (kullanıcı kararı 2026-09-28; gerekçe
      // `portfolio_performance/kartlar.dart` kontrol yığını notu).
      _donemCipleri(),
      const SizedBox(height: SandikSpace.sm),
      _grafik(ist, bicim, cizilen, bayat),
      if (sonGuncelleme != null) SeriSonGuncelleme(zaman: sonGuncelleme),
      const SizedBox(height: SandikSpace.md),
      if (ist != null) ...[
        _istatistikIzgarasi(ist, cizilen!),
        const SizedBox(height: SandikSpace.sm),
        _aralikCubugu(ist, bicim, gunIci: cizilen == 1),
        const SizedBox(height: SandikSpace.lg),
      ],
      FonKarnesiKarti(tur: k.type, ticker: k.ticker),
      ParaAkisiKarti(tur: k.type, ticker: k.ticker),
      HacimRadariKarti(tur: k.type, ticker: k.ticker),
      KriptoBaskiKarti(tur: k.type, ticker: k.ticker),
      AnalizNotuKutusu(tur: k.type, ticker: k.ticker),
      // Sahip olunmayan varlık için de teknik göstergeler hesaplanır; panel
      // bir `Asset` istemez.
      //
      // Seviye kapısı (2026-10-08): varlık detayı paneli
      // `seviyeGorunurlugu(...).teknikSinyaller` ile gizliyordu, bu sayfa
      // gizlemiyordu — Başlangıç kullanıcısı sinyali Takip'ten ya da
      // aramadan açınca görüyordu. Aynı kapı burada da.
      //
      // Paywall açıkken ücretsizde üç gösterge (2026-10-10); panel kalan
      // göstergelerin kilidini kendi altında gösterir.
      if (ref.watch(sinyalYuzeyiProvider) == SinyalYuzeyi.acik)
        TechnicalSignalPanel(
          ticker: k.ticker,
          type: k.type,
          subCategory: k.subCategory,
        ),
      // AL/SAT sinyali gösteren her yüzey yasal ibareyi de taşır.
      const SizedBox(height: SandikSpace.sm),
      const DisclaimerWidget(),
      const SizedBox(height: SandikSpace.md),
      Text(
        portfoydeMi(ref, k)
            ? context.l10n.vsOwnedNote
            : context.l10n.unitPriceDiffNote,
        textAlign: TextAlign.center,
        style: context.t.bodySmall?.copyWith(color: context.c.text36),
      ),
    ];
  }

  /// Fiyat bloğu — portföy varlık detayıyla ORTAK [VarlikFiyatBlogu];
  /// sayılar burada, sembol serisinin istatistiğinden ([DonemIstatistigi]).
  /// Düz değişim `isFlat` ile (ızgara ve detay ekranıyla aynı eşik).
  Widget _fiyatBlogu(
      DonemIstatistigi? ist, NumberFormat bicim, int? cizilen) {
    final kapsam = ist?.kapsananGun;
    final donem = cizilen == null
        ? ''
        : kapsam != null
            ? donemKapsamEtiketi(context, kapsam)
            : _donemEtiketi(cizilen);
    // Fonda gösterilen fiyatın GÜNÜ (müşteri raporu 30 Eki #2): önce canlı
    // TEFAS kotasyonunun günü, yoksa çizilen serinin son noktası — büyük
    // rakam (`ist.son`) o noktadır. Bugünün fiyatıysa etiket yer kaplamaz.
    final k = widget.kimlik;
    Widget? fonGunu;
    if (fonFiyatliMi(k.type)) {
      final seri = cizilen == null ? null : _seriler[cizilen];
      final sonNokta = seri == null || seri.isEmpty
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              seri.keys.reduce((a, b) => a > b ? a : b));
      fonGunu = FonFiyatGunuEtiketi(
          tarih: fonFiyatGunu(k.ticker) ?? sonNokta);
    }
    return VarlikFiyatBlogu(
      etiket: context.l10n.currentPriceUpper,
      etiketYani: fonGunu,
      kimlik: widget.kimlik.key,
      imlec: RemoteConfigService.instance.gozAlici ? _imlec : null,
      fiyat: ist == null ? '—' : bicim.format(ist.son),
      fiyatRengi: context.c.text90,
      degisim: donemDegisimSatiri(
        context,
        pct: ist?.degisimPct,
        donem: donem,
        fark: ist?.fark,
        bicim: bicim,
        duz: ist?.isFlat,
        // GÜNLÜK seri boş geldi (ağ yanıt verdi, nokta yok): boş satır
        // yerine detay ekranı ve Bugün kartıyla aynı cümle.
        veriGelmedi: cizilen == 1 && (_seriler[1]?.isEmpty ?? false),
      ),
    );
  }

  /// İskelet/mesaj → grafik çapraz solar (2026-10-14).
  Widget _grafik(
          DonemIstatistigi? ist, NumberFormat bicim, int? cizilen, bool bayat) =>
      SandikIcerikGecisi(
        anahtar: cizilen != null && _seriler[cizilen] != null && ist != null,
        child: _grafikHam(ist, bicim, cizilen, bayat),
      );

  Widget _grafikHam(
      DonemIstatistigi? ist, NumberFormat bicim, int? cizilen, bool bayat) {
    final seri = cizilen == null ? null : _seriler[cizilen];
    if (seri == null || ist == null) {
      // Seçili dönem hatalıysa ve çizilecek başka seri yoksa: neden ve çıkış
      // yolu. Aksi halde aynı yükseklikte iskelet (yerleşim zıplamaz).
      if (_hatali.contains(_gun)) {
        return SizedBox(
          height: _grafikYuksekligi,
          child: Center(
            child: Text(
              context.l10n.vsLoadFailed,
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
          ),
        );
      }
      if (!_yukleniyor.contains(_gun) && seri != null) {
        return SizedBox(
          height: _grafikYuksekligi,
          child: Center(
            child: Text(
              context.l10n.notEnoughHistoryForAsset,
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
          ),
        );
      }
      return const SandikSkeletonChart(height: _grafikYuksekligi);
    }
    return AnimatedOpacity(
      opacity: bayat ? 0.35 : 1.0,
      duration: SandikMotion.of(context, SandikMotion.state),
      curve: SandikMotion.enter,
      // Araç çubuğu (MUM · LOG · ƒx / MA20 · EMA50 · EMA200, aralık) ve
      // katmanlar varlık detayıyla ORTAK (yasin 2026-10-10 gece: "bu 3
      // ekran tutarlı olmalı"). Görünmüyorsa düz grafik, birebir eskisi.
      child: KatmanliFiyatGrafigi(
        ticker: widget.kimlik.ticker,
        type: widget.kimlik.type,
        currency: widget.kimlik.currency,
        subCategory: widget.kimlik.subCategory,
        sembolEtiketi: widget.kimlik.name,
        seri: seri,
        onSeri: _onSeri(cizilen!),
        periodDays: cizilen,
        bicim: bicim,
        imlecEtiketi: RemoteConfigService.instance.gozAlici ? _imlec : null,
        ucTitresimi: RemoteConfigService.instance.gozAlici,
        semanticLabel: context.l10n
            .vsChartSemantics(widget.kimlik.name, _donemEtiketi(cizilen)),
      ),
    );
  }

  /// EMA/Pine ısınması: bu dönemden UZUN, yüklenmiş en kısa dönemin serisi
  /// (sayfa altı dönemi birlikte ister; ek istek yok). 5Y'nin üstü yok:
  /// ortalama dönem içinden hesaplanır.
  Map<int, double>? _onSeri(int gun) {
    for (final g in [...varlikSayfasiDonemleri]..sort()) {
      if (g > gun && _seriler[g] != null) return _seriler[g];
    }
    return null;
  }

  /// Dönem seçici — ortak [DonemSecici]; her segmentin altında o dönemin
  /// getirisi. Seçici böylece aynı zamanda bir getiri şeridi olur: "son bir
  /// yılda ne yaptı" sorusu dokunmadan cevaplanır (eski çiplerin işi,
  /// tek görünüş kararıyla kabuğa taşındı, 2026-09-28).
  Widget _donemCipleri() {
    return DonemSecici(
      donemler: SummaryPeriod.values,
      secili: varlikSayfasiDonemleri.indexOf(_gun),
      getiriler: [
        for (final g in varlikSayfasiDonemleri) _istatistik[g]?.degisimPct,
      ],
      eksik: [
        for (final g in varlikSayfasiDonemleri)
          _istatistik[g]?.kapsamEksik ?? false,
      ],
      onSec: _ortakDonemSec,
    );
  }

  Widget _istatistikIzgarasi(DonemIstatistigi ist, int gun) =>
      DonemIstatistikIzgarasi(
        ist: ist,
        gun: gun,
        donemPct: ist.degisimPct,
        bugunPct: _istatistik[1]?.degisimPct,
        // Dönem getirisi fiyatın altında zaten yazıyor; GÜNLÜK'te (gun 1)
        // "Bugün" de aynı sayı (Ar-Ge 1 Kas 08:45 #3, yasin "yap").
        donemGetirisiGizli: true,
        bugunGizli: gun == 1,
      );

  /// Dönem aralığı: dip ve zirve arasında bugünkü fiyatın yeri.
  Widget _aralikCubugu(DonemIstatistigi ist, NumberFormat bicim,
          {bool gunIci = false}) =>
      DonemAralikCubugu(
        gunIci: gunIci,
        dusuk: ist.dusuk,
        yuksek: ist.yuksek,
        konum: ist.konum,
        bicim: bicim,
      );

  // ── Alt çubuk ─────────────────────────────────────────────────────────────

  /// Duruma göre alt çubuk:
  ///   · seçiciden açıldıysa → [Takip et] [Bunu seç]
  ///   · portföyde           → ([Takipte]) [Pozisyonuma git]
  ///   · diğer               → [Takip et | Takipte] [Portföyüme ekle]
  /// Portföy yüklenirken birincil eylem pasif: sahip olunan varlıkta bir an
  /// "Portföyüme ekle" görünmesi ikinci bir kayıt açtırabilirdi.
  Widget _altCubuk() {
    final k = widget.kimlik;
    final takipte = (ref.watch(watchlistProvider).valueOrNull ?? const [])
        .any((w) => w.key == k.key);
    final yukleniyor = portfoyYukleniyor(ref);
    final sahip = !yukleniyor && portfoydeMi(ref, k);
    final l = context.l10n;

    // Endeks (BIST 100, US100, DAX…) puandır, satın alınamaz: portföye
    // eklenecek bir şey yok. Yalnız takip düğmesi, tam genişlikte.
    if (endeksMi(k.ticker) && widget.onSec == null) {
      return _altCubukKabugu(
          Row(children: [Expanded(child: _takipDugmesi(takipte))]));
    }

    final Widget birincil;
    if (widget.onSec != null) {
      birincil = _birincilDugme(
        etiket: l.vsSelect,
        ikon: Icons.check_rounded,
        onPressed: () {
          Navigator.pop(context);
          widget.onSec!();
        },
      );
    } else if (sahip) {
      birincil = _birincilDugme(
        etiket: l.vsGoToPosition,
        ikon: Icons.arrow_forward_rounded,
        onPressed: () => _sayfadanGec((ctx) => pozisyonuAc(ctx, ref, k)),
      );
    } else {
      birincil = _birincilDugme(
        etiket: l.addToMyPortfolio,
        ikon: Icons.add_rounded,
        onPressed: yukleniyor
            ? null
            : () => _sayfadanGec((ctx) => portfoyeEkleAc(ctx, k)),
      );
    }

    // Portföydeki varlıkta takip düğmesi yalnızca zaten takipteyse görünür
    // (çıkarabilmek için); yeni takip önerilmez — ikisi aynı şeyi izler.
    final takipDugmesi = !sahip || takipte || widget.onSec != null;

    return _altCubukKabugu(Row(
      children: [
        if (takipDugmesi) ...[
          _takipDugmesi(takipte),
          const SizedBox(width: SandikSpace.sm),
        ],
        Expanded(child: birincil),
      ],
    ));
  }

  Widget _altCubukKabugu(Widget icerik) => Container(
        padding: EdgeInsets.fromLTRB(
          SandikSpace.screenH(context),
          SandikSpace.smd,
          SandikSpace.screenH(context),
          SandikSpace.smd + MediaQuery.viewPaddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: context.c.hairline)),
        ),
        child: icerik,
      );

  /// Sayfayı kapatıp alttaki ekrandan rota iter. Sayfanın kendi bağlamı
  /// kapanınca geçersizleşir; rota ALTTAKİ ekranın bağlamından itilir.
  void _sayfadanGec(void Function(BuildContext ctx) git) {
    final alt = widget.anaBaglam;
    Navigator.pop(context);
    if (alt != null && alt.mounted) git(alt);
  }

  Widget _birincilDugme({
    required String etiket,
    required IconData ikon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(ikon, size: 18),
        label: Text(etiket, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          backgroundColor: context.c.amberFill,
          foregroundColor: context.c.onAmber,
          textStyle:
              context.t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SandikRadius.md)),
        ),
      ),
    );
  }

  Widget _takipDugmesi(bool takipte) {
    final k = widget.kimlik;
    final l = context.l10n;
    // Ekran okuyucu eylemi okur ("THYAO takibe al"), yalnızca görünen
    // "Takip et" etiketini değil.
    return Semantics(
      toggled: takipte,
      label: takipte ? l.vsUnwatchSemantics(k.name) : l.vsWatchSemantics(k.name),
      child: SizedBox(
        height: 48,
        // Kilit + gösterge standart bileşende (tek yükleniyor davranışı,
        // 2026-10-08); eski `_takipIslemi` bayrağı yalnızca düğmeyi
        // pasifleştiriyordu, gösterge yoktu.
        child: SandikAsyncButton.kompakt(
          tur: SandikAsyncTur.cerceve,
          onPressed: () => _takipDegistir(takipte),
          icon: SandikIkonGecisi(
              takipte ? Icons.star_rounded : Icons.star_border_rounded,
              boyut: 20, renk: takipte ? context.c.gold : context.c.text90),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.c.text90,
            side: BorderSide(color: context.c.hairline),
            textStyle:
                context.t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SandikRadius.md)),
          ),
          child: Text(
            takipte ? l.watchlistInListLabel : l.vsWatch,
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  /// Takibe al / takipten çıkar — kural ve mesajlar `takipDegistir`'de
  /// (portföy varlık detayıyla ortak).
  Future<void> _takipDegistir(bool takipte) =>
      takipDegistir(context, ref, widget.kimlik, takipte: takipte);
}

/// Sayfa tutamacının çizgisi — dokunma hedefi [_VarlikSayfasiState._tutamac]
/// (44pt); çizgi yalnızca görsel işaret.
class _TutamacCizgisi extends StatelessWidget {
  const _TutamacCizgisi();

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: SandikSpace.xs,
        decoration: BoxDecoration(
          color: context.c.text20,
          borderRadius: BorderRadius.circular(SandikRadius.sm),
        ),
      );
}
