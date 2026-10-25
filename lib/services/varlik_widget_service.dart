import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart' show aktifLotlar;
import '../models/watchlist_item.dart';
import '../utils/piyasa_kapali_etiketi.dart' show borsaTakvimindeMi;
import '../utils/tr_format.dart';
import 'bugun_service.dart';
import 'crash_reporter.dart';
import 'history_service.dart';
import 'home_widget_service.dart';
import 'price_service.dart';

/// Ana ekrandaki TEK VARLIK widget'ını besler: iOS `SandikVarlikWidget`
/// (Ar-Ge kararı 2026-10-24 §1: "önce yalnız iOS") ve Android
/// `SandikVarlikWidgetProvider` (yasin onayı 2026-10-25). İki platform AYNI
/// anahtarı ve AYNI JSON'u okur; Android için ayrı anahtar ya da biçim yok.
///
/// ## Ne yazar
/// Widget sözleşmesine YALNIZ yeni bir anahtar ekler
/// ([HomeWidgetService.varlikListesiniYaz] → `sandik_varliklar`): seçilebilir
/// varlıkların listesi, her birinin biçimli fiyatı ve günlük değişimi.
/// Eski anahtarlar ve biçimleri olduğu gibi kalır; portföy widget'ı ve
/// kilit ekranı widget'ı bu servisten habersizdir.
///
/// ## Seçim listesi (karar: yalnız takip listesi + portföy)
/// Widget'ın düzenleme ekranında katalog araması YOK; kullanıcı yalnızca
/// portföyündeki ([aktifLotlar], kapanmış pozisyon girmez) ve takip
/// listesindeki varlıklardan seçer. Liste burada kurulur ve widget deposuna
/// yazılır; Swift tarafı (`SandikVarlikQuery`) ve Android seçim ekranı
/// (`SandikVarlikSecimActivity`) yalnızca bu listeyi sunar.
///
/// ## Gizlilik (portföy widget'ının değişmezinden bilinçli fark)
/// `HomeWidgetService` portföy özetine varlık adı/ticker yazmaz. Seçim
/// listesi ise tanım gereği varlık adlarını taşır — ama yalnız ADLARI:
/// miktar, maliyet, tutar, lot kimliği, kullanıcı kimliği ve bir varlığın
/// portföyden mi takipten mi geldiği YAZILMAZ. Depo iki platformda da
/// uygulamaya özel: iOS'ta App Group (yalnız bu geliştiricinin uygulaması ve
/// uzantısı), Android'de `home_widget`'ın `MODE_PRIVATE`
/// `SharedPreferences`'ı (widget'ı çizen sağlayıcı uygulamanın kendi
/// sürecinde koşar; launcher yalnız çizilmiş `RemoteViews`'u görür).
/// Android'de 2026-10-25'e kadar hiç yazılmıyordu; widget gelince aynı
/// sınırlarla açıldı. Oturum kapanınca [HomeWidgetService.clear]
/// anahtarı boşaltır. Ana ekranda görünen tek şey kullanıcının SEÇTİĞİ
/// varlığın piyasa fiyatıdır — kamuya açık bir sayı.
///
/// ## Fiyat (sözleşme `fiyat_kaynagi.dart`; `history_service` üzerinden)
/// Sembolü [FiyatKaynagi.widgetKotasyonSembolu] seçer; fiyat ve günlük
/// yüzde piyasa bandının ve portföy fiyat turunun kullandığı AYNI çağrıdan
/// (`PriceService.fetchQuotes`) gelir — ikisi aynı kotasyonun iki alanı.
/// TEFAS kotasyonu yüzde taşımaz; fonun günlük değişimi son iki NAV'dan
/// (gün içi motorun fon basamağıyla aynı seri, `seriCek(…, '5d')`) ve yalnız
/// NAV kotasyonla aynı güne aitse hesaplanır. Fiyat ya da yüzde
/// bilinmiyorsa alan BOŞ yazılır, widget "—" gösterir (uydurma sayı yok).
///
/// ## Kilit ekranı (Ar-Ge 2026-10-25 §2)
/// Aynı widget `accessoryRectangular` ve `accessoryInline` boyutlarında da
/// çizilir; anahtar, seçim ve yazma noktası AYNI. Pakete yalnız isteğe bağlı
/// alanlar eklendi (eski okuyucu tanımadığı alanı yok sayar, `v` hâlâ 1):
/// - `zaman` / `tarih`: yazım anı. Fiyat 1 günden eskiyse widget saatin
///   yerine tarihi gösterir — widget kendi başına ağa çıkmaz, eski bir
///   fiyat "şimdi" gibi durmasın.
/// - öğede `kapanis` / `seansSonu`: "Kapanış" etiketi. Karar burada
///   verilir, Swift'te değil: tür kuralı `borsaTakvimindeMi`, seans
///   `BugunService.seansAcikMi` (tatil takvimi dahil) — Bugün kartıyla aynı.
///   Kripto, altın, döviz hiçbir zaman "kapanış" almaz.
/// - öğede `kisa`: dar satır (`accessoryInline`) için kısa ad.
class VarlikWidgetService {
  VarlikWidgetService._();
  static final instance = VarlikWidgetService._();

