import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/utils/chart_axis.dart';

/// Hisse GÜNLÜK ekseni seanstan başlar (yasin 2026-10-30, karar kartı
/// "Seanstan başlasın"); diğer türler 00:00'da kalır. Varlık detayı ve
/// varlık sayfası (`FiyatGrafigi` → `zamanEkseni`) aynı yardımcıdan okur.
void main() {
  test('yalnız hisse seanslı', () {
    expect(gunIciSeansli(AssetType.hisse), isTrue);
    for (final t in AssetType.values.where((t) => t != AssetType.hisse)) {
      expect(gunIciSeansli(t), isFalse, reason: t.name);
    }
  });

  test('sol uç: hissede ilk nokta (önceki kapanış), diğerlerinde 00:00', () {
    const onceki = 9 * 60 + 55.0; // 09:55
    expect(gunIciEksenBasiDk(onceki, seansli: true), onceki);
    expect(gunIciEksenBasiDk(onceki, seansli: false), 0);
    // Gün dışı ya da negatif ilk nokta (önceki günden taşan) → 00:00.
    expect(gunIciEksenBasiDk(-30, seansli: true), 0);
    expect(gunIciEksenBasiDk(1500, seansli: true), 0);
  });

  test('sağ uç: %82 kuralı sol uçtan; varsayılan eski formül', () {
    expect(gunIciEksenSonuDk(820), closeTo(1000, 1e-9));
    expect(gunIciEksenSonuDk(0), 240);
    // 09:55 → 15:00: pencere 305 dk, son nokta pencerenin %82'sinde.
    const bas = 595.0, son = 900.0;
    final sag = gunIciEksenSonuDk(son, basDk: bas);
    expect((son - bas) / (sag - bas), closeTo(0.82, 1e-9));
    expect(gunIciEksenSonuDk(bas, basDk: bas), bas + 240);
  });

  test('zamanEkseni: hissede pencere önceki kapanıştan, altında 00:00', () {
    final gun = DateTime(2026, 10, 30);
    final ilk = gun.add(const Duration(hours: 9, minutes: 55));
    final son = gun.add(const Duration(hours: 15));
    final hisse = zamanEkseni(
        ilkMs: ilk.millisecondsSinceEpoch.toDouble(),
        sonMs: son.millisecondsSinceEpoch.toDouble(),
        periodDays: 0,
        seansli: true);
    expect(hisse.min, ilk.millisecondsSinceEpoch.toDouble());
    // Tick tabanı yine gece yarısı: etiketler 10:00 · 11:00'e oturur.
    expect(hisse.baseline, gun.millisecondsSinceEpoch.toDouble());
    final altin = zamanEkseni(
        ilkMs: ilk.millisecondsSinceEpoch.toDouble(),
        sonMs: son.millisecondsSinceEpoch.toDouble(),
        periodDays: 0);
    expect(altin.min, gun.millisecondsSinceEpoch.toDouble());
    // Uzun dönemde seanslı bayrağı etkisiz.
    final yil = zamanEkseni(
        ilkMs: 0, sonMs: 365 * 86400000.0, periodDays: 365, seansli: true);
    expect(yil.min, 0);
  });
}
