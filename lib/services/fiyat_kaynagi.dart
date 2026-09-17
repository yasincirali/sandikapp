import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import 'price_service.dart';

/// **Fiyat kaynağı sözleşmesi — bir varlık HER YERDE aynı yerden beslenir.**
///
/// ## Neden bu dosya var (kullanıcı kararı, 2026-09-17)
/// "Tüm varlıklar her yerde tek kaynaktan ve tutarlı şekilde çekilmelidir."
///
/// Karar bir arızanın ardından geldi: altın serisi dört ayrı yolda dört ayrı
/// merdivenle kuruluyordu ve hangi yolun hangi kaynağı seçtiği isteğe göre
/// değişiyordu (bkz. [altinGramSerisi] ve `TECHNICAL_DEBT.md`). Aynı sınıf
/// ayrışma bu projede daha önce de yaşandı: ağırlık çarpanı üç kopyaydı,
/// Yahoo `range` merdiveni iki kopyaydı, çözünürlük merdiveni iki kopyaydı.
/// Hepsinin ortak imzası aynı: **kod çalışıyor, sayı yanlış ve sessiz.**
///
/// ## Sözleşme
/// "Tek kaynak" burada "her varlık için tek SAĞLAYICI" demek DEĞİLDİR —
/// BIST hissesi Yahoo'dan, TEFAS fonu TEFAS'tan, yurt içi altın/döviz
/// kotasyonu truncgil'den gelir; bunlar farklı piyasalardır. Sözleşme şudur:
///
///   1. Bir varlığın hangi seriden besleneceğine **yalnızca burası** karar
///      verir ([seriSembolleri], [altinGramSerisi]).
///   2. Bir ekranın gösterdiği fiyat ile o ekranın çizdiği serinin ÖLÇEĞİ
///      aynı olmalıdır; farklı sağlayıcılar söz konusuysa seri canlı
///      kotasyonun ölçeğine hizalanır ([olcekCarpani], [kurSerisiniHizala],
///      [altinKalibrasyonHaritasi]).
///   3. **Uydurma sayı yasaktır.** Kur bilinmiyorsa nokta seriye girmez;
///      `35.0`/`40.0` gibi sabitler ölçülmüş veri değildir ve sessizce
///      yanlış toplam üretir.
///
/// Yeni bir fiyat yüzeyi (widget, sparkline, rapor) eklenirken sembol
/// seçimi buradan sorulur; kendi merdivenini kuran yüzey bu dosyanın
/// varlık sebebini ortadan kaldırır.
class FiyatKaynagi {
  const FiyatKaynagi._();

  /// Kur serisi/kotasyonu — TL çevrimlerinin TEK dayanağı.
  static const String usdTry = 'USDTRY=X';

  /// Spot altın, doğrudan TRY (ons). Altın serisinde BİRİNCİL kaynak.
  static const String xauTry = 'XAUTRY=X';

  /// COMEX vadeli altın (ons/USD). Yalnızca [xauTry] yokken yedek —
  /// vadeli sözleşme spot'un yapısal olarak üstünde işlem görür.
  static const String xauUsd = 'GC=F';

  /// Uygulamanın iç altın sembolleri (`ALTIN_GRAM`, `ALTIN_CEYREK`…)
  /// gerçek bir Yahoo/TEFAS sembolü DEĞİLDİR: hepsi gram22k serisinden
  /// ağırlık çarpanıyla türetilir.
  static bool altinMi(String ticker) =>
      ticker.trim().toUpperCase().startsWith('ALTIN_');

  /// [a] için ÇEKİLECEK seriler — çağıran bu listeyi paralel başlatır.
  ///
  /// Altında üç sembol döner (spot, vadeli, kur): merdiven hangisinin
  /// kullanılacağına veri geldikten sonra karar verir ([altinGramSerisi]),
  /// ama üçü de ÖNDEN başlatılmalıdır. Yedeği ancak birincisi boş dönünce
  /// başlatmak altını tek başına iki isteği sıralı yapan tür haline
  /// getiriyordu (en kötü 30 sn; kullanıcı bildirimi 2026-09-13).
  static List<String> seriSembolleri(Asset a) {
    if (a.isManualPrice) return const [];
    if (a.type == AssetType.altin) return const [xauTry, xauUsd, usdTry];
    final t = a.ticker.trim();
    if (t.isEmpty) return const [];
    final gerekli = <String>[t];
    if (usdKote(a)) gerekli.add(usdTry);
    return gerekli;
  }

