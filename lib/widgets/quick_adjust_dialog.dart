import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../demo/demo_modu.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/kapanis_ozeti.dart';
import '../models/position.dart' show positionKey;
import '../providers/add_asset_form_provider.dart'
    show addAssetPriceLookupProvider, fiyatBul, tutardanAdet;
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import '../screens/paywall_screen.dart';
import '../services/analytics_service.dart';
import '../services/fiyat_kaynagi.dart' show FiyatKaynagi;
import '../services/mevduat_hesabi.dart';
import '../services/sozlesme_deposu.dart';
import '../services/hizli_tekrar_al.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/money_format.dart';
import '../utils/tr_format.dart';
import 'kapanis_ozeti_sheet.dart';
import 'portfoy_secim_sayfasi.dart';
import 'sandik_acilir.dart';
import 'sandik_async_button.dart';
import 'sandik_segment.dart';
import 'tarih_cipleri.dart';
import 'tur_filtre_cipleri.dart' show SandikFiltreCipi;
import '../l10n/l10n.dart';

/// Bir varlığa hızlıca miktar EKLE veya ÇIKAR — form açmadan.
///
/// Al: yeni miktar + birim fiyat girer, ağırlıklı ortalama maliyet
/// yeniden hesaplanır (mevcut maliyet + yeni maliyet) / toplam adet.
///
/// Sat: sadece miktar girer; alış fiyatı (birim maliyet) korunur.
/// Miktar sıfıra düşerse varlık silinir.
///
/// Mevduat istisnadır: pay değil TL TUTARI girilir, birim fiyat alanı
/// yoktur (bkz. [mevduatTutarIslemi]).
///
/// Al'da "Adet · Tutar" kipi (2026-11-11, Ar-Ge 11 Kas #2): tutar yazılır,
/// adet = tutar ÷ birim fiyat (`tutardanAdet`, Varlık ekle formuyla aynı
/// fonksiyon) canlı hesaplanır; kayıt yine adet + fiyattır.
enum QuickAdjustMode { add, remove }

/// Hızlı miktar çiplerinin SAYISAL önerileri — "Hepsi" çipi hariç.
///
/// ## Neden saf fonksiyon (bulgu #9, 2026-09-29 emülatör testi)
/// 1 lotluk ATATP'de Sat açılınca çipler "Hepsi (1) | 10 | 100 | 1000 |
/// Hepsi (1)" idi: türün sabit listesi eldekine bakmadan basılıyor, sona
/// eldeki miktar "Hepsi" diye ekleniyordu; üstelik listedeki `1` eldekine
/// EŞİT olduğu için o da "Hepsi" etiketini alıyordu. Eldekini aşan öneri
/// satışta zaten `cannotExceedQuantity` hatasına gider — basılması tuzaktı.
///
/// Kural: satışta yalnızca eldekinden KÜÇÜK öneriler (eşiti "Hepsi"
/// çipidir, ikinci kez yazılmaz); alışta türün makul adımları. Kripto
/// ayrı: tam sayı adet nadirdir, 100 BTC öneri olmaz (Varlık Ekle
/// formundaki `quantityPresets` ile aynı ölçek).
///
/// [sonAlim] (Ar-Ge 8 Kas #1): alışta kullanıcının bu varlıktaki son alım
/// miktarı (`sonAlim` → `alimAlanDegeri`, ham defter). Verilirse ekran onu
/// "Son alımın" çipi olarak BAŞA koyar ve çip sayısı aynı kalsın diye
/// buradan bir standart öneri düşer: son alım standart bir değere eşitse
/// o değer (aynı sayı iki çipte yazılmasın), değilse listenin SONUNCUSU
/// (en büyük adım; aylık düzenli alımda en az kullanılan). Satışta yok
/// sayılır: "son alımın" satış önerisi değildir.
List<double> hizliMiktarOnerileri({
  required AssetType tur,
  required String birimTuru,
  required double eldeki,
  required bool satis,
  double? sonAlim,
}) {
  final List<double> taban;
  if (birimTuru == 'gram' || birimTuru == 'gr') {
    taban = const [1, 5, 10, 50];
  } else if (birimTuru == 'ounce' || birimTuru == 'oz') {
    taban = const [0.1, 0.5, 1];
  } else if (tur == AssetType.mevduat) {
    // Mevduatta alan TL tutarıdır (`mevduatTutarIslemi`); [eldeki] de
    // pay değil bakiye (₺) gelir.
    taban = const [1000, 5000, 10000, 50000];
  } else if (tur == AssetType.kripto) {
    taban = const [0.001, 0.01, 0.1, 1];
  } else if (tur == AssetType.doviz) {
    taban = const [10, 50, 100, 500];
  } else if (tur == AssetType.fon || tur == AssetType.hisse) {
    taban = const [1, 10, 100, 1000];
  } else {
    taban = const [1, 5, 10, 100];
  }
  if (!satis) {
    if (sonAlim == null || !(sonAlim > 0) || taban.isEmpty) return taban;
    final esit = taban.indexWhere((v) => (v - sonAlim).abs() < 1e-9);
    final dusen = esit >= 0 ? esit : taban.length - 1;
    return [
      for (var i = 0; i < taban.length; i++)
        if (i != dusen) taban[i],
    ];
  }
  // Kayan nokta payı: 10 − 1e-12 "10'dan küçük" sayılmasın.
  return [for (final v in taban) if (v < eldeki - 1e-9) v];
}

/// Hızlı Sat önizlemesi: bu satışın ortalama maliyete göre kârı/zararı.
class SatisKarOnizleme {
  const SatisKarOnizleme({required this.tutar, required this.yuzde});

  /// Varlığın para biriminde, işaretli (zarar negatif).
  final double tutar;

  /// Ortalama maliyete göre yüzde, işaretli.
  final double yuzde;

  bool get zarar => tutar < 0;
}

/// (satış fiyatı − aktif lotların ortalama maliyeti) × miktar.
///
/// Maliyet yolu yıllık raporun gerçekleşen kârıyla aynı: satılan miktar
/// `purchasePrice` (aktif lotların ağırlıklı ortalaması; hızlı işlem
/// `asset`'i zaten pozisyonun `aktifLotlar` toplamı) ile maliyetlenir.
/// Komisyon önizlemeye girmez — sat formunda komisyon alanı yok, rapor
/// kaydedilen işlemin komisyonunu ayrıca düşer.
///
/// "Uydurma sayı yasak" (fiyat kaynağı sözleşmesi): miktar boş/0, satış
/// fiyatı ya da maliyet bilinmiyorsa `null` — satır hiç çizilmez. Sat
/// önizlemesinin `purchasePrice`'a düşen yedeği burada kullanılmaz; o yedek
/// kârı sıfır gösterirdi.
SatisKarOnizleme? satisKarOnizleme({
  required double? miktar,
  required double? satisFiyati,
  required double? ortalamaMaliyet,
}) {
  if (miktar == null || miktar <= 0) return null;
  if (satisFiyati == null || satisFiyati <= 0) return null;
  if (ortalamaMaliyet == null || ortalamaMaliyet <= 0) return null;
  return SatisKarOnizleme(
    tutar: (satisFiyati - ortalamaMaliyet) * miktar,
    yuzde: (satisFiyati / ortalamaMaliyet - 1) * 100,
  );
}

/// Hızlı Al önizlemesi: bu alımdan sonra pozisyonun ağırlıklı ortalama
/// maliyeti, (eskiAdet × eskiMaliyet + yeniAdet × fiyat) / toplam adet.
///
/// Neden: "maliyetimi düşürür mü" sorusu alımdan ÖNCE sorulur; eskiden
/// cevap yalnız kaydettikten sonra pozisyon kartında görünüyordu (Ar-Ge
/// 6 Kas 22:30). Maliyet yolu [satisKarOnizleme] ile aynı: `purchasePrice`
/// aktif lotların ortalaması; komisyon girmez.
///
/// `null` → satır çizilmez: miktar/fiyat boş ya da 0, eldeki adet 0 (yeni
/// pozisyonda "şimdi" anlamsız) ya da bugünkü maliyet 0/bilinmiyor
/// ("bilinmiyor" işaretli lotun tahmini maliyetinden ortalama uydurulmaz).
double? yeniOrtalamaMaliyet({
  required double eskiAdet,
  required double? eskiMaliyet,
  required double? yeniAdet,
  required double? fiyat,
}) {
  if (yeniAdet == null || yeniAdet <= 0) return null;
  if (fiyat == null || fiyat <= 0) return null;
  if (eskiAdet <= 0) return null;
  if (eskiMaliyet == null || eskiMaliyet <= 0) return null;
  return (eskiAdet * eskiMaliyet + yeniAdet * fiyat) / (eskiAdet + yeniAdet);
}

