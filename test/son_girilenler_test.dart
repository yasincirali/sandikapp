import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/screens/all_transactions_screen.dart';

/// Ana sayfa "Portföy Hareketleri" akışı giriş anına göre (2026-10-03).
///
/// Kullanıcı bildirimi: "dosyayla eklenenler portföyde var, hareketlerde
/// yok". Ekstreden gelen kalem ekstrenin tarihini taşır; akış işlem
/// tarihine göre ilk 3'ü gösterdiği için hiç görünmüyordu.
Asset _kayit(String id, {required DateTime tarih, DateTime? girildi}) => Asset(
      id: id,
      userId: 'u1',
      name: id,
      ticker: 'TEFAS:$id',
      type: AssetType.fon,
      quantity: 10,
      purchasePrice: 5,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      addedDate: tarih,
      createdAt: girildi,
    );

void main() {
  test('geçmiş tarihli içe aktarma, girildiği an en üstte', () {
    final dunku = _kayit('DUN',
        tarih: DateTime(2026, 10, 2), girildi: DateTime(2026, 10, 2, 9));
    final ice = _kayit('IJC',
        tarih: DateTime(2026, 5, 31), girildi: DateTime(2026, 10, 3, 1));
    expect(sonGirilenler([dunku, ice]).map((a) => a.id), ['IJC', 'DUN']);
  });

  test('0095 öncesi satır (createdAt yok) işlem tarihiyle sıralanır', () {
    // 0095 eski satırlara created_at = added_date yazdı; yerelde null
    // gelen kopya aynı yere düşmeli — eski akışın sırası değişmez.
    final eski = _kayit('ESKI', tarih: DateTime(2026, 9, 1));
    final yeni = _kayit('YENI',
        tarih: DateTime(2026, 9, 20), girildi: DateTime(2026, 9, 20));
    expect(sonGirilenler([eski, yeni]).map((a) => a.id), ['YENI', 'ESKI']);
  });

  test('aynı anda girilenler işlem tarihine göre (toplu kayıt)', () {
    final an = DateTime(2026, 10, 3, 1);
    final r = sonGirilenler([
      _kayit('A', tarih: DateTime(2026, 5, 1), girildi: an),
      _kayit('B', tarih: DateTime(2026, 5, 31), girildi: an),
    ]);
    expect(r.map((a) => a.id), ['B', 'A']);
  });

  test('girdiyi değiştirmez (Tüm Hareketler defteri ayrı sırayı korur)', () {
    final l = [
      _kayit('X', tarih: DateTime(2026, 9, 1), girildi: DateTime(2026, 9, 1)),
      _kayit('Y', tarih: DateTime(2026, 5, 1), girildi: DateTime(2026, 10, 1)),
    ];
    sonGirilenler(l);
    expect(l.map((a) => a.id), ['X', 'Y']);
  });
}
