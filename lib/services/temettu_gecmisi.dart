import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/asset.dart';
import '../models/position.dart' show positionKey;
import 'crash_reporter.dart';

/// Temettü yakalama — istemci tarafı (plan §F5, ADR-2 A: Yahoo `events=div`).
///
/// ## Bu dosya KAYIT YAZMAZ
/// Temettü satırı (`kind='dividend'`) yine yalnız `addDividend` yolundan ve
/// kullanıcı ONAYIYLA yazılır; temettü miktara girmez değişmezi o tek yolda
/// korunur. Buradaki her şey ÖNERİ üretir: "Yahoo'ya göre şu gün şu kadar
/// dağıtıldı, o gün şu kadar lotun vardı, kaydettin mi?"
///
/// ## Uydurma sayı yok
/// Yahoo yalnız GERÇEKLEŞMİŞ (hak kullanımı yapılmış) temettüyü, BRÜT TL/pay
/// olarak verir. Tutarı okunamayan olay atılır; stopaj oranı bilinmiyorsa
/// (Remote Config `temettu_stopaj_orani` = -1) net tahmin EDİLMEZ, öneri
/// brüt kalır ve kullanıcı net tutarı kendisi girer.
///
/// ## Sunucu eşi
/// `supabase/functions/temettu-yakala` aynı kuralları push için uygular
/// (hak tarihinde lot, kayıt penceresi −7/+60 gün). Tek bilinçli fark: sunucu
/// mezar taşı sezgisini de uygular (yanlış bildirim pahalı), burası
/// kullanıcının ekranda gördüğü defteri (`Asset.isActive`) okur.

/// Epoch/yerel an → TR takvim günü (TR sabit UTC+3, yaz saati yok).
///
/// Hak tarihi ve alım günü AYNI takvimde karşılaştırılmalı: cihaz saat
/// dilimi Londra olan kullanıcıda 23:30 TR alımı önceki güne kaymasın.
/// Dönen değer saatsiz bir takvim günüdür (`DateTime.utc(y, m, d)`).
DateTime trGunu(DateTime t) {
  final u = t.toUtc().add(const Duration(hours: 3));
  return DateTime.utc(u.year, u.month, u.day);
}

/// Yahoo'nun bildirdiği tek bir gerçekleşmiş temettü.
class TemettuOlayi {
  /// Hak kullanım (ex) günü — TR takvimi, saatsiz.
  final DateTime hakTarihi;

  /// TL/pay, BRÜT.
  final double tutarPay;

  const TemettuOlayi({required this.hakTarihi, required this.tutarPay});

  @override
  bool operator ==(Object other) =>
      other is TemettuOlayi &&
      other.hakTarihi == hakTarihi &&
      other.tutarPay == tutarPay;

  @override
  int get hashCode => Object.hash(hakTarihi, tutarPay);
}

/// Diyaloğu ön dolduran öneri — push (`type: 'temettu'`), çan kaydı ya da
/// "Son 12 ay temettü" kartından gelir.
class TemettuOnerisi {
  /// Yahoo sembolü (`THYAO.IS`) — `assets.ticker` ile aynı yazım.
  final String ticker;
  final DateTime hakTarihi;
  final double tutarPay;

  /// Hak tarihindeki net lot (o gün ve sonrası alım sayılmaz).
  final double lot;

  const TemettuOnerisi({
    required this.ticker,
    required this.hakTarihi,
    required this.tutarPay,
    required this.lot,
  });

  /// BRÜT tutar — `lot × TL/pay`.
  double get brut => lot * tutarPay;

  /// Push/çan verisi (`temettu-yakala` › `temettuVerisi`). Sayılar makine
  /// biçiminde (nokta ondalık). Eksik ya da bozuk alan → `null`: yarım
  /// veriyle ön dolu diyalog yanlış tutar önerir, açmamak yeğdir.
  static TemettuOnerisi? fromPush(Map<String, dynamic> data) {
    final ticker = data['ticker']?.toString().trim().toUpperCase() ?? '';
    if (ticker.isEmpty) return null;
    final gun = _gunAyristir(data['hak_tarihi']?.toString());
    final tutar = double.tryParse(data['tutar_pay']?.toString() ?? '');
    final lot = double.tryParse(data['lot']?.toString() ?? '');
    if (gun == null || tutar == null || lot == null) return null;
    if (!tutar.isFinite || tutar <= 0 || !lot.isFinite || lot <= 0) {
      return null;
    }
    return TemettuOnerisi(
        ticker: ticker, hakTarihi: gun, tutarPay: tutar, lot: lot);
  }

