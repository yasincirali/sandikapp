import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/price_alert.dart';
import '../models/yuzde_alarmi.dart';
import '../providers/price_alert_provider.dart';
import '../providers/sembol_alarmlari_provider.dart';
import '../providers/yuzde_alarmi_provider.dart';
import '../screens/price_alerts_screen.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/tr_format.dart';
import 'alarm_kur_sheet.dart';
import '../l10n/l10n.dart';
import 'sandik_skeleton.dart';

/// Varlık ekranındaki alarm şeridi — bu sembolün KURULU alarmları.
///
/// Alarm varlığa aittir; kullanıcı "THY 320'yi geçince" derken varlığın
/// ekranındadır, Ayarlar'da değil. Sembolü olmayan (manuel fiyatlı) varlıkta
/// hiç çizilmez: sunucu onun fiyatını izleyemez.
///
/// ## Boşken çizilmez (2026-09-18)
/// Eskiden şerit boşken de tek bir "Alarm kur" çipi gösteriyordu — "özellik
/// keşfedilebilir olsun" diye. O karar app bar'a zil eklenmeden (2026-09-14)
/// önce verilmişti; zil geldikten sonra aynı eylem ekranda İKİ kez duruyordu
/// (sağ üstte ikon, sinyal kartının altında yalnız bir sarı buton) ve
/// kullanıcı bunu "estetikten uzak" diye bildirdi. Giriş noktası artık tek:
/// app bar'daki zil. Şerit yalnızca kurulu alarm varken görünür; sonuna
/// küçük bir "+" çipi eklenir ki ikinci alarm mevcut olanların yanından
/// kurulabilsin.
///
/// ## Gösterge ve çizgi alarmları (uçtan uca test, 2026-10-29)
/// Şerit yalnız fiyat alarmlarını sayıyordu: EMA50 ve trend çizgisi alarmı
/// olan THYAO'da "2 aktif fiyat alarmı" yazıyordu. Bu iki tür artık sayıya
/// girer ("4 aktif alarm") ve tek bir özet çipiyle görünür; çipe dokunmak
/// Alarmlarım'ı bu sembole süzülmüş açar. Tek tek çip yok: gösterge/çizgi
/// alarmı şeritte silinip yeniden kurulacak bir eşik değil, kurulduğu yer
/// (gösterge sayfası, yatay grafik) başka.
class AlarmSeridi extends ConsumerWidget {
  final String sembol;
  final String ad;
  final double guncelFiyat;
  const AlarmSeridi({
    super.key,
    required this.sembol,
    required this.ad,
    required this.guncelFiyat,
  });

  // Veri gelince yükseklik akarak belirir
  // (2026-10-14; bkz. [SandikBelirme]).
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SandikBelirme(child: _belirenGovde(context, ref));

