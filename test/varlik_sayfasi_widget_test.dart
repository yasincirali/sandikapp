import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/varlik_sayfasi.dart';
import 'package:portfoy_takip/widgets/donem_istatistik.dart';
import 'package:portfoy_takip/widgets/donem_secici.dart';
import 'package:portfoy_takip/widgets/varlik_iskeleti.dart';

/// Varlık sayfası — alt çubuğun duruma göre doğru eylemi göstermesi ve
/// sayıların seriden gelmesi.
///
/// Alt çubuk kuralı (kullanıcı kararı 2026-09-28, seçenek C):
///   · portföyde değil → [Takip et] [Portföyüme ekle]
///   · takipte         → [Takipte]  [Portföyüme ekle]
///   · portföyde       → [Pozisyonuma git]
///   · seçiciden       → [Takip et] [Bunu seç]
///   · portföy yüklenirken "Portföyüme ekle" PASİF (sahip olunan varlıkta
///     ikinci kayıt açtırmasın)

const _thy = VarlikKimligi(
  ticker: 'THYAO.IS',
  name: 'Türk Hava Yolları',
  type: AssetType.hisse,
  currency: 'TRY',
);

Asset _lot() => Asset(
      id: 'a1',
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 120,
      addedDate: DateTime(2026, 1, 1),
      kind: AssetKind.buy,
    );

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this._assets);
  final List<Asset> _assets;
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: _assets,
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _YuklenmeyenPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() => Completer<PortfolioState>().future;
}

class _Takip extends WatchlistNotifier {
  _Takip(this._items);
  final List<WatchlistItem> _items;
  @override
  Future<List<WatchlistItem>> build() async => _items;
}

/// Her dönem için sahte seri: 100'den başlayıp dönem uzunluğuna göre biten
/// iki nokta — çip getirisi hangi serinin kullanıldığını ele verir.
Future<Map<int, double>> _seri(String ticker, int gun) async {
  final son = DateTime(2026, 9, 28, 17).millisecondsSinceEpoch;
  final bas = son - Duration(days: gun == 1 ? 0 : gun).inMilliseconds -
      const Duration(hours: 8).inMilliseconds;
  return {bas: 100.0, son: 100.0 + gun / 10};
}

