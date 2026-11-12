import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/preferences_provider.dart' show paywallVisibleProvider;
import '../screens/paywall_screen.dart';
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
/// Ateşle-unut: çağıranlar (catch blokları, dokunma geri çağrıları) paywall
/// kapanmasını beklemez.
void sinirUyarisi(
  BuildContext context,
  WidgetRef ref, {
  required String ucretsizMetin,
  required String urunMetni,
  required String kaynak,
}) {
  if (!ref.read(paywallVisibleProvider)) {
    sandikSnack(context, urunMetni, kind: SandikSnackKind.warning);
    return;
  }
  unawaited(_paywallAc(context, ucretsizMetin, kaynak));
}

Future<void> _paywallAc(
    BuildContext context, String ucretsizMetin, String kaynak) async {
  final aldi = await PaywallScreen.show(context, source: kaynak);
  if (aldi == true || !context.mounted) return;
  sandikSnack(context, ucretsizMetin, kind: SandikSnackKind.warning);
}

/// Takip listesi sınırı (`WatchlistLimitException`).
void takipSiniriUyarisi(BuildContext context, WidgetRef ref, int limit) =>
    sinirUyarisi(
      context,
      ref,
      ucretsizMetin: context.l10n.watchlistLimitFree(limit),
      urunMetni: context.l10n.watchlistLimitReached(limit),
      kaynak: 'watchlist_limit',
    );

/// Aktif fiyat alarmı sınırı (`priceAlertLimitProvider`). Paywall kapalıyken
/// sınır zaten yok; metin yalnız tutarlılık için.
void alarmSiniriUyarisi(BuildContext context, WidgetRef ref, int limit) =>
    sinirUyarisi(
      context,
      ref,
      ucretsizMetin: context.l10n.alarmLimitFree(limit),
      urunMetni: context.l10n.alarmLimitReached(limit),
      kaynak: 'alarm_limit',
    );
