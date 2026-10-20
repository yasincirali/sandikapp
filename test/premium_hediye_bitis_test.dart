import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';

/// Hediye bitişi (paywall incelemesi, 2026-10-20): kalan gün ve
/// "hediyesi bitmiş" kararı. Hediye herkese aynı gün verildiği için aynı
/// günlerde biter; sessiz bitiş "bir sabah kilit" hissi. Profil satırı
/// kalan günü yazar, son 7 günde "devam et" düğmesi çıkar, bitince bir kez
/// sayfa açılır.
void main() {
  final simdi = DateTime.utc(2026, 11, 1, 12);

  PremiumHakki hediye(DateTime bitis) =>
      PremiumHakki(kaynak: 'erken_kullanici', bitis: bitis);

  test('kalan gün yukarı yuvarlanır; bugün biten 1, bitmiş 0, süresiz null',
      () {
    expect(hediye(simdi.add(const Duration(hours: 3))).kalanGun(simdi), 1);
    expect(hediye(simdi.add(const Duration(days: 6, hours: 1))).kalanGun(simdi),
        7);
    expect(
        hediye(simdi.subtract(const Duration(minutes: 1))).kalanGun(simdi), 0);
    expect(const PremiumHakki(kaynak: 'manuel', bitis: null).kalanGun(simdi),
        isNull);
  });

  test('son günler eşiği 7 gün', () {
    expect(hediyeSonGunlerEsigi, 7);
    expect(
        hediye(simdi.add(const Duration(days: 7))).kalanGun(simdi)! <=
            hediyeSonGunlerEsigi,
        isTrue);
    expect(
        hediye(simdi.add(const Duration(days: 8))).kalanGun(simdi)! <=
            hediyeSonGunlerEsigi,
        isFalse);
  });
}