  /// Widget iOS ve Android'de var (masaüstü/web'de yok). Test dikişi.
  @visibleForTesting
  static bool Function() platformKontrolu =
      () => Platform.isIOS || Platform.isAndroid;

  /// Bu platformda servis çalışır mı (iOS, Android)?
  static bool get etkin => platformKontrolu();

  /// Kotasyon kaynağı — üretimde piyasa bandıyla aynı çağrı. Test dikişi;
  /// ikinci bir fiyat yolu DEĞİL.
  @visibleForTesting
  Future<Map<String, YahooQuote>> Function(List<String> semboller)
      kotasyonYukleyici = (s) => PriceService.instance.fetchQuotes(s);

  /// Fon NAV serisi — gün içi motorun fon basamağıyla AYNI anahtar
  /// (`HistoryService` önbelleği; çoğu turda ağa çıkmaz). Test dikişi.
  @visibleForTesting
  Future<List<(int, double)>> Function(String sembol) navYukleyici =
      (s) => HistoryService.instance.seriCek(s, '5d');

  /// Widget ana ekranda kurulu mu? Kurulu değilken ağa çıkılmaz: liste
  /// yine yazılır (düzenleme ekranı boş açılmasın) ama fiyatlar yalnız bu
  /// oturumda zaten ölçülmüş olanlardan gelir. Test dikişi.
  @visibleForTesting
  Future<bool> Function() kuruluMu =
      () => HomeWidgetService.instance.varlikWidgetiKuruluMu();

  /// Saat kaynağı — testler sabitler.
  @visibleForTesting
  DateTime Function() saat = DateTime.now;

  /// Aynı liste bu süreden sık yazılmaz. Portföy dinleyicisi dakikada
  /// birkaç kez çağırıyor; widget'ın gösterdiği saat dakika çözünürlüğünde.
  static const yazimAraligi = Duration(seconds: 60);

  String? _sonAnahtar;
  DateTime? _sonYazim;
  Future<void> _kuyruk = Future.value();

  /// Testler için: kısma belleğini sıfırlar.
  @visibleForTesting
  void sifirla() {
    _sonAnahtar = null;
    _sonYazim = null;
    _kuyruk = Future.value();
  }

  /// Seçim listesini ve fiyatları widget deposuna yazar.
  ///
  /// [takip] `null` ise takip listesi henüz yüklenmemiştir: widget
  /// kuruluysa [takipYukle] ile istenir, değilse takip listesi bu turda
  /// atlanır. Gerekçe: takip listesini her açılışta yüklemek (her
  /// sembol için seri isteği) widget'ı kullanmayan kullanıcıya da ağ
  /// maliyeti olurdu.
  ///
  /// Sessizce başarısız olur: widget ikincil bir yüzeydir.
  Future<void> guncelle({
    required Iterable<Asset> lotlar,
    List<WatchlistItem>? takip,
    Future<List<WatchlistItem>> Function()? takipYukle,
  }) {
    if (!etkin) return Future.value();
    final lotListesi = lotlar.toList();
    _kuyruk = _kuyruk.then((_) => _guncelle(lotListesi, takip, takipYukle));
    return _kuyruk;
  }