/// Hızlı Al ters hesabı (Ar-Ge 2026-11-07 #3): ortalama maliyeti [hedef]'e
/// çekmek için [fiyat]'tan kaç birim almak gerekir.
///
/// [yeniOrtalamaMaliyet]'in tersi: (q·a + n·p) / (q + n) = t →
/// n = q·(a − t) / (t − p). Yalnız p < t < a iken anlamlı: hedef bugünkü
/// ortalamanın altında olmalı (alım ortalamayı yalnız fiyata doğru çeker)
/// ve alış fiyatının üstünde (ortalama fiyatın kendisine ancak sonsuz
/// alımla iner). Aksi hâlde `null` → ekran "inilemez" der; öneri dili yok,
/// yalnız hesap.
///
/// Sonuç [ondalik] haneye YUKARI yuvarlanır (BIST lotu 0 hane = tam sayı;
/// kesirli birimde alanın kabul ettiği hassasiyet): aşağı yuvarlamak
/// ortalamayı hedefin üstünde bırakırdı. Ekran "~" ile yazar.
///
/// Maliyet kapısı [yeniOrtalamaMaliyet] ile aynı: eldeki adet ya da
/// ortalama 0/bilinmiyorsa `null`.
double? hedefOrtalamaIcinAdet({
  required double eldeki,
  required double? ortalama,
  required double? fiyat,
  required double? hedef,
  required int ondalik,
}) {
  if (eldeki <= 0 || ondalik < 0) return null;
  if (ortalama == null || ortalama <= 0) return null;
  if (fiyat == null || fiyat <= 0) return null;
  if (hedef == null || hedef <= 0) return null;
  if (!(fiyat < hedef && hedef < ortalama)) return null;
  final n = eldeki * (ortalama - hedef) / (hedef - fiyat);
  return _yukariYuvarla(n, ondalik);
}

/// [n]'i [ondalik] haneye YUKARI yuvarlar (ters hesap ve anaparam ortak).
double _yukariYuvarla(double n, int ondalik) {
  var olcek = 1;
  for (var i = 0; i < ondalik; i++) {
    olcek *= 10;
  }
  // Kayan nokta payı: tam 25 lotluk sonuç 25,0000000001 diye 26 olmasın.
  // Tam sayı adımla bölmek (× 0,0001 yerine / 10.000) gürültü bırakmaz.
  return (n * olcek - 1e-6).ceil() / olcek;
}

/// Hızlı Sat "Anaparam" çipi (Ar-Ge 2026-11-12 #1, Premium): kârdaki
/// pozisyonda maliyetin kadarını geri almak için kaç birim satmak gerekir.
///
/// Toplam maliyet ([eldeki] × [ortalama]; hızlı işlem `asset`'i zaten
/// `aktifLotlar` toplamı, `purchasePrice` onların ağırlıklı ortalaması) ÷
/// [fiyat]. Kullanıcının bugün hesap makinesiyle bulduğu sayı; öneri değil,
/// aritmetik (ekran "satarsan … eline geçer" der, "sat" demez).
///
/// [ondalik] haneye YUKARI yuvarlanır ([hedefOrtalamaOndaligi]: BIST tam
/// lot, kesirli birimde alanın hassasiyeti): aşağı yuvarlamak maliyetin
/// altında kalırdı, çipin sözü "maliyetin kadar" eline geçmesi.
///
/// `null` → çip yok:
/// - zararda ya da başa başta (fiyat ≤ ortalama): maliyeti geri almak
///   tümünü satmaktan fazlasını ister; "anaparam" sözü boş kalır;
/// - fiyat ya da maliyet bilinmiyor/0 (uydurma sayı yasak);
/// - yuvarlanmış sonuç eldekine ulaşıyor: o zaman "Hepsi" çipiyle aynı
///   sayıdır (bulgu #9: aynı sayı iki çipte yazılmaz) ve kalan kâr
///   pozisyonu olmaz — eldekini asla aşmaz.
double? anaparamAdedi({
  required double eldeki,
  required double? ortalama,
  required double? fiyat,
  required int ondalik,
}) {
  if (eldeki <= 0 || ondalik < 0) return null;
  if (ortalama == null || ortalama <= 0 || !ortalama.isFinite) return null;
  if (fiyat == null || fiyat <= 0 || !fiyat.isFinite) return null;
  if (fiyat <= ortalama) return null;
  final n = _yukariYuvarla(eldeki * ortalama / fiyat, ondalik);
  if (n <= 0 || n >= eldeki - 1e-9) return null;
  return n;
}

/// Ters hesabın miktar hassasiyeti (ondalık hane): BIST hissesi tam lot
/// (0); ABD hissesi, fon, kripto, altın gibi kesirli birimde alanın
/// gösterdiği hassasiyet ([Asset.azamiOndalik]; miktar alanı ondalığı her
/// türde kabul ediyor).
int hedefOrtalamaOndaligi(Asset a) =>
    a.type == AssetType.hisse && !a.abdHissesi ? 0 : a.azamiOndalik;

Future<void> showQuickAdjustDialog(
  BuildContext context,
  WidgetRef ref, {
  required Asset asset,
  required QuickAdjustMode mode,
  double? baslangicMiktar,
}) async {
  if (DemoModu.yazmaKapisi('miktar')) return; // Demo: kaydetmek hesap ister (F1).
  // Çoklu portföy (0133): lotları birden çok portföyde olan pozisyonda önce
  // hangi portföyün pozisyonu olduğu sorulur; miktar sınırı ve maliyet o
  // pozisyondan. Karışık değilse (bayrak kapalıyken hep) [asset] aynen.
  // Karışık değilken araya hiçbir `await` girmez: açılış eskisiyle aynı
  // karede.
  if (asset.portfoyKarisik) {
    final pozisyon = await islemIcinPozisyon(context, asset);
    if (pozisyon == null || !context.mounted) return;
    asset = pozisyon;
  }
  final ozet = await showSandikGecisli<KapanisOzeti>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _QuickAdjustDialog(
        asset: asset, mode: mode, ref: ref, baslangicMiktar: baslangicMiktar),
  );
  // "Tümünü sat" kaydedildiyse diyalog kapanış özetiyle döner; özet diyalog
  // KAPANDIKTAN sonra açılır (iki katman modal olmasın).
  if (ozet != null && context.mounted) {
    await showKapanisOzeti(context, ozet,
        tutarGizli: ref.read(balanceHiddenProvider));
  }
}

class _QuickAdjustDialog extends StatefulWidget {
  final Asset asset;
  final QuickAdjustMode mode;
  final WidgetRef ref;

  /// Miktar alanının önden dolu değeri ("Bunu tekrar al", `hizli_tekrar_al.dart`).
  /// Alanın biriminde: çoğu türde miktar, mevduatta TL tutarı. Fiyat yine
  /// bugünün fiyatıdır (`initState`).
  final double? baslangicMiktar;

  const _QuickAdjustDialog({
    required this.asset,
    required this.mode,
    required this.ref,
    this.baslangicMiktar,
  });

  @override
  State<_QuickAdjustDialog> createState() => _QuickAdjustDialogState();
}

class _QuickAdjustDialogState extends State<_QuickAdjustDialog> {
  /// Al/Sat düğmesinin ✓ anı (Ar-Ge 11 Kas 19:04 #3).
  final _basari = SandikBasariSinyali();

