import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'helpers/kaynak.dart';

/// Varlık silmede "Geri al" (Faz 2.10).
///
/// Silme yumuşaktır (`deleted_at`) ve bir mezar taşı ekler; geri alma tam
/// tersini yapmalı: damga temizlenir, mezar taşı fiziksel silinir. Provider
/// Supabase istediği için akış kaynak denetimiyle kilitlenir (projede aynı
/// örüntü: onboarding_tour_test "akış korundu").
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

  test('diyalog "Geri al" sunar ve hatayı sebebiyle söyler', () {
    expect(dialog.contains('onUndo:'), isTrue);
    expect(dialog.contains('restorePositionLots(kayit)'), isTrue);
    // 3.20: metin sözlükte.
    expect(dialog.contains('prefix: context.l10n.undoFailed'), isTrue);
    expect(trMetni('undoFailed'), contains('Geri alınamadı'));
  });
}