Future<void> _kur(
  WidgetTester t, {
  PortfolioNotifier Function()? portfoy,
  List<WatchlistItem> takip = const [],
  VoidCallback? onSec,
  SeriYukleyici? yukleyici,
  bool tamAcilis = true,
}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      portfolioProvider.overrideWith(portfoy ?? () => _Portfoy(const [])),
      watchlistProvider.overrideWith(() => _Takip(takip)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: VarlikSayfasi(
          kimlik: _thy,
          tamAcilis: tamAcilis,
          onSec: onSec,
          seriYukleyici: yukleyici ?? _seri,
        ),
      ),
    ),
  ));
  // Seriler ve sağlayıcılar çözülsün. `pumpAndSettle` yok: gösterge paneli
  // ağa çıkmaya çalışıp kendi yükleme durumunda kalabilir.
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  // Açılış kapısı (kullanıcı kararı 2026-09-28): "ekranı açtığımda tek tek
  // değil tümden dolmalı". Bir dönem gecikirken sayfa iskelette kalır;
  // o da gelince çipler, grafik ve istatistik BİRLİKTE çizilir.
  testWidgets('açılış: hepsi gelmeden iskelet, gelince birlikte dolar',
      (t) async {
    final gec = Completer<Map<int, double>>();
    await _kur(t, yukleyici: (tk, gun) => gun == 1825 ? gec.future : _seri(tk, gun));
    expect(find.byType(VarlikIskeleti), findsOneWidget);
    expect(find.byType(DonemSecici), findsNothing,
        reason: 'hızlı dönemler gelse de çipler tek tek dolmamalı');

    gec.complete(await _seri('THYAO.IS', 1825));
    await t.pump();
    await t.pump();
    expect(find.byType(VarlikIskeleti), findsNothing);
    expect(find.byType(DonemSecici), findsOneWidget);
    expect(find.byType(DonemIstatistikIzgarasi), findsOneWidget);
  });

  testWidgets('açılış: yavaş dönem sayfayı süre sınırından fazla tutmaz',
      (t) async {
    await _kur(t,
        yukleyici: (tk, gun) =>
            gun == 1825 ? Completer<Map<int, double>>().future : _seri(tk, gun));
    expect(find.byType(VarlikIskeleti), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    expect(find.byType(VarlikIskeleti), findsNothing);
    expect(find.byType(DonemSecici), findsOneWidget);
  });

  testWidgets('portföyde değil: Takip et + Portföyüme ekle', (t) async {
    await _kur(t);
    expect(find.text('Takip et'), findsOneWidget);
    expect(find.text('Portföyüme ekle'), findsOneWidget);
    expect(find.text('Pozisyonuma git'), findsNothing);
  });

  testWidgets('takipte: düğme durumu değişir', (t) async {
    await _kur(t, takip: [_thy.toWatchlistItem(userId: 'u1')]);
    expect(find.text('Takipte'), findsOneWidget);
    expect(find.text('Takip et'), findsNothing);
  });

  testWidgets('portföyde: Pozisyonuma git, Portföyüme ekle YOK', (t) async {
    await _kur(t, portfoy: () => _Portfoy([_lot()]));
    expect(find.text('Pozisyonuma git'), findsOneWidget);
    expect(find.text('Portföyüme ekle'), findsNothing);
    expect(find.text('Takip et'), findsNothing,
        reason: 'sahip olunan varlığı ayrıca takibe almak önerilmez');
  });

  testWidgets('seçiciden açıldı: birincil eylem Bunu seç', (t) async {
    var secildi = false;
    await _kur(t, portfoy: () => _Portfoy([_lot()]), onSec: () => secildi = true);
    expect(find.text('Bunu seç'), findsOneWidget,
        reason: 'portföyde olsa bile ekleme akışı bozulmaz (yeni lot)');
    expect(find.text('Pozisyonuma git'), findsNothing);
    await t.tap(find.text('Bunu seç'));
    await t.pump();
    expect(secildi, isTrue);
  });

  testWidgets('portföy yüklenirken Portföyüme ekle pasif', (t) async {
    await _kur(t, portfoy: _YuklenmeyenPortfoy.new);
    final dugme = t.widget<FilledButton>(find.ancestor(
        of: find.text('Portföyüme ekle'), matching: find.byType(FilledButton)));
    expect(dugme.onPressed, isNull);
  });

  testWidgets('çip getirileri her dönemin KENDİ serisinden', (t) async {
    await _kur(t);
    // Sahte seri: dönem sonu = 100 + gün/10 → 1Y +%36,5, 1A +%3,0
    // (yönlü yüzde `fmtPctIsaretli`; eski biçim "%+36,5").
    expect(find.text('+%36,5'), findsWidgets);
    expect(find.text('+%3,0'), findsOneWidget);
    // Varsayılan dönem 1Y — başlıktaki fiyat 1Y serisinin son noktası.
    expect(find.textContaining('136,50'), findsWidgets);
  });

  testWidgets('altı dönem AYNI ANDA istenir — dalga dalga değil', (t) async {
    // Hiçbiri yanıtlanmaz: ardışık ya da ikişerli yükleme olsaydı ilk
    // yanıt gelmeden ikinci dalga başlamaz, istek sayısı 1 ya da 2'de kalırdı.
    final istenen = <int>[];
    final bekleyen = <Completer<Map<int, double>>>[];
    await _kur(t, yukleyici: (ticker, gun) {
      istenen.add(gun);
      final c = Completer<Map<int, double>>();
      bekleyen.add(c);
      return c.future;
    });
    expect(istenen.toSet(), varlikSayfasiDonemleri.toSet());
    expect(istenen.first, 365,
        reason: 'seçili dönem (varsayılan 1Y) ilk başlatılan olmalı');
    for (final c in bekleyen) {
      c.complete(const {});
    }
    await t.pump();
  });

  testWidgets('tutamaçtan YUKARI çekmek sayfayı büyütür, aşağısı küçültür',
      (t) async {
    // Kullanıcı bildirimi (2026-09-28): tutamaç aşağı çekiliyor ama yukarı
    // çekilip kart büyütülemiyordu — sayfa yalnızca listeden sürükleniyordu.
    await _kur(t, tamAcilis: false);
    final baslik = find.text('THYAO').first;
    // Testte sayfa üste yaslı (modal yok); boyu içerik listesinin
    // yüksekliğinden okunur.
    double boy() => t.getSize(find.byType(ListView).first).height;
    final yarim = boy();

    await t.drag(baslik, const Offset(0, -300));
    await t.pumpAndSettle();
    expect(boy(), greaterThan(yarim + 100), reason: 'sayfa tam boya büyümeli');

    await t.drag(baslik, const Offset(0, 150));
    await t.pumpAndSettle();
    expect(boy(), closeTo(yarim, 2),
        reason: 'aşağı çekince yarım boya döner');
  });
}
