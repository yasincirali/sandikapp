// Bugün kartının üç veri yükleyicisi — TEK KAYNAK.
//
// ## Neden ayrı dosya (kullanıcı isteği, 2026-09-28)
// *"Uygulamaya tıklandığında GIF başladığında ana sayfa için gereken tüm
// istekler paralel atılmalı; GIF bitene kadar ekran verileri hazır olmalı,
// müşteri GIF sonrası ana sayfayı hep dolu ve taze görsün, shimmer ile ayrı
// bir loading beklemesin."*
//
// Splash zaten portföyü, ortak listesini ve ortak varlıklarını ısıtıyordu
// (`_AuthGateState._warmUpData`). Ana ekranda kalan tek iskelet Bugün
// kartıydı: kartın üç yükleyicisi (gün içi seri, reel getiri, haftalık
// getiri) `BugunKarti` state'inin içindeydi ve ancak kart KURULDUKTAN sonra
// başlıyordu — fiyat turu da `MainNavigationScreen.initState`'te. Yani
// splash biter, ana ekran gelir, kart 2–10 sn iskelet çizer.
//
// Yükleyiciler buraya çıkarıldı: kart da splash da AYNI fonksiyonları
// çağırır. Splash'ta çağrılınca alttaki önbellekler dolar
// (`IntradaySeriesCache`, `InflationService` 12 sa TTL, `HistoryService`
// `_tierCache`); kart mount olduğunda aynı çağrılar önbellekten anında
// döner ve iskelet çizilmez. Mantık iki yerde yazılmadı: biri değişip
// diğeri kalınca splash "hazır" deyip kartın başka veri beklemesi
// riski yok.
//
// Bütçe: her yükleyici [enFazla] ile sınırlıdır; hata ve zaman aşımı
// `null`a düşer (Crashlytics'e non-fatal). Splash'ın kendi emniyet supabı
// ayrıdır (`_dataWaitTimer`).
import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/position.dart';
import '../providers/portfolio_provider.dart';
import 'bugun_service.dart';
import 'crash_reporter.dart';
import 'daily_summary.dart';
import 'history_service.dart';
import 'period_summary_service.dart';
import 'real_return_service.dart';
import 'remote_config_service.dart';
import 'tazelik_ritmi.dart';

abstract final class BugunYukleyici {
  /// Tek bir yüklemenin üst sınırı. Biri asılı kalırsa kart bu süreden
  /// sonra elindekiyle çizilir; iskelet sonsuza kadar kalmaz.
  static const Duration varsayilanButce = Duration(seconds: 10);

  /// Gün içi seri — her kapsamda ORTAK önbellekten (`IntradaySeriesCache`).
  ///
  /// Kişisel görünüm Ben yuvasını (kilit ekranı ve widget'la aynı), ortak/
  /// Birlikte görünümü kendi kümesinin yuvasını okur; Performans aynı
  /// kümeyi istediğinde aynı nesneyi alır (2026-10-02, "her yerde aynı").
  ///
  /// [azamiYas] önbellekteki serinin kabul edilen yaşı; [zorla] nabızda
  /// koşulsuz tazeleme.
  static Future<Map<int, double>?> seri(
    PortfolioState state, {
    required bool kisisel,
    Duration azamiYas = TazelikRitmi.yuzey,
    bool zorla = false,
    Duration enFazla = varsayilanButce,
  }) async {
    try {
      if (!kisisel) {
        final bd = await IntradaySeriesCache.instance
            .breakdown(
              state.activeAssets.where(FiyatKaynagi.seriyeGirer).toList(),
              ownerId: state.ownerId,
              azamiYas: azamiYas,
              zorla: zorla,
            )
            .timeout(enFazla);
        return bd.total;
      }
      return await IntradaySeriesCache.instance
          .get(state, azamiYas: azamiYas, zorla: zorla)
          .timeout(enFazla);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'BugunYukleyici.seri');
      return null;
    }
  }

  /// Reel getiri satırı — Remote Config kapalıysa `null`.
  ///
  /// Lot listesi `activeAssets` (2026-10-01 emülatör testi): `state.assets`
  /// HAM defterdir ve yumuşak silinmiş lot'ları taşır. Performans › Özet
  /// `isActive` süzgecinden geçirirken burası ham listeyi veriyordu; aynı
  /// dakikada Ana ekran "5,4 puan önde", Özet "4,5 puan" yazdı. Getiri
  /// hesaplayan her yüzey aynı kümeyi okumalı (`PortfolioState.activeAssets`
  /// notu).
  /// Testte reel satırını ağsız vermek için (TÜFE ve seri testte ağa
  /// çıkamaz; `HistoryService.seriCekici` ile aynı desen).
  @visibleForTesting
  static ReelGetiriSatiri? Function(PortfolioState state)? reelTest;

  static Future<ReelGetiriSatiri?> reel(
    PortfolioState state, {
    Duration enFazla = varsayilanButce,
  }) async {
    final test = reelTest;
    if (test != null) return test(state);
    if (!RemoteConfigService.instance.realReturnEnabled) return null;
    try {
      final r =
          await RealReturnService.yillik(state.activeAssets).timeout(enFazla);
      if (r == null) return null;
      return ReelGetiriSatiri(
          nominal: r.nominal, inflation: r.inflation, pencere: r.pencere);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'BugunYukleyici.reel');
      return null;
    }
  }

  /// Haftalık getiri yüzdesi — Remote Config kapalıysa `null`.
  static Future<double?> haftalik(
    PortfolioState state, {
    Duration enFazla = varsayilanButce,
  }) async {
    if (!RemoteConfigService.instance.periodSummaryEnabled) return null;
    try {
      final now = DateTime.now();
      // `activeAssets`: Özet ile aynı küme (gerekçe `reel`).
      final lotlar = state.activeAssets;
      final p = PeriodSummaryService.pencere(SummaryPeriod.birHafta, now);
      final bd = await HistoryService.instance
          .getPortfolioHistoryBreakdownAtResolution(
            assets: lotlar,
            from: p.start,
            to: p.end,
            tier: ResolutionTierMeta.pickForSpan(
                SummaryPeriod.birHafta.days.toDouble()),
          )
          .timeout(enFazla);
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birHafta,
        assets: lotlar,
        breakdown: bd,
        now: now,
        // Performans › Özet ile aynı sağ uç (bkz. `compute` [canliSon]).
        canliSon: DailySummary.kapsamToplami(state, lotlar),
      );
      return s.getiriPct;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'BugunYukleyici.haftalik');
      return null;
    }
  }

  /// Splash ısıtması: kartın açılışta ("Ben" görünümü) isteyeceği üç veriyi
  /// PARALEL çeker ve önbellekleri doldurur. Sonuç kullanılmaz; kart aynı
  /// çağrıları yapınca önbellekten alır. Hiç fırlatmaz.
  ///
  /// Boş defterde hiçbir şey çekilmez — kart da çizilmez.
  static Future<void> isit(PortfolioState state,
      {Duration enFazla = varsayilanButce}) async {
    if (aktifLotlar(state.assets).isEmpty) return;
    await Future.wait<Object?>([
      seri(state, kisisel: true, enFazla: enFazla),
      reel(state, enFazla: enFazla),
      haftalik(state, enFazla: enFazla),
    ]);
  }
}