  final _qtyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _hedefCtrl = TextEditingController();
  final _tutarCtrl = TextEditingController();

  // ── Adet · Tutar kipi (2026-11-11, Ar-Ge 11 Kas #2) ──────────────────────
  //
  // Fon/altın biriktiren kişi ikinci alımda da ödediği tutarı bilir
  // ("5.000 TL'lik fon aldım"); Varlık ekle formunda tutardan adet vardı,
  // Hızlı Al'da yalnız mevduatta. Hesap formla AYNI fonksiyondan
  // (`tutardanAdet`) — ikinci formül yok. Bölünen fiyat fiyat alanındakidir:
  // Bugün · Dün çipi alanı değiştirince adet de onu izler, kullanıcı fiyatı
  // elle düzeltirse de. Varsayılan Adet: bugünkü kullanıcı diyaloğu
  // değişmiş görmez. Yalnız Al'da: satışta kullanıcı elindeki ADEDİ bilir
  // ("Hepsi" çipi, eldekini aşma kuralı adetle çalışır); tutarla satış
  // ayrı bir soru (hangi fiyattan, kaç pay kalır) ve bu değişikliğin işi
  // değil. Ücretsiz: temel kayıt akışı, formda da ücretsiz.

  /// Tutar kipi seçili mi. Yalnız [_tutarKipiVar] iken anlamlı.
  bool _tutarModu = false;

  /// "Hedef ortalama" alanı açık mı (Hızlı Al ters hesabı). Kapalı başlar:
  /// çoğu alım bu soruyu sormaz, sayfa iki alanla kalsın.
  bool _hedefAcik = false;
  bool _saving = false;
  String? _error;

  // ── İşlem günü (Bugün · Dün, 2026-11-11) ─────────────────────────────────
  //
  // Hızlı al/sat çoğu zaman "dün aldım"ı kaydetmek için açılıyordu; tarih
  // seçilemediği için kayıt bugüne yazılıyor ya da kullanıcı tam formu
  // açıyordu. Yalnız Bugün · Dün: takvim tam formun işi, hızlı diyalog iki
  // dokunuşta kalsın.

  /// Seçili geçmiş gün (gün başı); `null` = bugün. Bugünde kayda tarih
  /// verilmez — sağlayıcı şimdiyi yazar, eski davranış birebir.
  DateTime? _gecmisGun;

  /// Seçili geçmiş günün kapanışı — Varlık ekle'nin geçmiş tarih fiyat
  /// önizlemesiyle AYNI yol (`fiyatBul` + `addAssetPriceLookupProvider`).
  /// Yalnız gerçekten o günün kapanışı bulunduysa dolu; güncel fiyata düşen
  /// yedek burada kullanılmaz (dünün fiyatı diye bugünün fiyatı yazılmaz).
  double? _gecmisFiyat;

  /// Kullanıcı fiyat alanına yazdı mı? Yazdıysa gün değişince alan
  /// ezilmez: bildiği fiyatı o yazmıştır.
  bool _fiyatElle = false;

  /// Açılıştaki fiyat metni — "Bugün"e dönüşte alan buna geri döner.
  String _ilkFiyatMetni = '';

  /// Geç gelen eski yanıt yeni seçimin fiyatını ezmesin.
  int _fiyatIstegi = 0;

  bool get _isAdd => widget.mode == QuickAdjustMode.add;

  /// Mevduat TL tutarıyla girilir (bkz. [mevduatTutarIslemi]).
  bool get _tutarla => widget.asset.type == AssetType.mevduat;

  /// Mevduatın bugünkü birim değeri. Önce sözleşmeden — sözleşme kartının
  /// "bugün" değeri ve "Çektim" tutarı da oradan (`sozlesme_karti`); lot'un
  /// son yazılan fiyatı vade gününde fiyat turundan önce eski kalabilir.
  late final double _birim = () {
    final a = widget.asset;
    final s = SozlesmeDeposu.instance
        .mevduatBirimDegeri(a.ticker, DateTime.now());
    if (s != null && s > 0) return s;
    return a.currentPrice > 0 ? a.currentPrice : a.purchasePrice;
  }();

  /// Mevduatın eldeki bakiyesi (₺), kuruşa yuvarlı — "Hepsi" çipi ve
  /// "Mevcut" satırı bunu yazar, `mevduatTutarIslemi` kuruş payıyla eşler.
  double get _bakiye => (widget.asset.quantity * _birim * 100).round() / 100;

  /// Bu varlığın son alımının alan değeri (ham defter, silinen hariç) —
  /// "Son alımın" çipi. Yalnız alışta; alış yoksa `null` → çip yok.
  /// Diyalog açılışında bir kez okunur: açıkken defter değişmez (kayıt
  /// diyaloğu kapatır).
  late final Asset? _sonAlimLot = () {
    if (!_isAdd) return null;
    final defter =
        widget.ref.read(portfolioProvider).valueOrNull?.assets ?? const [];
    return sonAlim(defter, widget.asset);
  }();

  late final double? _sonAlim =
      _sonAlimLot == null ? null : alimAlanDegeri(_sonAlimLot);

  /// "Anaparam" çipinin adedi (Ar-Ge 2026-11-12 #1): yalnız satışta, fiyatla
  /// girilen ve maliyeti bilinen varlıkta. Satış fiyatı kâr önizlemesiyle
  /// AYNI ve yedeksiz (`_gecmisFiyat ?? currentPrice`): maliyete düşen yedek
  /// pozisyonu başa baş gösterir, çip zaten çıkmazdı; ama sayıyı o yedekten
  /// kurmak uydurma olurdu.
  double? get _anaparamAdedi {
    final a = widget.asset;
    if (_isAdd || _tutarla || a.maliyetBilinmiyor == true) return null;
    return anaparamAdedi(
      eldeki: a.quantity,
      ortalama: a.purchasePrice,
      fiyat: _gecmisFiyat ?? a.currentPrice,
      ondalik: hedefOrtalamaOndaligi(a),
    );
  }

  /// Çip görünür mü / kilitli mi (başa baş satırının deseni): paywall
  /// kapalıyken (ve admin değilken) çip HİÇ yok — canlı kullanıcı bugünkü
  /// çip satırını birebir görür; açıkken ücretsizde kilitli çip, dokununca
  /// paywall (kaynak `anaparam`). Sağlayıcılar yalnız adet varken okunur
  /// (kârdaki satış): öteki açılışlar Premium durumuna hiç sormaz.
  bool get _anaparamGorunur =>
      widget.ref.read(premiumOzellikleriGorunurProvider);
  bool get _anaparamKilitli => widget.ref.read(premiumKilitliProvider);

  void _anaparamPaywall() {
    AnalyticsService.instance.logPremiumGateShown(feature: 'anaparam');
    PaywallScreen.show(context, source: 'anaparam');
  }

  /// Tutar kipindeki "Son alımın" çipi: son alımın ödenen tutarı
  /// (`alimTutari`; mevduatın alan değeriyle aynı hesap).
  late final double? _sonAlimTutari =
      _sonAlimLot == null ? null : alimTutari(_sonAlimLot);

  /// "Adet · Tutar" seçicisi bu varlıkta var mı. Varlık ekle formunun
  /// kuralıyla aynı: Eurobond hariç (fiyat temiz %, miktar nominal — bölme
  /// anlamsız). Mevduat zaten tutarla girilir, kendi yolunda kalır.
  bool get _tutarKipiVar =>
      _isAdd &&
      !_tutarla &&
      widget.asset.type != AssetType.eurobond &&
      !FiyatKaynagi.eurobondMu(widget.asset.ticker);

  bool get _tutarKipinde => _tutarKipiVar && _tutarModu;

  /// Tutarın bölüneceği birim fiyat: fiyat alanı (kaydedilecek olan).
  /// Boş/0 ise `null` → Tutar seçeneği kapalı, adet yazılmaz (uydurma sayı
  /// yasak).
  double? get _birimFiyat {
    final p = _parse(_priceCtrl.text);
    return p != null && p > 0 && p.isFinite ? p : null;
  }

