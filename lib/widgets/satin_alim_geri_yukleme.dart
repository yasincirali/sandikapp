import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/premium_provider.dart';
import '../utils/sandik_snack.dart';

/// "Satın alımları geri yükle"nin tek akışı (Ar-Ge 12 Kas #1).
///
/// Önce paywall'da doğru, Profil › Premium sayfasında yanlış çalışıyordu:
/// oradaki düğme yalnız `premiumHaklariProvider`'ı tazeliyor, mağazaya
/// (`restorePurchases`) hiç sormuyor ve hiçbir şey söylemiyordu; ödeyen
/// kullanıcı "bastım, bir şey olmadı" diyordu. Artık iki yer de bunu çağırır:
/// mağazaya sorar, sonucu üç cümleden biriyle söyler ("geri yüklendi /
/// bulunamadı / yapılamadı"), ardından sunucu haklarını tazeler (başka
/// cihazda alınmış ve webhook'la yazılmış abonelik de böylece görünür).
///
/// Snack nötr: sonuç ekranda başka yerde yazmaz (snack_basari_kurali).
/// Mağaza yapılandırılmamışsa (bayrak kapalı / anahtar yok) mağazaya
/// gidilmez, "kullanılamıyor" denir; sunucu hakları yine tazelenir (eski
/// Profil davranışı kaybolmasın). Dönüş: true = hak bulundu, false = yok,
/// null = soru sorulamadı/hata. Sayfayı kapatma kararı çağıranda.
Future<bool?> satinAlimlariGeriYukle(BuildContext context, WidgetRef ref) async {
  final servis = ref.read(satinAlmaServisiProvider);
  final l = context.l10n;
  if (!servis.yapilandirildi) {
    sandikSnack(context, l.pwKullanilamaz);
    ref.invalidate(premiumHaklariProvider);
    return null;
  }
  final bulundu = await servis.geriYukle();
  if (!context.mounted) return bulundu;
  sandikSnack(
    context,
    switch (bulundu) {
      true => l.pwGeriYuklendi,
      false => l.pwGeriYukBulunamadi,
      null => l.pwGeriYukHata,
    },
  );
  ref.invalidate(premiumHaklariProvider);
  return bulundu;
}
