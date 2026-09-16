import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/csv_import_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// CSV içe aktarma ekranı — "Önizle" butonunun etkinliği.
///
/// ## Ölçülen arıza (kullanıcı bildirimi, 2026-09-16)
/// Kullanıcı altı satırlık CSV'yi yapıştırdı, metin kutuda GÖRÜNÜYORDU ama
/// "Önizle" butonu gri/pasif kaldı ve içe aktarma hiç başlamadı.
///
/// Sebep: `TextField.onChanged` `setState`'i yalnızca `_result != null` iken
/// çağırıyordu. İlk yazışta `_result` zaten null olduğu için rebuild
/// tetiklenmiyor, buton `_ctrl.text` BOŞKEN hesaplanmış `onPressed: null`
/// hâliyle kalıyordu. Buton metnin kendisini okuduğu için her değişim bir
/// rebuild gerektiriyor.
void main() {
  // Tema uzantısı olmadan `context.c` patlar; ekranın kendi kabuğu bunu
  // gerektiriyor.
  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: const CsvImportScreen(),
        ),
      ),
    );
    await t.pump();
  }

  FilledButton onizleButonu(WidgetTester t) => t.widget<FilledButton>(
        find.ancestor(
          of: find.text('Önizle'),
          matching: find.byType(FilledButton),
        ),
      );

  testWidgets('boş kutuda Önizle PASİF', (t) async {
    await pump(t);
    expect(onizleButonu(t).onPressed, isNull);
  });

  testWidgets('metin girilince Önizle AKTİFLEŞİR — rebuild tetiklenmeli',
      (t) async {
    // Arızanın kendisi: eskiden bu adımdan sonra buton pasif kalıyordu.
    await pump(t);
    await t.enterText(find.byType(TextField), 'sembol;adet;fiyat;tarih\n'
        'KCHOL;500;185,00;21.01.2026');
    await t.pump();

    expect(onizleButonu(t).onPressed, isNotNull,
        reason: 'metin doluyken buton tıklanabilir olmalı');
  });

  testWidgets('Önizle satırları okur ve listeler', (t) async {
    await pump(t);
    await t.enterText(find.byType(TextField), 'sembol;adet;fiyat;tarih\n'
        'ALTIN_CEYREK;14;8950,00;12.11.2025\n'
        'KCHOL;500;185,00;21.01.2026');
    await t.pump();
    await t.tap(find.text('Önizle'));
    await t.pump();

    // Önizleme satırları `Text` olarak çizilir; metin kutusunun kendi
    // içeriği de aramaya takıldığı için `EditableText` hariç tutulur.
    Finder onizlemede(String s) => find.descendant(
          of: find.byType(ListView),
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').contains(s),
          ),
        );
    // Normalize edilmiş ticker önizlemede görünür (ham girdide `.IS` yok).
    expect(onizlemede('KCHOL.IS'), findsOneWidget);
    expect(onizlemede('ALTIN_CEYREK'), findsOneWidget);
    // Sepete ekle butonu sayıyı taşır.
    expect(find.textContaining('Sepete ekle (2)'), findsOneWidget);
  });

  testWidgets('metin silinince Önizle yeniden PASİF olur', (t) async {
    await pump(t);
    await t.enterText(find.byType(TextField), 'KCHOL;500;185,00;21.01.2026');
    await t.pump();
    expect(onizleButonu(t).onPressed, isNotNull);

    await t.enterText(find.byType(TextField), '');
    await t.pump();
    expect(onizleButonu(t).onPressed, isNull);
  });

  testWidgets('metin değişince eski önizleme TEMİZLENİR', (t) async {
    // Yapıştırılan yeni metne ait olmayan bir liste ekranda kalmamalı.
    await pump(t);
    await t.enterText(find.byType(TextField), 'KCHOL;500;185,00;21.01.2026');
    await t.pump();
    await t.tap(find.text('Önizle'));
    await t.pump();
    expect(find.textContaining('Sepete ekle'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'SAHOL;900;93,50;17.03.2026');
    await t.pump();
    expect(find.textContaining('Sepete ekle'), findsNothing,
        reason: 'önizleme artık girilen metne ait değil');
  });
}
