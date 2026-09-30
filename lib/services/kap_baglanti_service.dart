import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'crash_reporter.dart';

/// Hisse ekranındaki "KAP bildirimleri ↗" bağlantısının adresi
/// (karar 7.2, 2026-09-30).
///
/// ## Neden veri çekmiyoruz
/// KAP bildirimlerini uygulama içinde yayınlamak Borsa İstanbul veri
/// lisansı ister (karar 7.1 / 7.4). Bu servis bildirim OKUMAZ; yalnızca
/// şirketin KAP sayfasının ADRESİNİ bulur ve sayfa kullanıcının
/// tarayıcısında açılır — kullanıcı KAP'ta şirketi kendisi arasa olacak
/// şeyin aynısı, dokunuş başına tek istek.
///
/// ## Neden kodla adres kurulmuyor (ölçüm, 2026-09-30)
/// `…/sirket-bilgileri/ozet/THYAO` sunucuda şirketi ÇÖZMÜYOR (THYAO ile
/// uydurma "ZZZZZ" aynı boş kabuğu döndürdü). Şirketi tanıyan kimlik
/// KAP'ın kendi şirket arama ucundan gelir. (İlk sürüm özet sayfasının
/// kalıcı adresini — `…/ozet/1107-turk-hava-yollari-a-o` — açıyordu;
/// aynı gün bildirim listesine çevrildi, aşağıda.)
///
/// ## Neden bildirim LİSTESİ (2026-09-30, kullanıcı: "son haberler")
/// Özet sayfası şirket künyesini açıyordu; kullanıcının aradığı son
/// bildirimler. `…/bildirim-sorgu-sonuc?member=<mkkMemberOid>` şirketin
/// bildirimlerini en yeniden eskiye SUNUCUDA listeliyor (ölçüldü: SAHOL
/// 108 bildirim; sahte kimlik boş). Kimlik aynı arama yanıtından gelir.
///
/// ## Neden yalnız TEK sonuçta
/// Arama ucu kodla değil adla BULANIK arar: "GARAN" ilk sırada Garanti BBVA
/// Operasyonel Kiralama'yı döndürdü. İlk sonucu almak yanlış şirketi
/// açardı. Sonuç tam olarak bir şirketse o açılır; birden çok ya da hiç
/// sonuç / hata → KAP bildirim sorgu sayfası (kullanıcı kodu orada arar).
/// Yanlış şirket, hiç açmamaktan kötüdür.
class KapBaglantiService {
  KapBaglantiService._({http.Client? istemci}) : _istemci = istemci;

  static final KapBaglantiService instance = KapBaglantiService._();

  /// Test için.
  factory KapBaglantiService.test(http.Client istemci) =>
      KapBaglantiService._(istemci: istemci);

  final http.Client? _istemci;
  final Map<String, Uri> _onbellek = {};

  static const _kok = 'https://www.kap.org.tr/tr';
  static final Uri sorguSayfasi = Uri.parse('$_kok/bildirim-sorgu');
  static const _sure = Duration(seconds: 6);

  /// BIST kodu ("THYAO" ya da "THYAO.IS") → açılacak KAP adresi. Hata
  /// fırlatmaz; bulunamazsa [sorguSayfasi].
  Future<Uri> sirketSayfasi(String ticker) async {
    final kod = ticker
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\.IS$'), '');
    if (!RegExp(r'^[A-Z0-9]{3,6}$').hasMatch(kod)) return sorguSayfasi;
    final onceki = _onbellek[kod];
    if (onceki != null) return onceki;
    try {
      final uri = Uri.parse('$_kok/api/member/filter/$kod');
      final yanit = await (_istemci?.get(uri) ?? http.get(uri)).timeout(_sure);
      if (yanit.statusCode != 200) return sorguSayfasi;
      final uye = tekUyeKimligi(utf8.decode(yanit.bodyBytes));
      if (uye == null) return sorguSayfasi;
      final adres = Uri.parse('$_kok/bildirim-sorgu-sonuc')
          .replace(queryParameters: {'member': uye});
      _onbellek[kod] = adres;
      return adres;
    } on TimeoutException {
      return sorguSayfasi;
    } catch (e, st) {
      // Ağ yok / biçim değişti: kullanıcı yine sorgu sayfasına gider; biçim
      // değişikliği Crashlytics'te görünsün.
      CrashReporter.report(e, st, reason: 'KapBaglantiService.sirketSayfasi');
      return sorguSayfasi;
    }
  }

  /// Arama yanıtından şirketin KAP üye kimliği (`mkkMemberOid`) — YALNIZ
  /// tek sonuçta (bkz. sınıf notu). Biçim beklenmedikse `null`.
  static String? tekUyeKimligi(String govde) {
    final veri = jsonDecode(govde);
    if (veri is! List || veri.length != 1) return null;
    final ilk = veri.first;
    if (ilk is! Map) return null;
    final oid = ilk['mkkMemberOid'];
    if (oid is! String) return null;
    return RegExp(r'^[0-9a-f]{32}$').hasMatch(oid) ? oid : null;
  }
}
