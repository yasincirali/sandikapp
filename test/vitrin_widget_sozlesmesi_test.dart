import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/home_widget_service.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/varlik_widget_service.dart';

import 'helpers/kaynak.dart';

/// Vitrin widget'ı: orta boy, üç varlık alt alta (Ar-Ge 2026-10-29 §2, yasin
/// onayı). Yalnız iOS; Android sonra.
///
/// Swift burada derlenmiyor (iOS derlemesi `main` birleşmesinde TestFlight
/// hattında). Sözleşme iki yoldan kilitlenir: Dart'ın yazdığı paket kanal
/// taklidiyle, Swift tarafının anahtar/tür/aile/pbxproj kaydı kaynak
/// metinden (`varlik_widget_sozlesmesi_test` ile aynı yöntem).

class _Kanal {
  final Map<String, Object?> yazilan = {};
  final List<Map<String, Object?>> yenilemeler = [];
  List<Map<String, Object?>> kurulu = const [];

  void kur() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), (
          call,
        ) async {
          switch (call.method) {
            case 'saveWidgetData':
              final a = (call.arguments as Map).cast<String, Object?>();
              yazilan[a['id'] as String] = a['data'];
              return true;
            case 'updateWidget':
              yenilemeler.add(
                (call.arguments as Map? ?? {}).cast<String, Object?>(),
              );
              return true;
            case 'setAppGroupId':
              return true;
            case 'getInstalledWidgets':
              return kurulu;
          }
          return null;
        });
  }

  void kaldir() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
}

Asset _lot(String ticker, AssetType type, {String? sub}) => Asset(
  id: 'lot-$ticker',
  userId: 'u1',
  name: '',
  ticker: ticker,
  type: type,
  quantity: 10,
  purchasePrice: 100,
  currency: 'TRY',
  notes: '',
  subCategory: sub,
  currentPrice: 120,
  addedDate: DateTime(2026, 1, 1),
);

