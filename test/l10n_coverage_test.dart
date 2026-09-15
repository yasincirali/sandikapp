import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// İngilizce arayüz kapsamı — ratchet (3.20).
///
/// Çevrilmiş ekranlarda Türkçe harf içeren string literal sayısı buradaki
/// tavanın ÜSTÜNE çıkamaz: yeni metin `context.l10n` ile gelir, ham literal
/// olarak değil. Sayılar yalnızca AZALABİLİR; azaldıkça tavan da indirilir
/// (design_token_ratchet ile aynı disiplin).
///
/// Kalan literal'ler bilinçli: yasal metinler, teşhis/geliştirici araçları,
/// hata-nedeni dizeleri (`reason:`), analitik olay adları ve henüz
/// çevrilmemiş alt bölümler (kapsam listesi `docs/YOL_HARITASI_ILERLEME.md`
/// 3.20 satırında).
void main() {
  final tr = RegExp("'[^']*[çğıöşüÇĞİÖŞÜ][^']*'");

  int say(String yol) {
    var n = 0;
    for (final satir in File(yol).readAsLinesSync()) {
      final t = satir.trimLeft();
      if (t.startsWith('//') || t.startsWith('///')) continue;
      n += tr.allMatches(satir).length;
    }
    return n;
  }

  const tavan = <String, int>{
    'lib/screens/login_screen.dart': 0,
    'lib/screens/lock_screen.dart': 0,
    'lib/screens/main_navigation_screen.dart': 0,
    'lib/screens/disclaimer_acceptance_screen.dart': 0,
    'lib/screens/forgot_password_screen.dart': 0,
    'lib/screens/otp_verification_screen.dart': 0,
    'lib/screens/portfolio_screen.dart': 1,
    'lib/screens/portfolio_performance_screen.dart': 1,
    'lib/screens/portfolio_performance/grafik_kabi.dart': 3,
    'lib/screens/portfolio_performance/ozet_yan_veri.dart': 2,
    'lib/screens/home_screen.dart': 3,
    'lib/screens/asset_detail/seritler.dart': 4,
    'lib/screens/asset_detail/karsilastirma_secici.dart': 3,
    'lib/screens/price_alerts_screen.dart': 4,
    'lib/screens/paywall_screen.dart': 7,
    'lib/screens/watchlist_screen.dart': 8,
    'lib/screens/asset_detail_screen.dart': 8,
    'lib/screens/portfolio_performance/tur_dokumu_karti.dart': 10,
    // Tür adları ve sembol ipuçları sözlükte; `label` alanı TÜRKÇE kalır
    // (bildirim/özet/paylaşım metinleri ve alt kategori karşılaştırmaları
    // onu veri gibi kullanıyor — bkz. `AssetType.labelOf`).
    'lib/models/asset_type.dart': 12,
    'lib/screens/all_transactions_screen.dart': 13,
    'lib/screens/profile_screen.dart': 14,
    'lib/screens/recap_screen.dart': 14,
    'lib/screens/portfolio_performance/kartlar.dart': 14,
    'lib/screens/leaderboard_screen.dart': 19,
    'lib/screens/add_asset_screen.dart': 21,
    // Yasal metin blokları (KVKK, açık rıza) bilinçli Türkçe.
    'lib/screens/register_screen.dart': 25,
    'lib/screens/comparison_screen.dart': 25,
    'lib/widgets/period_summary_view.dart': 34,
    // Kalan: Canlı Etkinlik alt bölümü ve teşhis/geliştirici araçları.
    'lib/screens/settings_screen.dart': 39,
  };

  for (final e in tavan.entries) {
    test('${e.key}: Türkçe literal ≤ ${e.value}', () {
      final n = say(e.key);
      expect(n, lessThanOrEqualTo(e.value),
          reason: '${e.key} içinde $n Türkçe literal var; yeni metin '
              'context.l10n ile eklenmeli. Tavan düştüyse burayı da indir.');
    });
  }
}
