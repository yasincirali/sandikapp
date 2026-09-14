import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/l10n.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';

/// İngilizce arayüz altyapısı (3.20).
///
/// Sabitlenen kurallar:
///   1. `app_tr.arb` ile `app_en.arb` aynı anahtar kümesini taşır — eksik
///      çeviri derlemede değil burada yakalanır (gen-l10n eksik anahtarda
///      şablon dilini basar, sessizce Türkçe sızar).
///   2. `context.l10n` delegate yokken TÜRKÇE'ye düşer: 155+ widget testi
///      delegate'siz `MaterialApp` kuruyor, hiçbiri kırılmamalı.
///   3. Delegate + `Locale('en')` ile gerçekten İngilizce gelir.
///   4. `LocaleNotifier.parse/encode` gidiş-dönüş; bilinmeyen değer Türkçe.
void main() {
  Map<String, dynamic> arb(String yol) =>
      json.decode(File(yol).readAsStringSync()) as Map<String, dynamic>;
  Set<String> anahtarlar(Map<String, dynamic> m) =>
      m.keys.where((k) => !k.startsWith('@')).toSet();

  group('ARB paritesi', () {
    test('tr ve en aynı anahtarları taşır', () {
      final tr = anahtarlar(arb('lib/l10n/app_tr.arb'));
      final en = anahtarlar(arb('lib/l10n/app_en.arb'));
      expect(en.difference(tr), isEmpty, reason: 'en fazladan anahtar');
      expect(tr.difference(en), isEmpty, reason: 'en\'de çevrilmemiş anahtar');
    });

    test('hiçbir değer boş değil (otpSentSuffix hariç — bilinçli boş)', () {
      for (final yol in ['lib/l10n/app_tr.arb', 'lib/l10n/app_en.arb']) {
        final m = arb(yol);
        for (final e in m.entries) {
          if (e.key.startsWith('@')) continue;
          if (e.key == 'otpSentSuffix') continue;
          expect((e.value as String).trim(), isNotEmpty, reason: '$yol ${e.key}');
        }
      }
    });
  });

  group('context.l10n', () {
    testWidgets('delegate yokken Türkçe sözlüğe düşer', (tester) async {
      String? gorulen;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          gorulen = context.l10n.signIn;
          return const SizedBox();
        }),
      ));
      expect(gorulen, 'Giriş Yap');
    });

    testWidgets('en_US ile İngilizce', (tester) async {
      String? gorulen;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          gorulen = context.l10n.signIn;
          return const SizedBox();
        }),
      ));
      expect(gorulen, 'Sign In');
    });

    testWidgets('yer tutucu iki dilde de dolar', (tester) async {
      final gorulen = <String>[];
      for (final loc in const [Locale('tr', 'TR'), Locale('en', 'US')]) {
        await tester.pumpWidget(MaterialApp(
          locale: loc,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(builder: (context) {
            gorulen.add(context.l10n.codeSentTo('a@b.c'));
            return const SizedBox();
          }),
        ));
      }
      expect(gorulen[0], contains('a@b.c'));
      expect(gorulen[1], contains('a@b.c'));
      expect(gorulen[0], isNot(gorulen[1]));
    });
  });

  group('LocaleNotifier', () {
    test('parse: tr / en / system / bilinmeyen', () {
      expect(LocaleNotifier.parse('tr'), const Locale('tr', 'TR'));
      expect(LocaleNotifier.parse('en'), const Locale('en', 'US'));
      expect(LocaleNotifier.parse('system'), isNull);
      expect(LocaleNotifier.parse('xx'), const Locale('tr', 'TR'),
          reason: 'bozuk tercih Türkçe\'ye düşer');
      expect(LocaleNotifier.parse(null), const Locale('tr', 'TR'));
    });

    test('encode gidiş-dönüş', () {
      for (final raw in ['tr', 'en', 'system']) {
        expect(LocaleNotifier.encode(LocaleNotifier.parse(raw)), raw);
      }
    });
  });
}