  /// Kayda girecek adet: Adet kipinde alan, Tutar kipinde hesap.
  double? get _etkinAdet => _tutarKipinde
      ? tutardanAdet(tutar: _parse(_tutarCtrl.text), birimFiyat: _birimFiyat)
      : _parse(_qtyCtrl.text);

  /// Tutar → Adet dönüşünde hesaplanan adet alana yazılır (formdaki gibi:
  /// "bankadaki adet farklıysa düzelt" yolu). Adet → Tutar'da tutar alanı
  /// olduğu gibi kalır.
  void _miktarKipiniSec(int i) {
    final tutar = i == 1;
    if (tutar == _tutarModu) return;
    setState(() {
      if (!tutar) {
        final adet = _etkinAdet;
        if (adet != null) _qtyCtrl.text = _fmt(adet);
      }
      _tutarModu = tutar;
      _error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    final baslangic = widget.baslangicMiktar;
    if (baslangic != null && baslangic > 0) {
      _qtyCtrl.text = _fmt(baslangic);
    }
    if (_isAdd && !_tutarla) {
      final currentPrice = widget.asset.currentPrice > 0
          ? widget.asset.currentPrice
          : widget.asset.purchasePrice;
      if (currentPrice > 0) {
        _priceCtrl.text = _fmt(currentPrice);
      }
    }
    _ilkFiyatMetni = _priceCtrl.text;
  }

  /// Satışta kaydedilecek birim fiyat: seçili geçmiş günün kapanışı
  /// bulunduysa o, yoksa eski kural (güncel fiyat, o da yoksa maliyet).
  double get _satisFiyati {
    final a = widget.asset;
    return _gecmisFiyat ??
        (a.currentPrice > 0 ? a.currentPrice : a.purchasePrice);
  }

  Future<void> _gunSec(DateTime gun) async {
    final bugun = dayKey(DateTime.now());
    final gecmis = dayKey(gun).isBefore(bugun) ? dayKey(gun) : null;
    if (gecmis == _gecmisGun) return;
    final istek = ++_fiyatIstegi;
    setState(() {
      _gecmisGun = gecmis;
      _gecmisFiyat = null;
      _error = null;
      if (gecmis == null && _isAdd && !_fiyatElle) {
        _priceCtrl.text = _ilkFiyatMetni;
      }
    });
    if (gecmis == null) return;
    final fiyat = await _gecmisKapanis(gecmis);
    if (!mounted || istek != _fiyatIstegi || fiyat == null) return;
    setState(() {
      _gecmisFiyat = fiyat;
      if (_isAdd && !_fiyatElle) _priceCtrl.text = _fmt(fiyat);
    });
  }

  /// [gun]ün kapanışı, Varlık ekle önizlemesinin yolundan. Elle fiyatlı
  /// varlıkta ve eurobondda (form da tarihli önizleme vermez: kotasyon
  /// birim değer, alan temiz %) sorulmaz. Sembol kanonik biçime çekilir —
  /// sunucudan gelen lot zaten öyledir, form da bu biçimle kaydeder.
  Future<double?> _gecmisKapanis(DateTime gun) async {
    final a = widget.asset;
    if (a.isManualPrice || FiyatKaynagi.eurobondMu(a.ticker)) return null;
    final ticker = kanonikTicker(
            type: a.type, ticker: a.ticker, isManualPrice: a.isManualPrice)
        .trim();
    if (ticker.isEmpty) return null;
    final s = await fiyatBul(
      lookup: widget.ref.read(addAssetPriceLookupProvider),
      ticker: ticker,
      date: gun,
    );
    final p = s.price;
    return s.historical && p != null && p > 0 ? p : null;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _hedefCtrl.dispose();
    _tutarCtrl.dispose();
    super.dispose();
  }

  /// Alan metni `parseTrNumber` ile okunur; `toString()` (`41.235`) binlik
  /// sanılıp 1000 kat büyüyordu (2026-09-23 denetimi F1).
  String _fmt(double v) => fmtInputTr(v);

  /// Türkçe biçimi doğru çözer. Eski hâli `replaceAll(',', '.')` idi ve
  /// "1.000" girdisini 1.0 olarak okuyordu — kullanıcı 1000 lot yazıp
  /// portföyüne 1 lot kaydediyordu, üstelik hiçbir uyarı almadan.
  double? _parse(String text) => parseTrNumber(text);

  String get _unitLabel => widget.asset.unitLabel;

  String get _currencySymbol {
    switch (widget.asset.currency.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return '₺';
    }
  }

  /// Satış önizlemesinin kâr/zarar satırı. Anlamı işaret ve "kâr/zarar"
  /// kelimesi taşır, renk yalnız pekiştirir (HIG: yalnız renkle anlam yok).
  /// Tutar sayfanın toplam satırıyla aynı biçimde: ₺ varlıkta `fmtTRY`,
  /// dövizli varlıkta kendi para biriminde. Bakiye gizliyken tutar
  /// maskelenir, yüzde açık kalır (Ana ekran kuralı). Kaydettikten sonra
  /// ayrıca toast yok (16 Eyl kararı, bkz. `_submit`).
  Widget _karSatiri(BuildContext context, SatisKarOnizleme k) {
    final mutlak = k.tutar.abs();
    final isaret = mutlak == 0 ? '' : (k.zarar ? '\u2212' : '+');
    final tutar = _paraMetni(mutlak, isaret: isaret);
    final yuzde = fmtPctIsaretli(k.yuzde, digits: 1);
    final l = context.l10n;
    return Text(
      k.zarar ? l.quickSaleLoss(tutar, yuzde) : l.quickSaleGain(tutar, yuzde),
      key: const ValueKey('satis_kar_onizleme'),
      style: context.t.titleSmall?.copyWith(
        color: k.zarar ? context.c.loss : context.c.gain,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Önizleme satırlarının ortak para biçimi: ₺ varlıkta `fmtTRY`, dövizli
  /// varlıkta kendi para biriminde; bakiye gizliyken maskeli. [birim] birim
  /// fiyat içindir (ortalama maliyet): `fmtTRY` 0 ondalıkla ₺41,23'ü ₺41
  /// okuturdu.
  String _paraMetni(double v, {String isaret = '', bool birim = false}) {
    final gizli = widget.ref.read(balanceHiddenProvider);
    if (_currencySymbol == '₺') {
      if (gizli) return const BazPara.lira().gizliTutar;
      return '$isaret${birim ? fmtTRYFiyat(v) : fmtTRY(v)}';
    }
    if (gizli) return '•••• $_currencySymbol';
    final f = qtyFormatter(maxDigits: birim ? 4 : 2);
    return '$isaret${f.format(v)} $_currencySymbol';
  }

  /// Hızlı Al'ın ortalama maliyet satırı. Renksiz: yeni ortalama iyi ya da
  /// kötü değildir, bilgi verir (kâr satırının yeşil/kırmızısı burada yanlış
  /// bir yargı ima ederdi).
  Widget _ortalamaSatiri(BuildContext context, double yeni) {
    return Text(
      context.l10n.quickBuyAvgCost(
        _paraMetni(yeni, birim: true),
        _paraMetni(widget.asset.purchasePrice, birim: true),
      ),
      key: const ValueKey('alim_ortalama_onizleme'),
      style: context.t.titleSmall?.copyWith(color: context.c.text58),
    );
  }

  /// Hızlı Al ters hesabı: "Hedef ortalama" bağlantısı, açılınca tek alan
  /// ve sonuç satırı. Sonuca dokunmak miktar alanını o sayıyla doldurur
  /// (çip deseni). Renksiz ve öneri dilsiz: yalnız hesap
  /// ([hedefOrtalamaIcinAdet]). Hedef boşken sonuç satırı yok; yazılmış
  /// ama erişilemeyen hedefte (p < t < a değil) "inilemez" der.
  Widget _hedefBolumu(BuildContext context,
      {required double? hedef, required double? adet}) {
    final l = context.l10n;
    final c = context.c;
    final ondalik = hedefOrtalamaOndaligi(widget.asset);
    final adetMetni =
        adet == null ? null : qtyFormatter(maxDigits: ondalik).format(adet);
    final sonuc = hedef == null
        ? null
        : adetMetni == null
            ? l.quickTargetAvgUnreachable
            : l.quickTargetAvgResult(
                _paraMetni(hedef, birim: true), adetMetni, _unitLabel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            expanded: _hedefAcik,
            child: SandikTappable(
              key: const ValueKey('hedef_ortalama_ac'),
              haptic: SandikHaptic.none,
              onTap: () => setState(() => _hedefAcik = !_hedefAcik),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: SandikTouch.min),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l.quickTargetAvg,
                      style: context.t.titleSmall?.copyWith(
                          color: c.amberText, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: SandikSpace.xs),
                    SandikAcilirOk(
                      acik: _hedefAcik,
                      child: Icon(Icons.expand_more_rounded,
                          size: SandikSpace.lgs, color: c.amberText),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SandikAcilir(
          acik: _hedefAcik,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('hedef_ortalama_alani'),
                controller: _hedefCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                style: context.t.numMedium
                    .copyWith(fontWeight: FontWeight.w500, color: c.text90),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.quickTargetAvgField,
                  suffixText: _currencySymbol,
                  suffixStyle: context.t.titleMedium?.copyWith(color: c.text58),
                  // Dolgu/çerçeve temadan (`inputDecorationTheme`).
                ),
              ),
              if (sonuc != null)
                adet == null
                    ? Padding(
                        padding: const EdgeInsets.only(top: SandikSpace.sm),
                        child: Text(
                          sonuc,
                          key: const ValueKey('hedef_ortalama_sonuc'),
                          style:
                              context.t.titleSmall?.copyWith(color: c.text58),
                        ),
                      )
                    : SandikTappable(
                        haptic: SandikHaptic.none,
                        semanticLabel: '$sonuc. ${l.quickTargetAvgFillHint}',
                        // Sonuç ADET'tir: Tutar kipindeyse Adet'e dönülür,
                        // yoksa sayı tutar alanına yazılmış olurdu.
                        onTap: () => setState(() {
                          _qtyCtrl.text = _fmt(adet);
                          _tutarModu = false;
                          _error = null;
                        }),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              minHeight: SandikTouch.min),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  sonuc,
                                  key: const ValueKey('hedef_ortalama_sonuc'),
                                  style: context.t.titleSmall
                                      ?.copyWith(color: c.text90),
                                ),
                              ),
                              const SizedBox(width: SandikSpace.xs),
                              Icon(Icons.south_west_rounded,
                                  size: SandikSpace.md, color: c.text58),
                            ],
                          ),
                        ),
                      ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_tutarla) return _tutarlaKaydet();
    if (_tutarKipinde) {
      final t = _parse(_tutarCtrl.text);
      if (t == null || t <= 0) {
        setState(() => _error = context.l10n.enterValidAmount);
        return;
      }
    }
    final qty = _etkinAdet;
    if (qty == null || qty <= 0) {
      setState(() => _error = _tutarKipinde
          ? context.l10n.enterValidUnitPrice
          : context.l10n.enterValidQuantity);
      return;
    }

    if (_isAdd) {
      final price = _parse(_priceCtrl.text);
      if (price == null || price <= 0) {
        setState(() => _error = context.l10n.enterValidUnitPrice);
        return;
      }
    } else {
      if (qty > widget.asset.quantity) {
        setState(() => _error =
            context.l10n.cannotExceedQuantity(_fmt(widget.asset.quantity)));
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    KapanisOzeti? ozet;
    try {
      final asset = widget.asset;
      final notifier = widget.ref.read(portfolioProvider.notifier);

      if (_isAdd) {
        final addPrice = _parse(_priceCtrl.text)!;
        await notifier.addAsset(
          name: asset.name,
          ticker: asset.ticker,
          type: asset.type,
          quantity: qty,
          purchasePrice: addPrice,
          currency: asset.currency,
          // Yeni alış yeni bir işlemdir; önceki lot'un notu ona ait değil.
          notes: '',
          isManualPrice: asset.isManualPrice,
          subCategory: asset.subCategory,
          unitType: asset.unitType,
          sozlesmeId: asset.sozlesmeId,
          // Alış pozisyonun portföyüne (0133; bayrak kapalıyken yok sayılır).
          portfoyId: asset.portfoyId,
          addedDate: _gecmisGun,
        );
      } else {
        final tumu = (qty - asset.quantity).abs() < 0.0001;
        final baslangic = DateTime.now();
        await notifier.addSellTransaction(
          asset: asset,
          quantity: qty,
          sellPrice: _satisFiyati,
          addedDate: _gecmisGun,
        );
        if (tumu) ozet = _kapanisOzeti(qty, baslangic);
      }

      if (!mounted) return;
      // Başarı toast'ı YOK (kullanıcı kararı, 2026-09-16): sheet kapanıyor ve
      // varlığın miktarı arkadaki listede anında değişiyor — onay zaten
      // ekranda. Hata yolu sessiz değil; `_error` ile sheet içinde kalır.
      // Tümünü satışta kapanış özeti döner (`showQuickAdjustDialog` açar).
      // Sessiz başarıya düğmede ✓ eklendi (Ar-Ge 11 Kas 19:04 #3): sayfa
      // kapanmadan önce gösterge ✓'ye döner, başarı titreşimi gelir.
      await _basari.goster();
      if (!mounted) return;
      Navigator.pop(context, ozet);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.l10n.transactionFailed(friendlyError(e));
      });
    }
  }

