import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../screens/paywall_screen.dart';
import '../services/analytics_service.dart';
import '../services/crash_reporter.dart';
import '../services/disa_aktarim/disa_aktarim_service.dart';
import '../services/disa_aktarim/rapor_belgeleri.dart';
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
    await PaywallScreen.show(context, source: 'portfoy_disa_aktar');
    return;
  }
  final bicim = await disaAktarimBicimiSor(context);
  if (bicim == null || !context.mounted) return;
  final durum = kap.read(portfolioProvider).valueOrNull;
  final kullanici = kap.read(authProvider).valueOrNull;
  if (durum == null || kullanici == null) return;
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