  /// Varlığın kotasyonu USD mi — TL'ye çevrilmesi gerekir mi?
  ///
  /// Para birimi `Asset.currency`'den okunur; ticker'dan TAHMİN EDİLMEZ.
  /// (`HistoryService.getSymbolHistory` sembol bazlı çalıştığı için orada
  /// ayrı bir kural var: TRY kote olmayan her şey USD kabul edilir.)
  static bool usdKote(Asset a) => a.currency.trim().toUpperCase() == 'USD';
}

/// Altın gram22k serisinin hangi kaynaktan kurulduğu.
///
/// Teşhis için gerekli: iki kaynak AYNI ŞEYİ ÖLÇMEZ (bkz. [altinGramSerisi])
/// ve hangisinin kullanıldığı kullanıcıya gösterilen sayıyı değiştirir.
enum AltinSeriKaynagi {
  /// `XAUTRY=X` — spot altın, doğrudan TRY. TERCİH EDİLEN.
  spotTry,

  /// `GC=F × USDTRY=X` — COMEX VADELİ sözleşmesi, USD üzerinden çevrilmiş.
  vadeliUsd,

  /// Hiçbir kaynak nokta vermedi.
  yok,
}

/// Altının gram22k TL serisini kurar — KAYNAK MERDİVENİ TEK KOPYA.
///
/// ## Kök sebep bu merdivenin dört kopyaya ayrılmasıydı (2026-09-17)
/// Kullanıcı bildirimi: "Her zaman da olmuyor, şu anda düzeldi." Yani
/// altın grafiğindeki sapma KALICI değil, ARALIKLI — ve aralıklı olmasının
/// sebebi serinin kaynağının istekten isteğe DEĞİŞMESİdir:
///
///   * `XAUTRY=X` **spot** altındır (ons/TRY, çevrim yok),
///   * `GC=F` **COMEX vadeli sözleşmesi**dir; taşıma maliyeti yüzünden
///     spot'un yapısal olarak ~%1-2 ÜSTÜNDE işlem görür, üstelik USD
///     üzerinden ikinci bir çevrim (`USDTRY=X`) daha ekler.
///
/// Gün içi yolu birinciyi tercih edip boş dönerse ikinciye düşüyordu; üç
/// uzun dönem yolu ise İKİNCİYİ TEK KAYNAK olarak kullanıyordu. Yahoo
/// `XAUTRY=X` için bazen veri vermiyor (boş liste, 404, 429) ya da 8
/// saniyelik `_grafikCekimSuresi` sınırını aşıyor; boş yanıtlar
/// önbelleğe de ALINMADIĞI için her tazelemede zar yeniden atılıyor.
/// Sonuç: aynı grafik bir açılışta spot ölçeğinde, beş dakika sonra vadeli
/// ölçeğinde çiziliyordu. Serinin son noktası canlı (yurt içi) fiyata
/// sabitlendiği için fark, "ŞİMDİ" imlecinde ~%1-2'lik SAHTE BİR DÜŞÜŞ
/// olarak görünüyordu — bazen var, bazen yok.
///
/// Bu yüzden merdiven tek yerde: dört yolun dördü de aynı sırayı kullanır
/// ve aynı serinin iki tabı iki ayrı ölçekte çizilemez.
///
/// ## Karışım YASAK
/// Vadeli yol yalnızca spot serisi yetersizken kullanılır. İki kaynağın
/// noktaları tek seride birleşseydi, aradaki prim serinin ORTASINDA bir
/// basamak olurdu — kullanıcı için okunamaz bir "hareket".
///
/// ## Uydurma kur YOK
/// Vadeli yolda kuru bulunamayan nokta ATLANIR. Sabit 35.0/40.0 gibi
/// varsayılanlar (iki uzun dönem yolunda duruyordu) gerçek kurdan saptıkça
/// altını olduğundan ucuz/pahalı gösteriyordu: kur serisi düştüğü an,
/// ~%17'ye varan sessiz bir sapma.
///
/// [kurBul] kur serisinden bir ts için oran bulur (yolun kendi "en yakın
/// geçmiş" kuralı geçerli); `null` dönerse nokta atlanır.
({Map<int, double> seri, AltinSeriKaynagi kaynak}) altinGramSerisi({
  required Map<int, double> xauTry,
  required Map<int, double> xauUsd,
  required Map<int, double> usdTry,
  required double? Function(Map<int, double> kurSerisi, int ts) kurBul,
}) {
  // Spot TERCİH edilir — ama KAPSAMI da yeterliyse.
  //
  // Yahoo aynı range için iki sembole farklı uzunlukta/aralıkta seri
  // verebiliyor. Koşulsuz "spot doluysa spot" kuralı, spot üç nokta
  // döndüğünde 1Y grafiğini üç noktaya indirirdi: sapma yerine EKSİK GEÇMİŞ
  // — aynı sınıf bir yanlış gösterim.
  //
  // Ölçüt SÜRE (ilk→son damga), nokta sayısı değil. Sayı yanıltıcı olabilir:
  // vadeli sözleşme borsa saatlerinde işlem görürken spot parite 7/24 kote
  // edilir; aynı pencerede biri diğerinden çok daha SIK örneklenir. Süre ise
  // "aynı geçmişi kapsıyor mu" sorusunu doğrudan yanıtlar. Tek noktalı spot
  // yanıtının süresi sıfırdır ve bu ölçütle zaten elenir.
  //
  // %80 eşiği: bir-iki eksik bar ya da geç açılan seans spot'u elemez, ama
  // pencerenin beşte birinden fazlasını kaçıran bir yanıt elenir.
  double sure(Map<int, double> m) {
    if (m.length < 2) return 0;
    var enKucuk = m.keys.first, enBuyuk = m.keys.first;
    for (final k in m.keys) {
      if (k < enKucuk) enKucuk = k;
      if (k > enBuyuk) enBuyuk = k;
    }
    return (enBuyuk - enKucuk).toDouble();
  }

  final vadeliSure = sure(xauUsd);
  final spotYeterli = xauTry.isNotEmpty &&
      (xauUsd.length < 2 || sure(xauTry) >= vadeliSure * 0.8);
  if (spotYeterli) {
    return (
      seri: <int, double>{
        for (final e in xauTry.entries)
          e.key: PriceService.gram22kFromXauTry(e.value),
      },
      kaynak: AltinSeriKaynagi.spotTry,
    );
  }
  final out = <int, double>{};
  for (final e in xauUsd.entries) {
    final kur = kurBul(usdTry, e.key);
    if (kur == null || kur <= 0) continue;
    out[e.key] = PriceService.gram22kFromXauTry(e.value * kur);
  }
  return (
    seri: out,
    kaynak: out.isEmpty ? AltinSeriKaynagi.yok : AltinSeriKaynagi.vadeliUsd,
  );
}

