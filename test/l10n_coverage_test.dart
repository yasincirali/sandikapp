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
///
/// TAVANA HİÇ ALINMAYANLAR (ve nedeni):
///   · `legal_doc_screen` — yasal metinlerin kendisi; çevirisi hukuk işi.
///   · `push_diagnostics_screen` — yalnız admin'e görünen teşhis aracı.
///   · `asset_categories` — alt kategori etiketleri `sub_category` sütununda
///     VERİ olarak saklanıyor; çevirmek kayıtlı satırları bozar.
///   · `onboarding_screen` — tanıtım turu metinleri, sonraki tur.
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
    'lib/models/asset.dart': 0,
    'lib/models/position.dart': 0,
    'lib/models/price_alert.dart': 0,
    'lib/models/signal_alert.dart': 0,
    'lib/models/signal_preference.dart': 0,
    'lib/models/technical_signal.dart': 0,
    'lib/models/tefas_nav_gozlem.dart': 0,
    'lib/models/user_model.dart': 0,
    'lib/models/watchlist_item.dart': 0,
    'lib/models/yatirimci_seviyesi.dart': 0,
    'lib/screens/add_watchlist_screen.dart': 0,
    'lib/screens/asset_detail/eylemler.dart': 0,
    'lib/screens/csv_import_screen.dart': 0,
    'lib/screens/disclaimer_acceptance_screen.dart': 0,
    'lib/screens/forgot_password_screen.dart': 0,
    'lib/screens/lock_screen.dart': 0,
    'lib/screens/login_screen.dart': 0,
    'lib/screens/main_navigation_screen.dart': 0,
    'lib/screens/otp_verification_screen.dart': 0,
    'lib/screens/partnership_requests_screen.dart': 0,
    'lib/screens/portfolio_performance/kontroller.dart': 0,
    'lib/screens/portfolio_performance/seriler.dart': 0,
    'lib/screens/portfolio_performance/yardimci_widgetlar.dart': 0,
    'lib/screens/recap_screen.dart': 0,
    'lib/screens/watchlist_detail_screen.dart': 0,
    'lib/widgets/alarm_kur_sheet.dart': 0,
    'lib/widgets/asset_sparkline.dart': 0,
    'lib/widgets/chart_fullscreen_chip.dart': 0,
    'lib/widgets/disclaimer_widget.dart': 0,
    'lib/widgets/fullscreen_chart_route.dart': 0,
    'lib/widgets/grafik_tipi_secici.dart': 0,
    'lib/widgets/h_scroll_with_fade.dart': 0,
    'lib/widgets/milestone_sheet.dart': 0,
    'lib/widgets/modern_tab_selector.dart': 0,
    'lib/widgets/percentile_strip.dart': 0,
    'lib/widgets/portfolio_summary_widget.dart': 0,
    'lib/widgets/sandik_app_bar.dart': 0,
    'lib/widgets/sandik_async_button.dart': 0,
    'lib/widgets/sandik_error_view.dart': 0,
    'lib/widgets/social_sign_in_buttons.dart': 0,
    'lib/widgets/tour_anchor.dart': 0,
    'lib/widgets/transaction_row.dart': 0,
    'lib/widgets/transaction_segment.dart': 0,
    'lib/widgets/watchlist_chart.dart': 0,
    'lib/widgets/weekly_summary_chip.dart': 0,
    'lib/widgets/widget_install_sheet.dart': 0,
    'lib/widgets/zoom_data_controller.dart': 0,
    'lib/screens/all_transactions_screen.dart': 1,
    'lib/screens/asset_not_found_screen.dart': 1,
    'lib/screens/portfolio_performance/tur_dokumu_karti.dart': 1,
    'lib/screens/portfolio_performance_screen.dart': 1,
    'lib/screens/portfolio_screen.dart': 1,
    'lib/widgets/alarm_seridi.dart': 1,
    'lib/widgets/bar_interval_selector.dart': 1,
    'lib/widgets/custom_loading_indicator.dart': 1,
    'lib/widgets/delete_asset_dialog.dart': 1,
    'lib/widgets/dividend_dialog.dart': 1,
    'lib/widgets/quick_adjust_dialog.dart': 1,
    'lib/widgets/real_return_strip.dart': 1,
    'lib/screens/asset_detail/sinyal_widgetlari.dart': 2,
    'lib/screens/portfolio_performance/ozet_yan_veri.dart': 2,
    'lib/screens/price_alerts_screen.dart': 2,
    'lib/widgets/percent_comparison_chart.dart': 2,
    'lib/widgets/sandik_skeleton.dart': 2,
    'lib/widgets/zoomable_chart.dart': 2,
    'lib/models/grafik_tipi.dart': 3,
    'lib/screens/asset_detail/karsilastirma_secici.dart': 3,
    'lib/screens/bulk_add_asset_screen.dart': 3,
    'lib/screens/home_screen.dart': 3,
    'lib/screens/leaderboard_screen.dart': 3,
    'lib/screens/portfolio_performance/grafik_kabi.dart': 3,
    'lib/screens/portfolio_performance/kartlar.dart': 3,
    'lib/widgets/period_summary_view.dart': 3,
    'lib/widgets/share_card.dart': 3,
    'lib/screens/asset_detail/seritler.dart': 4,
    'lib/widgets/leaderboard_hero_card.dart': 5,
    'lib/models/signal_frequency.dart': 7,
    'lib/screens/paywall_screen.dart': 7,
    'lib/screens/asset_detail_screen.dart': 8,
    'lib/screens/watchlist_screen.dart': 8,
    'lib/models/asset_type.dart': 9,
    'lib/screens/settings_screen.dart': 12,
    'lib/screens/profile_screen.dart': 14,
    'lib/screens/signal_settings_screen.dart': 19,
    'lib/screens/add_asset_screen.dart': 20,
    'lib/screens/comparison_screen.dart': 23,
    'lib/screens/register_screen.dart': 25,
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
