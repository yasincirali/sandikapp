// Halka arz takvimi verisi (F6, ADR-3).
//
// ## Neden sunucu yok
// Yılda ~35 halka arz; elle derlenmiş statik JSON yeterli ve iki sunucu
// kuralına (Tokyo + Frankfurt birebir) hiç dokunmaz. Dosya GitHub Pages'te
// (`docs/data/halka_arz.json`) yayınlanır; uygulama sürümü çıkmadan
// güncellenebilir. KAP veri sözleşmesi gelince kaynak otomatiğe geçer (F8).
//
// ## Okuma sırası
//   1. Bellek (1 saat) — ekran her açılışta ağa çıkmasın.
//   2. Ağ (Pages, zaman aşımlı) — başarılıysa belleğe ve DOSYAYA yazılır.
//   3. Ağ olmazsa: dosyadaki son başarılı liste ile gömülü asset'ten
//      `guncelleme` tarihi YENİ olan. Uygulama güncellemesi daha yeni bir
//      gömülü kopya getirmiş olabilir; eski dosya onu gölgelememeli.
// Gömülü kopya her zaman vardır → çevrimdışı ilk açılışta bile liste boş
// kalmaz. Hiçbir yol çalışmazsa hata fırlar ve ekran `SandikErrorView`
// gösterir.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/halka_arz.dart';
import 'crash_reporter.dart';

class HalkaArzService {
  HalkaArzService({
    http.Client? client,
    Future<String> Function()? gomuluYukle,
    Future<File?> Function()? onbellekDosyasi,
    DateTime Function()? saat,
    this.zamanAsimi = const Duration(seconds: 8),
  })  : _client = client ?? http.Client(),
        _gomuluYukle = gomuluYukle ?? (() => rootBundle.loadString(assetYolu)),
        _onbellekDosyasi = onbellekDosyasi ?? _varsayilanDosya,
        _saat = saat ?? DateTime.now;

  static final HalkaArzService instance = HalkaArzService();

  /// GitHub Pages kökü `docs/` (bkz. docs/README.md).
  static const uzakAdres =
      'https://yasincirali.github.io/sandikapp/data/halka_arz.json';
  static const assetYolu = 'assets/data/halka_arz.json';

  // Şema değişirse v2'ye çıkar → eski dosya yok sayılır.
  static const _dosyaAdi = 'halka_arz_cache_v1.json';
  static const _bellekOmru = Duration(hours: 1);

  final http.Client _client;
  final Future<String> Function() _gomuluYukle;
  final Future<File?> Function() _onbellekDosyasi;
  final DateTime Function() _saat;
  final Duration zamanAsimi;

  /// Kaydın bugüne göre durumu — saf kural `halkaArzDurumu`'nda (model
  /// dosyası); ekran ve testler servisi üzerinden de çağırabilsin diye.
  static HalkaArzDurumu durum(HalkaArz a, DateTime simdi) =>
      halkaArzDurumu(a, simdi);

  HalkaArzListesi? _bellek;
  DateTime? _bellekZamani;

  static Future<File?> _varsayilanDosya() async {
    try {
      final klasor = await getApplicationSupportDirectory();
      return File('${klasor.path}/$_dosyaAdi');
    } catch (_) {
      return null; // test ortamı / eklenti yok → yalnız bellek
    }
  }

  /// Listeyi verir. [zorla]: bellek önbelleğini atla (aşağı çekip yenileme).
  Future<HalkaArzListesi> yukle({bool zorla = false}) async {
    final b = _bellek;
    final bz = _bellekZamani;
    if (!zorla && b != null && bz != null && _saat().difference(bz) < _bellekOmru) {
      return b;
    }

    final ag = await _agdan();
    if (ag != null) return _bellegeYaz(ag);

    final dosya = await _dosyadan();
    final gomulu = await _gomuludan();
    final secilen = _yeniOlan(dosya, gomulu);
    if (secilen == null) {
      throw StateError('Halka arz listesi hiçbir kaynaktan okunamadı');
    }
    // Çevrimdışı sonuç belleğe YAZILMAZ: bağlantı gelince bir sonraki
    // açılış ağı yeniden denesin.
    return secilen;
  }

  HalkaArzListesi _bellegeYaz(HalkaArzListesi l) {
    _bellek = l;
    _bellekZamani = _saat();
    return l;
  }

  Future<HalkaArzListesi?> _agdan() async {
    try {
      final yanit = await _client
          .get(Uri.parse(uzakAdres), headers: const {'Accept': 'application/json'})
          .timeout(zamanAsimi);
      if (yanit.statusCode != 200) return null;
      final govde = utf8.decode(yanit.bodyBytes);
      final liste = HalkaArzListesi.fromJson(jsonDecode(govde), HalkaArzKaynagi.ag);
      if (liste == null) {
        // Yayındaki dosya şemaya uymuyor: bu bir veri hatası, bağlantı
        // hatası değil — derleyen kişinin görmesi gerek.
        CrashReporter.report(
          const FormatException('halka_arz.json şemaya uymuyor'),
          StackTrace.current,
          reason: 'HalkaArzService.agdan.sema',
        );
        return null;
      }
      // Dosyaya yazma yanıtı bekletmez; hatası non-fatal raporlanır.
      CrashReporter.arkaPlan(_dosyayaYaz(govde),
          reason: 'HalkaArzService.dosyayaYaz');
      return liste;
    } on TimeoutException {
      return null; // bağlantı sorunu; çevrimdışı yol devralır
    } on SocketException {
      return null;
    } on http.ClientException {
      return null;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'HalkaArzService.agdan');
      return null;
    }
  }

  Future<void> _dosyayaYaz(String govde) async {
    try {
      final f = await _onbellekDosyasi();
      if (f == null) return;
      await f.writeAsString(govde, flush: true);
    } catch (e, st) {
      // Yazılamasa da bellek önbelleği çalışır; yalnızca raporla.
      CrashReporter.report(e, st, reason: 'HalkaArzService.dosyayaYaz');
    }
  }

  Future<HalkaArzListesi?> _dosyadan() async {
    try {
      final f = await _onbellekDosyasi();
      if (f == null || !await f.exists()) return null;
      return HalkaArzListesi.fromJson(
          jsonDecode(await f.readAsString()), HalkaArzKaynagi.onbellek);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'HalkaArzService.dosyadan');
      return null;
    }
  }

  Future<HalkaArzListesi?> _gomuludan() async {
    try {
      return HalkaArzListesi.fromJson(
          jsonDecode(await _gomuluYukle()), HalkaArzKaynagi.gomulu);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'HalkaArzService.gomuludan');
      return null;
    }
  }

  /// Eşitlikte dosya kazanır: aynı gün derlenmiş iki kopyadan ağdan inmiş
  /// olan en az gömülü kadar yenidir.
  static HalkaArzListesi? _yeniOlan(HalkaArzListesi? d, HalkaArzListesi? g) {
    if (d == null) return g;
    if (g == null) return d;
    final dt = d.guncelleme;
    final gt = g.guncelleme;
    if (dt == null) return gt == null ? d : g;
    if (gt == null) return d;
    return gt.isAfter(dt) ? g : d;
  }
}
