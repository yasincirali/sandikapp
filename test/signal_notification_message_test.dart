import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/technical_signal.dart';
import 'package:portfoy_takip/services/notification_service.dart';

/// Sinyal bildiriminin METNİ ve kısa etiketi.
///
/// Bu metin İKİ yerde üretiliyor: burada (uygulama içi analiz) ve
/// `analyze-signals/index.ts` içinde (cron push). İkisi ayrışırsa kullanıcı,
/// bildirimin nereden geldiğine göre farklı biçimde uyarı alır.
void main() {
  group('kısa varlık etiketi', () {
    test('TEFAS fon kodundan ön ek atılır', () {
      // Fon adları başlığa sığmaz ("YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ
      // SEKTÖRÜ HİSSE SENEDİ FONU"); işletim sistemi ortadan keserse ayırt
      // edici kısım kaybolur. Ham `TEFAS:` ön eki ise kullanıcıya teknik
      // bir hata gibi görünür.
      expect(
        NotificationService.shortAssetLabel('AK PORTFÖY ALTIN FONU',
            'TEFAS:AFO'),
        'AFO',
      );
    });

    test('BIST hisse kodundan .IS soneki atılır', () {
      expect(
        NotificationService.shortAssetLabel('AG Anadolu Grubu Holding',
            'AGHOL.IS'),
        'AGHOL',
      );
    });

    test('kur çiftinde ADA düşülür — kod kullanıcıya anlamsız', () {
      // `EURTRY=X` bir kod değil, kaynak sisteminin sembolü. "Euro" hem
      // kısa hem anlaşılır.
      expect(
        NotificationService.shortAssetLabel('Euro', 'EURTRY=X'),
        'Euro',
      );
    });

    test('ticker boşsa ada düşülür', () {
      expect(NotificationService.shortAssetLabel('Altın Gram', ''), 'Altın Gram');
    });

    test('tek harflik koda güvenilmez — ada düşülür', () {
      expect(NotificationService.shortAssetLabel('Bir Varlık', 'X'), 'Bir Varlık');
    });
  });

  group('bildirim metni', () {
    test('yukarı yönlü: ok, etiket, oran ve güven', () {
      final m = NotificationService.buildSignalMessage(
        assetName: 'AK PORTFÖY ALTIN FONU',
        ticker: 'TEFAS:AFO',
        signal: SignalType.buy,
        buyCount: 4,
        sellCount: 2,
      );

      // Yön oku EN SOLDA: kilit ekranında bildirimler yığılır ve kullanıcı
      // önce sol kenarı tarar.
      expect(m.title, startsWith('▲ '));
      expect(m.title, contains('AFO'));
      expect(m.body, contains('4/6'));
      // Güven AÇIKÇA verilir — "çoğunluğu yukarı yönlü" 4/6 ile 6/6
      // arasındaki farkı gizliyordu.
      expect(m.body, contains('%67'));
    });

    test('aşağı yönlü: ok ters, sayaç SELL üzerinden', () {
      final m = NotificationService.buildSignalMessage(
        assetName: 'Euro',
        ticker: 'EURTRY=X',
        signal: SignalType.sell,
        buyCount: 2,
        sellCount: 4,
      );

      expect(m.title, startsWith('▼ '));
      expect(m.title, contains('Euro'));
      expect(m.body, contains('4/6'));
      expect(m.body, contains('aşağı'));
    });

    test('nötr AYRI ele alınır — "aşağı" demez', () {
      // Eskiden yalnızca `isBuy` bakılıyordu ve "buy değilse aşağı trend"
      // varsayılıyordu. Nötr push açıldığında kullanıcı kararsız piyasada
      // "Aşağı trend" bildirimi alırdı — doğrudan yanlış bilgi.
      final m = NotificationService.buildSignalMessage(
        assetName: 'AG Anadolu Grubu Holding',
        ticker: 'AGHOL.IS',
        signal: SignalType.neutral,
        buyCount: 3,
        sellCount: 3,
      );

      expect(m.title, startsWith('◆ '));
      expect(m.title, contains('belirsiz'));
      expect(m.body, isNot(contains('güven')));
      expect(m.title, isNot(contains('▼')));
    });

    test('yasal ibare HER durumda korunur', () {
      for (final s in SignalType.values) {
        final m = NotificationService.buildSignalMessage(
          assetName: 'Test',
          ticker: 'TEFAS:ABC',
          signal: s,
          buyCount: 3,
          sellCount: 1,
        );
        expect(m.body, contains('Yatırım tavsiyesi değildir.'),
            reason: '$s için yasal ibare düşmüş');
      }
    });

    test('sıfır göstergede bölme hatası olmaz', () {
      final m = NotificationService.buildSignalMessage(
        assetName: 'Test',
        ticker: 'TEFAS:ABC',
        signal: SignalType.buy,
        buyCount: 0,
        sellCount: 0,
      );
      expect(m.body, contains('%0'));
    });
  });

  group('istemci ↔ sunucu sözleşmesi', () {
    test('sunucu da AYNI ok ve etiket kalıbını kullanır', () {
      // İki taraf ayrışırsa kullanıcı, push'un cron'dan mı uygulama içi
      // analizden mi geldiğine göre farklı biçimde bildirim alır.
      final fn = File('supabase/functions/analyze-signals/index.ts')
          .readAsStringSync();

      for (final isaret in ['▲ ', '▼ ', '◆ ']) {
        expect(fn, contains(isaret),
            reason: 'sunucu metni "$isaret" yön işaretini kullanmıyor');
      }

      expect(fn, contains('shortLabel'),
          reason: 'sunucu kısa etiket üretmiyor — uzun fon adları başlığı taşırır');
      expect(fn, contains('güven %'),
          reason: 'sunucu güven yüzdesini vermiyor');

      // `ticker` parametresi GEÇİLMELİ. Varsayılanı `''` olduğu için
      // geçilmezse kod derlenir, test geçer ve etiket sessizce hep ADA
      // düşer — kısaltmanın bütün amacı kaybolur. Bu tam olarak yaşandı.
      //
      // `buildMessage(` ile aramak YETMEZ: ilk eşleşme fonksiyon TANIMIdır
      // ve orada `ticker` parametresi zaten geçer (denendi, test bozuk kodu
      // yakalamadı). Aranan şey ÇAĞRIDIR — sonucu destructure eden satır.
      final cagri = RegExp(
        r'\{\s*title,\s*body\s*\}\s*=\s*buildMessage\((.*?)\);',
        dotAll: true,
      ).firstMatch(fn);

      expect(cagri, isNotNull, reason: 'buildMessage çağrısı bulunamadı');
      expect(
        cagri!.group(1),
        contains('ticker'),
        reason: 'buildMessage çağrısına ticker geçilmiyor — kısa etiket '
            'devre dışı kalır (varsayılan boş string, sessizce ada düşer)',
      );
    });
  });

  group('bildirime dokunma', () {
    test('sinyal bildirimi varlığın performans ekranını açar', () {
      // Bildirime dokunmak uygulamayı açıp ANA EKRANDA bırakıyordu: sinyal
      // dalı `handleRemoteMessageData` içinde hiç ele alınmamıştı ve yerel
      // bildirimde `payload` boş gönderiliyordu.
      //
      // Hedef `PerformanceScreen` — grafiğin altındaki teknik sinyal paneli
      // orada; kullanıcının bildirimden sonra görmek istediği yer orası.
      final kod = File('lib/services/notification_service.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .where((l) => !l.trimLeft().startsWith('///'))
          .join('\n');

      expect(kod, contains('_openAssetPerformance'),
          reason: 'sinyal bildirimi için yönlendirme yok');
      expect(kod, contains('PerformanceScreen'),
          reason: 'performans ekranına gidilmiyor');

      // Yerel bildirimde payload gönderilmezse ön planda basılan bildirime
      // dokunmak hangi varlığa ait olduğunu KAYBEDER.
      expect(kod, contains('payload:'),
          reason: 'yerel bildirimde payload gönderilmiyor — tıklama bilgisiz kalır');
    });
  });
}
