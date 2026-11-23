import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/preferences_provider.dart' show ortakSiniriDoluProvider, paywallVisibleProvider;
import '../screens/paywall_screen.dart';
import '../services/analytics_service.dart';
import '../services/crash_reporter.dart';
import '../services/remote_config_service.dart';
import '../utils/sandik_snack.dart';

/// Ücretsiz sınır dolunca tek uyarı (Premium seti netleştirme, 2026-10-10).
///
/// Neden ortak: takip listesi sınırı iki yerde iki farklı mesajla
/// söyleniyordu — arama ekranı "ücretsiz planda N" + Premium düğmesi,
/// varlık sayfasındaki yıldız düz "birini çıkar". Fiyat alarmında da paywall
/// açıkken bile düz bir uyarı çıkıyordu; kullanıcı sınırın neden var
/// olduğunu ve çıkış yolunu göremiyordu. Tek kural:
///  - Paywall açık (sınır satış kapısı): paywall DOĞRUDAN açılır, deste
///    sınırlar kartında ([kaynak]). 2026-11-12 (yasin: "6. eklenmek
///    istediğinde premiuma yönlendirecek"): önceden küçük bir uyarı +
///    "Premium" düğmesi çıkıyordu; uyarı birkaç saniyede kayboluyor, düğme
///    gözden kaçıyordu. Varlık sınırı (`asset_limit_*`) zaten paywall'u
///    doğrudan açıyordu; takip ve alarm ona hizalandı. Paywall kapatılırsa
///    [ucretsizMetin] uyarısı kalır ki kullanıcı neden eklenmediğini bilsin.
///  - Paywall kapalı (sınır ürün sınırı, ör. takipte 7): çıkış yolu
///    "birini çıkar / kapat"; satın alınamayan şey önerilmez.
///
/// Dönen değer: kullanıcı paywall'da Premium aldı mı. Çağıran, durdurduğu işi
/// `true` ise sürdürür (varlık akışındaki `yenidenDene` deseni, 2026-11-21:
/// ödeyen kullanıcı geri dönünce "bir şey olmadı" görüyordu). Paywall
/// kapatıldıysa ya da kapalıysa `false`; iş durur. Paywall ekranı bu
/// future tamamlanmadan kapanır, sonraki sayfa iç içe açılmaz.
Future<bool> sinirUyarisi(
  BuildContext context,
  WidgetRef ref, {
  required String ucretsizMetin,
  required String urunMetni,
  required String kaynak,
}) async {
  if (!ref.read(paywallVisibleProvider)) {
    sandikSnack(context, urunMetni, kind: SandikSnackKind.warning);
    return false;
  }
  final aldi = await PaywallScreen.show(context, source: kaynak);
  if (aldi == true) return true;
  if (context.mounted) {
    sandikSnack(context, ucretsizMetin, kind: SandikSnackKind.warning);
  }
  return false;
}

/// Sonucu beklemeyen çağıranlar (catch blokları, dokunma geri çağrıları).
void _arkaPlan(Future<bool> f, String neden) =>
    CrashReporter.arkaPlan(f, reason: neden);

/// Takip listesi sınırı (`WatchlistLimitException`).
Future<bool> takipSiniriBekle(
        BuildContext context, WidgetRef ref, int limit) =>
    sinirUyarisi(
      context,
      ref,
      ucretsizMetin: context.l10n.watchlistLimitFree(limit),
      urunMetni: context.l10n.watchlistLimitReached(limit),
      kaynak: 'watchlist_limit',
    );

/// Aktif fiyat alarmı sınırı (`priceAlertLimitProvider`). Paywall kapalıyken
/// sınır zaten yok; metin yalnız tutarlılık için.
Future<bool> alarmSiniriBekle(
        BuildContext context, WidgetRef ref, int limit) =>
    sinirUyarisi(
      context,
      ref,
      ucretsizMetin: context.l10n.alarmLimitFree(limit),
      urunMetni: context.l10n.alarmLimitReached(limit),
      kaynak: 'alarm_limit',
    );

/// Ortak sayısı sınırı (`ortakSiniriDoluProvider`). Paywall kapalıyken sınır
/// zaten yok; metin yalnız tutarlılık için.
Future<bool> ortakSiniriBekle(BuildContext context, WidgetRef ref, int limit) =>
    sinirUyarisi(
      context,
      ref,
      ucretsizMetin: context.l10n.partnerLimitFree(limit),
      urunMetni: context.l10n.partnerLimitFree(limit),
      kaynak: 'partner_limit',
    );

/// Ateşle-unut kısayolları. Takip listesinin ateşle-unut kısayolu
/// (`takipSiniriUyarisi`) son çağıranı da `takipSiniriBekle`'ye geçince
/// kalktı (Ar-Ge 23 Kas 22:03 #4): satın alınca dokunuşun işi sürmeli.
void alarmSiniriUyarisi(BuildContext context, WidgetRef ref, int limit) =>
    _arkaPlan(alarmSiniriBekle(context, ref, limit), 'sinirUyarisi.alarm');

/// Yeni ortak eklemeden önce: ücretsiz sınır doluysa paywall açılır; true =
/// işe DEVAM (sınır yok ya da Premium alındı), false = durdu. Üç giriş (kod
/// üret, kod gir, daveti kabul) aynı kararı buradan alır.
Future<bool> ortakEklenebilirMi(BuildContext context, WidgetRef ref) async {
  if (!ref.read(ortakSiniriDoluProvider)) return true;
  unawaited(
      AnalyticsService.instance.logPremiumGateShown(feature: 'partner_limit'));
  final limit = RemoteConfigService.instance.freePartnerLimit;
  return ortakSiniriBekle(context, ref, limit);
}
