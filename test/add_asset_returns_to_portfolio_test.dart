import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Varlık ekledikten sonra **Portföy sekmesine** dönülmeli.
///
/// Kullanıcı bildirimi (2026-08-10): "toplu eklemeden sonra ana sayfaya
/// atıyor, Portföy ekranına atmalıydı — tekli eklemede yaptığı gibi".
///
/// İnceleme, bildirimden biraz farklı bir tablo gösterdi: **hiçbir akış
/// sekme değiştirmiyordu.** `_showAddAsset()` sonucu yok sayıyor, kullanıcı
/// FAB'a hangi sekmeden bastıysa oraya dönüyordu.
///
/// Tekli eklemede sorun fark edilmiyordu çünkü kullanıcı çoğunlukla zaten
/// Portföy'deyken FAB'a basıyor — "geri dönmüş" olmak "Portföy'e gitmiş"
/// gibi görünüyordu. Ana sekmedeyken tekli ekleme de aynı hatayı yapıyordu.
///
/// İki parça birlikte gerekiyor:
///   1. `AddAssetScreen._save()` sonuç olarak `true` döndürmeli
///      (eskiden sonuçsuz `pop` ediyordu → sinyal kayboluyordu),
///   2. `_showAddAsset()` bu sonucu okuyup Portföy sekmesine geçmeli.
///
/// Biri olmadan diğeri işe yaramaz; test ikisini de kilitler.
///
/// Not: `MainNavigationScreen` widget testinde ayağa kaldırılamıyor —
/// Supabase, bildirim izni ve 5 ekranın provider zinciri gerekiyor. Bu
/// yüzden denetim kaynak üzerinden yapılır.
void main() {
  late String nav;
  late String add;
  late String bulk;

  setUpAll(() {
    String read(String p) => File(p)
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    nav = read('lib/screens/main_navigation_screen.dart');
    add = read('lib/screens/add_asset_screen.dart');
    bulk = read('lib/screens/bulk_add_asset_screen.dart');
  });

  test('_showAddAsset sonucu OKUR — yok saymaz', () {
    expect(
      RegExp(r'await pushGuarded<bool>\(').hasMatch(nav),
      isTrue,
      reason: 'Sonuç tipi belirtilmezse `added` daima null olur ve sekme '
          'geçişi hiç çalışmaz.',
    );
  });

  test('kayıt başarılıysa Portföy sekmesine geçilir', () {
    expect(
      RegExp(r'added == true').hasMatch(nav),
      isTrue,
      reason: 'Kayıt sinyali kontrol edilmeli.',
    );
    expect(
      RegExp(r'_currentIndex = _portfolioTab').hasMatch(nav),
      isTrue,
      reason: 'Sekme Portföy\'e alınmalı.',
    );
  });

  test('Portföy sekmesi indeksi ekran sırasıyla tutarlı', () {
    // `_screens`: 0=Home, 1=Charts(Portföy), 2=FAB, 3=Performans, 4=Profil
    final m = RegExp(r'_portfolioTab\s*=\s*(\d+)').firstMatch(nav);
    expect(m, isNotNull, reason: 'İndeks adlandırılmış sabit olmalı.');
    expect(m!.group(1), '1',
        reason: 'Portföy `_screens` listesinde ikinci sırada (ChartsScreen). '
            'Sıra değişirse bu sabit de değişmeli.');

    // Alt barda 1. indeks gerçekten "Portföy" etiketli mi?
    expect(
      RegExp(r"_navItem\(1,[^)]*'Portföy'\)").hasMatch(nav),
      isTrue,
      reason: 'Sekme sırası değişmiş olabilir.',
    );
  });

  test('AddAssetScreen kayıt sonrası `true` döndürür', () {
    expect(
      RegExp(r'Navigator\.pop\(context,\s*true\)').allMatches(add).length,
      greaterThanOrEqualTo(2),
      reason: 'Hem `_save()` hem hızlı giriş kaydı sinyal döndürmeli. '
          'Sonuçsuz `pop` sinyali yutar ve sekme geçişi sessizce çalışmaz.',
    );
  });

  test('sepet modu sinyal SIZDIRMAZ', () {
    // Sepete ekleme `BulkAddAssetScreen`'e döner, MainNav'a değil.
    // `true` döndürürse yanlışlıkla sekme geçişi tetiklenebilir.
    final cartBlock = RegExp(
      r'if \(widget\.cartMode\)[\s\S]{0,900}?return;',
    ).firstMatch(add);
    expect(cartBlock, isNotNull, reason: 'Sepet modu dalı bulunamadı.');
    expect(
      RegExp(r'pop\(true\)|pop\(context,\s*true\)')
          .hasMatch(cartBlock!.group(0)!),
      isFalse,
      reason: 'Sepete ekleme bir KAYIT değildir; sinyal döndürmemeli.',
    );
  });

  test('toplu ekleme zinciri korunur', () {
    // BulkAdd -> true -> AddAsset kendini kapatır -> MainNav sekmeyi çevirir.
    expect(RegExp(r'Navigator\.of\(context\)\.pop\(true\)').hasMatch(bulk),
        isTrue,
        reason: 'Toplu ekleme başarıda `true` döndürmeli.');
    expect(
      RegExp(r'added == true && context\.mounted[\s\S]{0,120}?pop\(true\)')
          .hasMatch(add),
      isTrue,
      reason: 'AddAssetScreen, BulkAdd sonucunu YUKARI taşımalı; yoksa '
          'zincir kopar ve MainNav sinyali hiç görmez.',
    );
  });
}
