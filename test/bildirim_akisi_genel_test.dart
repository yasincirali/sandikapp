import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/app_notification.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/bildirim_akisi.dart';
import 'package:portfoy_takip/models/price_alert_notification.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/technical_signal.dart';

/// Çan sayfası — üç kaynak, tek akış; toplu eylemler üçünü de kapsar.
///
/// Kullanıcı (2026-09-17): "Tümünü sil, hepsini temizle çalışmıyor. Tek tek
/// silme ve geçmişi silme çalışıyor. Ayrıca fiyat alarmı, sinyal, ortaklık,
/// özet — tüm push'lar çan altında görünebilmeli."
///
/// Sebep: toplu eylemler yalnızca sinyal notifier'ını çağırıyordu; liste
/// alarmlarla harmanlandığı için alarm satırları yerinde kalıyordu. Tekil
/// eylemler türüne göre doğru notifier'a gittiği için çalışıyordu.
void main() {
  SignalAlert sinyal(String id, DateTime t) => SignalAlert(
        id: id,
        assetId: 'a-$id',
        assetName: 'Varlık $id',
        assetTicker: 'TCK',
        assetType: AssetType.hisse,
        signal: SignalType.buy,
        buyCount: 3,
        sellCount: 1,
        confidence: 0.7,
        detectedAt: t,
      );

  PriceAlertNotification alarm(String id, DateTime t) => PriceAlertNotification(
        id: id,
        symbol: 'ALTIN_GRAM',
        label: 'Gram Altın',
        targetPrice: 6200,
        triggeredPrice: 6212.28,
        direction: 'above',
        sentAt: t,
      );

  AppNotification genel(String id, DateTime t, {DateTime? dismissed}) =>
      AppNotification(
        id: id,
        type: AppNotification.partnerInvite,
        title: 'Yeni ortaklık isteği',
        body: 'Ayşe ortaklık kodunu girdi.',
        data: const {'invite_id': 'inv-1'},
        sentAt: t,
        dismissedAt: dismissed,
      );

  group('bildirimAkisi üç kaynağı tek akışta harmanlar', () {
    final t0 = DateTime(2026, 9, 17, 10);

    test('genel bildirim zaman sırasına girer', () {
      final akis = bildirimAkisi(
        [sinyal('s1', t0)],
        [alarm('p1', t0.add(const Duration(minutes: 2)))],
        [genel('g1', t0.add(const Duration(minutes: 1)))],
      );
      expect(akis.map((e) => e.kimlik), ['p1', 'g1', 's1'],
          reason: 'en yeni önce; tür sıralamayı etkilemez');
      expect(akis[1], isA<GenelOgesi>());
    });

    test('dismiss edilmiş genel bildirim GEÇMİŞ sayılır', () {
      final akis = bildirimAkisi(const [], const [],
          [genel('g1', t0, dismissed: t0.add(const Duration(hours: 1)))]);
      expect(akis.single.dismissEdilmis, isTrue);
    });

    test('üçüncü liste isteğe bağlı — eski çağıranlar kırılmaz', () {
      expect(bildirimAkisi([sinyal('s1', t0)], const []).length, 1);
    });
  });

  group('çan sayfası kaynak kodu sözleşmesi', () {
    final src = File('lib/screens/home_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    test('toplu eylemler ÜÇ notifier\'ı birden çağırır', () {
      for (final eylem in ['dismissAll', 'deleteHistory', 'deleteAll']) {
        for (final saglayici in [
          'signalProvider',
          'priceAlertNotificationProvider',
          'appNotificationProvider',
        ]) {
          expect(
            RegExp('$saglayici\\.notifier\\)\\s*\\.$eylem\\(\\)')
                .hasMatch(src),
            isTrue,
            reason: '$eylem $saglayici için çağrılmıyor — o türün satırları '
                'listede kalır, kullanıcı "çalışmıyor" görür',
          );
        }
      }
    });

    test('akış ve rozet üçüncü kaynağı da sayar', () {
      expect(src.contains('bildirimAkisi(signals, alarmlar, genel)'), isTrue);
      expect(src.contains('ref.watch(activeAppNotificationsProvider)'), isTrue,
          reason: 'genel bildirim gelince rozet kıpırdamaz');
    });

    test('rozet "yeni"yi sayar; çan açılınca ve kapanınca görüldü (#26)', () {
      // Emülatör testi #26 (2026-09-29): sayfa açılıp okunduktan sonra da
      // "1 yeni bildirim" kalıyordu — rozet aktif sayısıydı.
      expect(src.contains('yeniBildirimSayisi('), isTrue);
      expect(src.contains('ref.watch(bildirimSonGorulenProvider)'), isTrue);
      final ac = src.indexOf('void _scrollToSignals()');
      final son = src.indexOf('void _bildirimleriGorulduSay()');
      expect(ac, greaterThan(-1));
      final govde = src.substring(ac, son);
      expect(govde.contains('_bildirimleriGorulduSay();'), isTrue,
          reason: 'açılışta görüldü damgası');
      expect(govde.contains('.whenComplete('), isTrue,
          reason: 'kapanışta görüldü damgası');
    });

    test('genel satırın kendi eylemleri var (kimlik uzayları ayrı)', () {
      expect(src.contains('case GenelOgesi(:final bildirim):'), isTrue);
      expect(src.contains('onGenelDismiss(bildirim.id)'), isTrue);
      expect(src.contains('onGenelDelete(bildirim.id)'), isTrue);
    });
  });

  group('yeniBildirimSayisi — rozetin saydığı', () {
    final t0 = DateTime.utc(2026, 9, 29, 9, 45);
    AppNotification g(String id, DateTime t, {bool temiz = false}) =>
        AppNotification(
          id: id,
          type: AppNotification.dailyBrief,
          title: 'ARDYZ son kapanışta %5,8 yükseldi',
          body: '',
          data: const {},
          sentAt: t,
          dismissedAt: temiz ? t : null,
        );

    test('çan hiç açılmadıysa aktiflerin hepsi yeni', () {
      final akis = bildirimAkisi(const [], const [],
          [g('a', t0), g('b', t0), g('c', t0, temiz: true)]);
      expect(yeniBildirimSayisi(akis, null), 2);
    });

    test('açıldıktan sonra rozet düşer; SONRA gelen yeniden sayılır', () {
      final akis = bildirimAkisi(const [], const [], [g('a', t0)]);
      final damga = gorulduDamgasi(akis, t0.add(const Duration(minutes: 1)));
      expect(yeniBildirimSayisi(akis, damga), 0,
          reason: 'okunan bildirim "yeni" kalmaz');
      final sonra = bildirimAkisi(const [], const [],
          [g('a', t0), g('b', t0.add(const Duration(hours: 1)))]);
      expect(yeniBildirimSayisi(sonra, damga), 1);
    });

    test('sunucu saati ilerideyse damga en yeni kayda çekilir', () {
      // Cihaz saati 2 dk geride: yalnız "şimdi" yazılsa az önce görülen
      // kayıt yeni kalırdı.
      final akis = bildirimAkisi(const [], const [], [g('a', t0)]);
      final damga =
          gorulduDamgasi(akis, t0.subtract(const Duration(minutes: 2)));
      expect(damga, t0);
      expect(yeniBildirimSayisi(akis, damga), 0);
    });
  });

  test('dört push türü de çan kaydı yazar (sunucu)', () {
    for (final f in [
      'daily-brief',
      'weekly-summary',
      'calendar-nudge',
      'send-partner-invite-push',
    ]) {
      final src = File('supabase/functions/$f/index.ts').readAsStringSync();
      expect(src.contains('recordAppNotification('), isTrue,
          reason: '$f push gönderiyor ama çana yazmıyor — kaçırılan push '
              'uygulama içinde iz bırakmaz');
    }
  });
}