/// Bir seriyi canlı kotasyonun ÖLÇEĞİNE taşıyan çarpan.
///
/// ## Neden gerekli
/// Grafik ile canlı fiyat farklı sağlayıcılardan gelebiliyor:
///   * altın  → seri Yahoo (uluslararası), canlı truncgil (yurt içi),
///   * kur    → seri Yahoo `USDTRY=X` (mid), canlı truncgil `USD` (Alış).
/// Her grafik son noktasını canlı değere sabitlediği için aradaki makas
/// "ŞİMDİ" imlecinde fiyat hareketi olmayan bir basamak olarak görünüyordu.
///
/// ## Neden ÇARPAN (fark değil)
/// Çarpan oransal olan her şeyi korur: gün içi hareketin şekli, dönem
/// yüzdesi, MA20, RSI aynı kalır — yalnızca serinin SEVİYESİ canlı kaynağın
/// seviyesine oturur. Sabit bir fark eklemek yüzdeleri bozardı.
///
/// ## Neden SINIRLI
/// Kalibrasyon ölçek FARKINI kapatmak içindir, ölçek HATASINI (ağırlık
/// çarpanı uygulanmamış, ons/gram çevrimi atlanmış) örtmek için değil.
/// Reşat hatasında oran 7,2 idi; sessizce "düzeltilseydi" grafik doğru
/// görünür ama pozisyon değeri yanlış kalırdı. Aralık dışındaki oran
/// UYGULANMAZ (1.0 döner) — hata görünür kalsın.
double olcekCarpani({
  required double seriSon,
  required double canli,
  required double alt,
  required double ust,
}) {
  if (!seriSon.isFinite || !canli.isFinite) return 1.0;
  if (seriSon <= 0 || canli <= 0) return 1.0;
  final k = canli / seriSon;
  if (k < alt || k > ust) return 1.0;
  return k;
}

