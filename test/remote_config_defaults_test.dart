import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tutundurma bayraklarının varsayılan değerleri.
///
/// **Bu testin varlık sebebi:** bayraklar 2026-09-07'de TestFlight'ta
/// görünsünler diye açıldı (kullanıcı kararı). Değerler `_defaults` içinde
/// private bir sabit; ne çalışma zamanında ne de testten okunabiliyor.
/// Bir refactor ya da merge bunları sessizce `false`'a döndürürse hiçbir
/// test kırılmaz ve özellikler TestFlight'ta habersizce kaybolur —
/// "neden görünmüyor?" turunu bir kez yaşadık.
///
/// **Neden kaynak metni okunuyor:** `RemoteConfigService.init()` Firebase
/// istiyor, widget testinde ayağa kalkmıyor; getter'lar da `_rc` null iken
/// varsayılana düşüyor ama sınıfı kurmadan bunu tetiklemek mümkün değil.
/// Dosyanın kendisini denetlemek, projedeki mevcut örüntüyle aynı
/// (bkz. `watchlist_detail_test.dart`).
void main() {
  late String kaynak;

  setUpAll(() {
    kaynak = File('lib/services/remote_config_service.dart').readAsStringSync();
  });

  /// `'anahtar': deger,` satırını bulur — yorum satırlarına takılmaz.
  String? varsayilan(String anahtar) {
    final m = RegExp("'${RegExp.escape(anahtar)}':\\s*([A-Za-z0-9_.]+)\\s*,")
        .firstMatch(kaynak);
    return m?.group(1);
  }

  group('tutundurma bayrakları AÇIK doğar', () {
    // Beşi de TestFlight'ta görünür olmalı. Biri kapanırsa ilgili yüzey
    // (şerit / rozet / kutlama / öneri) hiç render edilmez.
    // `percentile_strip_enabled` 2026-09-21'de KAPALI'ya alındı (kullanıcı
    // kararı: küresel sıralama havuz dolana kadar parametrik kapalı,
    // `global_leaderboard_enabled` ile birlikte) — "kapalı kalması
    // gerekenler" grubunda.
    const acikOlmali = [
      'widget_prompt_enabled',
      'push_prompt_after_first_asset',
      'real_return_enabled',
      'milestones_enabled',
      // Recap'in asıl kapısı takvim (26 Aralık–10 Ocak); bayrak yine de
      // paketle aynı rejimde tutulur ki pencere geldiğinde elle açma
      // adımı unutulmasın.
      'recap_enabled',
    ];

    for (final bayrak in acikOlmali) {
      test('$bayrak = true', () {
        expect(
          varsayilan(bayrak),
          'true',
          reason: '$bayrak varsayılanı kapatılmış. Kasıtlıysa bu testi de '
              'güncelle; değilse TestFlight\'ta o yüzey görünmeyecek.',
        );
      });
    }
  });

  group('kapalı kalması gerekenler', () {
    // Bunlar tutundurma paketine DAHİL DEĞİL; toplu "hepsini aç" turunda
    // yanlışlıkla sürüklenmediklerini doğrular.
    test('küresel sıralama kapalı — havuz dolana kadar (2026-09-21)', () {
      expect(varsayilan('global_leaderboard_enabled'), 'false');
      expect(varsayilan('percentile_strip_enabled'), 'false');
    });

    test('paywall_enabled hâlâ kapalı — IAP paketi yok', () {
      expect(varsayilan('paywall_enabled'), 'false');
    });

    test('deposits_enabled artık yok — vadeli mevduat koddan çıkarıldı', () {
      expect(varsayilan('deposits_enabled'), isNull);
    });
  });

  test('free_price_alert_limit sayısal ve makul', () {
    // Alarm kullanıcının KENDİ istediği bildirim; sınır cömert olmalı ama
    // premium kancası kalmalı.
    final v = int.tryParse(varsayilan('free_price_alert_limit') ?? '');
    expect(v, isNotNull);
    expect(v, greaterThanOrEqualTo(1));
    expect(v, lessThanOrEqualTo(10));
  });
}