  static DateTime? _gunAyristir(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final a = int.parse(m.group(2)!);
    final g = int.parse(m.group(3)!);
    final d = DateTime.utc(y, a, g);
    // `DateTime.utc(2025, 2, 31)` 3 Mart'a taşar — geçersiz tarih reddedilir.
    if (d.year != y || d.month != a || d.day != g) return null;
    return d;
  }
}

/// Kartın bir satırı: olay + o gün tutulan lot + (varsa) eşleşen kayıt.
class TemettuSatiri {
  final TemettuOlayi olay;
  final double lot;

  /// Bu olayı karşılayan temettü kaydı; `null` → kaydedilmemiş.
  final Asset? kayit;

  const TemettuSatiri({required this.olay, required this.lot, this.kayit});

  double get brut => lot * olay.tutarPay;
  bool get kaydedildi => kayit != null;

  TemettuOnerisi oneri(String ticker) => TemettuOnerisi(
        ticker: ticker,
        hakTarihi: olay.hakTarihi,
        tutarPay: olay.tutarPay,
        lot: lot,
      );
}

/// Saf hesaplar — ağ, Supabase, `BuildContext` yok; testler doğrudan çağırır.
abstract final class TemettuGecmisi {
  /// Kartın geriye bakış penceresi.
  static const pencereGun = 365;

  /// Bir kayıt, hak tarihinden bu kadar gün ÖNCE ile [kayitSonraGun] SONRA
  /// arasındaysa olayı karşılar. Kayıt satırı hak tarihini değil ödeme
  /// gününü taşır: BIST'te ödeme çoğunlukla hak günü, taksitli ödemede
  /// aylar sonra; kullanıcı tarihi birkaç gün önce de girebilir. Sunucu
  /// (`temettu-yakala`) AYNI pencereyi kullanır.
  static const kayitOnceGun = 7;
  static const kayitSonraGun = 60;

  /// Yahoo chart gövdesinden son [pencereGun] günün olayları, yeniden
  /// eskiye. Geçersiz tutar/tarih ATILIR (uydurma yok); aynı güne iki kayıt
  /// gelirse sonuncusu kalır.
  static List<TemettuOlayi> olaylariAyristir(
    Object? govde, {
    required DateTime simdi,
    int pencereGun = TemettuGecmisi.pencereGun,
  }) {
    final div = _divHaritasi(govde);
    if (div == null) return const [];
    final ust = trGunu(simdi);
    final alt = ust.subtract(Duration(days: pencereGun));
    final tekil = <DateTime, double>{};
    for (final v in div.values) {
      if (v is! Map) continue;
      // `as num?` DEĞİL: metin gelen alan fırlatır, tüm liste kaybolurdu.
      final d = v['date'];
      final m = v['amount'];
      final tarih = d is num ? d.toDouble() : null;
      final tutar = m is num ? m.toDouble() : null;
      if (tarih == null || !tarih.isFinite || tarih <= 0) continue;
      if (tutar == null || !tutar.isFinite || tutar <= 0) continue;
      final gun = trGunu(DateTime.fromMillisecondsSinceEpoch(
          (tarih * 1000).round(),
          isUtc: true));
      if (gun.isBefore(alt) || gun.isAfter(ust)) continue;
      tekil[gun] = tutar;
    }
    final out = [
      for (final e in tekil.entries)
        TemettuOlayi(hakTarihi: e.key, tutarPay: e.value),
    ]..sort((a, b) => b.hakTarihi.compareTo(a.hakTarihi));
    return out;
  }

  static Map<dynamic, dynamic>? _divHaritasi(Object? govde) {
    if (govde is! Map) return null;
    final chart = govde['chart'];
    if (chart is! Map) return null;
    final result = chart['result'];
    if (result is! List || result.isEmpty) return null;
    final ilk = result.first;
    if (ilk is! Map) return null;
    final events = ilk['events'];
    if (events is! Map) return null;
    final div = events['dividends'];
    return div is Map ? div : null;
  }

