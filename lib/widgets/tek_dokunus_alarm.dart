import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/yuzde_alarmi.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart' show priceAlertLimitProvider;
import '../providers/yuzde_alarmi_provider.dart';
import '../services/alarm_siniri.dart';
import '../services/bildirim_izni.dart';
import '../services/fiyat_kaynagi.dart';
import '../services/ozellik_olcumu.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import 'alarm_kur_sheet.dart'
    show
        AlarmAdayi,
        alarmKurAkisi,
        alarmSiniriDoluMu,
        alarmYazimiTavanli,
        yuzdeAlarmEtiketi;
import 'sinir_uyarisi.dart' show alarmSiniriUyarisi;

/// Kayıt anında tek dokunuşla günlük yüzde alarmı (Ar-Ge 29 Eki 12:45 #1).
///
/// Altın ya da dolar ekleyen kişinin aklında çoğu zaman bir hedef fiyat
/// yok; sorusu "sert oynarsa haberim olsun". Eskiden "Alarm kur" snack'i
/// sayfayı Fiyat kipinde açıp hedef yazdırıyordu; yüzde alarmı ikinci
/// sekmedeydi ve yeni kullanıcı onu bulmuyordu. Kapsamdaki varlıkta snack
/// artık soruyu kendisi sorar, "Kur" ±%2 alarmı sayfa açmadan kurar.
const double tekDokunusEsik = 2;

/// Kayıt sonrası snack yüzde alarmı mı önersin: varlık kapsamda
/// (`FiyatKaynagi.yuzdeAlarmiKapsamindaMi`: altın, TL döviz, kripto) ve
/// o sembolde henüz yüzde alarmı yok (ikinci bir aynı alarm önerilmez;
/// o zaman eski "Alarm kur" önerisi kalır).
bool yuzdeAlarmiOnerilsinMi(AlarmAdayi aday, List<YuzdeAlarmi> mevcut) =>
    FiyatKaynagi.yuzdeAlarmiKapsamindaMi(aday.sembol) &&
    !mevcut.any((a) => a.symbol == aday.sembol);

/// "Kur" dokunuşu. Tavan doluysa ya da bildirim izni reddedilmişse sessizce
/// kurmaz: bugünkü alarm sayfası açılır, oradaki uyarılar ne olduğunu
/// söyler (çalmayacak bir alarmı "kuruldu" diye onaylamak yanıltırdı).
Future<void> tekDokunusYuzdeAlarmiKur(
    BuildContext context, WidgetRef ref, AlarmAdayi aday) async {
  if (DemoModu.yazmaKapisi('alarm')) return;
  // Sayım listeleri BEKLER (2026-11-12): kayıt anında yüzde alarm listesi
  // çoğu zaman henüz yüklenmemiştir; eskiden 0 sayılıp tavan atlanıyordu.
  final tavanDolu = await alarmSiniriDoluMu(ref);
  if (tavanDolu || await BildirimIzni.reddedildi()) {
    if (!context.mounted) return;
    await alarmKurAkisi(context, ref, sabit: aday);
    return;
  }
  final me = ref.read(authProvider).valueOrNull;
  if (me == null) return;
  try {
    await alarmYazimiTavanli(
        ref,
        () => ref.read(yuzdeAlarmlariProvider.notifier).create(YuzdeAlarmi(
              id: '',
              userId: me.id,
              symbol: aday.sembol,
              label: aday.ad,
              esikPct: tekDokunusEsik,
              yon: YuzdeYon.ikisi,
              createdAt: DateTime.now(),
            )));
  } catch (e) {
    if (!context.mounted) return;
    if (alarmSiniriHatasiMi(e)) {
      alarmSiniriUyarisi(context, ref, ref.read(priceAlertLimitProvider));
    } else {
      showAppError(context, e);
    }
    return;
  }
  OzellikOlcumu.say(Ozellik.yuzdeAlarm);
  SandikHaptic.medium.perform();
  if (!context.mounted) return;
  // Onay metinle de söylenir, yalnız titreşimle değil (HIG).
  sandikSnack(
    context,
    context.l10n.tekDokunusYuzdeKuruldu(aday.ad,
        yuzdeAlarmEtiketi(context.l10n, tekDokunusEsik, YuzdeYon.ikisi)),
    kind: SandikSnackKind.success,
  );
}
