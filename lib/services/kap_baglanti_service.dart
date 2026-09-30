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
/// şeyin aynısı.
///
/// ## Neden kodla adres kurulmuyor (ölçüm, 2026-09-30)
/// `…/sirket-bilgileri/ozet/THYAO` sunucuda şirketi ÇÖZMÜYOR (THYAO ile
/// uydurma "ZZZZZ" aynı boş kabuğu döndürdü). Şirketi tanıyan kalıcı adres
/// (`…/ozet/1107-turk-hava-yollari-a-o`) KAP'ın kendi şirket arama ucundan
/// gelir.
///
/// ## Neden şirket sayfası (kullanıcı kararı, 2026-09-30 ikinci tur)
/// Aynı gün bir ara bildirim listesine (`bildirim-sorgu-sonuc?member=`)
/// çevrilmişti; kullanıcı: "tıklandığında o varlığın sayfası açılmalı".
/// Şirket sayfası bildirimlere de bağlantı veriyor.
///
/// ## Neden yalnız TEK sonuçta — ve bulunamazsa satır HİÇ yok
/// Arama ucu kodda VE unvanda alt dize arar. Hisse kodu dizinde olduğu için
/// doğru şirket her zaman sonuçlardadır; tek sonuç = o şirket. Ama başka
/// şirketlerin unvanı da eşleşebilir ("GARAN" → üç Garanti şirketi) — o
/// zaman hangisi olduğu bilinemez. Fon kodlarında ise dizinde değiller ve
/// TEK yanlış sonuç gelebiliyor ("AFT" → DO & CO AktiengesellschAFT);
/// bu yüzden servis yalnız BIST hissesi için çağrılır (`KapBaglantisi`).
/// Adres çözülemezse `null`: kullanıcı kararı "KAP bilgisi olabilecek
/// olanlarda gözükmeli" — yanlış şirkete ya da boş bir sorgu sayfasına
/// götüren satır göstermektense satır çizilmez.
class KapBaglantiService {
  KapBaglantiService._({http.Client? istemci}) : _istemci = istemci;

  static final KapBaglantiService instance = KapBaglantiService._();

  /// Test için.
  factory KapBaglantiService.test(http.Client istemci) =>
      KapBaglantiService._(istemci: istemci);

  final http.Client? _istemci;

  /// Oturum önbelleği — çözülemeyen kod da (`null`) saklanır: ekran her
  /// açıldığında yeniden sorulmaz.
  final Map<String, Uri?> _onbellek = {};

  static const _kok = 'https://www.kap.org.tr/tr';
  static const _sure = Duration(seconds: 6);

  /// Önbellekte cevap var mı (ekran ilk karede satırı çizebilsin diye).
  bool biliniyor(String ticker) => _onbellek.containsKey(_kod(ticker));
  Uri? onbellekte(String ticker) => _onbellek[_kod(ticker)];

  static String _kod(String ticker) =>
      ticker.trim().toUpperCase().replaceAll(RegExp(r'\.IS$'), '');

  /// BIST kodu ("THYAO" ya da "THYAO.IS") → şirketin KAP sayfası; tek ve
  /// kesin bir şirket bulunamazsa `null`. Hata fırlatmaz.
  Future<Uri?> sirketSayfasi(String ticker) async {
    final kod = _kod(ticker);
    if (!RegExp(r'^[A-Z0-9]{3,6}$').hasMatch(kod)) return null;
    if (_onbellek.containsKey(kod)) return _onbellek[kod];
    try {
      final uri = Uri.parse('$_kok/api/member/filter/$kod');
      final yanit = await (_istemci?.get(uri) ?? http.get(uri)).timeout(_sure);
      // Sunucu hatası kalıcı sayılmaz: önbelleğe yazılmaz, sonraki açılışta
      // yeniden sorulur.
      if (yanit.statusCode != 200) return null;
      final perma = tekPermaLink(utf8.decode(yanit.bodyBytes));
      final adres = perma == null
          ? null
          : Uri.parse('$_kok/sirket-bilgileri/ozet/$perma');
      _onbellek[kod] = adres;
      return adres;
    } on TimeoutException {
      return null;
    } catch (e, st) {
      // Ağ yok / biçim değişti: satır çizilmez; biçim değişikliği
      // Crashlytics'te görünsün.
      CrashReporter.report(e, st, reason: 'KapBaglantiService.sirketSayfasi');
      return null;
    }
  }

  /// Arama yanıtından şirketin kalıcı adresi — YALNIZ tek sonuçta (bkz.
  /// sınıf notu). Biçim beklenmedikse `null`.
  static String? tekPermaLink(String govde) {
    final veri = jsonDecode(govde);
    if (veri is! List || veri.length != 1) return null;
    final ilk = veri.first;
    if (ilk is! Map) return null;
    final perma = ilk['permaLink'];
    if (perma is! String) return null;
    return RegExp(r'^\d+-[a-z0-9-]+$').hasMatch(perma) ? perma : null;
  }
}
