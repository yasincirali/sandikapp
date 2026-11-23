import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../screens/paywall_screen.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart' show AuthException;
import '../services/crash_reporter.dart';
import '../services/disa_aktarim/disa_aktarim_service.dart';
import '../services/disa_aktarim/rapor_belgeleri.dart';
import '../services/share_card_service.dart';
import '../utils/friendly_error.dart';
import 'disa_aktarim_bicim_sayfasi.dart';

/// Portföy dökümü (Premium): biçim sorulur, belge kurulur, paylaşılır.
///
/// 2026-10-31 (müşteri raporu 31 Eki #3, yasin "yap"): Ayarlar › Veri'den
/// Raporlar kapısına taşındı. Ayarlar'da KVKK "Verilerimi indir" (JSON,
/// herkese açık yasal hak) ile bu Premium belge alt alta duruyordu; iki
/// "indir" satırı karışıyordu. Artık Ayarlar = ham veri, Raporlar = belge.
/// Görünürlük koşulu iki yerde aynıydı (`premiumOzellikleriGorunur`), kimse
/// erişim kaybetmez.
///
/// Riverpod'a [context]'in kapsayıcısından okunur (`ProviderScope`): kapının
/// alt sayfası kapandıktan SONRA çalışır, sayfanın `ref`'i o an ölüdür.
Future<void> portfoyDokumunuPaylas(BuildContext context, {Rect? kaynak}) async {
  final kap = ProviderScope.containerOf(context, listen: false);
  if (kap.read(premiumKilitliProvider)) {
    unawaited(AnalyticsService.instance
        .logPremiumGateShown(feature: 'portfoy_disa_aktar'));
    // Satın alma sonrası aynı akışa düşülür (UI/UX turu 15, 2026-11-23 #1):
    // eskiden burada `return` vardı; Raporlar sayfası çoktan kapandığı için
    // Premium'u alan kullanıcı Raporlar'ı yeniden açıp satıra yeniden
    // dokunmak zorundaydı. Ana sinyal `true` (Varlık Ekle tekli kaydıyla
    // aynı, `kayit.dart` `yenidenDene`); vazgeçen ya da kapatan döner.
    final aldi = await PaywallScreen.show(context, source: 'portfoy_disa_aktar');
    if (aldi != true || !context.mounted) return;
  }
  // Raporlar sayfasının satırı kapandı; popover'ın bakacağı yer çağıranın
  // (Raporlar düğmesi) kendisi. Yoksa servis ekran ortasına düşer.
  kaynak ??= ShareCardService.originOf(context);
  final bicim = await disaAktarimBicimiSor(context);
  if (bicim == null || !context.mounted) return;
  // Sessiz dönüş yok (UI/UX turu 15 #7): eskiden `valueOrNull` okunuyordu;
  // portföy henüz yükleniyorsa ya da oturum yoksa kullanıcı biçimi seçip
  // hiçbir şey görmüyordu. Portföy yükleniyorsa beklenir; yüklenemezse ya
  // da oturum yoksa hata gösterilir.
  final PortfolioState durum;
  try {
    durum = await kap.read(portfolioProvider.future);
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'portfoyDokumunuPaylas.portfoy');
    if (context.mounted) showAppError(context, e);
    return;
  }
  if (!context.mounted) return;
  final kullanici = kap.read(authProvider).valueOrNull;
  if (kullanici == null) {
    showAppError(context, AuthException(context.l10n.hataOturumDoldu));
    return;
  }
  final belge = portfoyBelgesi(
    lotlar: [
      for (final a in durum.assets)
        if (a.userId == kullanici.id) a
    ],
    tlYap: durum.toTRY,
    kim: kullanici.username ?? kullanici.email,
    olusturma: DateTime.now(),
  );
  try {
    await DisaAktarimService.instance
        .paylas(belge, bicim: bicim, tur: 'portfoy', kaynak: kaynak);
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'portfoyDokumunuPaylas');
    if (context.mounted) showAppError(context, e);
  }
}
