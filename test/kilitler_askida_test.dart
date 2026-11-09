import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';

/// Acil durum anahtarı (Premium netleştirme, 2026-10-10) ve hediye
/// güvencesinin kaldırılması (yasin 2026-11-01: eski kullanıcı da yeni gibi
/// görür). Kural `kilitlerAskidaProvider` belgesinde; burada saf karar.
///
/// İki eski hata kilitlenir:
///  - `premium_enabled=false` (artık `acil_kapali=true`) ödeyenler dahil
///    herkesi KİLİTLİYORDU; artık kilitleri kaldırır.
///  - Hediye güvencesi hak satırı olmayan eski hesabı kilitsiz bırakıyordu;
///    hediye verilmeyeceği için o yol yok: acil durum dışında kimse askıda değil.
void main() {
  test('acil durum: acil_kapali=true herkesin kilidini kaldırır', () {
    expect(kilitlerAskidaMi(acilKapali: true), isTrue);
  });

  test('normalde kilitler askıda değil (eski/yeni hesap ayrımı yok)', () {
    expect(kilitlerAskidaMi(acilKapali: false), isFalse);
  });
}
