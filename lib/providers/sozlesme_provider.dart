import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/tr_format.dart';
import 'package:uuid/uuid.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/sozlesme.dart';
import '../services/bes_hesabi.dart';
import '../services/crash_reporter.dart';
import '../services/mevduat_hesabi.dart';
import '../services/price_service.dart';
import '../services/sozlesme_deposu.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';
import 'portfolio_provider.dart';

const _uuid = Uuid();

/// BES fonunun fiyatı alınamadı — lot uydurma fiyatla yazılmaz.
class BesFiyatYokException implements Exception {
  const BesFiyatYokException(this.kod);
  final String kod;
  @override
  String toString() => 'BesFiyatYokException($kod)';
}

/// Kullanıcının sözleşmeleri ve mevduat dönemleri.
class SozlesmeState {
  const SozlesmeState({
    this.sozlesmeler = const {},
    this.donemler = const {},
  });

  final Map<String, Sozlesme> sozlesmeler;
  final Map<String, List<MevduatDonemi>> donemler;

  Sozlesme? sozlesme(String? id) => id == null ? null : sozlesmeler[id];

  List<MevduatDonemi> donemleri(String id) => donemler[id] ?? const [];
}

/// Sözleşme işlemleri — ekran hesap yapmaz, buradan ister.
///
/// Her işlem aynı sırayı izler: sözleşme satırı → dönem satırı → lot(lar).
/// Lot yazımı başarısız olursa yeni açılan sözleşme GERİ ALINIR (yarım
/// açılış, portföyde görünmeyen ama deftere bağlanacak bir sözleşme
/// bırakırdı). Mevcut sözleşmeye yapılan işlemde (yenileme, katkı) geri
/// alma gerekmez: dönem/lot tek başına tutarlıdır.
class SozlesmeNotifier extends AsyncNotifier<SozlesmeState> {
  @override
  Future<SozlesmeState> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) {
      // Çıkış / kullanıcı değişimi: önceki oturumun sözleşmeleri bellekte
      // kalmasın (bkz. `SozlesmeDeposu` "Kullanıcı değişimi").
      SozlesmeDeposu.instance.temizle();
      return const SozlesmeState();
    }
    final s = await SupabaseService.instance.fetchSozlesmelerByUser(user.id);
    final d = await SupabaseService.instance.fetchMevduatDonemleri([
      for (final x in s)
        if (x.tur == SozlesmeTuru.mevduat) x.id,
    ]);
    SozlesmeDeposu.instance.yaz(s, d);
    // BES varsa devlet katkısı sınırı/oranı sunucudan (0089). Arka planda:
    // gelmezse `BesHesabi` yedek tabloyla çalışır, sözleşmeler beklemez.
    if (s.any((x) => x.tur == SozlesmeTuru.bes)) {
      CrashReporter.arkaPlan(
        SupabaseService.instance
            .fetchBesDevletKatkisi()
            .then(BesHesabi.uzakParametreler),
        reason: 'bes_devlet_katkisi_yukle',
      );
    }
    return _durum(s, d);
  }

  SozlesmeState _durum(Iterable<Sozlesme> s, Iterable<MevduatDonemi> d) {
    final donemler = <String, List<MevduatDonemi>>{};
    for (final x in d) {
      (donemler[x.sozlesmeId] ??= []).add(x);
    }
    for (final l in donemler.values) {
      l.sort((a, b) => a.baslangic.compareTo(b.baslangic));
    }
    return SozlesmeState(
      sozlesmeler: {for (final x in s) x.id: x},
      donemler: donemler,
    );
  }

  SozlesmeState get _simdiki => state.valueOrNull ?? const SozlesmeState();

  void _yayinla(Iterable<Sozlesme> degisen, Iterable<MevduatDonemi> yeniDonem) {
    final c = _simdiki;
    final s = {...c.sozlesmeler, for (final x in degisen) x.id: x};
    final d = [
      for (final l in c.donemler.values) ...l,
      ...yeniDonem,
    ];
    state = AsyncData(_durum(s.values, d));
  }

  String _kullanici() {
    final u = ref.read(authProvider).valueOrNull;
    if (u == null) throw StateError('oturum yok');
    return u.id;
  }

  // ── Mevduat ────────────────────────────────────────────────────────────

  /// Yeni mevduat: sözleşme + ilk dönem + anapara lotu.
  ///
  /// Lot: miktar = anapara (ilk birim değer 1,0), fiyat 1,0, tarih dönem
  /// başı. Geçmiş tarihli açılışta seri o günden bugüne tahakkukla çizilir
  /// — sözleşme bilindiği için bu ÖLÇÜMdür, uydurma değil.
  Future<void> mevduatAc({
    required String kurum,
    required String ad,
    required double anapara,
    required double yillikFaiz,
    required double stopaj,
    required DateTime baslangic,
    required int? vadeGun,
  }) async {
    final uid = _kullanici();
    final bas = dayKey(baslangic);
    final s = Sozlesme(
      id: _uuid.v4(),
      userId: uid,
      tur: SozlesmeTuru.mevduat,
      kurum: kurum,
      baslangic: bas,
    );
    final d = MevduatDonemi(
      id: _uuid.v4(),
      sozlesmeId: s.id,
      baslangic: bas,
      vadeSonu: vadeGun == null ? null : bas.add(Duration(days: vadeGun)),
      yillikFaiz: yillikFaiz,
      stopaj: stopaj,
    );
    final bugunkuBirim =
        MevduatHesabi.birimDeger([d], DateTime.now()) ?? 1.0;
    final lot = Asset(
      id: _uuid.v4(),
      userId: uid,
      name: ad,
      ticker: mevduatSembolu(s.id),
      type: AssetType.mevduat,
      quantity: anapara,
      purchasePrice: 1.0,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: bugunkuBirim,
      lastUpdated: DateTime.now(),
      addedDate: bas,
      sozlesmeId: s.id,
    );

    await SupabaseService.instance.insertSozlesme(s);
    try {
      await SupabaseService.instance.insertMevduatDonemi(d, uid);
      await ref.read(portfolioProvider.notifier).sozlesmeLotlariniEkle([lot]);
    } catch (_) {
      await _geriAl(s.id);
      rethrow;
    }
    SozlesmeDeposu.instance.yaz([s], [d]);
    _yayinla([s], [d]);
  }

  /// Vadesi dolan (ya da dolmak üzere olan) mevduatı yeni dönemle yeniler.
  ///
  /// Yeni dönem ÖNCEKİNİN VADE SONUNDA başlar: faiz o gün anaparaya eklenir
  /// ve yeni faiz o tutara işler. Vade günü geçtikten sonra yenilense de
  /// banka otomatik yenilemesi vade gününde yapılır; kullanıcı farklı bir
  /// gün seçtiyse [baslangic] onu taşır (aradaki günler faizsiz, düz).
  Future<void> mevduatYenile({
    required String sozlesmeId,
    required double yillikFaiz,
    required double stopaj,
    required int? vadeGun,
    DateTime? baslangic,
  }) async {
    final uid = _kullanici();
    final onceki = MevduatHesabi.sonDonem(_simdiki.donemleri(sozlesmeId));
    final varsayilan = onceki?.vadeSonu ?? DateTime.now();
    final b = baslangic ?? varsayilan;
    final bas = dayKey(b);
    final d = MevduatDonemi(
      id: _uuid.v4(),
      sozlesmeId: sozlesmeId,
      baslangic: bas,
      vadeSonu: vadeGun == null ? null : bas.add(Duration(days: vadeGun)),
      yillikFaiz: yillikFaiz,
      stopaj: stopaj,
    );
    await SupabaseService.instance.insertMevduatDonemi(d, uid);
    SozlesmeDeposu.instance.donemEkle(d);
    _yayinla(const [], [d]);
    await ref.read(portfolioProvider.notifier).refreshPrices(force: true);
  }

  /// Vadesiz hesapta oran değişti: bugün başlayan yeni vadesiz dönem.
  Future<void> mevduatOranGuncelle({
    required String sozlesmeId,
    required double yillikFaiz,
    required double stopaj,
  }) =>
      mevduatYenile(
        sozlesmeId: sozlesmeId,
        yillikFaiz: yillikFaiz,
        stopaj: stopaj,
        vadeGun: null,
        baslangic: DateTime.now(),
      );

  /// Mevduat çekildi: kalan payların tamamı bugünkü birim değerle satılır,
  /// sözleşme bugün kapanır.
  Future<void> mevduatCek(String sozlesmeId) async {
    final portfoy = ref.read(portfolioProvider).valueOrNull;
    final s = _simdiki.sozlesme(sozlesmeId);
    if (portfoy == null || s == null) return;
    final lotlar = [
      for (final a in portfoy.assets)
        if (a.sozlesmeId == sozlesmeId && a.isActive) a,
    ];
    final alim = lotlar.where((a) => a.isBuy).toList();
    if (alim.isEmpty) return;
    final net = alim.fold<double>(0, (t, a) => t + a.quantity) -
        lotlar.where((a) => a.isSell).fold<double>(0, (t, a) => t + a.quantity);
    final birim = SozlesmeDeposu.instance
        .mevduatBirimDegeri(alim.first.ticker, DateTime.now());
    if (net > 1e-9 && birim != null) {
      await ref.read(portfolioProvider.notifier).addSellTransaction(
            // `pos:` kimliği: satış tek lota değil pozisyona aittir
            // (`addSellTransaction` referansı boş bırakır).
            asset: _pozisyonTemsili(alim.first, birim),
            quantity: net,
            sellPrice: birim,
          );
    }
    final kapali = Sozlesme(
      id: s.id,
      userId: s.userId,
      tur: s.tur,
      kurum: s.kurum,
      baslangic: s.baslangic,
      kapandi: _bugun(),
    );
    await SupabaseService.instance.updateSozlesme(kapali);
    SozlesmeDeposu.instance.yaz([kapali], _simdiki.donemleri(sozlesmeId));
    _yayinla([kapali], const []);
  }

  // ── BES ────────────────────────────────────────────────────────────────

  /// Yeni BES: sözleşme + fon başına açılış lotu (+ devlet katkısı lotu).
  ///
  /// Açılış lotları BUGÜN tarihlidir: geçmiş katkıların tarihleri ve pay
  /// adetleri bilinmiyor, bugünkü birikimi geçmişe yaymak uydurma bir
  /// tarihçe olurdu. Maliyet "bugüne kadar ödediğin katkı"dır; getiri
  /// (birikim − katkı) bu yüzden ilk günden doğru görünür.
  ///
  /// [adUret] lot adını kurar (`Anadolu Hayat · AH5`); dil ekranın işi.
  Future<void> besAc({
    required String kurum,
    required DateTime giris,
    required double birikim,
    required double odenen,
    required List<FonPayi> dagilim,
    required String Function(String kod, {required bool devlet}) adUret,
    double? dkBirikim,
    double? dkOdenen,
    String? dkFonKodu,
    double? aylikKatki,
    int? katkiGunu,
  }) async {
    final uid = _kullanici();
    final s = Sozlesme(
      id: _uuid.v4(),
      userId: uid,
      tur: SozlesmeTuru.bes,
      kurum: kurum,
      baslangic: dayKey(giris),
      aylikKatki: aylikKatki,
      katkiGunu: katkiGunu,
      fonDagilimi: dagilim,
      dkFonKodu: dkFonKodu,
    );
    final dkVar = dkFonKodu != null && (dkBirikim ?? 0) > 0;
    final fiyatlar = await _fonFiyatlari([
      for (final f in dagilim) f.kod,
      if (dkVar) dkFonKodu,
    ]);

    final an = DateTime.now();
    final lotlar = <Asset>[];
    final birikimPay = BesHesabi.katkiyiBol(birikim, dagilim);
    final odenenPay = BesHesabi.katkiyiBol(odenen, dagilim);
    for (final e in birikimPay.entries) {
      final fiyat = fiyatlar[e.key]!;
      final pay = e.value / fiyat;
      lotlar.add(_besLotu(
        uid: uid,
        s: s,
        kod: e.key,
        ad: adUret(e.key, devlet: false),
        pay: pay,
        maliyet: odenenPay[e.key] ?? e.value,
        fiyat: fiyat,
        tarih: an,
        devlet: false,
      ));
    }
    if (dkVar) {
      final fiyat = fiyatlar[dkFonKodu]!;
      final pay = dkBirikim! / fiyat;
      lotlar.add(_besLotu(
        uid: uid,
        s: s,
        kod: dkFonKodu,
        ad: adUret(dkFonKodu, devlet: true),
        pay: pay,
        maliyet: dkOdenen ?? dkBirikim,
        fiyat: fiyat,
        tarih: an,
        devlet: true,
      ));
    }

    await SupabaseService.instance.insertSozlesme(s);
    try {
      await ref.read(portfolioProvider.notifier).sozlesmeLotlariniEkle(lotlar);
    } catch (_) {
      await _geriAl(s.id);
      rethrow;
    }
    SozlesmeDeposu.instance.yaz([s], const []);
    _yayinla([s], const []);
  }

  /// Bu yıl bu sözleşmeye yazılmış devlet katkısı (TL, maliyetten).
  ///
  /// AÇILIŞ lotları sayılmaz: onların tutarı geçmiş yılların birikimidir.
  /// Açılış lotları aynı anda yazılır; sözleşmenin en eski lot anı açılış
  /// anıdır ve katkı lotları hep ondan sonradır (katkı tarihi açılıştan
  /// önce seçilemez).
  double buYilDevletKatkisi(String sozlesmeId, int yil) {
    final lotlar = [
      for (final a in ref.read(portfolioProvider).valueOrNull?.assets ??
          const <Asset>[])
        if (a.sozlesmeId == sozlesmeId && a.isBuy && a.isActive) a,
    ];
    if (lotlar.isEmpty) return 0;
    final acilis = lotlar
        .map((a) => a.addedDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return lotlar
        .where((a) =>
            a.subCategory == BesAltKategori.devletKatkisi &&
            a.addedDate.isAfter(acilis) &&
            a.addedDate.year == yil)
        .fold<double>(0, (t, a) => t + a.totalCost);
  }

  /// Katkı tarihleri (açılış hariç) — "bu ayın katkısı eklendi mi".
  List<DateTime> katkiTarihleri(String sozlesmeId) {
    final lotlar = [
      for (final a in ref.read(portfolioProvider).valueOrNull?.assets ??
          const <Asset>[])
        if (a.sozlesmeId == sozlesmeId && a.isBuy && a.isActive) a,
    ];
    if (lotlar.isEmpty) return const [];
    final acilis = lotlar
        .map((a) => a.addedDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return [
      for (final a in lotlar)
        if (a.addedDate.isAfter(acilis) &&
            a.subCategory != BesAltKategori.devletKatkisi)
          a.addedDate,
    ];
  }

  /// Aylık (ya da ara) katkı: dağılıma göre fon lotları + devlet katkısı.
  ///
  /// Pay adedi o anki TEFAS fiyatıyla hesaplanır; şirket katkıyı T+1/T+2'de
  /// fona yatırır, aradaki fiyat farkı küçüktür ve bir sonraki fiyat
  /// turunda değer zaten güncellenir.
  Future<void> besKatkiEkle({
    required String sozlesmeId,
    required double tutar,
    required double devletKatkisi,
    required String Function(String kod, {required bool devlet}) adUret,
    DateTime? tarih,
  }) async {
    final uid = _kullanici();
    final s = _simdiki.sozlesme(sozlesmeId);
    if (s == null || tutar <= 0) return;
    final dkVar = s.dkFonKodu != null && devletKatkisi > 0;
    final fiyatlar = await _fonFiyatlari([
      for (final f in s.fonDagilimi) f.kod,
      if (dkVar) s.dkFonKodu!,
    ]);
    final an = tarih ?? DateTime.now();
    final lotlar = <Asset>[];
    for (final e in BesHesabi.katkiyiBol(tutar, s.fonDagilimi).entries) {
      final fiyat = fiyatlar[e.key]!;
      lotlar.add(_besLotu(
        uid: uid,
        s: s,
        kod: e.key,
        ad: adUret(e.key, devlet: false),
        pay: e.value / fiyat,
        maliyet: e.value,
        fiyat: fiyat,
        tarih: an,
        devlet: false,
      ));
    }
    if (dkVar) {
      final kod = s.dkFonKodu!;
      final fiyat = fiyatlar[kod]!;
      lotlar.add(_besLotu(
        uid: uid,
        s: s,
        kod: kod,
        ad: adUret(kod, devlet: true),
        pay: devletKatkisi / fiyat,
        maliyet: devletKatkisi,
        fiyat: fiyat,
        tarih: an,
        devlet: true,
      ));
    }
    await ref.read(portfolioProvider.notifier).sozlesmeLotlariniEkle(lotlar);
  }

  // ── Yardımcılar ────────────────────────────────────────────────────────

  Asset _besLotu({
    required String uid,
    required Sozlesme s,
    required String kod,
    required String ad,
    required double pay,
    required double maliyet,
    required double fiyat,
    required DateTime tarih,
    required bool devlet,
  }) =>
      Asset(
        id: _uuid.v4(),
        userId: uid,
        name: ad,
        ticker: '$tefasOneki$kod',
        type: AssetType.bes,
        subCategory:
            devlet ? BesAltKategori.devletKatkisi : BesAltKategori.katki,
        quantity: pay,
        // Birim maliyet: toplam maliyet ÷ pay. Açılışta ödenen katkı
        // birikimden az olduğu için bu, bugünkü fiyattan düşüktür.
        purchasePrice: pay > 0 ? maliyet / pay : fiyat,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: fiyat,
        lastUpdated: DateTime.now(),
        addedDate: tarih,
        sozlesmeId: s.id,
      );

  /// TEFAS emeklilik fonu fiyatları; biri eksikse [BesFiyatYokException].
  Future<Map<String, double>> _fonFiyatlari(List<String> kodlar) async {
    final semboller = {for (final k in kodlar) '$tefasOneki$k'}.toList();
    final q = await PriceService.instance.fetchQuotes(semboller);
    final out = <String, double>{};
    for (final k in kodlar) {
      final p = q['$tefasOneki$k']?.regularMarketPrice;
      if (p == null || p <= 0) throw BesFiyatYokException(k);
      out[k] = p;
    }
    return out;
  }

  Future<void> _geriAl(String sozlesmeId) async {
    try {
      await SupabaseService.instance.deleteSozlesme(sozlesmeId);
    } catch (_) {
      // Geri alma da düşerse sözleşme yetim kalır; lotu olmadığı için
      // hiçbir yüzeyde görünmez. Asıl hata yukarı çıkar.
    }
  }

  static DateTime _bugun() {
    final n = DateTime.now();
    return dayKey(n);
  }

  static Asset _pozisyonTemsili(Asset a, double birim) => Asset(
        id: 'pos:${a.sozlesmeId}',
        userId: a.userId,
        name: a.name,
        ticker: a.ticker,
        type: a.type,
        quantity: a.quantity,
        purchasePrice: a.purchasePrice,
        currency: a.currency,
        notes: '',
        isManualPrice: false,
        currentPrice: birim,
        lastUpdated: DateTime.now(),
        sozlesmeId: a.sozlesmeId,
      );
}

final sozlesmeProvider =
    AsyncNotifierProvider<SozlesmeNotifier, SozlesmeState>(SozlesmeNotifier.new);
