import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'crash_reporter.dart';
import 'remote_config_service.dart';

/// Mağaza aboneliği (RevenueCat, 2026-10-08).
///
/// ## Neden RevenueCat
/// Sunucu tarafı (0116 `premium_haklari` + `revenuecat-webhook`) RevenueCat
/// üzerine kuruldu: webhook olayı geldiğinde RevenueCat API'sinden kullanıcının
/// güncel hakkı okunup tabloya yazılır. İstemci yalnız satın alma akışını
/// yürütür; "Premium mu" kararının kalıcı kaynağı sunucudur. Satın alma anında
/// webhook henüz gelmemiş olabileceği için SDK'nın `CustomerInfo`'su
/// [aktifMi] ile ANLIK köprü olarak kullanılır (bkz. `magazaPremiumProvider`).
///
/// ## Canlıdaki kullanıcı etkilenmez
/// SDK yalnız `paywall_enabled` açıkken ve anahtar build'e girmişken
/// yapılandırılır. Bayrak kapalıyken hiçbir yöntem mağazaya dokunmaz,
/// [yapilandirildi] false kalır; eski davranış (Premium sistemi yok)
/// birebir sürer.
///
/// ## Anahtarlar
/// Public SDK anahtarları dart-define ile gelir (`REVENUECAT_IOS_KEY`,
/// `REVENUECAT_ANDROID_KEY`; GitHub secret). Boşsa satın alma "şu an
/// kullanılamıyor" der; uydurma bir başarı DÖNMEZ (eskiden düğme 600 ms
/// bekleyip yerel anahtarı açıyordu: parası alınmadan Premium).
class SatinAlmaService {
  SatinAlmaService._();
  static final instance = SatinAlmaService._();

  static const _iosAnahtari = String.fromEnvironment('REVENUECAT_IOS_KEY');
  static const _androidAnahtari =
      String.fromEnvironment('REVENUECAT_ANDROID_KEY');

  /// RevenueCat panelindeki tek hak kimliği; sunucu (`_shared/premium.ts`
  /// `PREMIUM_HAK`) ile aynı olmalı.
  static const premiumHak = 'premium';

  bool _yapilandirildi = false;
  String? _bagliKullanici;
  Future<void>? _kurulum;

  /// Oturumdaki kullanıcı — bağlanmamış olsa da. `paywall_enabled` oturum
  /// ORTASINDA açılırsa (Remote Config sonradan etkinleşir, #141) girişte
  /// no-op olan bağlama burada yeniden denenir; yoksa satın alma düğmesi
  /// uygulama yeniden açılana kadar "kullanılamıyor" kalıyordu.
  String? _istenenKullanici;
  bool _rcDinleniyor = false;

  /// Hak değişince çağrılır (satın alma, iade, başka cihazdan geri yükleme).
  /// `main.dart` bağlar: istemci durumu + sunucu haklarını tazeler.
  void Function(bool aktif)? hakDegisti;

  bool get yapilandirildi => _yapilandirildi;