/// Altın kalibrasyonunun kabul aralığı (bkz. [olcekCarpani]).
///
/// Yurt içi makas birkaç yüzdedir, ziynet/eski çeyrek primi en kötü %20
/// mertebesinde; ağırlık çarpanı hatası ise kat mertebesindedir.
const double altinKalibreAltSinir = 0.75;
const double altinKalibreUstSinir = 1.33;

/// Kur kalibrasyonunun kabul aralığı.
///
/// İki FX kaynağı arasındaki fark alış-satış makası kadardır (binde birkaç).
/// %10'u aşan bir sapma "makas" değil ARIZADIR (yanlış sembol, ters
/// çevrilmiş parite) ve kalibrasyonla örtülmemelidir.
const double kurKalibreAltSinir = 0.90;
const double kurKalibreUstSinir = 1.11;

/// Altın serisinin canlı fiyat ölçeğine çarpanı — [olcekCarpani] sarmalayıcısı.
///
/// [seriSonBirimTRY] serinin son noktasının BİRİM (ürün başına) TL değeri,
/// yani `gram22k × ağırlık çarpanı`. [canliBirimTRY] `Asset.currentPrice`.
double altinKalibrasyonu({
  required double seriSonBirimTRY,
  required double canliBirimTRY,
}) =>
    olcekCarpani(
      seriSon: seriSonBirimTRY,
      canli: canliBirimTRY,
      alt: altinKalibreAltSinir,
      ust: altinKalibreUstSinir,
    );

/// Portföydeki her altın sembolü için [altinKalibrasyonu] çarpanı.
///
/// **Sembol BAŞINA hesaplanır, tek bir genel çarpan YETMEZ:** gram altının
/// makası ile çeyreğin/Cumhuriyet'in primi aynı değildir. Aynı sınıf hata
/// gün içi hizalamada yaşandı ("tek toplam çarpanı bir türdeki hareketi tüm
/// türlere yayıyordu") ve çözümü de aynıydı: her şeyi kendi ölçeğinde
/// hesapla.
///
/// [gramSerisi] `{ts: gram22k TL}` — dört grafik yolunun da elindeki ham
/// altın serisi. Boşsa harita boş döner ve çağıran tarafta çarpan 1.0 kalır.
///
/// Çarpan serinin SON noktasından türetilir: hizalanması gereken uç orasıdır.
Map<String, double> altinKalibrasyonHaritasi({
  required Iterable<Asset> assets,
  required Map<int, double> gramSerisi,
  /// Serinin hangi kaynaktan geldiği — biliniyorsa ölçek hafızası ÖĞRENİR
  /// (bkz. [OlcekHafizasi]). Ek ağ maliyeti yok: oran zaten hesaplanıyor.
  AltinSeriKaynagi? kaynak,
}) {
  final out = <String, double>{};
  if (gramSerisi.isEmpty) return out;
  final sonTs = gramSerisi.keys.reduce((a, b) => a > b ? a : b);
  final sonGram = gramSerisi[sonTs] ?? 0;
  if (sonGram <= 0) return out;
  for (final a in assets) {
    if (a.type != AssetType.altin) continue;
    if (a.currentPrice <= 0) continue;
    if (out.containsKey(a.ticker)) continue;
    final seriBirim = sonGram * PriceService.goldWeightFactor(a.ticker);
    out[a.ticker] = altinKalibrasyonu(
      seriSonBirimTRY: seriBirim,
      canliBirimTRY: a.currentPrice,
    );
    // Canlı kaynak düştüğünde yedeğin aynı ölçeğe taşınabilmesi için oran
    // hatırlanır. `a.currentPrice` yurt içi kotasyondur (truncgil).
    final etiket = switch (kaynak) {
      AltinSeriKaynagi.spotTry => FiyatKaynagiEtiketi.spot,
      AltinSeriKaynagi.vadeliUsd => FiyatKaynagiEtiketi.vadeli,
      _ => null,
    };
    if (etiket != null) {
      OlcekHafizasi.instance.ogren(a.ticker, etiket,
          birincil: a.currentPrice, yedek: seriBirim);
    }
  }
  return out;
}

/// Bir fiyatın hangi kaynaktan geldiği — ölçek hafızasının anahtarı.
///
/// Ölçek kaynağa bağlıdır: yurt içi kotasyon (truncgil) ile uluslararası
/// spot çevrimi arasında kalıcı bir makas vardır, vadeli sözleşme ise
/// spot'un da üstündedir. Aynı sembolün iki kaynağı AYNI SAYIYI VERMEZ.
enum FiyatKaynagiEtiketi {
  /// Yurt içi kotasyon (truncgil) — kullanıcıya gösterilen ÖLÇEK budur.
  yurtIci,