  /// [varlik] ile aynı sahip + aynı pozisyon anahtarındaki aktif satırlar.
  static Iterable<Asset> _pozisyonSatirlari(
      Iterable<Asset> defter, Asset varlik) {
    final anahtar = positionKey(varlik);
    return defter.where((a) =>
        a.isActive &&
        a.userId == varlik.userId &&
        positionKey(a) == anahtar);
  }

  /// Hak tarihindeki net lot: hak GÜNÜNDEN önceki alımlar − satımlar.
  ///
  /// BIST'te hak kullanım günü açılışında fiyat düzeltilir: o gün alan
  /// temettü ALMAZ, o gün satan ALIR. Temettü satırı miktara girmez.
  /// Geçmişi soran bir hesap olduğu için ham defter okunur (CLAUDE.md
  /// "Kapanmış pozisyon"): bugün kapalı pozisyonun geçmiş temettüsü de
  /// görünür.
  static double hakTarihindekiLot(
      Iterable<Asset> defter, Asset varlik, DateTime hakTarihi) {
    var net = 0.0;
    for (final a in _pozisyonSatirlari(defter, varlik)) {
      if (!a.isBuy && !a.isSell) continue;
      if (!trGunu(a.addedDate).isBefore(hakTarihi)) continue;
      net += a.isSell ? -a.quantity : a.quantity;
    }
    // Kayan nokta: 3 × 0,1 lot 0,30000000000000004 eder.
    return net > 1e-7 ? net : 0;
  }

  /// Olaylar × defter → kart satırları (yeniden eskiye). Hak tarihinde lot'u
  /// olmayan olay satır DEĞİLDİR (o temettü kullanıcıya ait değil).
  ///
  /// Eşleme BİRE BİR ve EN YAKIN önce: tüm (olay, kayıt) çiftleri pencere
  /// içindeyse gün farkına göre sıralanır, en yakın çift önce eşleşir. Yılda
  /// iki kez dağıtan hissede tek kayıt iki olayı birden "kaydedildi"
  /// göstermez; 16 Haziran'da girilen kayıt 20 Mayıs'a değil 16 Haziran
  /// olayına gider.
  static List<TemettuSatiri> satirlar({
    required Asset varlik,
    required Iterable<Asset> defter,
    required List<TemettuOlayi> olaylar,
  }) {
    final pozisyon = _pozisyonSatirlari(defter, varlik).toList();
    final kayitlar = [
      for (final a in pozisyon)
        if (a.isDividend) a,
    ];
    final lotlu = <(TemettuOlayi, double)>[
      for (final o in olaylar)
        (o, hakTarihindekiLot(pozisyon, varlik, o.hakTarihi)),
    ].where((e) => e.$2 > 0).toList();

    final ciftler = <(int olay, int kayit, int fark)>[];
    for (var i = 0; i < lotlu.length; i++) {
      final hak = lotlu[i].$1.hakTarihi;
      final alt = hak.subtract(const Duration(days: kayitOnceGun));
      final ust = hak.add(const Duration(days: kayitSonraGun));
      for (var j = 0; j < kayitlar.length; j++) {
        final gun = trGunu(kayitlar[j].addedDate);
        if (gun.isBefore(alt) || gun.isAfter(ust)) continue;
        ciftler.add((i, j, gun.difference(hak).inDays.abs()));
      }
    }
    ciftler.sort((a, b) => a.$3.compareTo(b.$3));
    final olayKaydi = <int, Asset>{};
    final kullanilan = <int>{};
    for (final (i, j, _) in ciftler) {
      if (olayKaydi.containsKey(i) || kullanilan.contains(j)) continue;
      olayKaydi[i] = kayitlar[j];
      kullanilan.add(j);
    }

    final out = [
      for (var i = 0; i < lotlu.length; i++)
        TemettuSatiri(olay: lotlu[i].$1, lot: lotlu[i].$2, kayit: olayKaydi[i]),
    ]..sort((a, b) => b.olay.hakTarihi.compareTo(a.olay.hakTarihi));
    return out;
  }

