import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/position.dart' show aktifLotlar;
import '../models/price_alert.dart';
import '../providers/portfolio_provider.dart';
import '../providers/price_alert_provider.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../l10n/l10n.dart';
import 'alarm_kur_sheet.dart' show alarmSembolu;

/// "Varlığı sil" onayı + silme — tek yerde.
///
/// Aynı diyalog `portfolio_screen` ve `asset_detail_screen`'de ayrı ayrı
/// yazılmıştı (metin, uyarı kutusu, buton renkleri dahil). Bir tanesinde
/// yapılan düzeltme ötekine taşınmıyordu. Şimdi her iki ekran da bunu
/// çağırır; `true` dönerse silme başarıyla yapılmıştır (çağıran isterse
/// ekranı kapatır).
///
/// [lots] içinde deleteLog izleri OLMAMALI — çağıran
/// `position.lots.where((l) => !l.isDeleteLog)` ile süzer.
///
/// ## Alarmlar (kullanıcı bildirimi, 2026-09-16)
///
/// **Ölçülen arıza:** varlığa alarm kurulup varlık silindiğinde alarm
/// sunucuda kalıyordu. Aynı sembol yeniden eklenince eski alarm zil
/// rozetinde görünüyor ve kullanıcı hiç kurmadığı bir alarmı görüyordu.
///
/// Sebep: alarm varlığa DEĞİL sembole bağlı (`price_alerts` tablosunda
/// `asset_id` kolonu yok, yalnızca `symbol`). Bu kasıtlı bir tasarım —
/// "gram altın 5.400 olunca haber ver" portföyde altın olmasa da anlamlı.
/// Ama silme akışı alarmlara hiç dokunmuyordu, yani kullanıcının
/// haberi olmadan arkada duruyorlardı.
///
/// Çözüm: sessizce silmek yerine SOR. Alarm bağımsız bir kayıt olduğu için
/// kullanıcı "portföyden çıktım ama fiyatı izlemeye devam edeyim" diyebilir;
/// karar onun. Alarmı olmayan varlıkta ek soru çıkmaz, akış değişmez.
Future<bool> confirmAndDeletePosition(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  required List<Asset> lots,
}) async {
  final multi = lots.length > 1;
  final ok = await showSandikConfirm(
    context: context,
    title: context.l10n.deleteAssetTitle,
    message: multi
        ? context.l10n.deleteAssetMulti(name, lots.length)
        : context.l10n.deleteAssetSingle(name),
    confirmLabel: context.l10n.deleteAnyway,
    cancelLabel: 'İptal',
    destructive: true,
    detail: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.c.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.danger.withValues(alpha: 0.25)),
      ),
      child: Text(
        context.l10n.deleteAssetWarning,
        style: context.t.bodySmall?.copyWith(
          height: 1.4,
          color: context.c.text90,
        ),
      ),
    ),
  );
  if (!ok || !context.mounted) return false;
  try {
    final notifier = ref.read(portfolioProvider.notifier);
    // ## Neden "Geri al" toast'ı YOK (kullanıcı kararı, 2026-09-16)
    //
    // Önceden silme sonrası "Varlık silindi" + "Geri al" toast'ı çıkıyordu.
    // Kullanıcı bunu gereksiz buldu: silme ZATEN onay diyaloğunun arkasında
    // (yukarıdaki `showSandikConfirm`, yıkıcı buton + uyarı kutusu), yani
    // kazara silme yolu kapalı. HIG'in geri alma beklentisi onaysız yıkıcı
    // eylem içindir; burada onay o işlevi görüyor.
    //
    // `deletePositionLots` makbuzu döndürmeye DEVAM ediyor ve
    // `restorePositionLots` provider'da duruyor — sunucu tarafı geri alma
    // yeteneği korunuyor (silme yumuşak, `deleted_at`). Yalnızca UI girişi
    // kaldırıldı; geri alma tekrar istendiğinde sıfırdan yazılmaz.
    await notifier.deletePositionLots(lots);
    if (context.mounted) await _alarmlariSor(context, ref, lots, name);
    return true;
  } catch (e) {
    if (context.mounted) sandikSnackError(context, e, prefix: 'Silinemedi');
    return false;
  }
}