  /// `XAUTRY=X` spot çevrimi ya da Yahoo `USDTRY=X`.
  spot,

  /// `GC=F × USDTRY` — vadeli sözleşme çevrimi.
  vadeli,

  /// `open.er-api.com` kur servisi.
  erApi,
}

/// **Kaynaklar arası ölçek hafızası — "kaynak değişti diye sayı zıplamasın".**
///
/// ## Ölçülen arıza (kullanıcı, TestFlight 2026-09-17)
/// "Çok kısa zaman içerisinde yüksek sıçramalar ve düşüşler gösteriyordu.
/// Canlı etkinliklerden fark ettim: bir eksi de bir artı da gözüküyordu."
///
/// Sebep: canlı altın fiyatı BİRİNCİL kaynaktan (truncgil, yurt içi
/// kotasyon) gelir; o kaynak bir tur cevap vermezse `_fetchGoldFallback`
/// devreye girer ve **başka bir ölçekten** (uluslararası spot çevrimi) sayı
/// üretir. İki ölçek arasında ~%1-2 makas var. 45 saniyelik kotasyon
/// önbelleğiyle birlikte bu, dakikalar içinde ileri geri zıplayan bir fiyat
/// demek: portföy toplamı, gün içi grafiğin son noktası ve Live Activity'nin
/// "bugünkü değişim"i aynı anda işaret değiştiriyor. Fiyat hareketi yok —
/// ölçek değişiyor.
///
/// ## Çözüm
/// Yedek kaynak ham haliyle KULLANILMAZ: birincil ile arasındaki ORAN
/// hatırlanır ve yedeğin sayısı o oranla birincilin ölçeğine taşınır.
/// Böylece kaynak değişse bile kullanıcının gördüğü sayı sürekli kalır;
/// gerçek fiyat hareketi ise yedek kaynağın kendi hareketinden gelmeye
/// devam eder (donmuş/bayat bir sayı göstermiyoruz).
///
/// ## Oran nereden öğrenilir — ek ağ maliyeti YOK
/// Grafik yolları zaten her çizimde bu oranı hesaplıyor
/// ([altinKalibrasyonHaritasi], [kurSerisiniHizala]): canlı kotasyon ÷
/// serinin son noktası. Öğrenme oradan akar. Yani uygulama bir kez grafik
/// çizdiyse, canlı kaynak düştüğünde ölçek zaten biliniyordur.
///
/// Oran bilinmiyorsa yedek HAM kullanılır (uydurma çarpan yok) ve bu durum
/// [sonKaynak] üzerinden teşhise açık kalır.
///
/// **Kalıcı bellek (2026-09-17, ikinci tur).** Hafıza ilk sürümde oturum
/// içiydi: uygulama soğuk açılırken birincil kaynak düşükse ve henüz grafik
/// çizilmediyse oran bilinmiyor, yedek HAM kullanılıyordu — kullanıcının
/// "bazen doğru, bazen zıplıyor" dediği artığın bir kaynağı buydu. Oranlar
/// artık `SharedPreferences`'a yazılır ve ilk kullanımda okunur: prim
/// haftalar ölçeğinde değişir, dünkü oran bugün de geçerlidir. Bu oturumda
/// öğrenilen oran diskteki eskiyi ezer (öğrenme her çizimde tazeler).
class OlcekHafizasi {
  OlcekHafizasi._();
  static final OlcekHafizasi instance = OlcekHafizasi._();

  final Map<String, double> _oranlar = {};

  static const _prefsKey = 'olcek_hafizasi_v1';
  Future<void>? _yukleme;

  /// Diskteki oranları bir kez yükler; bu oturumda öğrenilmiş olanlara
  /// DOKUNMAZ (taze oran eskiyi kazanır). Tekrar çağrılması ücretsizdir.
  Future<void> yukle() => _yukleme ??= _yukle();