WatchlistItem _takip(String ticker, AssetType type, {String? sub}) =>
    WatchlistItem(
      id: 'w-$ticker',
      userId: 'u1',
      ticker: ticker,
      name: '',
      type: type,
      subCategory: sub,
      currency: 'TRY',
      addedAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('tr_TR'));

  final altin = _takip('ALTIN_GRAM24', AssetType.altin);
  final dolar = _takip('USDTRY=X', AssetType.doviz, sub: 'USD');
  final euro = _takip('EURTRY=X', AssetType.doviz, sub: 'EUR');
  final thy = _takip('THYAO.IS', AssetType.hisse);

  group('varsayılan üçlü = takip listesinin ilk üçü', () {
    test('portföy önde olsa da varsayılan takip sırasından gelir', () {
      final takip = [altin, dolar, euro, thy];
      final adaylar = varlikWidgetAdaylari(
        lotlar: [_lot('TEFAS:AFT', AssetType.fon)],
        takip: takip,
      );
      // Seçim listesinin başı portföy (eski davranış değişmedi)…
      expect(adaylar.first.sembol, 'TEFAS:AFT');
      // …vitrin ise takip listesinin ilk üçü.
      expect(varsayilanVitrin(adaylar: adaylar, takip: takip), [
        'ALTIN_GRAM24',
        'USDTRY=X',
        'EURTRY=X',
      ]);
    });

    test('takip üçten kısaysa listenin başından tamamlanır, tekrar yok', () {
      final takip = [dolar];
      final adaylar = varlikWidgetAdaylari(
        lotlar: [
          _lot('USDTRY=X', AssetType.doviz, sub: 'USD'),
          _lot('ALTIN_GRAM24', AssetType.altin),
        ],
        takip: takip,
      );
      expect(varsayilanVitrin(adaylar: adaylar, takip: takip), [
        'USDTRY=X',
        'ALTIN_GRAM24',
      ]);
    });

    test(
      'seçim listesinde olmayan sembol girmez (satır "listende yok" olurdu)',
      () {
        final takip = [altin, dolar, euro];
        final adaylar = varlikWidgetAdaylari(
          lotlar: const [],
          takip: takip,
          azami: 2,
        );
        expect(varsayilanVitrin(adaylar: adaylar, takip: takip), [
          'ALTIN_GRAM24',
          'USDTRY=X',
        ]);
      },
    );

    test('boş listede boş üçlü', () {
      expect(varsayilanVitrin(adaylar: const [], takip: const []), isEmpty);
    });
  });

  group('paket: yalnız ekleme (eski okuyucu bozulmaz)', () {
    test('`vitrin` isteğe bağlı alan; `v` hâlâ 1', () {
      final p = jsonDecode(
        varlikWidgetPaketi(
          const [],
          saat: '14:05',
          vitrin: ['ALTIN_GRAM24', 'USDTRY=X'],
        ),
      );
      expect(p['v'], 1);
      expect(p['vitrin'], ['ALTIN_GRAM24', 'USDTRY=X']);
      // Eski çağrı biçimi aynı JSON'u üretir: alan hiç yazılmaz.
      final eski = jsonDecode(varlikWidgetPaketi(const [], saat: '14:05'));
      expect((eski as Map).containsKey('vitrin'), isFalse);
      expect(eski.keys, ['v', 'saat', 'ogeler']);
    });

    test('kapsam kararı Dart\'ta: kapsam dışı satır `sunucu` almaz', () {
      // Swift satırı yalnız `sunucu == true` ise fiyatla çizer; değilse
      // "Uygulamayı aç". Karar `FiyatKaynagi.widgetSunucuKapsamindaMi`.
      final adaylar = varlikWidgetAdaylari(
        lotlar: const [],
        takip: [altin, thy],
      );
      final ogeler = [
        for (final a in adaylar) varlikWidgetOgesi(a, fiyat: 100, gunlukPct: 1),
      ];
      for (final o in ogeler) {
        expect(
          o.sunucu == true,
          FiyatKaynagi.widgetSunucuKapsamindaMi(o.id),
          reason: o.id,
        );
      }
      expect(ogeler.firstWhere((o) => o.id == 'THYAO.IS').sunucu, isNull);
      expect(ogeler.firstWhere((o) => o.id == 'ALTIN_GRAM24').sunucu, isTrue);
    });
  });

  group('servis', () {
    late _Kanal kanal;
    final svc = VarlikWidgetService.instance;

    setUp(() {
      HomeWidgetService.instance.kiyasBelleginiSifirla();
      kanal = _Kanal()..kur();
      svc.sifirla();
      VarlikWidgetService.platformKontrolu = () => true;
      svc.kuruluMu = () async => true;
      svc.saat = () => DateTime(2026, 10, 29, 14, 5);
      svc.kotasyonYukleyici = (semboller) async => {
        'ALTIN_GRAM24': const YahooQuote(
          symbol: 'ALTIN_GRAM24',
          regularMarketPrice: 4215.3,
          regularMarketChangePercent: 0.42,
        ),
      };
      svc.navYukleyici = (_) async => const [];
      svc.sunucu = () => null;
    });

    tearDown(() {
      kanal.kaldir();
      VarlikWidgetService.platformKontrolu = () => false;
      HomeWidgetService.iOSMu = () => false;
    });

    Map<String, Object?> paket() =>
        jsonDecode(kanal.yazilan[HomeWidgetService.kVarliklar] as String)
            as Map<String, Object?>;

    test('aynı anahtara varsayılan üçlüyü yazar; yeni anahtar yok', () async {
      await svc.guncelle(
        lotlar: [_lot('THYAO.IS', AssetType.hisse)],
        takip: [altin, dolar, euro],
      );
      expect(paket()['vitrin'], ['ALTIN_GRAM24', 'USDTRY=X', 'EURTRY=X']);
      // Tek varlık widget'ının anahtarı; vitrin için ayrı anahtar yok.
      expect(kanal.yazilan.keys, [HomeWidgetService.kVarliklar]);
    });

    test(
      'takip sırası değişince (aday listesi aynı) üçlü beklemeden yazılır',
      () async {
        final lotlar = [
          _lot('ALTIN_GRAM24', AssetType.altin),
          _lot('USDTRY=X', AssetType.doviz, sub: 'USD'),
        ];
        await svc.guncelle(lotlar: lotlar, takip: [altin, dolar]);
        expect(paket()['vitrin'], ['ALTIN_GRAM24', 'USDTRY=X']);
        await svc.guncelle(lotlar: lotlar, takip: [dolar, altin]);
        expect(paket()['vitrin'], ['USDTRY=X', 'ALTIN_GRAM24']);
      },
    );

    test(
      'iOS\'ta vitrin türü de yenilenir; Android\'de ek çağrı yok',
      () async {
        HomeWidgetService.iOSMu = () => true;
        await svc.guncelle(lotlar: const [], takip: [altin]);
        expect(kanal.yenilemeler.map((y) => y['ios']), [
          HomeWidgetService.iOSVarlikWidgetName,
          HomeWidgetService.iOSVitrinWidgetName,
        ]);

        kanal.yenilemeler.clear();
        HomeWidgetService.instance.kiyasBelleginiSifirla();
        svc.sifirla();
        HomeWidgetService.iOSMu = () => false;
        await svc.guncelle(lotlar: const [], takip: [dolar]);
        expect(
          kanal.yenilemeler.single['ios'],
          HomeWidgetService.iOSVarlikWidgetName,
        );
      },
    );

    test(
      'yalnız vitrin kuruluyken de "kurulu" sayılır (fiyat çekilir)',
      () async {
        kanal.kurulu = [
          {
            'kind': HomeWidgetService.iOSVitrinWidgetName,
            'family': 'systemMedium',
          },
        ];
        expect(
          await HomeWidgetService.instance.varlikWidgetiKuruluMu(),
          isTrue,
        );
        kanal.kurulu = [
          {'kind': 'SandikWidget', 'family': 'systemMedium'},
        ];
        expect(
          await HomeWidgetService.instance.varlikWidgetiKuruluMu(),
          isFalse,
          reason: 'portföy widget\'ı sayılmaz',
        );
      },
    );
  });

  group('Swift sözleşmesi (kaynak kilidi — derleme burada yok)', () {
    final vitrin = ekranKaynagiSync(
      'ios/SandikWidget/SandikVitrinWidget.swift',
    );
    final varlik = ekranKaynagiSync(
      'ios/SandikWidget/SandikVarlikWidget.swift',
    );
    final bundle = ekranKaynagiSync(
      'ios/SandikWidget/SandikWidgetBundle.swift',
    );
    final pbx = ekranKaynagiSync('ios/Runner.xcodeproj/project.pbxproj');
    final sunucu = ekranKaynagiSync(
      'supabase/functions/_shared/widget_fiyat.ts',
    );

    test('tür Dart ile birebir; yalnız orta boy', () {
      expect(
        vitrin,
        contains('let kind = "${HomeWidgetService.iOSVitrinWidgetName}"'),
      );
      final m = RegExp(r'\.supportedFamilies\(\[([^\]]*)\]\)')
          .allMatches(vitrin)
          .toList();
      expect(m.single.group(1)!.trim(), '.systemMedium');
      expect(vitrin, contains('.configurationDisplayName("Vitrin")'));
      expect(vitrin, contains('.description("'));
    });

    test('aynı paket ve anahtarlar; yeni JSON alanı isteğe bağlı', () {
      expect(vitrin, contains('SandikVarlikPaketi.oku()'));
      expect(vitrin, contains('VarlikWidgetKeys.isLightTheme'));
      expect(varlik, contains('var vitrin: [String]? = nil'));
      expect(varlik, contains('static let surum = 1'));
      // Anahtarlar tek yerde (kopya liste yok).
      expect(vitrin, isNot(contains('"sandik_varliklar"')));
    });

    test('üç seçim App Intents ile; varsayılan sonuç türde değil pakette', () {
      expect(vitrin, contains('AppIntentConfiguration('));
      expect(vitrin, contains('WidgetConfigurationIntent'));
      expect(
        RegExp(r'@Parameter\(title: "[123]\. satır"\)')
            .allMatches(vitrin)
            .length,
        3,
      );
      // `defaultResult` üç satırı aynı varlıkla doldururdu.
      expect(vitrin, isNot(contains('func defaultResult')));
      expect(vitrin, contains('paket.vitrin'));
      expect(vitrin, isNot(contains('EntityStringQuery')));
    });

    test('kapsam kararı Swift\'te verilmez; kapsam dışı satır sayı yazmaz', () {
      expect(vitrin, contains('oge?.sunucu == true'));
      expect(vitrin, contains('"Uygulamayı aç"'));
      // Sembolün türüne bakan dal yok (önek/sonek karşılaştırması);
      // önizlemedeki örnek kimlikler yalnız veri.
      for (final yasak in ['hasPrefix(', 'hasSuffix(', 'FiyatKaynagi']) {
        expect(vitrin.replaceAll(RegExp(r'///.*'), ''),
            isNot(contains(yasak)),
            reason: 'Sembol kapsamı Dart\'ta (sözleşme madde 1)');
      }
    });

    test('tek istek, en çok sunucunun sınırı kadar sembol', () {
      expect(vitrin, contains('SandikWidgetFiyatServisi.cekToplu('));
      expect(vitrin, isNot(contains('SandikWidgetFiyatServisi.cek(')));
      final swiftSinir = RegExp(r'static let azamiSembol = (\d+)')
          .firstMatch(varlik)!
          .group(1);
      final tsSinir = RegExp(r'WIDGET_AZAMI_SEMBOL = (\d+)')
          .firstMatch(sunucu)!
          .group(1);
      expect(swiftSinir, tsSinir);
      expect(varlik, contains('["semboller": istenen]'));
      // Ritim tek varlık widget'ıyla aynı yerden.
      expect(vitrin, contains('SandikWidgetRitmi.cekilmeli('));
      expect(vitrin, contains('SandikWidgetRitmi.sonraki('));
      expect(vitrin, contains('policy: .never'));
    });

    test('yön ok + sayıyla; satır başına tek VoiceOver cümlesi; taşma yok', () {
      expect(vitrin, contains('"▲"'));
      expect(vitrin, contains('"▼"'));
      expect(vitrin, contains('.accessibilityElement(children: .ignore)'));
      expect(vitrin, contains('.accessibilityLabel(erisimMetni(satir))'));
      expect(vitrin, contains('.truncationMode(.tail)'));
      expect(vitrin, contains('.lineLimit(1)'));
    });

    test('dokunuş tek varlık widget\'ıyla aynı bağlantı', () {
      expect(vitrin, contains('.widgetURL(varlikWidgetClickURL)'));
      expect(vitrin, isNot(contains('URL(string:')));
    });

    test('paket kaydı ve pbxproj (Sources fazı) yerinde', () {
      expect(bundle, contains('SandikVitrinWidget()'));
      final ref = RegExp(
        r'(\w+) /\* SandikVitrinWidget\.swift \*/ = \{isa = PBXFileReference;',
      ).firstMatch(pbx);
      expect(ref, isNotNull, reason: 'dosya referansı yok');
      final build = RegExp(
        r'(\w+) /\* SandikVitrinWidget\.swift in Sources \*/ = \{isa = PBXBuildFile; fileRef = '
        '${ref!.group(1)}',
      ).firstMatch(pbx);
      expect(build, isNotNull, reason: 'derleme dosyası yok');
      final faz = RegExp(
        r'5A0D1K0000000000000022 /\* Sources \*/ = \{[^}]*\}',
        dotAll: true,
      ).firstMatch(pbx)!.group(0)!;
      expect(
        faz,
        contains(
          '${build!.group(1)} /* SandikVitrinWidget.swift in Sources */',
        ),
      );
      final grup = RegExp(
        r'5A0D1K0000000000000020 /\* SandikWidget \*/ = \{[^}]*\}',
        dotAll: true,
      ).firstMatch(pbx)!.group(0)!;
      expect(grup, contains('${ref.group(1)} /* SandikVitrinWidget.swift */'));
      // Kimlikler eşsiz: aynı kimlik iki nesneye verilirse proje açılmaz.
      for (final id in [ref.group(1)!, build.group(1)!]) {
        expect(
          RegExp('$id /\\* SandikVitrinWidget\\.swift(?: in Sources)? \\*/ = ')
              .allMatches(pbx)
              .length,
          1,
        );
        expect(
          RegExp('$id /\\* (?!SandikVitrinWidget)').hasMatch(pbx),
          isFalse,
        );
      }
    });
  });
}