  /// Son [pencereGun] günde bu pozisyon için KAYDEDİLMİŞ temettü toplamı
  /// (varlığın para biriminde, net — kullanıcının girdiği).
  static double kaydedilenToplam(
    Iterable<Asset> defter,
    Asset varlik, {
    required DateTime simdi,
  }) {
    final alt = trGunu(simdi).subtract(const Duration(days: pencereGun));
    var t = 0.0;
    for (final a in _pozisyonSatirlari(defter, varlik)) {
      if (!a.isDividend) continue;
      if (trGunu(a.addedDate).isBefore(alt)) continue;
      t += a.dividendAmount;
    }
    return t;
  }

  /// Diyaloğa önerilecek tutar.
  ///
  /// [stopaj] 0..1 aralığındaysa NET (`brüt × (1 − stopaj)`), değilse
  /// (`null` = bilinmiyor) tutar YOK (`null`) — oran uydurulmaz.
  ///
  /// Eskiden bilinmeyen oranda BRÜT dönüyordu ve diyalog "ele geçen NET
  /// tutar" alanını brütle ön dolduruyordu: tek dokunuş "Kaydet" brütü net
  /// diye yazıyordu (emülatör testi #12, 2026-09-29) — uydurma sayının
  /// kılık değiştirmiş hâli. Bilinmiyorsa alan boş açılır, brüt yalnız
  /// yardımcı metinde durur; neti kullanıcı yazar.
  static ({double? tutar, bool net}) oneriTutari(double brut, double? stopaj) {
    if (stopaj == null || !stopaj.isFinite || stopaj < 0 || stopaj >= 1) {
      return (tutar: null, net: false);
    }
    return (tutar: brut * (1 - stopaj), net: true);
  }
}

/// Yahoo'dan temettü olaylarını çeken ince G/Ç katmanı.
///
/// `http` yalnız burada (CLAUDE.md katmanlama: ekran/widget'ta yok). Sembol
/// kararı `FiyatKaynagi.temettuSembolu`'nda; bu sınıf verilen sembolü çeker.
class TemettuGecmisiService {
  static final TemettuGecmisiService instance = TemettuGecmisiService();

  TemettuGecmisiService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  /// Temettü günde en çok bir kez değişir; varlık ekranı her açılışta ağa
  /// çıkmasın. Oturum içi, sembol başına.
  static const _omur = Duration(hours: 6);
  final _onbellek = <String, ({DateTime at, List<TemettuOlayi> olaylar})>{};

  /// Aynı sembol için süren istek paylaşılır (ekran hızlı açılıp kapanınca
  /// ikinci istek çıkmasın).
  final _suren = <String, Future<List<TemettuOlayi>>>{};

  /// [sembol]'ün son 12 aydaki gerçekleşmiş temettüleri, yeniden eskiye.
  ///
  /// Hata → boş liste: kart kendini gizler. Ağ hatası beklenen durumdur,
  /// Crashlytics'e yalnız ağ DIŞI hatalar (ayrıştırma vb.) gider.
  Future<List<TemettuOlayi>> olaylariCek(String sembol, {DateTime? simdi}) {
    final an = simdi ?? DateTime.now();
    final kayit = _onbellek[sembol];
    if (kayit != null && an.difference(kayit.at) < _omur) {
      return Future.value(kayit.olaylar);
    }
    return _suren[sembol] ??= _cek(sembol, an).whenComplete(() {
      _suren.remove(sembol);
    });
  }

  Future<List<TemettuOlayi>> _cek(String sembol, DateTime simdi) async {
    // `2y`: pencere 365 gün; `1y` aralığı Yahoo'da takvim sınırına
    // yuvarlandığında uçtaki olayı kaçırabiliyor. Fazlası saf katmanda
    // pencereyle kırpılır. `1mo`: yalnız olaylar gerekiyor, fiyat değil.
    final uri = Uri.https('query1.finance.yahoo.com',
        '/v8/finance/chart/$sembol', {
      'range': '2y',
      'interval': '1mo',
      'events': 'div',
    });
    try {
      final res = await _client.get(uri, headers: {
        'User-Agent': _ua,
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final olaylar = TemettuGecmisi.olaylariAyristir(
        jsonDecode(res.body),
        simdi: simdi,
      );
      _onbellek[sembol] = (at: simdi, olaylar: olaylar);
      return olaylar;
    } catch (e, st) {
      if (!CrashReporter.agHatasiMi(e)) {
        CrashReporter.report(e, st, reason: 'TemettuGecmisiService.olaylariCek');
      }
      return const [];
    }
  }
}
