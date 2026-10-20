import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// `NotificationService.init` ilk çağrıda kilitlenir (`_initialized`); ikinci
/// çağrının parametresi yok sayılır. 2026-10-20'ye kadar main.dart'ta
/// ertelemesiz bir çağrı ertelemeli olanın önünde kaldığı için iOS bildirim
/// izni `push_prompt_after_first_asset` açıkken bile açılışta soruluyordu.
void main() {
  test('main.dart bildirim servisini tek kez ve ertelemeli başlatır', () {
    final kaynak = ekranKaynagiSync('lib/main.dart');
    final cagrilar =
        RegExp(r'NotificationService\.instance\.init\(').allMatches(kaynak);
    expect(cagrilar.length, 1,
        reason: 'İkinci init çağrısı ilkinin ayarını ezemez; tek çağrı kalmalı.');
    final i = kaynak.indexOf('NotificationService.instance.init(');
    final govde = kaynak.substring(i, kaynak.indexOf(');', i));
    expect(govde, contains('iosIzniErtele:'),
        reason: 'Açılıştaki tek çağrı iOS iznini erteleme bayrağını taşımalı.');
  });
}
