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
/// (bkz. `varlik_sayfasi_test.dart`).
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
    test('küresel yarış AÇIK (2026-09-28), yüzdelik şeridi kapalı', () {
      // 2026-09-21'de ikisi birlikte kapatılmıştı; 2026-09-28 kullanıcı
      // kararı yarışı ortaktan bağımsız bir özellik olarak açtı. Şerit
      // ("N kişi" sayısı) havuz dolana kadar kapalı kalır.
      expect(varsayilan('global_leaderboard_enabled'), 'true');
      expect(varsayilan('percentile_strip_enabled'), 'false');
    });

    // Karar 8.1 (2026-09-30): kâr payı stopajı %15 (9286 s. CBK, RG
    // 22.12.2024). Değer değişirse mevzuat değişmiş olmalı — kaynağı yaz.
    // 0111: açılırsa yeni satış `sell_fx_rate` yazar; sütun sunucuda yokken
    // açık doğarsa her dövizli satış PGRST204 ile düşer.
    test('satış günü kuru KAPALI doğar', () {
      expect(varsayilan('satis_gunu_kuru'), 'false');
    });

    // Ana yüzeyde yeni bilgi (Özet kartı + kutlama); önce yasin'in cihazı.
    test('birikim serisi KAPALI doğar', () {
      expect(varsayilan('birikim_serisi'), 'false');
    });

    // Sadeleştirme 2 (2026-10-08): ana yüzeyleri değiştirir; önce yasin'in
    // TestFlight cihazında açılır. Kapalıyken ekranlar birebir eski.
    for (final b in const [
      'donem_hafizasi',
      'performans_tek_akis',
      'portfoy_dagilim_cubugu',
      'varlik_detay_katmanli',
      'sinyal_on_ayar',
      'raporlar_kapisi',
      'genel_arama',
    ]) {
      test('$b KAPALI doğar', () => expect(varsayilan(b), 'false'));
    }

    // 0124 iki sunucuya gidip eurobond-fiyat ilk turunu atmadan açılırsa
    // eklenen lot fiyatsız kalır.
    test('eurobond KAPALI doğar', () {
      expect(varsayilan('eurobond'), 'false');
    });

    // Yeni hisse pazarı: form, arama ve rozetler; kapalıyken birebir eski.
    test('ABD hissesi KAPALI doğar', () {
      expect(varsayilan('abd_hisse'), 'false');
    });

    // Varlık ekranında yeni kart; kapalıyken ekran birebir eski.
    test('varlık masrafları KAPALI doğar', () {
      expect(varsayilan('varlik_masraflari'), 'false');
    });

    // Formun ilk sorusu değişir (arama + gruplu ızgara); kapalıyken çip
    // `Wrap`'ı birebir eski.
    test('tür seçici ızgarası KAPALI doğar', () {
      expect(varsayilan('tur_secici_izgara'), 'false');
    });

    // Göz alıcılık (tek bayrak): ana listenin ve fiyatın görünüşü değişir;
    // kapalıyken birebir eski.
    test('göz alıcılık KAPALI doğar', () {
      expect(varsayilan('goz_alici'), 'false');
    });

    // Sunucu tabloları (0129) ve ilk faiz turu olmadan açılırsa liste boş
    // gelir; kapalıyken mevduat formu birebir eski.
    test('mevduat banka seçici KAPALI doğar', () {
      expect(varsayilan('mevduat_banka_secici'), 'false');
    });

    test('temettü stopaj oranı %15 (mevzuat, kaynaklı)', () {
      expect(varsayilan('temettu_stopaj_orani'), '0.15');
    });

    // 2026-10-04'te AÇIK doğan sadeleştirme bayrakları 2026-10-05'te KODDAN
    // KALDIRILDI (kullanıcı kararı: "önerilerin hepsini uygula"); davranış
    // kalıcı. Bu kilit anahtarın `_defaults`'a ya da bir okuyucuya
    // (`'anahtar'` dizgesi) geri gelmesini yakalar: geri gelen bayrak
    // Console'daki eski `false` değerini yeniden okur ve kalıcı davranışı
    // sessizce kapatabilir.
    for (final b in const [
      'ilk_varlik_kolay',
      'karsilama_tanitimi',
      'seviye_anketi',
      'bugun_karti_kiyas',
      'varlik_islem_cubugu',
      'tek_ortak_secici',
      'tek_kiyas_yuzeyi',
      'siralama_tek_sayfa',
      'performans_ayar_sade',
      'yaris_duello_arena',
      'tek_onay_kutusu',
      'ortak_secimi_tasi',
      'yasal_onay_kaydi',
      'yasal_kapi_en_yeni',
      'zorunlu_okuma',
    ]) {
      test('$b kaldırıldı: _defaults ve okuyucu kodda yok', () {
        expect(varsayilan(b), isNull, reason: '_defaults geri gelmiş');
        final okuyan = [
          for (final f in Directory('lib').listSync(recursive: true))
            if (f is File &&
                f.path.endsWith('.dart') &&
                f.readAsStringSync().contains("'$b'"))
              f.path,
        ];
        expect(okuyan, isEmpty, reason: '$b anahtarını okuyan kod geri gelmiş');
      });
    }

    test('paywall_enabled hâlâ kapalı — IAP paketi yok', () {
      expect(varsayilan('paywall_enabled'), 'false');
    });

    test('deposits_enabled artık yok — vadeli mevduat koddan çıkarıldı', () {
      expect(varsayilan('deposits_enabled'), isNull);
    });
  });

  test('free_price_alert_limit sayısal ve makul', () {
    // Alarm kullanıcının KENDİ istediği bildirim; sınır cömert olmalı ama
    // premium kancası kalmalı. 3 → 20 (yasin, 2026-10-10: "pinti
    // görünmeyelim"; rakiplerin hiçbiri alarmı kilitlemiyor).
    final v = int.tryParse(varsayilan('free_price_alert_limit') ?? '');
    expect(v, isNotNull);
    expect(v, greaterThanOrEqualTo(1));
    expect(v, lessThanOrEqualTo(20));
  });
}