/// Silinen varlığın alarmları varsa kullanıcıya sorar, onaylarsa siler.
///
/// SİLMEDEN SONRA sorulur: alarm sorusu yüzünden varlık silinmemesi
/// olmaz. Silme başarılıysa asıl iş bitmiştir; bu bir temizlik adımı.
///
/// Alarm silme başarısız olursa sessiz kalınmaz ama silme de geri
/// alınmaz — varlık gitti, alarm kaldı; kullanıcı Alarmlar ekranından
/// silebilir ve mesaj onu oraya yönlendirir.
Future<void> _alarmlariSor(
  BuildContext context,
  WidgetRef ref,
  List<Asset> lots,
  String name,
) async {
  final alarmlar = _ilgiliAlarmlar(ref, lots);
  if (alarmlar.isEmpty) return;

  final n = alarmlar.length;
  final l10n = context.l10n;
  final ok = await showSandikConfirm(
    context: context,
    title: l10n.alarmAlsoDeleteTitle(n),
    message: l10n.alarmAlsoDeleteBody(n, name),
    confirmLabel: l10n.alarmAlsoDeleteConfirm(n),
    // "Vazgeç" YANLIŞ olurdu: silme zaten bitti, vazgeçilecek bir şey yok.
    cancelLabel: l10n.alarmKeep,
    destructive: true,
  );
  if (!ok) return;

  try {
    final notifier = ref.read(priceAlertsProvider.notifier);
    for (final a in alarmlar) {
      await notifier.delete(a.id);
    }
  } catch (e) {
    if (context.mounted) {
      sandikSnackError(context, e, prefix: l10n.alarmDeleteFailed);
    }
  }
}

/// Silinen lot'ların sembolüne ait alarmlar.
///
/// Sembol `alarmSembolu` ile türetilir — alarm kurulurken kullanılan AYNI
/// fonksiyon. Kendi eşlemesini yazmak altın alt kategorilerinde (ALTIN_GRAM
/// vs ticker) sessizce ıskalardı.
///
/// ## Hâlâ sahip olunan semboller ELENİR
///
/// Kullanıcı aynı sembolden iki ayrı pozisyon tutuyor olabilir (farklı
/// ortak, ayrı alım grubu). Birini silip ötekini tutuyorsa alarm HÂLÂ
/// geçerlidir — "THYAO 300 olunca haber ver" isteği sürüyor. Bu kontrol
/// olmadan kullanıcıya gereksiz bir soru sorulur ve "evet" derse hâlâ
/// sahip olduğu varlığın alarmını kaybeder.
List<PriceAlert> _ilgiliAlarmlar(WidgetRef ref, List<Asset> lots) =>
    oksuzKalanAlarmlar(
      silinen: lots,
      // `deletePositionLots` sonrası okunuyor, yani silinenler state'ten
      // çoktan düşmüş.
      kalanVarliklar: ref.read(portfolioProvider).valueOrNull?.assets ?? const [],
      alarmlar: ref.read(priceAlertsProvider).valueOrNull ?? const [],
    );

/// Silmeden sonra sahibi kalmayan alarmlar — SAF karar.
///
/// Widget'tan ayrı tutuldu: asıl incelik sembol eşlemesi ve "hâlâ sahibim"
/// elemesi, ikisi de Supabase olmadan doğrulanabilmeli
/// (`alarm_silme_test.dart`).
@visibleForTesting
List<PriceAlert> oksuzKalanAlarmlar({
  required List<Asset> silinen,
  required List<Asset> kalanVarliklar,
  required List<PriceAlert> alarmlar,
}) {
  final semboller = <String>{};
  for (final l in silinen) {
    final s = alarmSembolu(l.ticker, l.subCategory);
    if (s != null) semboller.add(s);
  }
  if (semboller.isEmpty) return const [];

  for (final l in aktifLotlar(kalanVarliklar)) {
    semboller.remove(alarmSembolu(l.ticker, l.subCategory));
  }
  if (semboller.isEmpty) return const [];

  return [
    for (final a in alarmlar)
      if (semboller.contains(a.symbol)) a,
  ];
}
