import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Yorumları atarak okur.
///
/// Kaldırılan toast'ların gerekçesi kaynakta YORUM olarak duruyor ("önceden
/// … takipten çıkarıldı toast'ı çıkıyordu") — karar kaydı üslubu gereği.
/// Ham metinde arayan bir test kendi açıkladığı cümleyi yakalayıp sahte
/// kırılır. Yalnızca çalışan koda bak.
String _kod(String yol) => ekranKaynagiSync(yol)
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///');
    })
    .join('\n');

/// Kaldırılan başarı toast'ları geri GELMESİN (kullanıcı kararı, 2026-09-16).
///
/// ## Neden bu test var
///
/// Kullanıcı uygulamadaki 31 toast'ı tek tek gözden geçirdi ve sekizini
/// gereksiz buldu. Ortak gerekçe: **işlem sonrası ekran zaten değişiyor.**
/// Diyalog kapanıyor, satır listeden düşüyor, sepet doluyor ya da sistem
/// paylaşım sayfası açılıyor — onay kullanıcının gözünün önünde. Toast bunun
/// üstüne ikinci bir onay koyuyor, alt menüyü kapatıyor ve kapanmasını
/// beklemek gerekiyordu.
///
/// Bu tür "gereksiz bildirim" temizlikleri kalıcı olmuyor: sonraki bir
/// özellik eklerken yanına refleksle `sandikSnack(... success)` yazılıyor ve
/// karar sessizce geri alınıyor. Test kararı kaynakta kilitliyor.
///
/// ## Kilitlenmeyen şey: HATA yolları
///
/// Kaldırılanların hepsi BAŞARI (ya da başarıya bağlı geri alma) toast'ı.
/// Hata toast'ları yerinde duruyor ve durmalı — sessiz başarısızlık en kötü
/// seçenek. Aşağıdaki ikinci grup tam da onu kilitliyor: temizlik hataları
/// da süpürmüş olmasın.
void main() {
  // ── Kaldırılan sekiz başarı toast'ı ────────────────────────────────────

  test('#3 hızlı al/sat "alındı/satıldı" toast\'ı göstermez', () {
    final src = _kod('lib/widgets/quick_adjust_dialog.dart');
    expect(src.contains('boughtAmount'), isFalse);
    expect(src.contains('soldAmount'), isFalse);
    expect(src.contains('sandikSnack'), isFalse,
        reason: 'Sheet kapanıyor ve miktar arkadaki listede değişiyor.');
  });

  test('#4 temettü "kaydedildi" toast\'ı göstermez', () {
    final src = _kod('lib/widgets/dividend_dialog.dart');
    expect(src.contains('dividendSaved'), isFalse);
    expect(src.contains('sandikSnack'), isFalse,
        reason: 'Diyalog kapanıyor, temettü hareket listesine düşüyor.');
  });

  test('#25 CSV "satır sepete eklendi" toast\'ı göstermez', () {
    final src = _kod('lib/screens/csv_import_screen.dart');
    expect(src.contains('csvRowsAddedToCart'), isFalse);
    expect(src.contains('sandikSnack'), isFalse,
        reason: 'Sepet ekranı açılıyor, satırlar orada listeleniyor.');
  });

  test('#27 dışa aktarmada "hazırlandı" toast\'ı göstermez', () {
    final src = _kod('lib/screens/settings_screen.dart');
    expect(src.contains('context.l10n.dataExported'), isFalse,
        reason: 'Sistem paylaşım sayfası açılıyor; toast onun ARKASINDA '
            'kalıyordu.');
  });

  test('#8 takibe alındı toast\'ı göstermez', () {
    final src = _kod('lib/screens/add_watchlist_screen.dart');
    expect(src.contains('addedToWatchlist'), isFalse,
        reason: 'Satırdaki "+" ikonu eklendi durumuna geçiyor.');
  });

  test('#5/#6 varlık silmede başarı ve geri alma toast\'ı yok', () {
    final src = _kod('lib/widgets/delete_asset_dialog.dart');
    expect(src.contains('assetDeleted'), isFalse);
    expect(src.contains('undoFailed'), isFalse);
    expect(src.contains('onUndo:'), isFalse,
        reason: 'Silme zaten onay diyaloğunun arkasında.');
  });

  test('#11 takipten çıkarmada başarı ve geri alma toast\'ı yok', () {
    final src = _kod('lib/screens/watchlist_screen.dart');
    expect(src.contains('takipten çıkarıldı'), isFalse);
    expect(src.contains('onUndo:'), isFalse,
        reason: 'Sembol arama ekranından tek dokunuşla geri eklenebiliyor.');
  });

  // ── Korunan hata yolları ───────────────────────────────────────────────
  //
  // Temizlik başarıyı aldı, hatayı ALMADI. Bir işlem başarısız olduğunda
  // kullanıcı bunu öğrenmeli: satırın sessizce geri gelmesi ya da kaydın
  // hiç oluşmaması "uygulama bozuk" hissi verir.

  test('silme BAŞARISIZ olursa hâlâ söylenir', () {
    final src = _kod('lib/widgets/delete_asset_dialog.dart');
    expect(src.contains("sandikSnackError(context, e, prefix: 'Silinemedi')"),
        isTrue);
  });

  test('takipten çıkarma BAŞARISIZ olursa hâlâ söylenir', () {
    final src = _kod('lib/screens/watchlist_screen.dart');
    expect(src.contains('Takipten çıkarılamadı'), isTrue);
    expect(src.contains('SandikSnackKind.error'), isTrue);
  });

  test('takip limiti ve çakışma hâlâ söylenir — çıkış yolu gösterilir', () {
    final src = _kod('lib/screens/add_watchlist_screen.dart');
    expect(src.contains('watchlistLimitFree'), isTrue,
        reason: 'Limit hatası çıkışsız bırakmamalı: Premium eylemi kalır.');
    expect(src.contains('Eklenemedi. Zaten takipte olabilir.'), isTrue);
  });

  test('dışa aktarma ve ayar hataları hâlâ söylenir', () {
    final src = _kod('lib/screens/settings_screen.dart');
    expect(src.contains('showAppError(context, e)'), isTrue,
        reason: 'Dışa aktarma hatası dialogla söyleniyor.');
    expect(src.contains('Ayar kaydedilemedi, tekrar dene.'), isTrue);
  });

  test('hızlı al/sat ve temettü hataları diyalog İÇİNDE kalır', () {
    // Bu ikisinde hata toast değil, `_error` alanı — diyalog kapanmadığı
    // için kullanıcı girdisini düzeltebiliyor. Toast'ı kaldırmak bu yolu
    // bozmamalı.
    final quick = _kod('lib/widgets/quick_adjust_dialog.dart');
    expect(quick.contains('transactionFailed'), isTrue);
    final div = _kod('lib/widgets/dividend_dialog.dart');
    expect(div.contains('Kaydedilemedi.'), isTrue);
  });

  // ── Geri alma YETENEĞİ (UI girişi gitti, sunucu yolu durdu) ────────────

  test('provider geri alma yeteneğini KORUR', () {
    // UI girişi kaldırıldı ama silme yumuşak; geri alma tekrar istendiğinde
    // sıfırdan yazılmasın. Ayrıntı: delete_position_undo_test.
    final src = _kod('lib/providers/portfolio_provider.dart');
    expect(src.contains('restorePositionLots'), isTrue);
  });
}
