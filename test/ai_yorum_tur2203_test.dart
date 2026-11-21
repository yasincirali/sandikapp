import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/portfoy_yorumu_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/portfoy_yorumu_karti.dart';

/// AI yorum kartı 2026-11-21 turu: hata dalında yeniden dene, Premium hatasında
/// kilit, varlık adıyla kilit, hak dolunca pasif düğme, canlı bölge, w600.
void main() {
  testWidgets('kayıt okunamadı: Tekrar dene sağlayıcıyı yeniden okur',
      (tester) async {
    var okuma = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        premiumKilitliProvider.overrideWithValue(false),
        portfoyYorumRizaProvider.overrideWith((ref) async => true),
        portfoyYorumuProvider.overrideWith((ref, tur) async {
          okuma++;
          throw StateError('okunamadi');
        }),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.dark]),
        home: const Scaffold(body: SingleChildScrollView(child: PortfoyYorumuKarti())),
      ),
    ));
    await tester.pumpAndSettle();
    expect(okuma, 1);
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    expect(okuma, 2);
  });

  group('kaynak', () {
    final kart = File('lib/widgets/portfoy_yorumu_karti.dart').readAsStringSync();
    final saglayici =
        File('lib/providers/portfoy_yorumu_provider.dart').readAsStringSync();

    test('Premium hatası kırmızı metin değil, hak yeniden okuma', () {
      expect(kart, contains('YorumHataTuru.premium'));
      expect(kart, contains('ref.invalidate(premiumHaklariProvider)'));
    });

    test('varlık kilidi varlık adını söyler', () {
      expect(kart, contains('l.pyzKilitVarlik(widget.varlikAdi!)'));
    });

    test('hak dolunca düğme pasif, satır sessiz renkte', () {
      expect(kart, contains('onPressed: hakDoldu ? null : onYorumla'));
      expect(kart, contains('hakDoldu ? c.text58 : c.danger'));
      for (final t in ['kota', 'kotaAy', 'tavan']) {
        expect(kart, contains('hataTuru == YorumHataTuru.$t'));
      }
    });

    test('hata satırı canlı bölge, başlık w600', () {
      expect(kart, contains('liveRegion: true'));
      expect(kart, isNot(contains('FontWeight.w700')));
    });

    test('hata dalı SandikErrorView + non-fatal rapor', () {
      expect(RegExp(r'SandikErrorView\(').allMatches(kart).length, 2);
      expect(saglayici, contains("'portfoy_yorumu_kayit'"));
      expect(saglayici, contains("'varlik_yorumu_kayit'"));
    });
  });
}