  /// "Tümünü sat" kaydından sonra kapanış özeti. Satış satırı defterden
  /// okunur (satış günü kuru ve kimlik sağlayıcının yazdığı gibi); bulunamazsa
  /// (demo, yazılamamış satır) özet yok: tahmini satırla sayı uydurulmaz.
  /// [baslangic]: kayıttan hemen önce; eski aynı miktarlı satış seçilmesin.
  /// Mevduat buraya gelmez (`_tutarlaKaydet`): getirisi sözleşmeden okunur.
  KapanisOzeti? _kapanisOzeti(double qty, DateTime baslangic) {
    final defter =
        widget.ref.read(portfolioProvider).valueOrNull?.assets ?? const [];
    final anahtar = positionKey(widget.asset);
    final esik = baslangic.subtract(const Duration(seconds: 1));
    for (final a in defter) {
      if (!a.isSell || positionKey(a) != anahtar) continue;
      if ((a.quantity - qty).abs() > 1e-9) continue;
      final yazildi = a.createdAt;
      if (yazildi == null || yazildi.isBefore(esik)) continue;
      return kapanisOzeti(defter: defter, satis: a);
    }
    return null;
  }

  /// Mevduat: yazılan tutar alışın maliyeti / satışın değeri olur; pay
  /// tutarın birim değere bölümüdür. Faiz birim değerde kalır, satış
  /// tutarına ikinci kez binmez (kullanıcı bildirimi, 2026-10-08).
  Future<void> _tutarlaKaydet() async {
    final tutar = _parse(_qtyCtrl.text);
    if (tutar == null || tutar <= 0) {
      setState(() => _error = context.l10n.enterValidAmount);
      return;
    }
    final islem = mevduatTutarIslemi(
      tutar: tutar,
      birim: _birim,
      eldekiPay: widget.asset.quantity,
      satis: !_isAdd,
    );
    if (islem == null) {
      setState(() => _error = _isAdd
          ? context.l10n.enterValidAmount
          : context.l10n.cannotExceedBalance(fmtTRY(_bakiye, digits: 2)));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final asset = widget.asset;
      final notifier = widget.ref.read(portfolioProvider.notifier);
      if (_isAdd) {
        await notifier.addAsset(
          name: asset.name,
          ticker: asset.ticker,
          type: asset.type,
          quantity: islem.pay,
          purchasePrice: islem.birim,
          currency: asset.currency,
          notes: '',
          isManualPrice: asset.isManualPrice,
          subCategory: asset.subCategory,
          unitType: asset.unitType,
          sozlesmeId: asset.sozlesmeId,
          portfoyId: asset.portfoyId,
        );
      } else {
        await notifier.addSellTransaction(
          asset: asset,
          quantity: islem.pay,
          sellPrice: islem.birim,
        );
      }
      if (!mounted) return;
      // Düğmede ✓ (Ar-Ge 11 Kas 19:04 #3), sonra kapanış.
      await _basari.goster();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.l10n.transactionFailed(friendlyError(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final numFmt = qtyFormatter(maxDigits: asset.azamiOndalik);
    final accent = _isAdd ? context.c.gain : context.c.loss;
    final qty = _etkinAdet ?? 0;
    final price = _parse(_priceCtrl.text) ?? 0;
    // Satışta önizleme, KAYDEDİLECEK satış fiyatını kullanır (bkz.
    // `addSellTransaction` çağrısı). Eskiden "Satış değeri" etiketiyle alış
    // maliyeti gösteriliyordu; kaydedilen tutar başkaydı (2026-09-23
    // denetimi F10).
    final satisFiyati = _satisFiyati;
    final total = qty * (_isAdd ? price : satisFiyati);
    // Kâr önizlemesi yalnız satışta ve fiyatla girilen varlıkta (mevduatta
    // alan tutardır). Fiyat yedeksiz okunur; maliyeti "bilinmiyor" işaretli
    // lot tahmini maliyet taşıdığı için önizleme vermez.
    final karOnizleme = _isAdd || _tutarla || asset.maliyetBilinmiyor == true
        ? null
        : satisKarOnizleme(
            miktar: qty,
            satisFiyati: _gecmisFiyat ?? asset.currentPrice,
            ortalamaMaliyet: asset.purchasePrice,
          );
    final tumunuSatiyor = !_isAdd &&
        qty > 0 &&
        (_tutarla
            ? (qty - _bakiye).abs() < 0.01
            : (qty - asset.quantity).abs() < 0.0001);
    final anaparam =
        karOnizleme == null ? null : _anaparamAdedi;
    final anaparamKilitli = anaparam != null && _anaparamKilitli;
    // Alım önizlemesi: girilen birim fiyatla (kaydedilecek olan) yeni
    // ortalama. Satıştaki kâr satırıyla aynı maliyet kapısı.
    final ortalamaOnizleme =
        !_isAdd || _tutarla || asset.maliyetBilinmiyor == true
            ? null
            : yeniOrtalamaMaliyet(
                eskiAdet: asset.quantity,
                eskiMaliyet: asset.purchasePrice,
                yeniAdet: qty,
                fiyat: price,
              );

    // Ters hesap (Ar-Ge 2026-11-07 #3): ortalama önizlemesiyle AYNI maliyet
    // kapısı (alım, fiyatla girilen varlık, maliyet biliniyor, elde var).
    // Alış fiyatı yazılan fiyat; boşsa bugünkü fiyat.
    final hedefKapisi = _isAdd &&
        !_tutarla &&
        asset.maliyetBilinmiyor != true &&
        asset.quantity > 0 &&
        asset.purchasePrice > 0;
    final hedef = _parse(_hedefCtrl.text);
    final hedefAdet = !hedefKapisi || hedef == null || hedef <= 0
        ? null
        : hedefOrtalamaIcinAdet(
            eldeki: asset.quantity,
            ortalama: asset.purchasePrice,
            fiyat: price > 0 ? price : asset.currentPrice,
            hedef: hedef,
            ondalik: hedefOrtalamaOndaligi(asset),
          );

    // Marka kabuğu (Ar-Ge 5 Kas 22:40 #7; eskiden Material `Dialog`): kart
    // onay/bilgi diyaloğuyla aynı, kenar vurgusu işlemin rengi (al yeşil,
    // sat kırmızı). İç pay ve kaydırma düzeni aşağıdaki `Padding`'de
    // kaldı; kabuk klavye payını `Dialog` gibi kendisi verir.
    return SandikDiyalogKabugu(
      vurgu: accent,
      kaydir: false,
      padding: EdgeInsets.zero,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              SandikSpace.lgs, SandikSpace.lgs, SandikSpace.lgs, SandikSpace.md),
          // Klavye açıkken (miktar alanı autofocus) diyalog ekranın
          // yarısına sığmak zorunda: başlık + iki alan + toplam + düğmeler
          // ~490px, iOS ondalık klavyeyle kalan ~410–490px. Gövde kayar,
          // düğme satırı DIŞARIDA kalır — Al/Sat hiçbir yükseklikte
          // kırpılmaz (klavye denetimi 2026-10-08).
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
           Flexible(
            child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // ── Başlık ────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                  ),
                  child: Icon(
                    _isAdd
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: accent,
                    size: SandikSpace.lg,
                  ),
                ),
                const SizedBox(width: SandikSpace.smd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // Swipe etiketiyle aynı dil: orada "Al/Sat" deyip
                        // burada "Ekle/Çıkar" göstermek akışı kopartıyordu.
                        // Aynı anahtar (`buyAction`/`sellAction`).
                        _isAdd
                            ? context.l10n.buyAction
                            : context.l10n.sellAction,
                        style: context.t.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.c.text90,
                        ),
                      ),
                      Text(
                        asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.titleSmall?.copyWith(
                          color: context.c.text58,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.close,
                  icon: Icon(Icons.close_rounded,
                      color: context.c.text58, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: SandikSpace.sm),

            // ── Mevcut durum ──────────────────────────────────────────
            // Düz satır (tasarım turu 2026-11-12, Ar-Ge #5): eskiden gri
            // dolgulu kutuydu; bilgi satırı kutu istemez, Varlık Ekle'deki
            // gibi etiket + değer. Kutular sayfada yalnız giriş alanlarına
            // kaldı — göz neyin yazılabilir olduğunu şekilden okur.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm2),
              child: Row(
                children: [
                  Text(context.l10n.quickHolding,
                      style: context.t.bodySmall?.copyWith(color: context.c.text36)),
                  const SizedBox(width: SandikSpace.sm),
                  // Esnek + sağa yaslı: kabuk 360 pt'de sınırlı (marka
                  // kabuğu, Ar-Ge 5 Kas 22:40 #7); uzun "adet · ort." metni
                  // dar ekranda ya da büyük yazıda satırı taşırmasın, kırılsın.
                  Expanded(
                    child: Text(
                    // Mevduatta pay ve "ort. 1,00 ₺" kullanıcıya bir şey
                    // söylemez; bakiye söyler.
                    _tutarla
                        ? fmtTRY(_bakiye, digits: 2)
                        : '${numFmt.format(asset.quantity)} $_unitLabel · '
                            '${context.l10n.quickAvgShort('${numFmt.format(asset.purchasePrice)} $_currencySymbol')}',
                    textAlign: TextAlign.end,
                    style: context.t.numSmall
                        .copyWith(color: context.c.text90),
                  ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SandikSpace.md),

            // ── İşlem günü ────────────────────────────────────────────
            // Mevduatta yok: birim değer güne göre sözleşmeden işler, geçmiş
            // günün birimi bu diyalogun sorusu değil (tam form sorar).
            if (!_tutarla) ...[
              TarihCipleri(
                secili: _gecmisGun ?? DateTime.now(),
                onSecildi: _gunSec,
                sonIsGunu: false,
              ),
              const SizedBox(height: SandikSpace.md),
            ],

            // ── Adet · Tutar ──────────────────────────────────────────
            if (_tutarKipiVar) ...[
              _miktarKipiSegmenti(context),
              const SizedBox(height: SandikSpace.md),
            ],

            // ── Miktar ────────────────────────────────────────────────
            Text(
                _tutarla
                    ? context.l10n.depositAmountLabel
                    : _tutarKipinde
                        ? context.l10n.tutarAlani
                        : context.l10n.quantity,
                style: context.t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.c.text58)),
            const SizedBox(height: SandikSpace.xs2),
            TextField(
              // Kip değişince denetleyici değişir, alan (ve odak) aynı kalır.
              controller: _tutarKipinde ? _tutarCtrl : _qtyCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              // Sayfanın birincil girdisi: hero tutar ölçeği (`numLarge`,
              // w600 tavanı, tabular). Eskiden ham 18 + w700 idi; Varlık
              // Ekle ile aynı tipografi.
              style: context.t.numLarge.copyWith(color: context.c.text90),
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: context.t.numLarge.copyWith(color: context.c.text36),
                suffixText:
                    _tutarla || _tutarKipinde ? _currencySymbol : _unitLabel,
                suffixStyle:
                    context.t.titleMedium?.copyWith(color: context.c.text58),
                // Dolgu/çerçeve temadan (`inputDecorationTheme` = `inputFill` kuralı).
              ),
            ),
            if (_tutarKipinde) _tutardanAdetSatiri(context),
            // Tümünü satarken alanın altında tek satır nötr ipucu: bu bir
            // "satış" kaydı, silme değil — kullanıcı "sattım = sil" diye
            // düşünmesin. Eskiden amber zemin + çerçeve + ikonlu kutuydu
            // (Ar-Ge 12 Kas #6): amber yalnız birincil eyleme ait (Varlık
            // Ekle 02:03 kararı, boş fiyat kutusu → tek satır ile aynı) ve
            // kutu bilgiyi "bir şey mi yanlış" uyarısı gibi okutuyordu.
            // Yükseklikle açılır (SandikAcilir; hareketi azalt'ta anlık).
            if (!_isAdd)
              SandikAcilir(
                acik: tumunuSatiyor,
                child: Padding(
                  padding: const EdgeInsets.only(top: SandikSpace.xs2),
                  child: Text(
                    context.l10n.sellAllWarning,
                    key: const ValueKey('tumunu_sat_ipucu'),
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58),
                  ),
                ),
              ),
            const SizedBox(height: SandikSpace.sm),
            _quickChips(),

            // ── Fiyat (sadece ekleme için) ────────────────────────────
            if (_isAdd && !_tutarla) ...[
              const SizedBox(height: SandikSpace.md),
              Text(context.l10n.quickUnitPrice,
                  style: context.t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.c.text58)),
              const SizedBox(height: SandikSpace.xs2),
              TextField(
                controller: _priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                style: context.t.numMedium.copyWith(
                    fontWeight: FontWeight.w500, color: context.c.text90),
                onChanged: (_) => setState(() {
                  _error = null;
                  _fiyatElle = true;
                }),
                decoration: InputDecoration(
                  hintText: '0.00',
                  hintStyle:
                      context.t.titleLarge?.copyWith(color: context.c.text36),
                  suffixText: _currencySymbol,
                  suffixStyle:
                      context.t.titleMedium?.copyWith(color: context.c.text58),
                  // Dolgu/çerçeve temadan (`inputDecorationTheme` = `inputFill` kuralı).
                ),
              ),
            ],

            // ── Toplam önizleme ──────────────────────────────────────
            // Mevduatta ve Tutar kipinde toplam yazılan tutarın kendisidir;
            // tekrar etmez.
            if (qty > 0 && !_tutarla && !_tutarKipinde) ...[
              const SizedBox(height: SandikSpace.md2),
              // Düz satır (tasarım turu 2026-11-12): eskiden işlem renginde
              // dolgu + çerçeveli kutuydu. Toplam bir bilgi; renkli kutu onu
              // uyarı gibi okutuyordu ve işlemin rengi kenar vurgusunda ile
              // düğmede zaten var. Etiket esnek: 2× yazıda "Satış değeri"
              // sabit genişlikte satırı taşırıyordu.
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                        _isAdd
                            ? context.l10n.quickTotalCost
                            : context.l10n.saleValue,
                        style: context.t.titleSmall
                            ?.copyWith(color: context.c.text58)),
                  ),
                  const SizedBox(width: SandikSpace.sm),
                  // Esnek + sağa yaslı (2026-11-11): kabuk 360 pt'de
                  // sınırlı; dört haneli tutarda (ya da büyük yazıda) sabit
                  // genişlikli değer satırı taşıyordu, testler bu yüzden
                  // 600 pt yüzey kullanıyordu. Sığmazsa alta kırılır.
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${numFmt.format(total)} $_currencySymbol',
                      textAlign: TextAlign.end,
                      style: context.t.numMedium
                          .copyWith(color: context.c.text90),
                    ),
                  ),
                ],
              ),
            ],

            if (ortalamaOnizleme != null) ...[
              const SizedBox(height: SandikSpace.sm),
              _ortalamaSatiri(context, ortalamaOnizleme),
            ],

            if (hedefKapisi) ...[
              const SizedBox(height: SandikSpace.xs),
              _hedefBolumu(context,
                  hedef: hedef != null && hedef > 0 ? hedef : null,
                  adet: hedefAdet),
            ],

            if (karOnizleme != null) ...[
              const SizedBox(height: SandikSpace.sm),
              _karSatiri(context, karOnizleme),
              // Anaparam çipi seçiliyken (alan çipin sayısını taşıyor) tek
              // satır aritmetik: kâr satırı gerçekleşen kârı zaten söyler,
              // bu satır "eline geçen = maliyetin kadar" der. Renksiz,
              // emir kipi yok (yatırım tavsiyesi gibi okunmasın).
              if (anaparam != null &&
                  !anaparamKilitli &&
                  (qty - anaparam).abs() < 1e-9) ...[
                const SizedBox(height: SandikSpace.xs),
                Text(
                  context.l10n.quickPrincipalNote(
                      _paraMetni(anaparam * (_gecmisFiyat ?? asset.currentPrice))),
                  key: const ValueKey('anaparam_aciklama'),
                  style: context.t.bodySmall?.copyWith(color: context.c.text58),
                ),
              ],
              // Fon satışında kâr brüttür: stopaj fon türüne ve elde tutma
              // süresine göre değişir, oranı yazmak uydurma sayı olurdu
              // (fiyat kaynağı sözleşmesi ruhu). Yalnız uyarı.
              if (asset.type == AssetType.fon) ...[
                const SizedBox(height: SandikSpace.xs),
                Text(
                  context.l10n.quickSaleFundTaxNote,
                  key: const ValueKey('satis_fon_stopaj_notu'),
                  style: context.t.bodySmall?.copyWith(color: context.c.text58),
                ),
              ],
            ],

            if (_error != null) ...[
              const SizedBox(height: SandikSpace.sm2),
              Text(
                _error!,
                style: context.t.titleSmall?.copyWith(color: context.c.loss),
              ),
            ],

            ],
            ),
            ),
           ),

            const SizedBox(height: SandikSpace.lgs),

            // ── Butonlar ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: SandikSpace.md2),
                      backgroundColor: context.c.overlay,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SandikRadius.md)),
                    ),
                    child: Text(context.l10n.cancel,
                        style: context.t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.c.text90)),
                  ),
                ),
                const SizedBox(width: SandikSpace.sm2),
                Expanded(
                  flex: 2,
                  // Gösterge + çift dokunuş kilidi standart bileşende (tek
                  // yükleniyor davranışı, 2026-10-08). `_saving` kalır:
                  // kayıt sürerken İptal pasif.
                  child: SandikAsyncButton.kompakt(
                    onPressed: _submit,
                    mesgul: _saving,
                    basari: _basari,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding:
                          const EdgeInsets.symmetric(vertical: SandikSpace.md2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SandikRadius.md)),
                    ),
                    child: Text(
                        _isAdd
                            ? context.l10n.buyAction
                            : context.l10n.sellAction,
                        style: context.t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.c.text90)),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  /// Son alım çipinin miktarı birimiyle: "12 pay", "5 gr", "$100".
  /// Mevduatta alan TL tutarı olduğundan tutar yazılır ("₺5.000").
  String _sonAlimMetni(double v) => _tutarla
      ? fmtTRY(v)
      : widget.asset.miktarMetni(v, (d, o) => fmtNum(d, digits: o));

  /// Tutar metni: ₺'de `fmtTRY` (küsuratlıysa kuruşla — çip ₺5.000 deyip
  /// alana 4.999,99 yazmasın), dövizli varlıkta kendi sembolüyle.
  String _tutarMetni(double v) {
    final tam = (v - v.roundToDouble()).abs() < 0.005;
    if (_currencySymbol == '₺') return fmtTRY(v, digits: tam ? 0 : 2);
    return '${qtyFormatter(maxDigits: 2).format(v)} $_currencySymbol';
  }

  /// "Adet · Tutar" seçicisi — ortak `SandikSegment` (TASARIM_DILI "mod
  /// değiştiren seçici"). Seçili kip kayan zemin + kalın yazıyla, yalnız
  /// renkle değil. Fiyat yokken Tutar kapalı ve nedeni altında yazılı.
  Widget _miktarKipiSegmenti(BuildContext context) {
    final l = context.l10n;
    final etiketler = [l.miktarModuAdet, l.miktarModuTutar(_currencySymbol)];
    final fiyatVar = _birimFiyat != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SandikSegment(
          key: const ValueKey('hizli_miktar_kipi'),
          adet: 2,
          secili: _tutarModu ? 1 : 0,
          onSec: _miktarKipiniSec,
          etkin: (i) => i == 0 || fiyatVar,
          semantik: (i) => l.miktarModuSemantik(etiketler[i]),
          oge: (context, i, _) => Text(etiketler[i],
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (!fiyatVar && !_tutarModu)
          Padding(
            padding: const EdgeInsets.only(top: SandikSpace.xs),
            child: Text(
              l.quickAmountNeedsPrice,
              key: const ValueKey('hizli_tutar_fiyat_yok'),
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
          ),
      ],
    );
  }

  /// Tutar kipinde hesaplanan adet: "≈ 2.500 pay", "≈ 49,98 pay" (birim ve
  /// ondalık Son alımın çipiyle aynı: `miktarMetni`). Fiyat yoksa adet
  /// yazılmaz, fiyat gerektiği söylenir. Ekran okuyucu "≈" yerine
  /// "Hesaplanan miktar" cümlesini okur (formla aynı anahtar).
  Widget _tutardanAdetSatiri(BuildContext context) {
    final l = context.l10n;
    final tutar = _parse(_tutarCtrl.text);
    final adet = _etkinAdet;
    final String? miktar = adet == null
        ? null
        : widget.asset
            .miktarMetni(adet, (d, o) => fmtNum(d, digits: o));
    if (miktar == null && (tutar == null || tutar <= 0)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.sm),
      child: miktar == null
          ? Text(l.tutardanAdetFiyatYok,
              key: const ValueKey('hizli_tutardan_adet'),
              style: context.t.bodySmall?.copyWith(color: context.c.text58))
          : Semantics(
              label: l.tutardanAdetSatiri(miktar),
              excludeSemantics: true,
              child: Text(
                l.quickAmountQtyApprox(miktar),
                key: const ValueKey('hizli_tutardan_adet'),
                style: context.t.titleSmall?.copyWith(
                    color: context.c.text90, fontWeight: FontWeight.w600),
              ),
            ),
    );
  }

  Widget _quickChips() {
    // Öneriler `hizliMiktarOnerileri`'nden (saf, testli). Alanın metni ve
    // çipin yazısı AYNI Türkçe biçimde (`_fmt`): eski '0.1' ham yazımı
    // ekranda "0.1" görünüyordu.
    // Mevduatta alan tutar olduğu için çipler de bakiyeyle (₺) kurulur.
    final eldeki = _tutarla ? _bakiye : widget.asset.quantity;
    final son = _sonAlim;
    final sonTutar = _sonAlimTutari;
    final anaparam = _anaparamAdedi;
    final anaparamCipi = anaparam != null && _anaparamGorunur;
    final anaparamKilitli = anaparamCipi && _anaparamKilitli;
    // Tutar kipinde adet önerileri (1, 10, 100) tutar olarak anlamsız; yalnız
    // son alımın tutarı önerilir. Son alım yoksa çip satırı boş kalır.
    final chips = _tutarKipinde
        ? <_HizliCip>[
            if (sonTutar != null)
              (
                deger: _fmt(sonTutar),
                etiket: context.l10n.quickLastBuyChip(_tutarMetni(sonTutar)),
                ses: context.l10n
                    .quickLastBuyChipSemantics(_tutarMetni(sonTutar)),
                kilit: false,
              ),
          ]
        : <_HizliCip>[
      // "Son alımın" BAŞTA (Ar-Ge 8 Kas #1); çip sayısı aynı kalır, bir
      // standart öneri düşer (bkz. `hizliMiktarOnerileri`). Rozet yok.
      if (son != null)
        (
          deger: _fmt(son),
          etiket: context.l10n.quickLastBuyChip(_sonAlimMetni(son)),
          // "·" ekran okuyucuda okunmaz ya da "nokta" okunur; virgüllü cümle.
          ses: context.l10n.quickLastBuyChipSemantics(_sonAlimMetni(son)),
          kilit: false,
        ),
      // "Anaparam" (Ar-Ge 2026-11-12 #1, Premium): "Son alımın"dan sonra
      // (satışta o çip yok, bu yüzden başta). Yalnız kârda (adet varken).
      // Kilitliyken sayı yazılmaz: sayının kendisi Premium'un işi; çip adı
      // + kilit ikonu, dokunuş paywall'a.
      if (anaparamCipi)
        anaparamKilitli
            ? (
                deger: '',
                etiket: context.l10n.quickPrincipalChipLocked,
                ses: context.l10n.quickPrincipalChipLockedSemantics,
                kilit: true,
              )
            : (
                deger: _fmt(anaparam),
                etiket: context.l10n.quickPrincipalChip(_sonAlimMetni(anaparam)),
                ses: context.l10n
                    .quickPrincipalChipSemantics(_sonAlimMetni(anaparam)),
                kilit: false,
              ),
      for (final v in hizliMiktarOnerileri(
        tur: widget.asset.type,
        birimTuru: widget.asset.unitType,
        eldeki: eldeki,
        satis: !_isAdd,
        sonAlim: son,
      ))
        (deger: _fmt(v), etiket: _fmt(v), ses: null, kilit: false),
      // Satışta TEK "Hepsi" — eldekinin tamamı (bkz. bulgu #9).
      if (!_isAdd && eldeki > 0)
        (
          deger: _fmt(eldeki),
          etiket: context.l10n.quickAllChip(_fmt(eldeki)),
          ses: null,
          kilit: false,
        ),
    ];

    // Sabit 32pt şerit kalktı (HIG denetimi 2026-10-10): hedef 32pt'de
    // kalıyor, büyük yazıda çip metni kesiliyordu. Tasarım turu (2026-11-12,
    // Ar-Ge #5): Varlık Ekle önayarları ve tarih çipleriyle AYNI bileşen
    // ([SandikFiltreCipi]) — görsel de 44 pt, alandaki değere eşit çip
    // seçili (amber dolgu + onay işareti; yalnız renkle anlam yok). Kilitli
    // Premium çipi baştaki kilit ikonuyla okunur, hiç seçili olmaz.
    final alan = (_tutarKipinde ? _tutarCtrl : _qtyCtrl).text;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in chips)
            Padding(
              padding: const EdgeInsets.only(right: SandikSpace.sm),
              child: SandikFiltreCipi(
                ad: chip.etiket,
                semantik: chip.ses,
                secili: !chip.kilit && alan == chip.deger,
                ikon: chip.kilit ? Icons.lock_outline_rounded : null,
                onTap: chip.kilit
                    ? _anaparamPaywall
                    : () => setState(() {
                          (_tutarKipinde ? _tutarCtrl : _qtyCtrl).text =
                              chip.deger;
                          _error = null;
                        }),
              ),
            ),
        ],
      ),
    );
  }
}

/// Hızlı miktar çipinin verisi. [kilit]: Premium kilidi (dokunuş paywall'a,
/// [deger] kullanılmaz).
typedef _HizliCip = ({String deger, String etiket, String? ses, bool kilit});