  /// Bu platformun anahtarı; web/masaüstü ya da build'e girmemişse null.
  static String? get _anahtar {
    if (kIsWeb) return null;
    final a = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => _iosAnahtari,
      TargetPlatform.android => _androidAnahtari,
      _ => '',
    };
    return a.isEmpty ? null : a;
  }

  /// Satın alma bu build'de mümkün mü (bayrak + anahtar). Paywall düğmesi
  /// buna göre "kullanılamıyor" der.
  bool get kullanilabilir =>
      RemoteConfigService.instance.paywallEnabled && _anahtar != null;

  /// Oturumdaki kullanıcıyı RevenueCat'e bağlar. Kimlik Supabase `auth.uid()`:
  /// webhook UUID olmayan kimliği yazmaz (bkz. `etkilenenKullanicilar`).
  /// Bayrak kapalıysa ya da anahtar yoksa hiçbir şey yapmaz.
  Future<void> kullaniciyiBagla(String uid) async {
    _istenenKullanici = uid;
    _rcDinle();
    if (!kullanilabilir) return;
    try {
      if (!_yapilandirildi) {
        _kurulum ??= _yapilandir(uid);
        await _kurulum;
        return;
      }
      if (_bagliKullanici == uid) return;
      final sonuc = await Purchases.logIn(uid);
      _bagliKullanici = uid;
      _bildir(sonuc.customerInfo);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SatinAlmaService.kullaniciyiBagla');
    }
  }

  void _rcDinle() {
    if (_rcDinleniyor) return;
    _rcDinleniyor = true;
    RemoteConfigService.instance.etkinlesmeSayaci.addListener(() {
      final uid = _istenenKullanici;
      if (uid == null || _bagliKullanici == uid || !kullanilabilir) return;
      CrashReporter.arkaPlan(kullaniciyiBagla(uid),
          reason: 'SatinAlmaService.kullaniciyiBagla(rc)');
    });
  }

  Future<void> _yapilandir(String uid) async {
    final cfg = PurchasesConfiguration(_anahtar!)..appUserID = uid;
    await Purchases.configure(cfg);
    _yapilandirildi = true;
    _bagliKullanici = uid;
    Purchases.addCustomerInfoUpdateListener(_bildir);
  }

  /// Çıkışta anonim kullanıcıya düş: sonraki hesap öncekinin aboneliğini
  /// görmesin. Yapılandırılmamışsa no-op.
  Future<void> cikis() async {
    _istenenKullanici = null;
    if (!_yapilandirildi || _bagliKullanici == null) return;
    try {
      await Purchases.logOut();
    } catch (e, st) {
      // Zaten anonimse `logOut` hata verir; önemsiz ama ölçülsün.
      CrashReporter.report(e, st, reason: 'SatinAlmaService.cikis');
    }
    _bagliKullanici = null;
    hakDegisti?.call(false);
  }

  void _bildir(CustomerInfo info) => hakDegisti?.call(aktifMi(info));

  /// Saf: `premium` hakkı etkin mi.
  static bool aktifMi(CustomerInfo info) =>
      info.entitlements.active.containsKey(premiumHak);

  /// Geçerli teklif (aylık + yıllık paket). Yapılandırılmamışsa ya da
  /// mağaza yanıt vermezse null: paywall Remote Config fiyatına düşer ve
  /// satın alma düğmesi kapalı kalır.
  Future<MagazaTeklifi?> teklif() async {
    if (!_yapilandirildi) return null;
    try {
      final o = (await Purchases.getOfferings()).current;
      if (o == null) return null;
      final aylik = o.monthly;
      final yillik = o.annual;
      if (aylik == null && yillik == null) return null;
      return MagazaTeklifi(aylik: aylik, yillik: yillik);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SatinAlmaService.teklif');
      return null;
    }
  }

  /// Satın al. Kullanıcı vazgeçerse [SatinAlmaSonucu.vazgecti]; hata
  /// sessiz değil, Crashlytics'e gider.
  Future<SatinAlmaSonucu> satinAl(Package paket) async {
    if (!_yapilandirildi) return SatinAlmaSonucu.kullanilamaz;
    try {
      final r = await Purchases.purchase(PurchaseParams.package(paket));
      final aktif = aktifMi(r.customerInfo);
      _bildir(r.customerInfo);
      return aktif ? SatinAlmaSonucu.basarili : SatinAlmaSonucu.beklemede;
    } on PlatformException catch (e, st) {
      final kod = PurchasesErrorHelper.getErrorCode(e);
      if (kod == PurchasesErrorCode.purchaseCancelledError) {
        return SatinAlmaSonucu.vazgecti;
      }
      if (kod == PurchasesErrorCode.paymentPendingError) {
        return SatinAlmaSonucu.beklemede;
      }
      CrashReporter.report(e, st, reason: 'SatinAlmaService.satinAl');
      return SatinAlmaSonucu.hata;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SatinAlmaService.satinAl');
      return SatinAlmaSonucu.hata;
    }
  }

  /// Geri yükle (cihaz değişikliği, yeniden kurulum). true = hak bulundu.
  Future<bool?> geriYukle() async {
    if (!_yapilandirildi) return null;
    try {
      final info = await Purchases.restorePurchases();
      _bildir(info);
      return aktifMi(info);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SatinAlmaService.geriYukle');
      return null;
    }
  }
}

enum SatinAlmaSonucu { basarili, vazgecti, beklemede, hata, kullanilamaz }

/// Paywall'a gereken iki paket.
class MagazaTeklifi {
  const MagazaTeklifi({this.aylik, this.yillik});
  final Package? aylik;
  final Package? yillik;
}

/// Saf: ürünün ücretsiz deneme süresi (gün). Yoksa null.
///
/// iOS'ta deneme "introductory price = 0", Android'de varsayılan teklifin
/// ücretsiz fazıdır. Mağazada tanımlanmamış bir deneme ekranda VAAT
/// EDİLMEZ: eskiden "7 gün ücretsiz dene" sabit metindi.
int? denemeGunu(StoreProduct urun) {
  final intro = urun.introductoryPrice;
  if (intro != null && intro.price == 0) {
    return _gun(intro.periodUnit, intro.periodNumberOfUnits * intro.cycles);
  }
  final serbest = urun.defaultOption?.freePhase?.billingPeriod;
  if (serbest != null) return _gun(serbest.unit, serbest.value);
  return null;
}

int? _gun(PeriodUnit birim, int adet) => switch (birim) {
      PeriodUnit.day => adet,
      PeriodUnit.week => adet * 7,
      PeriodUnit.month => adet * 30,
      PeriodUnit.year => adet * 365,
      PeriodUnit.unknown => null,
    };