  Future<void> _guncelle(
    List<Asset> lotlar,
    List<WatchlistItem>? takip,
    Future<List<WatchlistItem>> Function()? takipYukle,
  ) async {
    try {
      var kurulu = true;
      try {
        kurulu = await kuruluMu();
      } catch (_) {
        // Bilinmiyorsa kurulu say: fiyatsız bir widget'tan iyidir.
      }

      var takipListesi = takip;
      if (takipListesi == null && kurulu && takipYukle != null) {
        try {
          takipListesi =
              await takipYukle().timeout(const Duration(seconds: 20));
        } catch (_) {
          takipListesi = null;
        }
      }

      final adaylar =
          varlikWidgetAdaylari(lotlar: lotlar, takip: takipListesi ?? const []);

      final simdi = saat();
      final anahtar = '$kurulu|${adaylar.map((a) => a.sembol).join(',')}';
      final son = _sonYazim;
      if (anahtar == _sonAnahtar &&
          son != null &&
          simdi.difference(son) < yazimAraligi) {
        return;
      }

      final semboller = [for (final a in adaylar) a.sembol];
      var kotasyon = const <String, YahooQuote>{};
      if (kurulu && semboller.isNotEmpty) {
        try {
          kotasyon = await kotasyonYukleyici(semboller);
        } catch (e, st) {
          CrashReporter.report(e, st, reason: 'VarlikWidget.kotasyon');
        }
      }

      final ogeler = <VarlikWidgetOgesi>[];
      for (final a in adaylar) {
        final q = kotasyon[a.sembol];
        // Aynı kotasyonun iki alanı birlikte alınır; kotasyon yoksa bu
        // oturumda ölçülmüş son değerler (ikisi de `PriceService` belleği).
        final fiyat = q != null
            ? q.regularMarketPrice
            : PriceService.instance.sonBilinenFiyat(a.sembol);
        var yuzde = q != null
            ? q.regularMarketChangePercent
            : PriceService.instance.gunlukDegisimPct(a.sembol);
        if (yuzde == null &&
            kurulu &&
            fiyat != null &&
            a.sembol.startsWith(tefasOneki)) {
          try {
            yuzde = fonGunlukYuzdesi(await navYukleyici(a.sembol), fiyat);
          } catch (_) {
            yuzde = null;
          }
        }
        ogeler.add(
            varlikWidgetOgesi(a, fiyat: fiyat, gunlukPct: yuzde, simdi: simdi));
      }

      final paket = varlikWidgetPaketi(ogeler,
          saat: DateFormat('HH:mm', 'tr_TR').format(simdi), zaman: simdi);
      await HomeWidgetService.instance.varlikListesiniYaz(paket);
      _sonAnahtar = anahtar;
      _sonYazim = simdi;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'VarlikWidget.guncelle');
    }
  }
}

/// Seçim listesinin bir adayı — fiyat sorulmadan önceki hâli.
@immutable
class VarlikWidgetAdayi {
  const VarlikWidgetAdayi({
    required this.sembol,
    required this.ad,
    required this.type,
    this.alt,
    this.borsaTakviminde = false,
  });

  /// [FiyatKaynagi.widgetKotasyonSembolu] — aynı zamanda widget'ın seçimi
  /// saklarken kullandığı kimlik (sembol; kullanıcıya ya da lot'a ait değil).
  final String sembol;
  final String ad;

  /// İkinci satır (fonun uzun adı, "Amerikan Doları"); [ad] ile aynıysa yok.
  final String? alt;
  final AssetType type;

  /// Fiyatı BIST takvimine bağlı mı ([borsaTakvimindeMi]) — "Kapanış"
  /// etiketi yalnız bunlarda.
  final bool borsaTakviminde;
}

