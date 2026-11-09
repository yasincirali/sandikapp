import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/cevrimdisi_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/cevrimdisi_seridi.dart';

import 'helpers/kaynak.dart';

/// "İnternet yok · fiyatlar 14:32'deki hâli" (Ar-Ge 7 Kas 08:03 #3):
/// ağ hatasında belirir, ilk başarılı turda kalkar; karar fiyat turunun
/// HTTP sayacından, saat son fiyat güncellemesinden.
void main() {
  final l = AppLocalizationsTr();

  group('tur kararı', () {
    test('yanıt varsa bağlı, yalnız ağ hatası varsa kopuk, ağ yoksa karar yok',
        () {
      expect(turBaglantiKarari(hata: 0, yanit: 3), isFalse);
      expect(turBaglantiKarari(hata: 2, yanit: 1), isFalse,
          reason: 'bir kaynak düştü, diğeri yanıt verdi: internet var');
      expect(turBaglantiKarari(hata: 4, yanit: 0), isTrue);
      expect(turBaglantiKarari(hata: 0, yanit: 0), isNull,
          reason: 'hepsi önbellekten: önceki durum korunur');
    });

    test('son fiyat anı: ağdan fiyatlanan aktif lotların en yenisi', () {
      Asset a(String id, DateTime? t,
              {bool manuel = false, String ticker = 'THYAO.IS'}) =>
          Asset(
            id: id,
            userId: 'u',
            name: id,
            ticker: ticker,
            type: AssetType.hisse,
            quantity: 1,
            purchasePrice: 1,
            currency: 'TRY',
            notes: '',
            isManualPrice: manuel,
            lastUpdated: t,
          );
      final eski = DateTime(2026, 11, 7, 9, 10);
      final yeni = DateTime(2026, 11, 7, 14, 32);
      expect(
          sonFiyatZamani([
            a('1', eski),
            a('2', yeni),
            a('3', DateTime(2026, 11, 7, 16), manuel: true),
            a('4', DateTime(2026, 11, 7, 17), ticker: ''),
          ]),
          yeni);
      expect(sonFiyatZamani([a('1', null)]), isNull);
    });
  });

  group('metin', () {
    final simdi = DateTime(2026, 11, 7, 15);
    test('bugünün saati: "14:32\'deki hâli"', () {
      expect(cevrimdisiMetni(l, DateTime(2026, 11, 7, 14, 32), simdi),
          "İnternet yok · fiyatlar 14:32'deki hâli");
    });
    test('saat bilinmiyorsa saatsiz', () {
      expect(cevrimdisiMetni(l, null, simdi),
          'İnternet yok · son fiyatlar gösteriliyor');
    });
    test('dünün saati tarihle yazılır', () {
      expect(cevrimdisiMetni(l, DateTime(2026, 11, 6, 22, 5), simdi),
          "İnternet yok · fiyatlar 06.11 22:05'teki hâli");
    });
    test('Türkçe ek son okunan sayıya uyar', () {
      expect(trSaatBulunmaEki(14, 32), 'deki'); // otuz iki
      expect(trSaatBulunmaEki(14, 30), 'daki'); // otuz
      expect(trSaatBulunmaEki(14, 0), 'teki'); // on dört
      expect(trSaatBulunmaEki(9, 5), 'teki'); // beş
      expect(trSaatBulunmaEki(9, 40), 'taki'); // kırk
      expect(trSaatBulunmaEki(9, 3), 'teki'); // üç
      expect(trSaatBulunmaEki(9, 6), 'daki'); // altı
      expect(trSaatBulunmaEki(9, 50), 'deki'); // elli
      expect(trSaatBulunmaEki(10, 0), 'daki'); // on
      expect(trSaatBulunmaEki(0, 0), 'daki'); // sıfır
    });
  });

  group('şerit', () {
    Future<ProviderContainer> kur(WidgetTester t) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: ThemeData(extensions: const [SandikPalette.dark]),
          home: const Scaffold(body: CevrimdisiSeridi()),
        ),
      ));
      return c;
    }

    testWidgets('ağ hatasında belirir, başarılı turda kalkar (animasyonsuz)',
        (t) async {
      final c = await kur(t);
      expect(find.textContaining('İnternet yok'), findsNothing);
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);

      final bugun = DateTime.now();
      c.read(cevrimdisiProvider.notifier).agHatasi(
          sonFiyat: DateTime(bugun.year, bugun.month, bugun.day, 0, 0));
      await t.pump();
      expect(find.text("İnternet yok · fiyatlar 00:00'daki hâli"),
          findsOneWidget);
      // Anlam yalnız renkle değil: ikon + cümle; ekran okuyucuya duyurulur.
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      final h = t.ensureSemantics();
      await t.pump();
      expect(find.bySemanticsLabel(RegExp('^İnternet yok')), findsOneWidget);
      h.dispose();

      c.read(cevrimdisiProvider.notifier).baglandi();
      // Tek kare: geçiş animasyonu yok, hareketi azalt ayarından bağımsız.
      await t.pump();
      expect(find.textContaining('İnternet yok'), findsNothing);
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('saat bilinmiyorsa saatsiz cümle', (t) async {
      final c = await kur(t);
      c.read(cevrimdisiProvider.notifier).agHatasi();
      await t.pump();
      expect(find.text('İnternet yok · son fiyatlar gösteriliyor'),
          findsOneWidget);
    });
  });

  test('Ana sayfa ve Portföy şeridi gösterir; fiyat turu durumu yazar', () {
    expect(ekranKaynagiSync('lib/screens/home_screen.dart'),
        contains('CevrimdisiSeridi('));
    expect(ekranKaynagiSync('lib/screens/portfolio_screen.dart'),
        contains('CevrimdisiSeridi('));
    final p = ekranKaynagiSync('lib/providers/portfolio_provider.dart');
    expect(p, contains('turBaglantiKarari('));
    expect(p, contains('.agHatasi('));
    expect(p, contains('.baglandi()'));
  });
}
