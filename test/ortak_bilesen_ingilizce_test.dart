import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/l10n/l10n.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';
import 'package:portfoy_takip/utils/sandik_snack.dart';
import 'package:portfoy_takip/widgets/sandik_error_view.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ortak bileşen metinleri seçilen dilde (rapor 2026-11-08 02:30 #3).
///
/// İngilizce seçen kullanıcı "Geri al", "Tekrar dene", ekran okuyucunun
/// "Yükleniyor"u ve genel hata metinlerini Türkçe görüyordu. Türkçe
/// kullanıcı için metinler BİREBİR aynı kalmalı: bağlamsız `friendlyError`
/// eski Türkçe metni döndürür.
void main() {
  Widget uygulama(Locale dil, Widget govde) => MaterialApp(
        locale: dil,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: govde),
      );

  testWidgets('İngilizce: hata görünümü İngilizce metin ve düğme', (t) async {
    await t.pumpWidget(uygulama(
      const Locale('en'),
      SandikErrorView(
          error: const SocketException('Failed host lookup'), onRetry: () {}),
    ));
    await t.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text(AppLocalizationsEn().hataBaglanti), findsOneWidget);
    expect(find.text('Tekrar dene'), findsNothing);
    expect(find.text(kBaglantiHatasiMesaji), findsNothing);
  });

  testWidgets('İngilizce: snack "Undo" ve İngilizce hata nedeni', (t) async {
    await t.pumpWidget(uygulama(
      const Locale('en'),
      Builder(
        builder: (context) => Column(children: [
          TextButton(
            onPressed: () => sandikSnack(context, 'x', onUndo: () {}),
            child: const Text('geri'),
          ),
          TextButton(
            onPressed: () => sandikSnackError(context, TimeoutException('t')),
            child: const Text('hata'),
          ),
        ]),
      ),
    ));
    await t.tap(find.text('geri'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Geri al'), findsNothing);

    await t.tap(find.text('hata'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text(AppLocalizationsEn().hataBaglanti), findsOneWidget);
  });

  testWidgets('İngilizce: iskeletin ekran okuyucu etiketi', (t) async {
    final handle = t.ensureSemantics();
    await t
        .pumpWidget(uygulama(const Locale('en'), const SandikSkeletonList()));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    expect(find.bySemanticsLabel('Yükleniyor'), findsNothing);
    handle.dispose();
  });

  testWidgets('Türkçe: metinler aynı kalır', (t) async {
    await t.pumpWidget(uygulama(
      const Locale('tr'),
      SandikErrorView(error: TimeoutException('t'), onRetry: () {}),
    ));
    await t.pumpAndSettle();
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.text(kBaglantiHatasiMesaji), findsOneWidget);
  });

  group('bağlamsız friendlyError Türkçe ve bayt bayt eski metin', () {
    // Bu metinler 2026-11-08 öncesi koddaki literallerdir; .arb'a
    // taşınırken değişmemeleri gerekir (eski testler ve kullanıcı alışkanlığı).
    test('genel mesajlar', () {
      expect(friendlyError(null), 'Bilinmeyen bir hata oluştu.');
      expect(friendlyError(const SocketException('x')), kBaglantiHatasiMesaji);
      expect(kBaglantiHatasiMesaji, AppLocalizationsTr().hataBaglanti);
      expect(friendlyError(const FormatException('x')),
          'Sunucudan gelen veri okunamadı.');
      expect(
          friendlyError(const PostgrestException(message: 'x', code: '23505')),
          'Bu kayıt zaten var.');
      expect(
          friendlyError(const PostgrestException(message: 'x', code: '42501')),
          'Bu işlem için yetkin yok.');
      expect(friendlyError(const PostgrestException(message: 'x', code: '1')),
          'Veri işlemi başarısız oldu.');
      expect(
          friendlyError(StorageException('x')), 'Dosya işlemi başarısız oldu.');
      expect(friendlyError(AuthException('JWT expired')),
          'Oturumun süresi doldu. Tekrar giriş yap.');
      expect(friendlyError(AuthException('rate limit')),
          'Çok fazla deneme. Lütfen birkaç dakika sonra tekrar dene.');
      expect(friendlyError(AuthException('weird')),
          'İşlem tamamlanamadı. Biraz sonra tekrar dene.');
      expect(friendlyError(Exception('weird')),
          'Bir şeyler ters gitti, tekrar dene.');
    });

    test('İngilizce sözlük verilince İngilizce', () {
      final en = AppLocalizationsEn();
      expect(friendlyError(null, l10n: en), en.hataBilinmeyen);
      expect(friendlyError(Exception('weird'), l10n: en), en.hataGenel);
      expect(friendlyError(AuthException('JWT expired'), l10n: en),
          en.hataOturumDoldu);
    });
  });
}
