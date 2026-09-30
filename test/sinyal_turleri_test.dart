import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';

/// Sinyal ayarları her varlık türünü kapsar (kullanıcı kuralı, 2026-09-28):
/// "kripto ve eklenecek tüm yeni varlık kategorileri için sinyal ayarları
/// sekmesi de olmalı". Kripto eklenirken ayar ekranından elle çıkarılmıştı,
/// çünkü sunucu analizi (`analyze-signals` ANALYZABLE) onu tanımıyordu.
///
/// Bu test iki tarafı birbirine bağlar: yeni bir `AssetType` eklenip sunucu
/// kümesi güncellenmezse kırılır. `diger` elle fiyatlanır, seri yoktur.
/// `mevduat` (2026-09-30) piyasa serisi taşımaz — değeri sözleşmenin
/// tahakkukudur, teknik sinyal anlamsızdır; ayar ekranında da görünmez.
void main() {
  test('sunucu ANALYZABLE = tüm AssetType\'lar (diger ve mevduat hariç)', () {
    final src =
        File('supabase/functions/analyze-signals/index.ts').readAsStringSync();
    final m = RegExp(r"ANALYZABLE = new Set\(\[([^\]]*)\]\)").firstMatch(src);
    expect(m, isNotNull, reason: 'ANALYZABLE tanımı bulunamadı');
    final sunucu = RegExp(r"'(\w+)'")
        .allMatches(m!.group(1)!)
        .map((e) => e.group(1)!)
        .toSet();
    final istemci = {
      for (final t in AssetType.values)
        if (t != AssetType.diger && t != AssetType.mevduat) t.name,
    };
    expect(sunucu, istemci,
        reason: 'Yeni tür eklendiyse analyze-signals ANALYZABLE ve seri '
            'kaynağı (price_history.ts) da güncellenmeli.');
  });

  test('ayar ekranı türleri elle süzmez', () {
    final src =
        File('lib/screens/signal_settings_screen.dart').readAsStringSync();
    expect(src.contains('for (final type in AssetType.values)'), isTrue);
    expect(src.contains('t != AssetType.kripto'), isFalse);
  });
}