  Future<void> _yukle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ham = prefs.getString(_prefsKey);
      if (ham == null) return;
      final map = jsonDecode(ham) as Map<String, dynamic>;
      for (final e in map.entries) {
        final v = (e.value as num?)?.toDouble();
        if (v == null || !v.isFinite || v <= 0) continue;
        _oranlar.putIfAbsent(e.key, () => v);
      }
    } catch (_) {
      // Bozuk kayıt — sessizce yok say; oran öğrenildikçe üstüne yazılır.
    }
  }

  Future<void> _kaydet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_oranlar));
    } catch (_) {}
  }

  static String _anahtar(String sembol, FiyatKaynagiEtiketi kaynak) =>
      '${sembol.trim().toUpperCase()}|${kaynak.name}';

  /// Birincil ÷ yedek oranını öğrenir.
  ///
  /// Sınır [altinKalibreAltSinir]–[altinKalibreUstSinir]: bunun dışındaki bir
  /// oran makas değil HATADIR (yanlış sembol, atlanmış ağırlık çarpanı) ve
  /// hafızaya yazılırsa hatayı kalıcılaştırırdı.
  void ogren(
    String sembol,
    FiyatKaynagiEtiketi kaynak, {
    required double birincil,
    required double yedek,
  }) {
    final oran = olcekCarpani(
      seriSon: yedek,
      canli: birincil,
      alt: altinKalibreAltSinir,
      ust: altinKalibreUstSinir,
    );
    // 1.0 iki şey demek olabilir: gerçekten aynı ölçek ya da sınır dışı
    // olduğu için reddedilmiş bir oran. İkisi de "düzeltme gerekmiyor"
    // sonucunu verir; yazmak da zarar vermez, kaydı tazeler.
    _oranlar[_anahtar(sembol, kaynak)] = oran;
    // Diske de yaz — bir sonraki soğuk açılış bu oranla başlasın.
    unawaited(_kaydet());
  }

  /// Bilinen oran — yoksa `null`.
  double? oran(String sembol, FiyatKaynagiEtiketi kaynak) =>
      _oranlar[_anahtar(sembol, kaynak)];

  /// Yedek kaynaktan gelen [deger]i birincilin ölçeğine taşır.
  ///
  /// Oran bilinmiyorsa değer OLDUĞU GİBİ döner — tahmin edilmiş bir çarpan,
  /// hiç çarpan olmamasından daha kötüdür.
  double hizala(String sembol, FiyatKaynagiEtiketi kaynak, double deger) {
    if (deger <= 0 || !deger.isFinite) return deger;
    final o = oran(sembol, kaynak);
    return o == null ? deger : deger * o;
  }

  /// Testler için: hem RAM hem "yüklendi" durumu sıfırlanır (disk değil).
  @visibleForTesting
  void temizle() {
    _oranlar.clear();
    _yukleme = null;
  }
}

/// Kur serisini uygulamanın CANLI kuruna hizalar — tek kur gerçeği.
///
/// Ekranda görünen TL karşılığı `PortfolioState.toTRY` üzerinden CANLI
/// kurla (truncgil `USD`, yoksa er-api/Yahoo) hesaplanıyor; grafik serisi
/// ise Yahoo `USDTRY=X` ile çevriliyordu. İki FX gerçeği aynı ekranda:
/// USD kote bir hissede kâr/zarar çipi ile grafiğin son noktası aynı sayıyı
/// vermiyordu — üstelik ikisi de "canlı" diyordu.
///
/// Hizalama serinin SON noktasını canlı kura eşitler; oranlar korunur, yani
/// geçmiş kur hareketi aynen durur. Canlı kur bilinmiyorsa seri OLDUĞU GİBİ
/// döner (uydurma çarpan yok).
Map<int, double> kurSerisiniHizala(Map<int, double> seri, double? canliKur) {
  if (seri.isEmpty || canliKur == null || canliKur <= 0) return seri;
  final sonTs = seri.keys.reduce((a, b) => a > b ? a : b);
  final son = seri[sonTs] ?? 0;
  // Kur serisi Yahoo'dan (spot/mid), canlı kotasyon yurt içinden gelir.
  // Oran hatırlanır ki canlı kur kaynağı düştüğünde yedek aynı ölçeğe
  // taşınabilsin (bkz. `OlcekHafizasi`).
  if (son > 0) {
    OlcekHafizasi.instance.ogren(FiyatKaynagi.usdTry, FiyatKaynagiEtiketi.spot,
        birincil: canliKur, yedek: son);
  }
  final k = olcekCarpani(
    seriSon: son,
    canli: canliKur,
    alt: kurKalibreAltSinir,
    ust: kurKalibreUstSinir,
  );
  if (k == 1.0) return seri;
  return {for (final e in seri.entries) e.key: e.value * k};
}