  Widget _belirenGovde(BuildContext context, WidgetRef ref) {
    final c = context.c;
    // Dört tür tek yerden (`sembolAlarmlariProvider`, Ar-Ge 29 Eki 16:45
    // #1): yüzde alarmı şeritte görünmüyordu, takip çanında görünüyordu.
    final hepsi = ref.watch(sembolAlarmlariProvider(sembol));
    final alarmlar = hepsi.fiyat;
    final yuzdeler = hepsi.yuzde;
    final n = ref.read(priceAlertsProvider.notifier);
    final seviyeSayisi = hepsi.gosterge.length + hepsi.cizim.length;
    if (hepsi.bos) return const SizedBox.shrink();
    final aktif = hepsi.aktif;

    // Alt boşluk şeridin KENDİ sorumluluğu: üst ekran "şerit + SizedBox"
    // dizerse boş durumda boşluk tek başına kalır ve sinyal kartıyla periyot
    // seçici arasında açıklanamayan bir delik açılırdı.
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.smd),
      child: Semantics(
        container: true,
        label: context.l10n.nActiveAlarmsAll(aktif),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final a in alarmlar) ...[
                if (a != alarmlar.first)
                  const SizedBox(width: SandikSpace.xs2),
                _AlarmCipi(
                  alarm: a,
                  // Tetiklenmiş alarm dokununca yeniden kurulur; aktif alarm
                  // dokununca silme sorulur. İki durumun tek dokunuşu vardır,
                  // ikinci bir ikon şeridi sıkıştırırdı.
                  // Tekrarlı alarm (0171) hiç "sönmüş" olmaz: çalmış olsa da
                  // kendiliğinden nöbete döner, dokunuş silme sorar.
                  onTap: () async {
                    if (a.sondu) {
                      // Fiyat eşiğin ötesindeyse eşik ön dolu sayfa;
                      // değilse yeniden kur + onay (`alarmiYenidenKur`).
                      await alarmiYenidenKur(context, ref, a,
                          aday: AlarmAdayi(sembol, ad, guncelFiyat));
                      return;
                    }
                    final ok = await showSandikConfirm(
                      context: context,
                      title: context.l10n.deleteAlertTitle,
                      message: a.isAbove
                          ? context.l10n.deleteAlertAbove(
                              fmtTRYFiyat(a.targetPrice))
                          : context.l10n.deleteAlertBelow(
                              fmtTRYFiyat(a.targetPrice)),
                      confirmLabel: 'Sil',
                      destructive: true,
                    );
                    if (ok) await n.delete(a.id);
                  },
                ),
              ],
              // Yüzde alarmı: her biri bir çip. Dokununca silme sorulur;
              // "yeniden kur" dalı yok, ertesi gün kendiliğinden nöbette.
              for (final y in yuzdeler) ...[
                if (alarmlar.isNotEmpty || y != yuzdeler.first)
                  const SizedBox(width: SandikSpace.xs2),
                _YuzdeCipi(
                  alarm: y,
                  onTap: () async {
                    final etiket =
                        yuzdeAlarmEtiketi(context.l10n, y.esikPct, y.yon);
                    final ok = await showSandikConfirm(
                      context: context,
                      title: context.l10n.deleteAlertTitle,
                      message: context.l10n.yuzdeAlarmSilSoru(etiket),
                      confirmLabel: 'Sil',
                      destructive: true,
                    );
                    if (!ok) return;
                    try {
                      await ref
                          .read(yuzdeAlarmlariProvider.notifier)
                          .delete(y.id);
                    } catch (e) {
                      if (context.mounted) showAppError(context, e);
                    }
                  },
                ),
              ],
              if (seviyeSayisi > 0) ...[
                if (alarmlar.isNotEmpty || yuzdeler.isNotEmpty)
                  const SizedBox(width: SandikSpace.xs2),
                _Cip(
                  key: const ValueKey('alarmSeridiSeviyeOzeti'),
                  onTap: () => pushGuarded(
                    context,
                    adaptiveRoute<void>(
                      settings: const RouteSettings(name: 'price_alerts'),
                      builder: (_) => PriceAlertsScreen(sembol: sembol),
                    ),
                  ),
                  renk: c.text58,
                  zemin: c.text58.withValues(alpha: 0.08),
                  semanticLabel:
                      context.l10n.seviyeAlarmOzetCipiEtiket(seviyeSayisi),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.show_chart_rounded,
                          size: 16, color: c.text90),
                      const SizedBox(width: SandikSpace.xs),
                      Text(
                        context.l10n.seviyeAlarmOzetCipi(seviyeSayisi),
                        style: context.t.labelLarge?.copyWith(
                            color: c.text90, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: SandikSpace.xs2),
              // "+" — yalnızca ikon: metin app bar'daki zilin tooltip'inde
              // zaten var, burada tekrar edilse şerit yine ikinci bir "Alarm
              // kur" butonuna dönerdi.
              _Cip(
                onTap: () => alarmKurAkisi(context, ref,
                    sabit: AlarmAdayi(sembol, ad, guncelFiyat)),
                renk: c.amberText,
                zemin: c.amberFill.withValues(alpha: 0.12),
                semanticLabel: context.l10n.setPriceAlert,
                child: Icon(Icons.add_rounded, size: 18, color: c.amberText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlarmCipi extends StatelessWidget {
  final PriceAlert alarm;
  final VoidCallback onTap;
  const _AlarmCipi({required this.alarm, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tetiklendi = alarm.sondu;
    final renk = tetiklendi ? c.text58 : (alarm.isAbove ? c.gain : c.loss);
    final fiyat = fmtTRYFiyat(alarm.targetPrice);
    final etiket = tetiklendi
        ? context.l10n.triggeredAlertSemantics(fiyat)
        : (alarm.isAbove
            ? context.l10n.alertAboveSemantics(fiyat)
            : context.l10n.alertBelowSemantics(fiyat));
    return _Cip(
      onTap: onTap,
      renk: renk,
      zemin: renk.withValues(alpha: tetiklendi ? 0.06 : 0.12),
      // Tekrarlı alarm (0171): döngü ikonu + etikette "her geçişte".
      semanticLabel: alarm.tekrar
          ? '$etiket, ${context.l10n.alarmHerGeciste}'
          : etiket,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(alarm.isAbove ? '▲' : '▼',
              style: context.t.labelLarge
                  ?.copyWith(color: renk, fontWeight: FontWeight.w700)),
          const SizedBox(width: SandikSpace.xs),
          Text(
            tetiklendi ? context.l10n.alertTriggered(fiyat) : fiyat,
            style: context.t.labelLarge?.copyWith(
              color: tetiklendi ? c.text58 : c.text90,
              fontWeight: FontWeight.w600,
              decoration: tetiklendi ? TextDecoration.lineThrough : null,
            ),
          ),
          if (tetiklendi) ...[
            const SizedBox(width: SandikSpace.xs),
            Icon(Icons.refresh_rounded, size: 14, color: c.text58),
          ],
          if (alarm.tekrar) ...[
            const SizedBox(width: SandikSpace.xs),
            Icon(Icons.repeat_rounded, size: 14, color: c.text58),
          ],
        ],
      ),
    );
  }
}

/// Yüzde alarmı çipi: "Günlük %2 hareket". Bugün çaldıysa sönük ve
/// "bugün çaldı" ekli; anlam renkte değil, metinde ve ikonda (onay işareti).
class _YuzdeCipi extends StatelessWidget {
  final YuzdeAlarmi alarm;
  final VoidCallback onTap;
  const _YuzdeCipi({required this.alarm, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final caldi = alarm.bugunCaldi(DateTime.now());
    final etiket = yuzdeAlarmEtiketi(l10n, alarm.esikPct, alarm.yon);
    final renk = caldi ? c.text58 : c.amberText;
    return _Cip(
      onTap: onTap,
      renk: renk,
      zemin: renk.withValues(alpha: caldi ? 0.06 : 0.12),
      semanticLabel: [
        l10n.watchlistYuzdeAlarmSet(etiket),
        if (caldi) l10n.watchlistYuzdeAlarmCaldi,
      ].join(', '),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(caldi ? Icons.check_rounded : Icons.percent_rounded,
              size: 16, color: renk),
          const SizedBox(width: SandikSpace.xs),
          Text(
            caldi ? l10n.yuzdeCipBugunCaldi(etiket) : etiket,
            style: context.t.labelLarge?.copyWith(
                color: caldi ? c.text58 : c.text90,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Cip extends StatelessWidget {
  final VoidCallback onTap;
  final Color renk;
  final Color zemin;
  final String semanticLabel;
  final Widget child;
  const _Cip({
    super.key,
    required this.onTap,
    required this.renk,
    required this.zemin,
    required this.semanticLabel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SandikTappable(
      semanticLabel: semanticLabel,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
        decoration: BoxDecoration(
          color: zemin,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: renk.withValues(alpha: 0.35)),
        ),
        child: child,
      ),
    );
  }
}