/// Widget'ın seçebileceği varlıklar: önce portföy (açık pozisyonlar), sonra
/// takip listesi; aynı sembol bir kez. En çok [azami] öğe — düzenleme
/// ekranındaki liste kaydırılabilir ama uzun liste depoyu şişirir.
List<VarlikWidgetAdayi> varlikWidgetAdaylari({
  required Iterable<Asset> lotlar,
  required Iterable<WatchlistItem> takip,
  int azami = 40,
}) {
  final out = <VarlikWidgetAdayi>[];
  final gorulen = <String>{};

  void ekle({
    required AssetType type,
    required String ticker,
    required String name,
    required bool isManualPrice,
    String? subCategory,
  }) {
    if (out.length >= azami) return;
    final sembol = FiyatKaynagi.widgetKotasyonSembolu(
        type: type, ticker: ticker, isManualPrice: isManualPrice);
    if (sembol == null || !gorulen.add(sembol)) return;
    final ad =
        kisaVarlikEtiketi(ticker: ticker, name: name, subCategory: subCategory);
    final uzun = name.trim();
    out.add(VarlikWidgetAdayi(
      sembol: sembol,
      ad: ad,
      type: type,
      alt: uzun.isEmpty || uzun == ad ? null : uzun,
      borsaTakviminde: borsaTakvimindeMi(type: type, subCategory: subCategory),
    ));
  }

  for (final a in aktifLotlar(lotlar)) {
    if (!a.isBuy) continue;
    ekle(
      type: a.type,
      ticker: a.ticker,
      name: a.name,
      isManualPrice: a.isManualPrice,
      subCategory: a.subCategory,
    );
  }
  for (final w in takip) {
    ekle(
      type: w.type,
      ticker: w.ticker,
      name: w.name,
      isManualPrice: false,
      subCategory: w.subCategory,
    );
  }
  return out;
}

/// Seçim listesindeki bir öğe, widget'ın göstereceği biçimde.
@immutable
class VarlikWidgetOgesi {
  const VarlikWidgetOgesi({
    required this.id,
    required this.ad,
    this.alt,
    this.fiyat,
    this.degisim,
    this.yon,
    this.kisa,
    this.kapanis,
    this.seansSonu,
  });

  final String id;
  final String ad;
  final String? alt;

  /// Biçimli fiyat (`₺6.123,45`; endeks puanı `10.245`); bilinmiyorsa null.
  final String? fiyat;

  /// İşaretli günlük yüzde (`+%0,42` / `−%0,06` / `%0,00`); bilinmiyorsa null.
  final String? degisim;

  /// Yön: 1 artış, −1 düşüş, 0 değişim yok; bilinmiyorsa null. Widget yönü
  /// yalnız renkle değil ▲/▼ ile de gösterir.
  final int? yon;

  /// Kilit ekranının tek satırı için kısa ad ("Gr altın"); [ad] ile aynıysa
  /// yazılmaz.
  final String? kisa;

  /// `true`: yazım anında seans kapalıydı, fiyat son kapanış. Yalnız borsa
  /// takvimindeki türlerde; diğerlerinde hiç yazılmaz.
  final bool? kapanis;

  /// Yazım anında seans AÇIKTI: bugünkü kapanış (epoch ms). Widget bu andan
  /// sonra fiyatı "kapanış" diye göstermez (kapanıştan önceki bir an), yazım
  /// saatini gösterir.
  final int? seansSonu;

  Map<String, Object?> toJson() => {
        'id': id,
        'ad': ad,
        if (alt != null) 'alt': alt,
        if (fiyat != null) 'fiyat': fiyat,
        if (degisim != null) 'degisim': degisim,
        if (yon != null) 'yon': yon,
        if (kisa != null) 'kisa': kisa,
        if (kapanis != null) 'kapanis': kapanis,
        if (seansSonu != null) 'seansSonu': seansSonu,
      };
}

