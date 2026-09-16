import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Varlık silmede geri alma YETENEĞİ (Faz 2.10).
///
/// Silme yumuşaktır (`deleted_at`) ve bir mezar taşı ekler; geri alma tam
/// tersini yapmalı: damga temizlenir, mezar taşı fiziksel silinir. Provider
/// Supabase istediği için akış kaynak denetimiyle kilitlenir (projede aynı
/// örüntü: onboarding_tour_test "akış korundu").
///
/// ## 2026-09-16: UI girişi kaldırıldı, YETENEK korundu
///
/// Kullanıcı silme sonrası "Varlık silindi" + "Geri al" toast'ını gereksiz
/// buldu (silme zaten onay diyaloğunun arkasında). Toast kaldırıldı, ama
/// `deletePositionLots` makbuzu döndürmeye ve `restorePositionLots` geri
/// almaya DEVAM ediyor. Bu testin amacı da değişti: artık "diyalog Geri al
/// sunuyor mu"yu değil, "sunucu tarafı geri alma yolu hâlâ sağlam mı"yı
/// kilitliyor. Yetenek bozulursa geri alma tekrar istendiğinde sessizce
/// yarım çalışan bir şey bulunur.
void main() {
  final provider =
      File('lib/providers/portfolio_provider.dart').readAsStringSync();
  final service =
      File('lib/services/supabase_service.dart').readAsStringSync();
  final dialog = File('lib/widgets/delete_asset_dialog.dart').readAsStringSync();

  test('silme bir makbuz döner, geri alma onu tüketir', () {
    expect(
        provider.contains(
            'Future<SilinenPozisyon?> deletePositionLots(List<Asset> lots)'),
        isTrue);
    expect(
        provider.contains(
            'Future<void> restorePositionLots(SilinenPozisyon kayit)'),
        isTrue);
  });

  test('geri alma damgayı temizler VE mezar taşını siler', () {
    expect(service.contains("update({'deleted_at': null})"), isTrue,
        reason: 'restoreAssets damgayı temizlemeli.');
    // Sıfır satır → hata: softDeleteAssets ile aynı doğrulama.
    final restore = service.substring(service.indexOf('restoreAssets('));
    expect(restore.substring(0, 900).contains('rows.isEmpty'), isTrue,
        reason: 'Sessiz sıfır satır güncellemesi "geri alındı" yalanı olur.');
    final geri = provider.substring(provider.indexOf('restorePositionLots('));
    expect(geri.substring(0, 1200).contains('deleteAsset(logId)'), isTrue,
        reason: 'Mezar taşı kalırsa hareket listesinde olmamış bir silme durur.');
  });

  test('diyalog başarı/geri alma toast\'ı GÖSTERMEZ', () {
    // Kullanıcı kararı 2026-09-16. Onay diyaloğu zaten kazara silmeyi
    // engelliyor; silme sonrası ikinci bir bildirim fazlalıktı.
    expect(dialog.contains('onUndo:'), isFalse,
        reason: 'Silme sonrası "Geri al" toast\'ı kaldırıldı.');
    expect(dialog.contains('context.l10n.assetDeleted'), isFalse,
        reason: '"Varlık silindi" başarı toast\'ı kaldırıldı.');
  });

  test('BAŞARISIZ silme hâlâ sebebiyle söylenir', () {
    // Sessiz başarısızlık kalmadı: kullanıcı sildiğini sanıp uygulamayı
    // açtığında kaydı geri görürse uygulamaya güveni sarsılır.
    expect(dialog.contains("prefix: 'Silinemedi'"), isTrue);
  });
}
