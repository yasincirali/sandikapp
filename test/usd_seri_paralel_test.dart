import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// USD kote sembolün serisi ile kur serisi AYNI ANDA istenir.
///
/// `getSymbolHistory` emtia/ons gibi USD kote varlıkta önce sembolü, yanıt
/// gelince kuru çekiyordu: iki ağ turu ardışık. Kur sembolün yanıtına bağlı
/// değil; varlık sayfası ve takip listesi bu yolla açılır (kullanıcı kararı
/// 2026-09-28: "tüm varlıklar için paralel çağrı").
void main() {
  final cagrilar = <String>[];

  setUp(() {
    cagrilar.clear();
    HistoryService.clearCache();
  });

  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.clearCache();
  });

  test('sembol yanıtlanmadan kur isteği de yolda', () async {
    final bekleyen = <Completer<List<(int, double)>>>[];
    HistoryService.seriCekici = (sym, range, interval) {
      cagrilar.add(sym);
      final c = Completer<List<(int, double)>>();
      bekleyen.add(c);
      return c.future;
    };

    final sonuc =
        HistoryService.instance.getSymbolHistory('BZ=F', periodDays: 30);
    await Future<void>.delayed(Duration.zero);

    expect(cagrilar, containsAll(['BZ=F', FiyatKaynagi.usdTry]),
        reason: 'kur, sembolün cevabını beklememeli');

    for (final c in bekleyen) {
      c.complete(const []);
    }
    expect(await sonuc, isEmpty);
  });

  test('TRY kote sembolde kur hiç istenmez', () async {
    HistoryService.seriCekici = (sym, range, interval) async {
      cagrilar.add(sym);
      return const [];
    };
    await HistoryService.instance.getSymbolHistory('THYAO.IS', periodDays: 30);
    expect(cagrilar, isNot(contains(FiyatKaynagi.usdTry)));
  });
}