/// Adayı fiyat ve günlük yüzdeyle widget öğesine çevirir. Ölçülmemiş ya da
/// geçersiz sayı alana YAZILMAZ (sözleşme madde 3).
///
/// [simdi] verilirse seans bilgisi (`kapanis` / `seansSonu`) eklenir; yalnız
/// fiyatı bilinen, borsa takvimindeki varlıkta. Bilinmiyorsa etiket yok.
VarlikWidgetOgesi varlikWidgetOgesi(
  VarlikWidgetAdayi a, {
  double? fiyat,
  double? gunlukPct,
  DateTime? simdi,
}) {
  final f = (fiyat != null && fiyat.isFinite && fiyat > 0) ? fiyat : null;
  final p =
      (f != null && gunlukPct != null && gunlukPct.isFinite) ? gunlukPct : null;
  String? fiyatMetni;
  if (f != null) {
    // Endeks puandır: simge ve kuruş yok (takip satırıyla aynı kural).
    fiyatMetni = endeksMi(a.sembol)
        ? fmtNum(f, digits: 0)
        : fmtFiyat(f, azami: a.type.fiyatHassasiyeti);
  }
  String? degisim;
  int? yon;
  if (p != null) {
    degisim = fmtPctIsaretli(p);
    // Sıfıra yuvarlanan değer yön taşımaz — işaretsiz metinle aynı kural.
    yon = degisim == fmtPct(0) ? 0 : (p > 0 ? 1 : -1);
  }
  bool? kapanis;
  int? seansSonu;
  if (f != null && simdi != null && a.borsaTakviminde) {
    if (BugunService.seansAcikMi(simdi)) {
      seansSonu = BugunService.seansKapanisi(simdi)?.millisecondsSinceEpoch;
    } else {
      kapanis = true;
    }
  }
  final kisa = kilitEkraniKisaAd(a.ad);
  return VarlikWidgetOgesi(
    id: a.sembol,
    ad: a.ad,
    alt: a.alt,
    fiyat: fiyatMetni,
    degisim: degisim,
    yon: yon,
    kisa: kisa == a.ad ? null : kisa,
    kapanis: kapanis,
    seansSonu: seansSonu,
  );
}

/// Kilit ekranının tek satırı (`accessoryInline`, saatin üstü) dar: "Gram"
/// "Gr" olur ("Gram altın" → "Gr altın"). Başka kelime kısaltılmaz — tahmin
/// edilen kısaltma yanlış okunur; sığmayanı sistem keser.
String kilitEkraniKisaAd(String ad) =>
    ad.replaceAll(RegExp(r'\bGram\b', caseSensitive: false), 'Gr');

/// Fonun günlük yüzdesi: son iki NAV. Son NAV gösterilen kotasyondan
/// belirgin farklıysa (seri bir gün geride) yüzde HESAPLANMAZ — farklı
/// günlerin sayısını birleştirmek yanlış bir "bugün" üretirdi.
double? fonGunlukYuzdesi(List<(int, double)> nav, double fiyat) {
  if (nav.length < 2) return null;
  final onceki = nav[nav.length - 2].$2;
  final son = nav.last.$2;
  if (onceki <= 0 || son <= 0 || fiyat <= 0) return null;
  if (((son - fiyat) / fiyat).abs() > 0.0005) return null;
  return (son - onceki) / onceki * 100;
}

/// Widget sözleşmesinin `sandik_varliklar` değeri. Biçim sürümlüdür (`v`):
/// Swift tarafı tanımadığı sürümü okumaz, eski build'in widget'ı bozulmaz.
///
/// [zaman] (isteğe bağlı) yazım anı: `zaman` epoch ms + `tarih` ("24 Eki
/// 14:05"). Widget fiyatın 1 günden eski olduğunu buradan anlar.
String varlikWidgetPaketi(
  List<VarlikWidgetOgesi> ogeler, {
  required String saat,
  DateTime? zaman,
}) =>
    jsonEncode({
      'v': 1,
      'saat': saat,
      if (zaman != null) 'zaman': zaman.millisecondsSinceEpoch,
      if (zaman != null)
        'tarih': DateFormat('d MMM HH:mm', 'tr_TR').format(zaman),
      'ogeler': [for (final o in ogeler) o.toJson()],
    });
