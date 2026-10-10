import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';

/// Acil durum anahtarı ve hediye güvencesi (Premium netleştirme,
/// 2026-10-10). Kural `kilitlerAskidaProvider` belgesinde; burada saf karar.
///
/// İki eski hata kilitlenir:
///  - `premium_enabled=false` ödeyenler dahil herkesi KİLİTLİYORDU; artık
///    kilitleri kaldırır.
///  - Paywall hediyeden önce açılırsa mevcut herkes kilitlenirdi; artık
///    kesimden eski, hak satırı olmayan hesap kilit görmez.
void main() {
  final kesim = DateTime.parse('2026-11-01T00:00:00+03');
  final eski = DateTime.utc(2026, 6, 1);
  final yeni = DateTime.utc(2026, 11, 5);
  final hediye = PremiumHakki(
    kaynak: 'erken_kullanici',
    bitis: DateTime.utc(2027, 1, 30),
  );
  final bitmis = PremiumHakki(
    kaynak: 'erken_kullanici',
    bitis: DateTime.utc(2026, 1, 1),
  );

  bool askida({
    bool premiumEnabled = true,
    List<PremiumHakki>? haklar = const [],
    DateTime? hesap,
    DateTime? kesimi,
  }) =>
      kilitlerAskidaMi(
        premiumEnabled: premiumEnabled,
        haklar: haklar,
        hesapOlusturma: hesap,
        hediyeKesimi: kesimi,
      );

  test('acil durum: premium_enabled=false herkesin kilidini kaldırır', () {
    expect(askida(premiumEnabled: false, hesap: yeni, kesimi: kesim), isTrue);
    expect(askida(premiumEnabled: false, haklar: [bitmis], hesap: eski),
        isTrue);
  });

  test('kesimden sonra açılan hesap: normal kurallar (kilit)', () {
    expect(askida(hesap: yeni, kesimi: kesim), isFalse);
    expect(askida(haklar: null, hesap: yeni, kesimi: kesim), isFalse);
  });

  test('eski hesap, hak satırı yok ya da okunamadı: kilit yok', () {
    expect(askida(hesap: eski, kesimi: kesim), isTrue);
    expect(askida(haklar: null, hesap: eski, kesimi: kesim), isTrue);
  });

  test('eski hesap, hediye verilmiş: kurallar hakka bakar', () {
    expect(askida(haklar: [hediye], hesap: eski, kesimi: kesim), isFalse);
    // Hediyesi biten hesap "satırı var" sayılır: kilit döner.
    expect(askida(haklar: [bitmis], hesap: eski, kesimi: kesim), isFalse);
  });

  test('kesim girilmemiş: satırsız kimse kilitlenmez (güvenli taraf)', () {
    expect(askida(hesap: yeni), isTrue);
    expect(askida(haklar: [bitmis], hesap: yeni), isFalse);
  });

  test("Remote Config biçimi: '+03' ofsetli tarih okunur", () {
    expect(DateTime.tryParse('2026-11-01T00:00:00+03'), kesim);
    expect(kesim.toUtc(), DateTime.utc(2026, 10, 31, 21));
  });
}
