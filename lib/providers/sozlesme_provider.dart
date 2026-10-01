import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/tr_format.dart';
import 'package:uuid/uuid.dart';

import '../demo/demo_modu.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../models/sozlesme.dart';
import '../services/bes_hesabi.dart';
import '../services/crash_reporter.dart';
import '../services/history_service.dart';
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

/// [a] lotu [s] sözleşmesine mi ait?
///
/// Önce `sozlesme_id`. Mevduatta ek olarak `MEVDUAT:<id>` sembolü de
/// sayılır (stopaj incelemesi, 2026-10-01): portföydeki "+" (hızlı alım)
/// lotu sözleşme kimliği taşımadan yazılıyordu. O lot pozisyonda ve
/// toplamda görünüyor ama kart ve "Çektim" onu görmüyordu — çekimden sonra
/// eklenen para portföyde açık kalıp faiz işletmeye devam ediyordu. Canlıda
/// böyle yazılmış lotlar olabileceği için düzeltme okuma tarafında da
/// yapılır; sembol sözleşmeye özgüdür, başka sözleşmenin lotu karışmaz.
/// BES'te sembol (`TEFAS:KOD`) sözleşmeye özgü değildir, yalnızca kimlik.
bool sozlesmeLotuMu(Asset a, Sozlesme s) {
  if (a.sozlesmeId == s.id) return true;
  return s.tur == SozlesmeTuru.mevduat &&
      a.sozlesmeId == null &&
      mevduatSozlesmeId(a.ticker) == s.id.toLowerCase();
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
    // Seri dönemlerden üretilir; önbellekteki eski seri unutulmazsa grafik
    // eski çizgide kalır ve geriye dönük faiz bugünkü kazanç gibi görünür.
    HistoryService.instance.sembolUnut(mevduatSembolu(sozlesmeId));
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
        if (sozlesmeLotuMu(a, s) && a.isActive) a,
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
  /// ## Açılış lotları GİRİŞ tarihlidir (kullanıcı kararı 2026-10-01)
  /// Kullanıcı ekstresindeki üç sayıyı girer: ana para (ödediği katkı),
  /// getiri ve devlet katkısı (ana para + getiri). Geçmiş katkıların
  /// tarihleri ve pay adetleri bilinmiyor; bugünkü fonların serisini geçmişe
  /// uygulamak, dağılım sık değiştiyse uydurma bir tarihçe olurdu. Bu yüzden
  /// birikim sisteme giriş gününde var sayılır ve açılış anına kadar DÜZ
  /// çizilir (`BesAcilis`). Sonuç: kâr ilk günden görünür, açılış günü
  /// sahte bir "piyasa etkisi" sıçraması olmaz, geçmiş dönemlerin piyasa
  /// etkisi 0'dır.
  ///
  /// Önceden açılış lotları BUGÜN tarihliydi; o kayıtlarda açılış anı ile
  /// lot anı aynı olduğundan düz çizgi kuralı etkisizdir (geriye uyumlu).
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
    bool otomatikKatki = false,
  }) async {
    final uid = _kullanici();
    final an = DateTime.now();
    // Otomatik katkı yalnız plan tamken (0096 kısıtı da ister). İmleç
    // bugün: açılış birikimi bugüne kadarki katkıları zaten içerir.
    final otomatik = otomatikKatki && aylikKatki != null && katkiGunu != null;
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
      // Sunucunun `created_at`'i ile aynı an (birkaç ms farkla); yeniden
      // yüklemeye kadar açılış anını bu taşır.
      olusturuldu: an,
      otomatikKatki: otomatik,
      otomatikKatkiSon: otomatik ? dayKey(an) : null,
    );
    // Giriş bugünse ya da gelecekteyse (saat farkı) lot şimdi tarihli.
    final girisGunu = dayKey(giris);
    final lotTarihi = girisGunu.isBefore(an) ? girisGunu : an;
    final dkVar = dkFonKodu != null && (dkBirikim ?? 0) > 0;
    final fiyatlar = await _fonFiyatlari([
      for (final f in dagilim) f.kod,
      if (dkVar) dkFonKodu,
    ]);

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
        tarih: lotTarihi,
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
        tarih: lotTarihi,
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
    final hepsi = [
      for (final a in ref.read(portfolioProvider).valueOrNull?.assets ??
          const <Asset>[])
        if (a.sozlesmeId == sozlesmeId && a.isActive) a,
    ];
    final lotlar = [
      for (final a in hepsi)
        if (a.isBuy) a,
    ];
    if (lotlar.isEmpty) return const [];
    final acilis = lotlar
        .map((a) => a.addedDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final degisim = _fonDegisimAnlari(hepsi);
    return [
      for (final a in lotlar)
        if (a.addedDate.isAfter(acilis) &&
            a.subCategory != BesAltKategori.devletKatkisi &&
            !degisim.contains(a.addedDate.microsecondsSinceEpoch))
          a.addedDate,
    ];
  }

  /// Fon değişikliğinin anları. Değişimin alış ayağı katkı DEĞİLDİR: satış
  /// ayağıyla aynı anda yazılır (`besFonDegistir`, tek `an`). Sayılsaydı fon
  /// değiştirilen ay "katkı eklendi" görünür; hatırlatma susar, otomatik
  /// katkı o ayı atlardı (2026-10-01'de otomatik katkı yazılırken bulundu).
  static Set<int> _fonDegisimAnlari(Iterable<Asset> lotlar) => {
        for (final a in lotlar)
          if (a.isSell) a.addedDate.microsecondsSinceEpoch,
      };

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
    final lotlar = _katkiLotlari(
      uid: uid,
      s: s,
      tutar: tutar,
      devletKatkisi: dkVar ? devletKatkisi : 0,
      fiyatlar: fiyatlar,
      tarih: tarih ?? DateTime.now(),
      adUret: adUret,
    );
    await ref.read(portfolioProvider.notifier).sozlesmeLotlariniEkle(lotlar);
  }

  // ── BES otomatik katkı (0096, kullanıcı isteği 2026-10-01) ─────────────

  bool _otomatikCalisiyor = false;

  /// Otomatik katkısı açık BES'lerde günü gelen katkıları yazar.
  ///
  /// Uygulama açılışında ve öne dönüşte çağrılır (`_AuthGate`); sunucuda
  /// cron yok. Her katkı KENDİ günüyle ve o günün TEFAS fiyatıyla yazılır
  /// (`_fonFiyatlariGunu`): uygulama üç ay açılmadıysa üç ayrı katkı,
  /// bugünün fiyatıyla tek yığın değil. Fiyat bulunamazsa o günde durulur
  /// ve imleç o günün öncesine kurulur: bir sonraki açılış yeniden dener,
  /// uydurma fiyatla pay yazılmaz.
  ///
  /// Tutar sözleşmedeki aylık katkıdır ("miktar değişmediği sürece").
  /// Kullanıcı farklı ödediyse kart sorar, [otomatikKatkiGuncelle] düzeltir.
  /// Son yazılan gün [Sozlesme.otomatikKatkiBekleyen]'e konur: soru o
  /// onaylanana kadar kartta durur.
  ///
  /// Dönen liste yazılan katkılar (bildirim için); hiçbir şey yazılmadıysa
  /// boş. Hatalar Crashlytics'e gider, yukarı çıkmaz: açılışı bozmamalı.
  Future<List<({String sozlesmeId, DateTime gun, double tutar})>>
      otomatikKatkilariIsle({
    required String Function(Sozlesme s, String kod, {required bool devlet})
        adUret,
    required String not,
  }) async {
    if (_otomatikCalisiyor || DemoModu.aktif) return const [];
    _otomatikCalisiyor = true;
    final eklenen = <({String sozlesmeId, DateTime gun, double tutar})>[];
    try {
      final durum = await future;
      final adaylar = [
        for (final s in durum.sozlesmeler.values)
          if (s.tur == SozlesmeTuru.bes && s.otomatikKatki && s.acik) s,
      ];
      if (adaylar.isEmpty) return const [];
      await ref.read(portfolioProvider.future);
      final uid = _kullanici();
      for (final s in adaylar) {
        final gunler = BesHesabi.otomatikKatkiGunleri(
          s: s,
          simdi: DateTime.now(),
          katkiTarihleri: katkiTarihleri(s.id),
        );
        if (gunler.isEmpty) continue;
        var imlec = _bugun();
        DateTime? sonYazilan;
        final seriler = <String, List<(int, double)>>{};
        for (final gun in gunler) {
          final tutar = s.aylikKatki!;
          final dk = s.dkFonKodu == null
              ? 0.0
              : BesHesabi.devletKatkisi(
                  katki: tutar,
                  tarih: gun,
                  buYilAlinan: buYilDevletKatkisi(s.id, gun.year),
                ).tutar;
          try {
            final fiyatlar = await _fonFiyatlariGunu([
              for (final f in s.fonDagilimi) f.kod,
              if (dk > 0) s.dkFonKodu!,
            ], gun, seriler);
            await ref.read(portfolioProvider.notifier).sozlesmeLotlariniEkle(
                  _katkiLotlari(
                    uid: uid,
                    s: s,
                    tutar: tutar,
                    devletKatkisi: dk,
                    fiyatlar: fiyatlar,
                    // Yerel gece yarısı = "saati bilinmiyor" (bkz.
                    // `saatBiliniyor`): şirketin hangi saatte çektiği
                    // bilinmez; hareket listesi uydurma saat göstermesin.
                    tarih: dayKey(gun),
                    adUret: (kod, {required devlet}) =>
                        adUret(s, kod, devlet: devlet),
                    not: not,
                  ),
                );
            sonYazilan = gun;
            eklenen.add((sozlesmeId: s.id, gun: gun, tutar: tutar));
          } catch (e, st) {
            if (e is! BesFiyatYokException) {
              CrashReporter.report(e, st,
                  reason: 'SozlesmeNotifier.otomatikKatki');
            }
            imlec = DateTime(gun.year, gun.month, gun.day - 1);
            break;
          }
        }
        final yeni = s.kopya(
          otomatikKatkiSon: imlec,
          otomatikKatkiBekleyen: sonYazilan,
        );
        // Bu yazım düşerse lotlar yazılmış ama imleç eski kalır; bir sonraki
        // açılış aynı ayı "dolu" görür (`katkiTarihleri`) ve tekrar yazmaz.
        await SupabaseService.instance.updateSozlesme(yeni);
        SozlesmeDeposu.instance.yaz([yeni], const []);
        _yayinla([yeni], const []);
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SozlesmeNotifier.otomatikKatki');
    } finally {
      _otomatikCalisiyor = false;
    }
    return eklenen;
  }

  /// Otomatik katkıyı açar/kapatır (kart anahtarı).
  ///
  /// Açarken imleç `max(açılış günü, geçen ayın son günü)`: bu ayın katkı
  /// günü geçtiyse ve bu ay katkı yoksa hemen yazılır; daha eski aylar
  /// GERİYE doldurulmaz (o aylarda gerçekten ödenip ödenmediği bilinmiyor).
  /// Kapatırken bekleyen soru da kalkar.
  Future<void> otomatikKatkiAyarla(String sozlesmeId, bool acik) async {
    final s = _simdiki.sozlesme(sozlesmeId);
    if (s == null || s.tur != SozlesmeTuru.bes) return;
    if (acik && (s.aylikKatki == null || s.katkiGunu == null)) return;
    final Sozlesme yeni;
    if (acik) {
      final n = DateTime.now();
      final gecenAySonu = DateTime(n.year, n.month, 0);
      final acilis = dayKey(s.olusturuldu ?? s.baslangic);
      yeni = s.kopya(
        otomatikKatki: true,
        otomatikKatkiSon:
            acilis.isAfter(gecenAySonu) ? acilis : gecenAySonu,
      );
    } else {
      yeni = s.kopya(otomatikKatki: false, bekleyenSil: true);
    }
    await _sozlesmeYaz(yeni);
  }

  /// "Tutar doğru": bekleyen soru kalkar.
  Future<void> otomatikKatkiOnayla(String sozlesmeId) async {
    final s = _simdiki.sozlesme(sozlesmeId);
    if (s == null || s.otomatikKatkiBekleyen == null) return;
    await _sozlesmeYaz(s.kopya(bekleyenSil: true));
  }

  /// Bekleyen otomatik katkının o günkü lotları ve tutarı (kart sorusu).
  ({List<Asset> katki, Asset? dk, double tutar})? otomatikKatkiLotlari(
      String sozlesmeId) {
    final s = _simdiki.sozlesme(sozlesmeId);
    final gun = s?.otomatikKatkiBekleyen;
    if (s == null || gun == null) return null;
    final hepsi = [
      for (final a in ref.read(portfolioProvider).valueOrNull?.assets ??
          const <Asset>[])
        if (a.sozlesmeId == sozlesmeId && a.isActive) a,
    ];
    final degisim = _fonDegisimAnlari(hepsi);
    final oGun = [
      for (final a in hepsi)
        if (a.isBuy &&
            dayKey(a.addedDate) == gun &&
            !degisim.contains(a.addedDate.microsecondsSinceEpoch))
          a,
    ];
    final katki = [
      for (final a in oGun)
        if (a.subCategory != BesAltKategori.devletKatkisi) a,
    ];
    if (katki.isEmpty) return null;
    final dk = [
      for (final a in oGun)
        if (a.subCategory == BesAltKategori.devletKatkisi) a,
    ];
    return (
      katki: katki,
      dk: dk.isEmpty ? null : dk.first,
      tutar: katki.fold<double>(0, (t, a) => t + a.totalCost),
    );
  }

  /// Otomatik yazılan katkının tutarını düzeltir (kullanıcı farklı ödedi).
  ///
  /// Lotlar YERİNDE güncellenir, silinip yeniden yazılmaz: hareket
  /// listesinde "Silindi" satırı bırakmasın. Pay adedi aynı oranla
  /// ölçeklenir (birim fiyat o günün fiyatıdır, değişmez); devlet katkısı
  /// yeni tutardan yeniden hesaplanır. [planiDa] ise sonraki aylar da yeni
  /// tutarla yazılır ("miktar değişmediği sürece" kuralının değiştiği an).
  Future<void> otomatikKatkiGuncelle({
    required String sozlesmeId,
    required double yeniTutar,
    required bool planiDa,
  }) async {
    final s = _simdiki.sozlesme(sozlesmeId);
    final gun = s?.otomatikKatkiBekleyen;
    final l = otomatikKatkiLotlari(sozlesmeId);
    if (s == null || gun == null || l == null || yeniTutar <= 0) return;
    final p = ref.read(portfolioProvider.notifier);
    if (l.tutar > 0 && (yeniTutar - l.tutar).abs() > 0.005) {
      final k = yeniTutar / l.tutar;
      for (final a in l.katki) {
        await p.updateAsset(
            a.copyWithDeletedAt(a.deletedAt)..quantity = a.quantity * k);
      }
      final dk = l.dk;
      if (dk != null) {
        final eskiDk = dk.totalCost;
        final yeniDk = BesHesabi.devletKatkisi(
          katki: yeniTutar,
          tarih: gun,
          buYilAlinan: buYilDevletKatkisi(s.id, gun.year) - eskiDk,
        ).tutar;
        if (yeniDk <= 0) {
          await p.deleteAsset(dk.id);
        } else if (eskiDk > 0) {
          await p.updateAsset(dk.copyWithDeletedAt(dk.deletedAt)
            ..quantity = dk.quantity * yeniDk / eskiDk);
        }
      }
    }
    await _sozlesmeYaz(s.kopya(
      bekleyenSil: true,
      aylikKatki: planiDa ? yeniTutar : null,
    ));
  }

  Future<void> _sozlesmeYaz(Sozlesme yeni) async {
    await SupabaseService.instance.updateSozlesme(yeni);
    SozlesmeDeposu.instance.yaz([yeni], const []);
    _yayinla([yeni], const []);
  }

  /// Bu yıl bu sözleşmede yapılan fon değişikliği sayısı (bilgi; bkz.
  /// `BesHesabi.buYilFonDegisikligi`).
  int buYilFonDegisikligi(String sozlesmeId, int yil) =>
      BesHesabi.buYilFonDegisikligi([
        for (final a in ref.read(portfolioProvider).valueOrNull?.assets ??
            const <Asset>[])
          if (a.sozlesmeId == sozlesmeId &&
              a.isSell &&
              a.isActive &&
              a.subCategory != BesAltKategori.devletKatkisi)
            a.addedDate,
      ], yil);

  /// Fon değişikliği (kullanıcı kararı 2026-10-01): kendi birikimini
  /// bugünkü fiyatlarla [yeniDagilim]'a taşır.
  ///
  /// Azalan fonda satış, artan fonda alış lotu yazılır; plan ve ana para
  /// taşıma kuralı `BesHesabi.fonDegisimPlani`'nda. Satış lotu MALİYET
  /// fiyatından yazılır (`sellPrice == purchasePrice`): gerçekleşen kâr 0,
  /// nakit akışı (satış geliri = taşınan ana para = alış maliyeti) net 0.
  /// Dönem hesapları bu yüzden değişimi para giriş/çıkışı ya da piyasa
  /// hareketi saymaz; grafik bugünden sonra yeni fonların serisiyle yürür.
  ///
  /// Devlet katkısı lotlarına dokunulmaz: onun fonu ayrı talimattır ve
  /// yalnız devlet katkısı fonları arasında değişebilir.
  ///
  /// [katkiTalimatiDa] `true` ise sözleşmenin yeni katkı dağılımı da aynı
  /// olur — gerçek BES'te iki ayrı talimattır, çoğu kullanıcı ikisini
  /// birlikte değiştirir. Dönen değer: yazılan lot sayısı (0 = değişecek
  /// bir şey yoktu).
  Future<int> besFonDegistir({
    required String sozlesmeId,
    required List<FonPayi> yeniDagilim,
    required bool katkiTalimatiDa,
    required String Function(String kod, {required bool devlet}) adUret,
    required String not,
  }) async {
    final uid = _kullanici();
    final s = _simdiki.sozlesme(sozlesmeId);
    final portfoy = ref.read(portfolioProvider).valueOrNull;
    if (s == null || portfoy == null) return 0;
    final kendi = [
      for (final a in portfoy.assets)
        if (a.sozlesmeId == sozlesmeId &&
            a.isActive &&
            a.subCategory != BesAltKategori.devletKatkisi)
          a,
    ];
    final mevcut = <String, ({double pay, double maliyet})>{};
    final temsil = <String, Position>{};
    for (final p in aggregatePositions(kendi)) {
      final kod = p.representative.ticker.replaceFirst(tefasOneki, '');
      mevcut[kod] = (pay: p.totalQuantity, maliyet: p.totalCost);
      temsil[kod] = p;
    }
    final fiyatlar = await _fonFiyatlari({
      ...mevcut.keys,
      for (final f in yeniDagilim) f.kod,
    }.toList());
    final plan = BesHesabi.fonDegisimPlani(
        mevcut: mevcut, fiyatlar: fiyatlar, hedef: yeniDagilim);

    final an = DateTime.now();
    final lotlar = <Asset>[
      for (final x in plan)
        if (x.satis)
          _besSatisi(
            uid: uid,
            s: s,
            temsil: temsil[x.kod]!.representative,
            pay: x.pay,
            birimMaliyet: x.maliyet / x.pay,
            fiyat: fiyatlar[x.kod]!,
            tarih: an,
            not: not,
          )
        else
          _besLotu(
            uid: uid,
            s: s,
            kod: x.kod,
            ad: adUret(x.kod, devlet: false),
            pay: x.pay,
            maliyet: x.maliyet,
            fiyat: fiyatlar[x.kod]!,
            tarih: an,
            devlet: false,
            not: not,
          ),
    ];
    if (lotlar.isNotEmpty) {
      await ref.read(portfolioProvider.notifier).sozlesmeLotlariniEkle(lotlar);
    }
    if (katkiTalimatiDa) {
      final yeni = s.kopya(fonDagilimi: yeniDagilim);
      await SupabaseService.instance.updateSozlesme(yeni);
      SozlesmeDeposu.instance.yaz([yeni], const []);
      _yayinla([yeni], const []);
    }
    return lotlar.length;
  }

  // ── Yardımcılar ────────────────────────────────────────────────────────

  /// Fon değişikliğinin satış ayağı — maliyet fiyatından (bkz.
  /// [besFonDegistir]). `addSellTransaction` ile aynı alanlar; ayrı kurulur
  /// çünkü alışlarla TEK istekte yazılır (yarım kalan değişim olmasın).
  Asset _besSatisi({
    required String uid,
    required Sozlesme s,
    required Asset temsil,
    required double pay,
    required double birimMaliyet,
    required double fiyat,
    required DateTime tarih,
    required String not,
  }) =>
      Asset(
        id: _uuid.v4(),
        userId: uid,
        name: temsil.name,
        ticker: temsil.ticker,
        type: AssetType.bes,
        subCategory: BesAltKategori.katki,
        quantity: pay,
        purchasePrice: birimMaliyet,
        sellPrice: birimMaliyet,
        currency: 'TRY',
        notes: not,
        isManualPrice: false,
        currentPrice: fiyat,
        lastUpdated: DateTime.now(),
        kind: AssetKind.sell,
        addedDate: tarih,
        sozlesmeId: s.id,
      );

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
    String not = '',
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
        notes: not,
        isManualPrice: false,
        currentPrice: fiyat,
        lastUpdated: DateTime.now(),
        addedDate: tarih,
        sozlesmeId: s.id,
      );

  /// Bir katkının lotları: dağılıma göre fon lotları + devlet katkısı lotu
  /// ([devletKatkisi] > 0 ve fonu biliniyorsa). Elle ve otomatik katkı aynı
  /// kurucudan geçer: iki yol ayrışıp biri yeni alanı unutmasın.
  List<Asset> _katkiLotlari({
    required String uid,
    required Sozlesme s,
    required double tutar,
    required double devletKatkisi,
    required Map<String, double> fiyatlar,
    required DateTime tarih,
    required String Function(String kod, {required bool devlet}) adUret,
    String not = '',
  }) {
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
        tarih: tarih,
        devlet: false,
        not: not,
      ));
    }
    final kod = s.dkFonKodu;
    if (kod != null && devletKatkisi > 0) {
      final fiyat = fiyatlar[kod]!;
      lotlar.add(_besLotu(
        uid: uid,
        s: s,
        kod: kod,
        ad: adUret(kod, devlet: true),
        pay: devletKatkisi / fiyat,
        maliyet: devletKatkisi,
        fiyat: fiyat,
        tarih: tarih,
        devlet: true,
        not: not,
      ));
    }
    return lotlar;
  }

  /// [gun]'ün TEFAS fiyatları: o gün ya da en çok 7 gün önceki son işlem
  /// günü (hafta sonu, bayram). Bugünse anlık kotasyon. Bulunamazsa
  /// [BesFiyatYokException]: pay adedi uydurma fiyatla yazılmaz.
  ///
  /// Seri `PriceService.fetchHistory` ile gelir (fon serisinin tek kaynağı);
  /// [seriler] aynı turda fon başına bir kez çekilsin diye. Günler eskiden
  /// yeniye işlendiği için ilk çekilen (en geniş) aralık sonrakileri de
  /// kapsar.
  Future<Map<String, double>> _fonFiyatlariGunu(
    List<String> kodlar,
    DateTime gun,
    Map<String, List<(int, double)>> seriler,
  ) async {
    if (!dayKey(gun).isBefore(_bugun())) return _fonFiyatlari(kodlar);
    final ay = (DateTime.now().difference(gun).inDays / 30).ceil();
    final aralik = ay <= 1
        ? '1mo'
        : ay <= 3
            ? '3mo'
            : ay <= 6
                ? '6mo'
                : ay <= 12
                    ? '1y'
                    : '3y';
    final gunSonu =
        DateTime(gun.year, gun.month, gun.day + 1).millisecondsSinceEpoch;
    final enEski =
        DateTime(gun.year, gun.month, gun.day - 7).millisecondsSinceEpoch;
    final out = <String, double>{};
    for (final k in kodlar) {
      final seri = seriler[k] ??=
          await PriceService.instance.fetchHistory('$tefasOneki$k', aralik);
      double? f;
      for (final (t, p) in seri) {
        if (t >= gunSonu) break;
        if (t >= enEski && p > 0) f = p;
      }
      if (f == null) throw BesFiyatYokException(k);
      out[k] = f;
    }
    return out;
  }

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
