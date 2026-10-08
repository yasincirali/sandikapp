import 'package:supabase_flutter/supabase_flutter.dart';
import '../demo/demo_modu.dart';
import '../models/price_alert_notification.dart';
import '../models/app_notification.dart';
import '../models/asset.dart';
import '../models/eurobond.dart';
import '../models/kripto_fiyat.dart';
import '../models/kayitli_cihaz.dart';
import '../models/kullanici_adi.dart';
import '../models/signal_alert.dart';
import '../models/signal_frequency.dart';
import '../models/signal_preference.dart';
import '../models/sozlesme.dart';
import '../models/tefas_nav_gozlem.dart';
import '../models/user_model.dart';
import '../models/watchlist_item.dart';
import 'crash_reporter.dart';
import 'db_logger.dart';
import 'ekstre/ekstre_tablosu.dart' show EkstreAiHatasi;

/// Tüm Supabase veri erişimi bu sınıf üzerinden geçer.
/// RLS kuralları Supabase tarafında uygulandığı için burada
/// ekstra kullanıcı filtresi yazmaya gerek yoktur.
class SupabaseService {
  static final SupabaseService instance = SupabaseService._();
  SupabaseService._();

  // Demo (F1) sunucuya dokunmaz: kaçan bir çağrı ağa çıkmadan burada
  // düşer ve izi `DemoModu.ihlaller`e yazılır (`demo_izolasyon_test`).
  SupabaseClient get _db => DemoModu.aktif
      ? throw DemoModu.sunucuEngeli('SupabaseService')
      : Supabase.instance.client;
  final _log = DbLogger.instance;

  String? get _uid => _db.auth.currentUser?.id;
  bool? _hasPerSideHidden;

  Future<bool> _supportsPerSideHidden() async {
    final cached = _hasPerSideHidden;
    if (cached != null) return cached;
    try {
      await _db.from('partnerships').select('hidden_for_1').limit(1);
      _hasPerSideHidden = true;
    } catch (_) {
      _hasPerSideHidden = false;
    }
    return _hasPerSideHidden!;
  }

  // ── TEFAS NAV gözlemi ────────────────────────────────────────────────────

  /// Verilen fon kodları için son NAV gözlemleri (kod → en yeni satır).
  ///
  /// Yalnızca [gun] ve sonrasına ait NAV tarihleri istenir: istemci çizdiği
  /// günün basamağını arıyor, geçmiş satırların ona faydası yok. Tablo yoksa
  /// (0063 henüz koşmadı) ya da istek düşerse çağıran boş harita alır ve
  /// basamak sabit saate düşer — bu yol üretimde sessizce çalışmaya devam
  /// etmeli, o yüzden hata burada yutulmaz, çağıranda Crashlytics'e gider.
  Future<Map<String, TefasNavGozlem>> tefasNavGozlemleri(
    Set<String> fonKodlari, {
    required DateTime gun,
  }) async {
    if (fonKodlari.isEmpty) return const {};
    final kodlar = fonKodlari.toList()..sort();
    final gunStr =
        '${gun.year}-${gun.month.toString().padLeft(2, '0')}-${gun.day.toString().padLeft(2, '0')}';
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.tefasNavGozlemleri',
      table: 'tefas_nav_gozlem',
      op: 'SELECT',
      request: {'fon_kodu': kodlar, 'nav_tarihi_gte': gunStr},
      call: () => _db
          .from('tefas_nav_gozlem')
          .select('fon_kodu, nav_tarihi, ilk_gorulme, onceki_kontrol')
          .inFilter('fon_kodu', kodlar)
          .gte('nav_tarihi', gunStr)
          .order('nav_tarihi', ascending: false),
    );
    final out = <String, TefasNavGozlem>{};
    for (final r in rows) {
      final g = TefasNavGozlem.fromMap(r);
      if (g == null) continue;
      // Satırlar tarih azalan geldi: ilk görülen = en yeni.
      out.putIfAbsent(g.fonKodu, () => g);
    }
    return out;
  }

  // ── Yurt içi kotasyon kaydı (0101) ───────────────────────────────────────

  /// [sembol]'ün [baslangic]'tan bu yana kaydedilmiş yurt içi kotasyonu
  /// (`(ms, TL fiyat)`, artan sırada).
  ///
  /// Sembol başına AYRI istek: günde ~288 satır, PostgREST'in varsayılan
  /// 1.000 satır sınırının altında kalır; birleşik sorgu birkaç sembolde
  /// sınırı aşıp günün sonunu sessizce keserdi. Tablo yoksa (0101 henüz
  /// koşmadı) istisna çağırana gider; çağıran Crashlytics'e yazıp eski
  /// yoldan devam eder.
  Future<List<(int, double)>> yurtIciKotasyonSerisi(
    String sembol, {
    required DateTime baslangic,
  }) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.yurtIciKotasyonSerisi',
      table: 'yurt_ici_kotasyon',
      op: 'SELECT',
      request: {'sembol': sembol, 'ts_gte': baslangic.toUtc().toIso8601String()},
      call: () => _db
          .from('yurt_ici_kotasyon')
          .select('ts, fiyat')
          .eq('sembol', sembol)
          .gte('ts', baslangic.toUtc().toIso8601String())
          .order('ts', ascending: true)
          .limit(1000),
    );
    final out = <(int, double)>[];
    for (final r in rows) {
      final ts = DateTime.tryParse('${r['ts']}');
      final fiyat = (r['fiyat'] as num?)?.toDouble();
      if (ts == null || fiyat == null || !fiyat.isFinite || fiyat <= 0) {
        continue;
      }
      out.add((ts.millisecondsSinceEpoch, fiyat));
    }
    return out;
  }

  // ── Fon para akışı (0106) ────────────────────────────────────────────────

  /// [fonKodu]'nun [baslangic]'tan bu yana günlük satırları (HAM, artan
  /// tarih). Ayrıştırma ve toplama `fon_akisi.dart`'ta (saf, testli).
  ///
  /// Kişisel veri değil: tablo oturum açmış herkese okunur (RLS `using
  /// (true)`), yazma yalnız `akis-gozlem`. 63 günde en çok ~45 satır.
  /// Tablo yoksa (0106 henüz koşmadı) istisna çağırana gider; çağıran
  /// Crashlytics'e yazıp kartı çizmez.
  Future<List<Map<String, dynamic>>> fonAkisGunleri(
    String fonKodu, {
    required DateTime baslangic,
  }) {
    final gun = _isoGun(baslangic);
    return _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fonAkisGunleri',
      table: 'fon_akis_gunluk',
      op: 'SELECT',
      request: {'fon_kodu': fonKodu, 'tarih_gte': gun},
      call: () => _db
          .from('fon_akis_gunluk')
          .select('tarih, portfoy_degeri, net_akis, yatirimci')
          .eq('fon_kodu', fonKodu)
          .gte('tarih', gun)
          .order('tarih', ascending: true)
          .limit(200),
    );
  }

  /// [ticker]'ın ('TEFAS:TTE') [baslangic]'tan bu yana büyük giriş/çıkış
  /// olayları (HAM, yeniden eskiye). Kuralı sunucu uygular; istemci yalnız
  /// okur.
  Future<List<Map<String, dynamic>>> balinaOlaylari(
    String ticker, {
    required DateTime baslangic,
  }) {
    final gun = _isoGun(baslangic);
    return _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.balinaOlaylari',
      table: 'balina_olay',
      op: 'SELECT',
      request: {'ticker': ticker, 'tarih_gte': gun},
      call: () => _db
          .from('balina_olay')
          .select('tarih, tur, tutar, buyukluk_orani, sapma_kati')
          .eq('ticker', ticker)
          // Tablo 0107'ten beri hisse olaylarını da taşıyor.
          .inFilter('tur', ['fon_giris', 'fon_cikis'])
          .gte('tarih', gun)
          .order('tarih', ascending: false)
          .limit(50),
    );
  }

  /// BIST hissesinin ([sembol] 'THYAO.IS') [baslangic]'tan bu yana günlük
  /// kapanış ve para hacmi (HAM, artan tarih). Ayrıştırma `hisse_hacmi.dart`.
  /// Tablo oturum açmış herkese okunur; yazma yalnız `hacim-gozlem` (0107).
  Future<List<Map<String, dynamic>>> hisseHacimGunleri(
    String sembol, {
    required DateTime baslangic,
  }) {
    final gun = _isoGun(baslangic);
    return _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.hisseHacimGunleri',
      table: 'hisse_hacim_gunluk',
      op: 'SELECT',
      request: {'ticker': sembol, 'tarih_gte': gun},
      call: () => _db
          .from('hisse_hacim_gunluk')
          .select('tarih, kapanis, para_hacmi')
          .eq('ticker', sembol)
          .gte('tarih', gun)
          .order('tarih', ascending: true)
          .limit(200),
    );
  }

  /// [sembol]'ün olağandışı hacim günleri (HAM). `balinaOlaylari`'ndan ayrı:
  /// hisse olayının sütunları farklı (kat ve fiyat değişimi).
  Future<List<Map<String, dynamic>>> hacimOlaylari(
    String sembol, {
    required DateTime baslangic,
  }) {
    final gun = _isoGun(baslangic);
    return _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.hacimOlaylari',
      table: 'balina_olay',
      op: 'SELECT',
      request: {'ticker': sembol, 'tarih_gte': gun},
      call: () => _db
          .from('balina_olay')
          .select('tarih, tur, tutar, ortalama_kati, fiyat_degisim')
          .eq('ticker', sembol)
          .inFilter('tur', ['hisse_hacim_yukselis', 'hisse_hacim_dusus'])
          .gte('tarih', gun)
          .order('tarih', ascending: false)
          .limit(50),
    );
  }

  /// Coin'in ([ticker] 'KRIPTO:BTC') günlük Binance USDT hacmi ve alıcı payı
  /// (HAM, artan tarih). Yazma yalnız `kripto-hacim-gozlem` (0108).
  Future<List<Map<String, dynamic>>> kriptoHacimGunleri(
    String ticker, {
    required DateTime baslangic,
  }) {
    final gun = _isoGun(baslangic);
    return _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.kriptoHacimGunleri',
      table: 'kripto_hacim_gunluk',
      op: 'SELECT',
      request: {'ticker': ticker, 'tarih_gte': gun},
      call: () => _db
          .from('kripto_hacim_gunluk')
          .select('tarih, kapanis, para_hacmi, alici_payi')
          .eq('ticker', ticker)
          .gte('tarih', gun)
          .order('tarih', ascending: true)
          .limit(200),
    );
  }

  /// Coin'in olağandışı hacim günleri (HAM).
  Future<List<Map<String, dynamic>>> kriptoHacimOlaylari(
    String ticker, {
    required DateTime baslangic,
  }) {
    final gun = _isoGun(baslangic);
    return _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.kriptoHacimOlaylari',
      table: 'balina_olay',
      op: 'SELECT',
      request: {'ticker': ticker, 'tarih_gte': gun},
      call: () => _db
          .from('balina_olay')
          .select('tarih, tur, tutar, ortalama_kati, fiyat_degisim, alici_payi')
          .eq('ticker', ticker)
          .inFilter('tur', ['kripto_hacim_yukselis', 'kripto_hacim_dusus'])
          .gte('tarih', gun)
          .order('tarih', ascending: false)
          .limit(50),
    );
  }

  /// Fonun kategorisindeki akış sırası (0115 `fon_kategori_akis_sirasi`):
  /// ilk 5 + (ilk 5'te değilse) fonun kendisi. Aralık en çok 14 gün.
  Future<List<Map<String, dynamic>>> fonKategoriSirasi(
    String fonKodu, {
    required DateTime baslangic,
    required DateTime bitis,
  }) async {
    final params = {
      'p_fon_kodu': fonKodu,
      'p_baslangic': _isoGun(baslangic),
      'p_bitis': _isoGun(bitis),
    };
    final ham = await _log.log<dynamic>(
      source: 'SupabaseService.fonKategoriSirasi',
      table: 'rpc/fon_kategori_akis_sirasi',
      op: 'RPC',
      request: params,
      call: () => _db.rpc('fon_kategori_akis_sirasi', params: params),
    );
    return [
      for (final r in (ham as List? ?? const []))
        Map<String, dynamic>.from(r as Map)
    ];
  }

  /// Coinin saatlik mumları (0115 `kripto_hacim_saatlik`), [baslangic]'tan
  /// bu yana, eskiden yeniye.
  Future<List<Map<String, dynamic>>> kriptoSaatleri(
    String ticker, {
    required DateTime baslangic,
  }) {
    final an = baslangic.toUtc().toIso8601String();
    return _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.kriptoSaatleri',
      table: 'kripto_hacim_saatlik',
      op: 'SELECT',
      request: {'ticker': ticker, 'saat_gte': an},
      call: () => _db
          .from('kripto_hacim_saatlik')
          .select('saat, para_hacmi, alici_payi')
          .eq('ticker', ticker)
          .gte('saat', an)
          .order('saat', ascending: true)
          .limit(60),
    );
  }

  /// Oturumdaki kullanıcının Premium hakları (0116 `premium_haklari`; RLS
  /// yalnız kendi satırlarını verir).
  Future<List<Map<String, dynamic>>> premiumHaklari() {
    return _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.premiumHaklari',
      table: 'premium_haklari',
      op: 'SELECT',
      request: const {},
      call: () => _db
          .from('premium_haklari')
          .select('kaynak, urun, magaza, bitis, iptal_edildi, baslangic'),
    );
  }

  /// Varlıkların en yeni yayındaki notunun başlığı (0117 `analiz_ozetleri`;
  /// ücretsiz katmanın gördüğü kısım).
  Future<List<Map<String, dynamic>>> analizOzetleri(
    List<String> tickerlar, {
    String tur = 'haftalik',
  }) async {
    final params = {'p_tickerlar': tickerlar, 'p_tur': tur};
    final ham = await _log.log<dynamic>(
      source: 'SupabaseService.analizOzetleri',
      table: 'rpc/analiz_ozetleri',
      op: 'RPC',
      request: params,
      call: () => _db.rpc('analiz_ozetleri', params: params),
    );
    return [
      for (final r in (ham as List? ?? const []))
        Map<String, dynamic>.from(r as Map)
    ];
  }

  /// Notun tamamı (0117 `varlik_analizi`). Premium kapısı açıkken RLS
  /// Premium olmayana satır vermez → `null`.
  Future<Map<String, dynamic>?> varlikAnalizi(
    String ticker, {
    required String tur,
    required DateTime donem,
  }) {
    final gun = _isoGun(donem);
    return _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.varlikAnalizi',
      table: 'varlik_analizi',
      op: 'SELECT',
      request: {'ticker': ticker, 'tur': tur, 'donem': gun},
      call: () => _db
          .from('varlik_analizi')
          .select('ticker, tur, donem, baslik, maddeler, rozet, girdi')
          .eq('ticker', ticker)
          .eq('tur', tur)
          .eq('donem', gun)
          .maybeSingle(),
    );
  }

  /// Kullanıcının bu nota önceki oyu ve yanlış sayı bildirimi; yoksa null.
  /// Ekran yeniden açıldığında 👍 boş görünmesin.
  Future<({int? oy, bool yanlisSayi})?> notGeriBildirimim({
    required String ticker,
    required String tur,
    required DateTime donem,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    final r = await _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.notGeriBildirimim',
      table: 'not_geri_bildirim',
      op: 'SELECT',
      request: {'ticker': ticker, 'tur': tur},
      call: () => _db
          .from('not_geri_bildirim')
          .select('oy, yanlis_sayi')
          .eq('user_id', uid)
          .eq('ticker', ticker)
          .eq('tur', tur)
          .eq('donem', _isoGun(donem))
          .maybeSingle(),
    );
    if (r == null) return null;
    return (
      oy: (r['oy'] as num?)?.toInt(),
      yanlisSayi: r['yanlis_sayi'] == true,
    );
  }

  /// Not geri bildirimi (0117 `not_geri_bildirim`): oy ve/veya "yanlış sayı".
  ///
  /// Oy ile "yanlış sayı" bildirimi aynı satırdadır ama AYRI çağrılardır:
  /// gövde yalnız o çağrının alanlarını taşır (upsert yalnız gönderilen
  /// kolonları günceller). Tüm kolonları göndermek, yanlış sayı bildirimiyle
  /// önceki 👍'yu, sonraki oyla da açıklamayı siliyordu (2026-10-05 web
  /// testi: ekran yeniden açılınca `_oy` boş başlar).
  Future<void> notGeriBildirim({
    required String ticker,
    required String tur,
    required DateTime donem,
    NotGeriBildirimi? oy,
    String? yanlisSayiAciklamasi,
    bool yanlisSayi = false,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final body = {
      'user_id': uid,
      'ticker': ticker,
      'tur': tur,
      'donem': _isoGun(donem),
      if (oy != null) 'oy': oy.deger,
      if (yanlisSayi) ...{
        'yanlis_sayi': true,
        'aciklama': yanlisSayiAciklamasi,
      },
    };
    await _log.log<void>(
      source: 'SupabaseService.notGeriBildirim',
      table: 'not_geri_bildirim',
      op: 'UPSERT',
      request: {
        'ticker': ticker,
        'tur': tur,
        'oy': oy?.deger,
        'yanlis_sayi': yanlisSayi
      },
      call: () => _db
          .from('not_geri_bildirim')
          .upsert(body, onConflict: 'user_id,ticker,tur,donem'),
    );
  }

  /// Pazartesi özetinde hareket satırı (0118 `profiles.haftalik_hareket_satiri`).
  Future<bool?> haftalikHareketSatiri(String userId) async {
    final row = await _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.haftalikHareketSatiri',
      table: 'profiles',
      op: 'SELECT',
      request: {'id': userId},
      call: () => _db
          .from('profiles')
          .select('haftalik_hareket_satiri')
          .eq('id', userId)
          .maybeSingle(),
    );
    return row?['haftalik_hareket_satiri'] as bool?;
  }

  Future<void> setHaftalikHareketSatiri(String userId, bool acik) async {
    await _log.log<void>(
      source: 'SupabaseService.setHaftalikHareketSatiri',
      table: 'profiles',
      op: 'UPDATE',
      request: {'id': userId, 'haftalik_hareket_satiri': acik},
      call: () => _db
          .from('profiles')
          .update({'haftalik_hareket_satiri': acik}).eq('id', userId),
    );
  }

  static String _isoGun(DateTime t) => '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  // ── Profiles ─────────────────────────────────────────────────────────────

  Future<AppUser?> getProfile(String userId) async {
    final row = await _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.getProfile',
      table: 'profiles',
      op: 'SELECT',
      request: {'id': userId},
      call: () => _db.from('profiles').select().eq('id', userId).maybeSingle(),
    );
    if (row == null) return null;
    return AppUser.fromSupabase(row);
  }

  Future<AppUser?> getCurrentProfile() async {
    final uid = _uid;
    if (uid == null) return null;
    return getProfile(uid);
  }

  Future<void> upsertProfile(AppUser user) async {
    final body = {
      'id': user.id,
      'email': user.email,
      'display_name': user.displayName,
      'onboarding_completed': user.onboardingCompleted,
    };
    await _log.log<void>(
      source: 'SupabaseService.upsertProfile',
      table: 'profiles',
      op: 'UPSERT',
      request: body,
      call: () => _db.from('profiles').upsert(body),
    );
  }

  /// Yazarken anlık kontrol (0079 `kullanici_adi_uygun_mu`). Karar
  /// sunucuda: biçim, uygunsuz söz, ayrılmış ad, benzersizlik.
  Future<KullaniciAdiSonuc> kullaniciAdiUygunMu(String ad) async {
    final kod = await _log.log<dynamic>(
      source: 'SupabaseService.kullaniciAdiUygunMu',
      table: 'rpc/kullanici_adi_uygun_mu',
      op: 'RPC',
      request: {'p_ad': ad},
      call: () => _db.rpc('kullanici_adi_uygun_mu', params: {'p_ad': ad}),
    );
    return KullaniciAdi.sonucCoz(kod);
  }

  /// Kayıt formu — oturum YOK (0080 `kullanici_adi_kayitta_uygun_mu`).
  /// Anonim yüzey 'ayrilmis'i 'alinmis'e katlar; kullanıcıya "alınmış"
  /// denir, gerekçe migration notunda.
  Future<KullaniciAdiSonuc> kullaniciAdiKayittaUygunMu(String ad) async {
    final kod = await _log.log<dynamic>(
      source: 'SupabaseService.kullaniciAdiKayittaUygunMu',
      table: 'rpc/kullanici_adi_kayitta_uygun_mu',
      op: 'RPC',
      request: {'p_ad': ad},
      call: () =>
          _db.rpc('kullanici_adi_kayitta_uygun_mu', params: {'p_ad': ad}),
    );
    return KullaniciAdi.sonucCoz(kod);
  }

  /// Kullanıcı adını kaydeder (0079 `kullanici_adi_ayarla`). Sunucu
  /// `display_name`'i de eşitler; ret nedeni istisna değil sonuçtur.
  Future<KullaniciAdiSonuc> kullaniciAdiAyarla(String ad) async {
    final kod = await _log.log<dynamic>(
      source: 'SupabaseService.kullaniciAdiAyarla',
      table: 'rpc/kullanici_adi_ayarla',
      op: 'RPC',
      request: {'p_ad': ad},
      call: () => _db.rpc('kullanici_adi_ayarla', params: {'p_ad': ad}),
    );
    return KullaniciAdi.sonucCoz(kod);
  }

  /// Yarış opt-in'ini sunucuya yazar (0081 `profiles.leaderboard_opt_in`).
  ///
  /// Günlük snapshot cron'u (`leaderboard-snapshot`) yalnızca bu bayrağı
  /// açık kullanıcıları hesaplar; cihaz tercihi tek kaynak olmaktan çıktı.
  /// Yazım RLS `profiles_update_own` ile kendi satırına sınırlı.
  Future<void> yarisOptInYaz(String userId, bool acik) async {
    await _log.log<void>(
      source: 'SupabaseService.yarisOptInYaz',
      table: 'profiles',
      op: 'UPDATE',
      request: {'id': userId, 'leaderboard_opt_in': acik},
      call: () => _db
          .from('profiles')
          .update({'leaderboard_opt_in': acik})
          .eq('id', userId),
    );
  }

  Future<void> markOnboardingCompleted(String userId) async {
    await _log.log<void>(
      source: 'SupabaseService.markOnboardingCompleted',
      table: 'profiles',
      op: 'UPDATE',
      request: {'id': userId, 'onboarding_completed': true},
      call: () => _db
          .from('profiles')
          .update({'onboarding_completed': true}).eq('id', userId),
    );
  }

  /// Ortak hareketinin günlük brifingde anılıp anılmayacağı.
  ///
  /// Tercih SUNUCUDA tutulur (`profiles`) çünkü brifingi üreten edge
  /// function okuyor; cihaz tercihleri (SharedPreferences) oradan görünmez.
  ///
  /// Okuma hatasında `true` döner: bu bildirim yeni bir bilgi açmıyor
  /// (ortağın lot'ları zaten karşı tarafta görünür), o yüzden varsayılan
  /// açık olmak güvenli. Ağ hatası yüzünden anahtarın kapalı görünmesi,
  /// kullanıcıya "kapattım" yanılgısı verirdi.
  Future<bool> getPartnerActivityPush(String userId) async {
    try {
      final row = await _db
          .from('profiles')
          .select('partner_activity_push')
          .eq('id', userId)
          .maybeSingle();
      return row?['partner_activity_push'] != false;
    } catch (_) {
      return true;
    }
  }

  Future<void> setPartnerActivityPush(String userId, bool enabled) async {
    await _log.log<void>(
      source: 'SupabaseService.setPartnerActivityPush',
      table: 'profiles',
      op: 'UPDATE',
      request: {'id': userId, 'partner_activity_push': enabled},
      call: () => _db
          .from('profiles')
          .update({'partner_activity_push': enabled}).eq('id', userId),
    );
  }

  /// Brifing saati (0068): 'morning' (09:45) | 'evening' (18:30).
  /// Okuma hatasında 'morning' — sunucu varsayılanı; anahtar yanlış
  /// tarafta görünmesin.
  Future<String> getBriefSlot(String userId) async {
    try {
      final row = await _db
          .from('profiles')
          .select('brief_slot')
          .eq('id', userId)
          .maybeSingle();
      final v = row?['brief_slot']?.toString();
      return v == 'evening' ? 'evening' : 'morning';
    } catch (_) {
      return 'morning';
    }
  }

  Future<void> setBriefSlot(String userId, String slot) async {
    assert(slot == 'morning' || slot == 'evening');
    await _log.log<void>(
      source: 'SupabaseService.setBriefSlot',
      table: 'profiles',
      op: 'UPDATE',
      request: {'id': userId, 'brief_slot': slot},
      call: () =>
          _db.from('profiles').update({'brief_slot': slot}).eq('id', userId),
    );
  }

  /// Maaş günü birikim hatırlatması (0119): ayın günü 1–31, `null` = kapalı.
  ///
  /// Okuma hatasında `null` (kapalı) döner: sunucu varsayılanı da kapalı;
  /// ağ hatası anahtarı açık gösterip "açtım" yanılgısı vermesin.
  Future<int?> getBirikimHatirlatmaGunu(String userId) async {
    try {
      final row = await _db
          .from('profiles')
          .select('birikim_hatirlatma_gunu')
          .eq('id', userId)
          .maybeSingle();
      final v = row?['birikim_hatirlatma_gunu'];
      return v is num ? v.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setBirikimHatirlatmaGunu(String userId, int? gun) async {
    assert(gun == null || (gun >= 1 && gun <= 31));
    await _log.log<void>(
      source: 'SupabaseService.setBirikimHatirlatmaGunu',
      table: 'profiles',
      op: 'UPDATE',
      request: {'id': userId, 'birikim_hatirlatma_gunu': gun},
      call: () => _db
          .from('profiles')
          .update({'birikim_hatirlatma_gunu': gun}).eq('id', userId),
    );
  }

  /// Sessiz saatler (0057) — TR saati, null = kapalı.
  Future<({int? start, int? end})> getQuietHours(String userId) async {
    final row = await _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.getQuietHours',
      table: 'profiles',
      op: 'SELECT',
      request: {'id': userId},
      call: () => _db
          .from('profiles')
          .select('quiet_start, quiet_end')
          .eq('id', userId)
          .maybeSingle(),
    );
    return (
      start: (row?['quiet_start'] as num?)?.toInt(),
      end: (row?['quiet_end'] as num?)?.toInt(),
    );
  }

  Future<void> setQuietHours(String userId, {int? start, int? end}) async {
    await _log.log<void>(
      source: 'SupabaseService.setQuietHours',
      table: 'profiles',
      op: 'UPDATE',
      request: {'id': userId, 'quiet_start': start, 'quiet_end': end},
      call: () => _db
          .from('profiles')
          .update({'quiet_start': start, 'quiet_end': end}).eq('id', userId),
    );
  }

  Future<List<AppUser>> getProfilesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    // Her profili ayrı ayrı çek — inFilter RLS policy'siyle bazen uyumsuz davranır
    final results = await Future.wait(ids.map((id) => getProfile(id)));
    return results.whereType<AppUser>().toList();
  }

  // ── Assets ───────────────────────────────────────────────────────────────

  Future<List<Asset>> fetchByUser(String userId) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchByUser',
      table: 'assets',
      op: 'SELECT',
      request: {'user_id': userId, 'order': 'added_date desc'},
      call: () => _db
          .from('assets')
          .select()
          .eq('user_id', userId)
          .order('added_date', ascending: false),
    );
    return rows.map<Asset>((r) => Asset.fromSupabase(r)).toList();
  }

  Future<void> insertAsset(Asset asset) async {
    final body = asset.toSupabase();
    await _log.log<void>(
      source: 'SupabaseService.insertAsset',
      table: 'assets',
      op: 'INSERT',
      request: {'id': body['id'], 'user_id': body['user_id'], 'ticker': body['ticker']},
      call: () => _db.from('assets').insert(body),
    );
  }

  /// Partner kodundan gelen varlığı içe aktar — zaten varsa güncelle (resync)
  Future<void> upsertAsset(Asset asset) async {
    final body = asset.toSupabase();
    await _log.log<void>(
      source: 'SupabaseService.upsertAsset',
      table: 'assets',
      op: 'UPSERT',
      request: {'id': body['id'], 'user_id': body['user_id'], 'ticker': body['ticker']},
      call: () => _db.from('assets').upsert(body),
    );
  }

  /// Varlığı günceller — **silme damgasına DOKUNMAZ.**
  ///
  /// `deleted_at` gövdeden çıkarılır (2026-09-16). `toSupabase()` tüm
  /// alanları yazıyor ve elindeki nesne damgasızsa UPDATE damgayı NULL'a
  /// çekiyordu: kullanıcının sildiği varlık, bir sonraki fiyat
  /// güncellemesinde DİRİLİYORDU. Uygulama kapatılıp açıldığında silinenler
  /// geri geliyordu ve kullanıcı aynı varlığı defalarca siliyordu (logda
  /// dört ayrı silme turu görüldü).
  ///
  /// Damga yalnızca [softDeleteAssets] / [restoreAssets] ile değişir —
  /// ikisi de dönen satırlarla doğrulanıyor. Bu metodun işi fiyat, miktar,
  /// not gibi alanlar; silinmişlik durumu onun sorumluluğu değil.
  ///
  /// Çağıran tarafta da kapı var (`refreshPrices` `isActive` kontrolü) ama
  /// bu satır YAPISAL koruma: yeni bir çağrı yeri eklendiğinde kimse bu
  /// tuzağa düşmesin.
  Future<void> updateAsset(Asset asset) async {
    final body = asset.toSupabase()..remove('deleted_at');
    await _log.log<void>(
      source: 'SupabaseService.updateAsset',
      table: 'assets',
      op: 'UPDATE',
      request: {'id': asset.id, 'ticker': body['ticker']},
      call: () => _db.from('assets').update(body).eq('id', asset.id),
    );
  }

  /// Fiyat turunun yazımı — YALNIZ fiyat sütunları.
  ///
  /// Eskiden fiyat turu [updateAsset] ile satırın TAMAMINI yazıyordu:
  /// miktar, maliyet, not… bellekteki kopyadan. Bellekteki defter bayatsa
  /// (aynı hesap başka cihazda açık, orada miktar düzeltildi; 2026-10-03
  /// kullanıcı bildirimi) bu cihazın 5 dakikalık fiyat yazımı o düzeltmeyi
  /// sessizce geri alıyordu — kayıp güncelleme. Fiyat turu yalnızca fiyatın
  /// sahibidir; [alisFiyatiDa] yalnız maliyeti hiç girilmemiş lotta (tur
  /// maliyeti güncel fiyata kilitlediğinde) true'dur.
  Future<void> fiyatYaz(Asset asset, {bool alisFiyatiDa = false}) async {
    await _log.log<void>(
      source: 'SupabaseService.fiyatYaz',
      table: 'assets',
      op: 'UPDATE',
      request: {'id': asset.id, 'ticker': asset.ticker},
      call: () => _db.from('assets').update({
        'current_price': asset.currentPrice,
        'last_updated': asset.lastUpdated?.toUtc().toIso8601String(),
        if (alisFiyatiDa) 'purchase_price': asset.purchasePrice,
      }).eq('id', asset.id),
    );
  }

  /// Yalnızca bir işlemin notunu yazar.
  ///
  /// [updateAsset] tüm gövdeyi yazar (fiyat, miktar…); notu düzenlemek için
  /// satırın geri kalanını istemcideki kopyayla ezmek gereksiz risk — o an
  /// bayat bir `current_price` sunucudakinin üstüne yazılırdı. Tek sütun.
  ///
  /// [softDeleteAssets] gibi dönen satırla doğrulanır: RLS eşleşmeyen
  /// UPDATE'i hata vermeden 0 satırla geçer, kullanıcı "kaydedildi" sanardı.
  Future<void> updateAssetNotes(String id, String notes) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.updateAssetNotes',
      table: 'assets',
      op: 'UPDATE',
      request: {'id': id, 'len': notes.length},
      call: () => _db
          .from('assets')
          .update({'notes': notes})
          .eq('id', id)
          .select('id'),
    );
    if (rows.isEmpty) {
      throw StateError('Not hiçbir satıra yazılamadı.');
    }
  }

  Future<void> deleteAsset(String id) async {
    await _log.log<void>(
      source: 'SupabaseService.deleteAsset',
      table: 'assets',
      op: 'DELETE',
      request: {'id': id},
      call: () => _db.from('assets').delete().eq('id', id),
    );
  }

  /// Yumuşak silme — satır kalır, `deleted_at` damgalanır.
  ///
  /// Varlık silmenin normal yolu budur. [deleteAsset] (fiziksel DELETE)
  /// kaydı geçmişten de yok eder; hareket listesi ham ledger'dan
  /// beslendiği için o varlığın Alım/Satım/Temettü satırlarını da
  /// götürürdü.
  /// Damganın FİİLEN yazıldığı, dönen satırlarla doğrulanır.
  ///
  /// PostgREST'te eşleşmeyen bir UPDATE **hata değildir** — sessizce sıfır
  /// satır günceller. Doğrulama olmadan silme başarısız olsa bile çağıran
  /// "oldu" sanıyordu: uygulama kendi durumunu iyimser güncellediği için
  /// kullanıcı varlığı silinmiş görüyor, ama sunucudaki lot AKTİF kalıyor ve
  /// push işleri (`analyze-signals`, `daily-brief`) onun için bildirim
  /// göndermeye devam ediyordu. Kullanıcı şikâyeti buydu: "sildiğim
  /// varlıklar için push atılmaması gerekiyor."
  ///
  /// Sıfır satır dönerse ATILIR; çağıran ekranlar hatayı zaten yakalayıp
  /// "Silinemedi" gösteriyor. Kısmi eşleşme (bir lot daha önce fiziksel
  /// silinmişse olabilir) hata sayılmaz — kullanıcının niyeti gerçekleşmiştir.
  Future<void> softDeleteAssets(List<String> ids, DateTime deletedAt) async {
    if (ids.isEmpty) return;
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.softDeleteAssets',
      table: 'assets',
      op: 'UPDATE',
      request: {'ids': ids.length, 'deleted_at': deletedAt.toIso8601String()},
      call: () => _db
          .from('assets')
          .update({'deleted_at': deletedAt.toUtc().toIso8601String()})
          .inFilter('id', ids)
          .select('id'),
    );
    if (rows.isEmpty) {
      throw StateError(
        'Silme damgası hiçbir satıra yazılamadı (${ids.length} lot). '
        'Kayıtlar sunucuda aktif kaldı.',
      );
    }
  }

  /// Yumuşak silmeyi geri alır — `deleted_at` temizlenir.
  ///
  /// "Geri al" için: [softDeleteAssets] ile aynı doğrulama; sıfır satır
  /// dönerse atılır, çağıran "geri alınamadı" gösterir.
  Future<void> restoreAssets(List<String> ids) async {
    if (ids.isEmpty) return;
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.restoreAssets',
      table: 'assets',
      op: 'UPDATE',
      request: {'ids': ids.length},
      call: () => _db
          .from('assets')
          .update({'deleted_at': null})
          .inFilter('id', ids)
          .select('id'),
    );
    if (rows.isEmpty) {
      throw StateError(
        'Geri alma hiçbir satıra yazılamadı (${ids.length} lot).',
      );
    }
  }

  Future<int> countAssetsForUser(String userId) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.countAssetsForUser',
      table: 'assets',
      op: 'SELECT',
      request: {'user_id': userId, 'columns': 'id'},
      call: () => _db.from('assets').select('id').eq('user_id', userId),
    );
    return rows.length;
  }

  /// Birden çok lotu TEK istekte yazar (BES açılışı: fon başına bir lot +
  /// devlet katkısı lotu). Tek istek, yarım kalmış bir açılışı önler:
  /// PostgREST çoklu INSERT'i tek ifadede koşar, biri reddedilirse hiçbiri
  /// yazılmaz.
  Future<void> insertAssets(List<Asset> assets) async {
    if (assets.isEmpty) return;
    final rows = [for (final a in assets) a.toSupabase()];
    await _log.log<void>(
      source: 'SupabaseService.insertAssets',
      table: 'assets',
      op: 'INSERT',
      request: {'count': rows.length, 'user_id': rows.first['user_id']},
      call: () => _db.from('assets').insert(rows),
    );
  }

  // ── Sözleşmeler (mevduat / BES, 0088) ─────────────────────────────────────

  /// Sözleşmeleri id ile okur — kendi ya da ortağın (RLS iki politikayla
  /// izin verir). Fiyat servisi bilinmeyen `MEVDUAT:` sembolünde buradan
  /// yükler.
  Future<List<Sozlesme>> fetchSozlesmeler(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchSozlesmeler',
      table: 'sozlesmeler',
      op: 'SELECT',
      request: {'ids': ids.length},
      call: () => _db.from('sozlesmeler').select().inFilter('id', ids),
    );
    return rows.map(Sozlesme.fromSupabase).toList();
  }

  Future<List<Sozlesme>> fetchSozlesmelerByUser(String userId) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchSozlesmelerByUser',
      table: 'sozlesmeler',
      op: 'SELECT',
      request: {'user_id': userId},
      call: () => _db.from('sozlesmeler').select().eq('user_id', userId),
    );
    return rows.map(Sozlesme.fromSupabase).toList();
  }

  /// BES devlet katkısı yıllık parametreleri (0089) — referans verisi,
  /// kullanıcıya bağlı değil. Yıl → (azami devlet katkısı TL, oran %).
  Future<Map<int, ({double sinir, double oran})>>
      fetchBesDevletKatkisi() async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchBesDevletKatkisi',
      table: 'bes_devlet_katkisi',
      op: 'SELECT',
      request: const {},
      call: () => _db
          .from('bes_devlet_katkisi')
          .select('yil, azami_devlet_katkisi, oran_yuzde'),
    );
    return {
      for (final r in rows)
        (r['yil'] as num).toInt(): (
          sinir: (r['azami_devlet_katkisi'] as num).toDouble(),
          oran: (r['oran_yuzde'] as num).toDouble(),
        ),
    };
  }

  Future<List<MevduatDonemi>> fetchMevduatDonemleri(
      List<String> sozlesmeIds) async {
    if (sozlesmeIds.isEmpty) return const [];
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchMevduatDonemleri',
      table: 'mevduat_donemleri',
      op: 'SELECT',
      request: {'sozlesme_ids': sozlesmeIds.length},
      call: () => _db
          .from('mevduat_donemleri')
          .select()
          .inFilter('sozlesme_id', sozlesmeIds)
          .order('baslangic'),
    );
    return rows.map(MevduatDonemi.fromSupabase).toList();
  }

  Future<void> insertSozlesme(Sozlesme s) async {
    final body = s.toSupabase();
    await _log.log<void>(
      source: 'SupabaseService.insertSozlesme',
      table: 'sozlesmeler',
      op: 'INSERT',
      request: {'id': s.id, 'tur': s.tur.name},
      call: () => _db.from('sozlesmeler').insert(body),
    );
  }

  Future<void> updateSozlesme(Sozlesme s) async {
    final body = s.toSupabase()..remove('id')..remove('user_id');
    await _log.log<void>(
      source: 'SupabaseService.updateSozlesme',
      table: 'sozlesmeler',
      op: 'UPDATE',
      request: {'id': s.id},
      call: () => _db.from('sozlesmeler').update(body).eq('id', s.id),
    );
  }

  /// Sözleşmeyi siler — yalnız lot yazımı başarısız olan yarım açılışı
  /// geri almak için. Lotlar `on delete set null` ile korunur (0088).
  Future<void> deleteSozlesme(String id) async {
    await _log.log<void>(
      source: 'SupabaseService.deleteSozlesme',
      table: 'sozlesmeler',
      op: 'DELETE',
      request: {'id': id},
      call: () => _db.from('sozlesmeler').delete().eq('id', id),
    );
  }

  Future<void> insertMevduatDonemi(MevduatDonemi d, String userId) async {
    final body = d.toSupabase(userId);
    await _log.log<void>(
      source: 'SupabaseService.insertMevduatDonemi',
      table: 'mevduat_donemleri',
      op: 'INSERT',
      request: {'sozlesme_id': d.sozlesmeId},
      call: () => _db.from('mevduat_donemleri').insert(body),
    );
  }

  /// Dönemin faiz ve stopajını yerinde günceller (vade içi oran değişikliği).
  /// Başlangıç ve vade DEĞİŞMEZ; yalnız iki oran gönderilir.
  Future<void> updateMevduatDonemiOrani(MevduatDonemi d, String userId) async {
    await _log.log<void>(
      source: 'SupabaseService.updateMevduatDonemiOrani',
      table: 'mevduat_donemleri',
      op: 'UPDATE',
      request: {'id': d.id},
      call: () => _db
          .from('mevduat_donemleri')
          .update({'yillik_faiz': d.yillikFaiz, 'stopaj': d.stopaj})
          .eq('id', d.id)
          .eq('user_id', userId),
    );
  }

  // ── Snapshots ─────────────────────────────────────────────────────────────

  /// Kullanıcı başına son anlık görüntü yazımı — [snapshotAraligi]'ndan sık
  /// yazılmaz.
  static final Map<String, DateTime> _sonSnapshot = {};

  /// Anlık görüntü seyreltmesi (2026-09-28, 0077). Her fiyat yenilemesi bir
  /// satır yazıyordu: pilot hesapta günde 136, bir günde 1.259 satır; okuyanlar
  /// (Yıllık Özet, weekly-summary) yalnız pencerenin ilk/son değerini
  /// kullanıyor. Sunucu tetikleyicisi zaten saatte bir satıra birleştiriyor;
  /// bu aralık gereksiz İSTEĞİ de keser.
  static const snapshotAraligi = Duration(minutes: 15);

  Future<void> insertSnapshot(Map<String, double> categoryValues,
      {String userId = '', DateTime? simdi}) async {
    final uid = userId.isNotEmpty ? userId : (_uid ?? '');
    if (uid.isEmpty) return;
    final an = simdi ?? DateTime.now();
    final son = _sonSnapshot[uid];
    if (son != null && an.difference(son) < snapshotAraligi) return;

    await _log.log<void>(
      source: 'SupabaseService.insertSnapshot',
      table: 'snapshots',
      op: 'INSERT',
      request: {'user_id': uid, 'categories': categoryValues.keys.toList()},
      // `ts` gönderilmez: sunucu saati (default now()) — istemci saati kaymış
      // olabilir ve saatlik birleştirme `ts`'ten türüyor.
      call: () => _db.from('snapshots').insert({
        'user_id': uid,
        'data': categoryValues,
      }),
    );
    // Yalnız BAŞARILI yazımdan sonra: hata olursa bir sonraki tur yeniden dener.
    _sonSnapshot[uid] = an;

    // 2 yıl saklama artık sunucuda (0077, `snapshots-retention` cron'u).
    // Eskiden her yazımdan sonra buradan DELETE gidiyordu — fiyat yenilemesi
    // başına ikinci bir gidiş-dönüş.
  }

  Future<List<({int ts, Map<String, double> values})>> fetchSnapshots(
      int sinceMs,
      {String? userId}) async {
    final uid = userId ?? _uid ?? '';
    if (uid.isEmpty) return [];

    final since =
        DateTime.fromMillisecondsSinceEpoch(sinceMs).toUtc().toIso8601String();

    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchSnapshots',
      table: 'snapshots',
      op: 'SELECT',
      request: {'user_id': uid, 'since': since},
      call: () => _db
          .from('snapshots')
          .select()
          .eq('user_id', uid)
          .gte('ts', since)
          .order('ts', ascending: true),
    );

    final out = <({int ts, Map<String, double> values})>[];
    for (final r in rows) {
      try {
        final tsRaw = r['ts'];
        if (tsRaw is! String) continue;
        final ts = DateTime.parse(tsRaw).millisecondsSinceEpoch;
        final raw = r['data'];
        if (raw is! Map<String, dynamic>) continue;
        final data = <String, double>{};
        raw.forEach((k, v) {
          if (v is num) data[k] = v.toDouble();
          // Eski snapshot'larda v string olabilir — sessizce atla
        });
        if (data.isNotEmpty) out.add((ts: ts, values: data));
      } catch (_) {
        // Bozuk satır tüm fetch'i öldürmesin
        continue;
      }
    }
    return out;
  }

  // ── Partner invites ───────────────────────────────────────────────────────

  Future<void> insertInvite({
    required String id,
    required String fromUserId,
    required String code,
    required String payload,
    required DateTime expiresAt,
    String? toUserId,
    String? requesterName,
    String status = 'pending',
  }) async {
    final body = {
      'id': id,
      'from_user_id': fromUserId,
      if (toUserId != null) 'to_user_id': toUserId,
      if (requesterName != null) 'requester_name': requesterName,
      'code': code,
      'payload': payload,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'used': false,
      'status': status,
    };
    await _log.log<void>(
      source: 'SupabaseService.insertInvite',
      table: 'partner_invites',
      op: 'UPSERT',
      request: {
        'id': id,
        'from_user_id': fromUserId,
        'code': code,
        'status': status,
        'expires_at': expiresAt.toUtc().toIso8601String(),
      },
      call: () => _db.from('partner_invites').upsert(body),
    );
  }

  Future<Map<String, dynamic>?> getValidInvite(String code) async {
    return _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.getValidInvite',
      table: 'partner_invites',
      op: 'SELECT',
      request: {'code': code, 'used': false},
      call: () => _db
          .from('partner_invites')
          .select()
          .eq('code', code)
          .eq('used', false)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .maybeSingle(),
    );
  }

  Future<void> markInviteUsed(String id) async {
    await _log.log<void>(
      source: 'SupabaseService.markInviteUsed',
      table: 'partner_invites',
      op: 'UPDATE',
      request: {'id': id, 'used': true},
      call: () =>
          _db.from('partner_invites').update({'used': true}).eq('id', id),
    );
  }

  /// Kod girildiğinde davetiyeye to_user_id ve status=pending yaz
  Future<void> setInviteTarget({
    required String inviteId,
    required String toUserId,
    required String requesterName,
  }) async {
    await _log.log<void>(
      source: 'SupabaseService.setInviteTarget',
      table: 'partner_invites',
      op: 'UPDATE',
      request: {
        'id': inviteId,
        'to_user_id': toUserId,
        'requester_name': requesterName,
        'status': 'pending',
      },
      call: () => _db.from('partner_invites').update({
        'to_user_id': toUserId,
        'requester_name': requesterName,
        'status': 'pending',
      }).eq('id', inviteId),
    );
  }

  /// Kod sahibi onayladığında
  Future<void> acceptInvite(String inviteId) async {
    await _log.log<void>(
      source: 'SupabaseService.acceptInvite',
      table: 'partner_invites',
      op: 'UPDATE',
      request: {'id': inviteId, 'status': 'accepted', 'used': true},
      call: () => _db.from('partner_invites').update({
        'status': 'accepted',
        'used': true,
      }).eq('id', inviteId),
    );
  }

  /// Kod sahibi reddetti
  Future<void> rejectInvite(String inviteId) async {
    await _log.log<void>(
      source: 'SupabaseService.rejectInvite',
      table: 'partner_invites',
      op: 'UPDATE',
      request: {'id': inviteId, 'status': 'rejected', 'used': true},
      call: () => _db.from('partner_invites').update({
        'status': 'rejected',
        'used': true,
      }).eq('id', inviteId),
    );
  }

  /// Mevcut kullanıcıya gelen onay bekleyen davetleri getir
  Future<List<Map<String, dynamic>>> getPendingInvitesForMe(
      String userId) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.getPendingInvitesForMe',
      table: 'partner_invites',
      op: 'SELECT',
      request: {'from_user_id': userId, 'status': 'pending', 'used': false},
      call: () => _db
          .from('partner_invites')
          .select()
          .eq('from_user_id', userId)
          .eq('status', 'pending')
          .eq('used', false)
          .not('to_user_id', 'is', null)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String()),
    );
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Kod giren kişi için sonucu polling ile kontrol et
  Future<String?> getInviteStatus(String inviteId) async {
    final row = await _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.getInviteStatus',
      table: 'partner_invites',
      op: 'SELECT',
      request: {'id': inviteId, 'columns': 'status'},
      call: () => _db
          .from('partner_invites')
          .select('status')
          .eq('id', inviteId)
          .maybeSingle(),
    );
    return row?['status'] as String?;
  }

  Future<Map<String, dynamic>?> getInviteById(String inviteId) async {
    return _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.getInviteById',
      table: 'partner_invites',
      op: 'SELECT',
      request: {'id': inviteId},
      call: () => _db
          .from('partner_invites')
          .select()
          .eq('id', inviteId)
          .maybeSingle(),
    );
  }

  // ── Push tokens ───────────────────────────────────────────────────────────

  /// Push token'ını yazar — cihaz başına TEK satır kalacak şekilde.
  ///
  /// [deviceId] verildiyse aynı cihazın ESKİ token satırları önce silinir.
  /// Bu olmadan FCM token rotasyonu (yeniden kurulum, veri temizleme) tabloya
  /// her seferinde bir satır daha ekliyordu ve edge function kullanıcının her
  /// token'ına ayrı push gönderdiği için kullanıcı aynı telefonda tek sinyal
  /// için birden çok bildirim alıyordu.
  ///
  /// Silme işlemi upsert'ten ÖNCE ve yeni token hariç tutularak yapılır:
  /// sonra yapılsaydı az önce yazdığımız satırı silerdi.
  /// Push token'ını bu hesaba yazar — sunucudaki `claim_push_token` RPC'si.
  ///
  /// **Neden doğrudan `upsert` değil (0069, 2026-09-21).** Tablonun
  /// birincil anahtarı `token` ve token CİHAZA bağlı. Aynı telefonda A
  /// çıkıp B girince B'nin upsert'i `on conflict do update` yoluna düşer ve
  /// UPDATE politikasının USING ifadesi A'nın satırına bakar → 42501. B'nin
  /// token'ı hiç yazılmaz (B'ye push gitmez), A'nın satırı kalır (A'nın
  /// brifingi B'nin telefonuna düşer). Canlıda ölçüldü (db_logs 664946).
  /// RPC token'ı sunana devreder; aynı cihazın bayat token temizliği de
  /// orada (eskiden burada `delete().eq('device_id')` idi — başka hesabın
  /// satırını RLS yüzünden zaten silemiyordu).
  ///
  /// [deviceId] boşsa sunucu eski cihaz kimliğini korur.
  ///
  /// **Sürüm kayması (2026-09-21 akşamı, canlıda ölçüldü).** Build 0069'dan
  /// ÖNCE cihazlara indi: RPC yok, `PGRST202`, token hiç yazılmadı — eski
  /// hatadan daha kötü. Fonksiyon bulunamazsa eski doğrudan upsert yoluna
  /// düşülür: aynı hesabın satırıysa yazılır, başka hesabınsa 42501 sürer
  /// (0069 gelene kadar bilinen sınır). Yalnızca PGRST202'de; başka hata
  /// (RLS, ağ) olduğu gibi fırlar. Non-fatal rapor: migration eksikliği
  /// Crashlytics'te görünür olsun.
  Future<void> upsertPushToken({
    required String userId,
    required String token,
    required String platform,
    String? deviceId,
  }) async {
    try {
      await _log.log<void>(
        source: 'SupabaseService.upsertPushToken',
        table: 'user_push_tokens',
        op: 'RPC',
        request: {'user_id': userId, 'platform': platform},
        call: () => _db.rpc<dynamic>(
          'claim_push_token',
          params: {
            'p_token': token,
            'p_platform': platform,
            'p_device_id':
                (deviceId != null && deviceId.isNotEmpty) ? deviceId : null,
          },
        ),
      );
      return;
    } on PostgrestException catch (e, st) {
      if (e.code != 'PGRST202') rethrow;
      CrashReporter.report(e, st,
          reason: 'upsertPushToken: claim_push_token RPC yok (0069 eksik)');
    }
    await _log.log<void>(
      source: 'SupabaseService.upsertPushToken',
      table: 'user_push_tokens',
      op: 'UPSERT',
      request: {'user_id': userId, 'platform': platform, 'fallback': true},
      call: () => _db.from('user_push_tokens').upsert(
        {
          'user_id': userId,
          'token': token,
          'platform': platform,
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'token',
      ),
    );
  }

  // ── Kayıtlı cihazlar / tek aktif cihaz (0098) ────────────────────────────

  /// Bu cihazın hesaptaki durumu. `null`: sunucu tanımadığı bir değer döndü.
  Future<CihazDurumu?> cihazDurumu(String cihazId) async {
    final r = await _log.log<dynamic>(
      source: 'SupabaseService.cihazDurumu',
      table: 'kayitli_cihazlar',
      op: 'RPC',
      request: {},
      call: () => _db.rpc<dynamic>('cihaz_durumu',
          params: {'p_cihaz_id': cihazId}),
    );
    return CihazDurumu.parse(r);
  }

  /// Cihazı güvenilen listeye yazar. Sunucu ilk cihaz dışında son 15 dk'da
  /// e-posta kodu kanıtı ister; yoksa `otp_gerekli` ile reddeder.
  Future<void> cihazKaydet({
    required String cihazId,
    required String ad,
    required String platform,
  }) async {
    await _log.log<void>(
      source: 'SupabaseService.cihazKaydet',
      table: 'kayitli_cihazlar',
      op: 'RPC',
      request: {'platform': platform},
      call: () => _db.rpc<dynamic>('cihaz_kaydet', params: {
        'p_cihaz_id': cihazId,
        'p_ad': ad,
        'p_platform': platform,
      }),
    );
  }

  /// Bu cihazı hesabın TEK aktif cihazı yapar; diğer cihazların push
  /// token'larını düşürür. Başka cihaz bu oturumun girişinden sonra aktif
  /// olduysa `yerinden_edildi` ile reddeder.
  Future<void> oturumAl({
    required String cihazId,
    String? pushCihazId,
    String? pushToken,
  }) async {
    await _log.log<void>(
      source: 'SupabaseService.oturumAl',
      table: 'aktif_cihaz',
      op: 'RPC',
      request: {},
      call: () => _db.rpc<dynamic>('oturum_al', params: {
        'p_cihaz_id': cihazId,
        'p_push_cihaz_id': pushCihazId,
        'p_push_token': pushToken,
      }),
    );
  }

  /// Hesabın şu an aktif cihazı. Satır yoksa (muaf ya da henüz alınmadı) null.
  Future<String?> aktifCihazId(String userId) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.aktifCihazId',
      table: 'aktif_cihaz',
      op: 'SELECT',
      request: {},
      call: () => _db
          .from('aktif_cihaz')
          .select('cihaz_id')
          .eq('user_id', userId)
          .limit(1),
    );
    return rows.isEmpty ? null : rows.first['cihaz_id'] as String?;
  }

  Future<List<KayitliCihaz>> kayitliCihazlar(String userId) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.kayitliCihazlar',
      table: 'kayitli_cihazlar',
      op: 'SELECT',
      request: {},
      call: () => _db
          .from('kayitli_cihazlar')
          .select('cihaz_id, ad, platform, ilk_kayit, son_gorulme')
          .eq('user_id', userId)
          .order('son_gorulme', ascending: false),
    );
    return rows.map<KayitliCihaz>(KayitliCihaz.fromSupabase).toList();
  }

  /// Cihazı güvenilen listeden çıkarır. Aktif cihaz silinemez
  /// (`aktif_cihaz_silinemez`). Dönüş: silinen satır sayısı.
  Future<int> cihazSil(String cihazId) async {
    final r = await _log.log<dynamic>(
      source: 'SupabaseService.cihazSil',
      table: 'kayitli_cihazlar',
      op: 'RPC',
      request: {},
      call: () => _db.rpc<dynamic>('cihaz_sil', params: {'p_cihaz_id': cihazId}),
    );
    return r is int ? r : 0;
  }

  Future<void> deletePushToken(String token) async {
    await _log.log<void>(
      source: 'SupabaseService.deletePushToken',
      table: 'user_push_tokens',
      op: 'DELETE',
      request: {'token': '[redacted]'},
      call: () => _db.from('user_push_tokens').delete().eq('token', token),
    );
  }

  /// Bu cihazın anladığı bildirim biçimini token satırına yazar (0092).
  ///
  /// Sunucu kart görselini yalnız `bildirim_surumu >= 2` olan cihaza
  /// gönderir; eski sürümler bu çağrıyı hiç yapmaz ve satırları NULL kalır —
  /// onlara giden bildirim birebir eskisi gibi (kullanıcı kuralı
  /// 2026-10-01: store kullanıcıları etkilenmesin).
  ///
  /// ASLA fırlatmaz: kart bir süs, token kaydı değil. 0092 o sunucuda henüz
  /// yoksa sütun bilinmez (PGRST204 / 42703) — sessiz geçilir, bildirim yine
  /// düz metin gelir. Başka hatalar Crashlytics'e non-fatal.
  Future<void> setPushBildirimSurumu(String token, int surum) async {
    try {
      await _log.log<void>(
        source: 'SupabaseService.setPushBildirimSurumu',
        table: 'user_push_tokens',
        op: 'UPDATE',
        request: {'bildirim_surumu': surum},
        call: () => _db
            .from('user_push_tokens')
            .update({'bildirim_surumu': surum}).eq('token', token),
      );
    } on PostgrestException catch (e, st) {
      if (e.code == 'PGRST204' || e.code == '42703') return;
      CrashReporter.report(e, st, reason: 'setPushBildirimSurumu');
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'setPushBildirimSurumu');
    }
  }

  // ── Sinyal tercihleri ─────────────────────────────────────────────────────

  /// Kullanıcının sunucudaki sinyal tercihlerini okur.
  ///
  /// Oturum açılışında çağrılır: sunucu doğruluk kaynağıdır, cihaz onu
  /// indirir. Kayıt yoksa boş liste döner — arayan bunu "ilk kurulum"
  /// olarak yorumlayıp yerel değerleri yukarı taşır.
  Future<List<SignalPreferenceRow>> fetchSignalPreferences(
      String userId) async {
    final rows = await _log.log<List<dynamic>>(
      source: 'SupabaseService.fetchSignalPreferences',
      table: 'signal_preferences',
      op: 'SELECT',
      request: {'user_id': userId},
      call: () => _db
          .from('signal_preferences')
          .select(
              'asset_type, threshold, indicators, neutral_push, signals_enabled, frequency, notify_hours')
          .eq('user_id', userId),
    );

    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        SignalPreferenceRow(
          assetType: r['asset_type'] as String,
          threshold: (r['threshold'] as num?)?.toInt() ?? 70,
          indicators:
              (r['indicators'] as List?)?.cast<String>().toList() ?? const [],
          neutralPush: r['neutral_push'] as bool? ?? false,
          // Sütun yoksa/boşsa açık kabul et — kullanıcıyı sessizce
          // bildirimsiz bırakmaktansa varsayılanı korumak doğru.
          signalsEnabled: r['signals_enabled'] as bool? ?? true,
          frequency: SignalFrequency.fromId(r['frequency'] as String?),
          notifyHours:
              (r['notify_hours'] as List?)?.map((e) => (e as num).toInt())
                      .toList() ??
                  const [11, 15],
        ),
    ];
  }

  /// Kullanıcının bir varlık türü için eşik/gösterge tercihlerini sunucuya
  /// yazar.
  ///
  /// Neden gerekli: sinyal analizi artık sunucuda (`analyze-signals` edge
  /// function) çalışıyor ve push kararını orada veriyor. Tercihler yalnızca
  /// cihazda kalırsa sunucu kullanıcının eşiğini bilemez ve herkese aynı
  /// varsayılanı uygular.
  ///
  /// SharedPreferences yazımı korunur (çevrimdışı okuma ve anlık UI için);
  /// burası ikinci, kalıcı kopyadır.
  Future<void> upsertSignalPreference({
    required String userId,
    required String assetType,
    required int threshold,
    required List<String> indicators,
    required bool neutralPush,
    required bool signalsEnabled,
    SignalFrequency? frequency,
    List<int>? notifyHours,
  }) async {
    await _log.log<void>(
      source: 'SupabaseService.upsertSignalPreference',
      table: 'signal_preferences',
      op: 'UPSERT',
      request: {
        'user_id': userId,
        'asset_type': assetType,
        'threshold': threshold,
        'indicators': indicators.length,
        'frequency': frequency?.id,
      },
      call: () => _db.from('signal_preferences').upsert(
        {
          'user_id': userId,
          'asset_type': assetType,
          'threshold': threshold,
          'indicators': indicators,
          'neutral_push': neutralPush,
          'signals_enabled': signalsEnabled,
          // Sıklık alanları YALNIZCA verildiğinde yazılır. Her upsert'te
          // koşulsuz göndermek, sıklığı değiştirmeyen bir eşik güncellemesinin
          // kullanıcının seçtiği sıklığı varsayılana döndürmesine yol açardı.
          if (frequency != null) 'frequency': frequency.id,
          if (notifyHours != null) 'notify_hours': notifyHours,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,asset_type',
      ),
    );
  }

  // ── Kripto (0074) ─────────────────────────────────────────────────────────
  //
  // Kripto fiyatını telefon DEĞİL sunucu çeker (kripto-fiyat, iki dakikada bir — 0113);
  // burası yalnızca tabloyu okur. Gerekçe `supabase/functions/_shared/kripto.ts`.

  /// Kod → sunucudaki son TL fiyat satırı. Katalogda olmayan ya da henüz
  /// fiyatlanmamış kod haritada YOKTUR (uydurma sıfır dönmez).
  Future<Map<String, KriptoFiyat>> kriptoFiyatlari(List<String> kodlar) async {
    if (kodlar.isEmpty) return const {};
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.kriptoFiyatlari',
      table: 'kripto_fiyat',
      op: 'SELECT',
      request: {'kod': kodlar},
      call: () => _db
          .from('kripto_fiyat')
          .select('kod, fiyat_try, gun_acilis_try, guncellendi')
          .inFilter('kod', kodlar),
    );
    final out = <String, KriptoFiyat>{};
    for (final r in rows) {
      final f = KriptoFiyat.fromMap(r);
      if (f != null) out[f.kod] = f;
    }
    return out;
  }

  /// Etkin kripto kataloğu, hacim sırasıyla; son fiyat gömülü gelir
  /// (tek istek). Pasif (listeden düşmüş) coin aramada çıkmaz; onu tutan
  /// kullanıcının kaydı `kripto_fiyat`'tan okunmaya devam eder.
  Future<List<KriptoKatalogOgesi>> kriptoKatalogu() async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.kriptoKatalogu',
      table: 'kripto_varlik',
      op: 'SELECT',
      request: const {'aktif': true},
      call: () => _db
          .from('kripto_varlik')
          .select('kod, ad, logo_url, hacim_sirasi, '
              'kripto_fiyat(fiyat_try, gun_acilis_try, guncellendi)')
          .eq('aktif', true)
          .order('hacim_sirasi', ascending: true, nullsFirst: false),
    );
    return [
      for (final r in rows)
        if (KriptoKatalogOgesi.fromMap(r) case final o?) o,
    ];
  }

  /// Grafik mumları — `kripto-seri` fonksiyonu, paylaşılan önbellekli.
  ///
  /// [aralik] ve [donem] Yahoo adlarıdır (`1h`, `1mo`): `ResolutionTier`
  /// kriptoda da değişmeden kullanılır. `x-region`: Binance ABD IP'lerine
  /// 451 döner; fonksiyon Frankfurt'ta koşmalı (0074 cron'u da öyle).
  Future<List<(int, double)>> kriptoSerisi({
    required String kod,
    required String aralik,
    required String donem,
  }) async {
    final res = await _log.log(
      source: 'SupabaseService.kriptoSerisi',
      table: 'functions/kripto-seri',
      op: 'FUNCTION',
      request: {'kod': kod, 'aralik': aralik, 'donem': donem},
      call: () => _db.functions.invoke(
        'kripto-seri',
        body: {'kod': kod, 'aralik': aralik, 'donem': donem},
        headers: const {'x-region': 'eu-central-1'},
      ),
    );
    final noktalar = (res.data is Map) ? (res.data as Map)['noktalar'] : null;
    if (noktalar is! List) return const [];
    final out = <(int, double)>[];
    for (final n in noktalar) {
      if (n is! List || n.length < 2) continue;
      final t = (n[0] as num?)?.toInt();
      final v = (n[1] as num?)?.toDouble();
      if (t != null && v != null && v > 0) out.add((t, v));
    }
    return out;
  }

  // ── Eurobond (0124) ──────────────────────────────────────────────────────
  // Kripto gibi: fiyatı sunucu çeker (eurobond-fiyat, hafta içi 20 dk'da
  // bir), telefon yalnızca tabloyu okur. Gerekçe `_shared/eurobond.ts`.

  /// Etkin eurobond kataloğu, vadeye göre; son fiyat gömülü gelir.
  Future<List<(EurobondSozlesmesi, EurobondFiyati?)>> eurobondKatalogu() async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.eurobondKatalogu',
      table: 'eurobond_katalog',
      op: 'SELECT',
      request: const {'aktif': true},
      call: () => _db
          .from('eurobond_katalog')
          .select('isin, ad, para_birimi, kupon_orani, vade, ihrac_yili, '
              'kupon_sikligi, ihracci, eurobond_fiyat(*)')
          .eq('aktif', true)
          .order('vade', ascending: true),
    );
    final out = <(EurobondSozlesmesi, EurobondFiyati?)>[];
    for (final r in rows) {
      final s = eurobondSozlesmesiFromMap(r);
      if (s == null) continue;
      final f = r['eurobond_fiyat'];
      final fm = f is List ? (f.isEmpty ? null : f.first) : f;
      out.add((s, fm is Map ? EurobondFiyati.fromMap(Map<String, dynamic>.from(fm)) : null));
    }
    return out;
  }

  /// [isinler] için katalog + son fiyat (portföydeki eurobondlar).
  Future<Map<String, (EurobondSozlesmesi, EurobondFiyati?)>> eurobondlar(
      List<String> isinler) async {
    if (isinler.isEmpty) return const {};
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.eurobondlar',
      table: 'eurobond_katalog',
      op: 'SELECT',
      request: {'isin': isinler},
      call: () => _db
          .from('eurobond_katalog')
          .select('isin, ad, para_birimi, kupon_orani, vade, ihrac_yili, '
              'kupon_sikligi, ihracci, eurobond_fiyat(*)')
          .inFilter('isin', isinler),
    );
    final out = <String, (EurobondSozlesmesi, EurobondFiyati?)>{};
    for (final r in rows) {
      final s = eurobondSozlesmesiFromMap(r);
      if (s == null) continue;
      final f = r['eurobond_fiyat'];
      final fm = f is List ? (f.isEmpty ? null : f.first) : f;
      out[s.isin] = (s, fm is Map ? EurobondFiyati.fromMap(Map<String, dynamic>.from(fm)) : null);
    }
    return out;
  }

  /// Grafik noktaları (TEMİZ fiyat) — `eurobond-seri`, paylaşılan önbellekli.
  /// [aralik]/[donem] Yahoo adlarıdır (kriptoSerisi gibi).
  Future<List<(int, double)>> eurobondSerisi({
    required String isin,
    required String aralik,
    required String donem,
  }) async {
    final res = await _log.log(
      source: 'SupabaseService.eurobondSerisi',
      table: 'functions/eurobond-seri',
      op: 'FUNCTION',
      request: {'isin': isin, 'aralik': aralik, 'donem': donem},
      call: () => _db.functions.invoke(
        'eurobond-seri',
        body: {'isin': isin, 'aralik': aralik, 'donem': donem},
      ),
    );
    final noktalar = (res.data is Map) ? (res.data as Map)['noktalar'] : null;
    if (noktalar is! List) return const [];
    final out = <(int, double)>[];
    for (final n in noktalar) {
      if (n is! List || n.length < 2) continue;
      final t = (n[0] as num?)?.toInt();
      final v = (n[1] as num?)?.toDouble();
      if (t != null && v != null && v > 0) out.add((t, v));
    }
    return out;
  }

  // ── Edge Functions ────────────────────────────────────────────────────────

  /// Ekstre AI sütun eşleme (0121, `ekstre-esle`). [iskelet] ANONİM
  /// tanılama iskeletidir (`ekstreIskeleti`); günlüğe yalnız uzunluğu
  /// yazılır. Yanıt `tablolar` listesi; 2xx dışında `FunctionException`.
  Future<List<Map<String, dynamic>>> ekstreEsle(String iskelet) async {
    final FunctionResponse res;
    try {
      res = await _log.log(
        source: 'SupabaseService.ekstreEsle',
        table: 'functions/ekstre-esle',
        op: 'FUNCTION',
        request: {'uzunluk': iskelet.length},
        timeout: const Duration(seconds: 60),
        call: () => _db.functions.invoke(
          'ekstre-esle',
          body: {'iskelet': iskelet},
        ),
      );
    } on FunctionException catch (e, st) {
      if (e.status != 429 && e.status != 403) {
        CrashReporter.report(e, st, reason: 'ekstre_esle_${e.status}');
      }
      throw EkstreAiHatasi(kota: e.status == 429, premium: e.status == 403);
    }
    final t = (res.data is Map) ? (res.data as Map)['tablolar'] : null;
    if (t is! List) return const [];
    return [for (final x in t) if (x is Map) Map<String, dynamic>.from(x)];
  }

  Future<void> sendPartnerInvitePush(String inviteId) async {
    final response = await _log.log(
      source: 'SupabaseService.sendPartnerInvitePush',
      table: 'functions/send-partner-invite-push',
      op: 'FUNCTION',
      request: {'inviteId': inviteId},
      call: () => _db.functions.invoke(
        'send-partner-invite-push',
        body: {'inviteId': inviteId},
      ),
    );

    if (response.status >= 400) {
      throw Exception('Push gonderilemedi: ${response.data}');
    }
  }

  // ── Partnerships ──────────────────────────────────────────────────────────

  Future<void> insertPartnership({
    required String id,
    required String userId1,
    required String userId2,
  }) async {
    final supportsHidden = await _supportsPerSideHidden();
    final existing = await _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.insertPartnership[check]',
      table: 'partnerships',
      op: 'SELECT',
      request: {'user_id_1': userId1, 'user_id_2': userId2},
      call: () => _db
          .from('partnerships')
          .select('id')
          .or('and(user_id_1.eq.$userId1,user_id_2.eq.$userId2),and(user_id_1.eq.$userId2,user_id_2.eq.$userId1)')
          .maybeSingle(),
    );

    if (existing != null) {
      await _log.log<void>(
        source: 'SupabaseService.insertPartnership[reset-hidden]',
        table: 'partnerships',
        op: 'UPDATE',
        request: supportsHidden
            ? {'id': existing['id'], 'hidden_for_1': false, 'hidden_for_2': false}
            : {'id': existing['id'], 'active': true},
        call: () => _db
            .from('partnerships')
            .update(supportsHidden
                ? {
                    'hidden_for_1': false,
                    'hidden_for_2': false,
                  }
                : {'active': true})
            .eq('id', existing['id'] as String),
      );
    } else {
      await _log.log<void>(
        source: 'SupabaseService.insertPartnership',
        table: 'partnerships',
        op: 'INSERT',
        request: {'id': id, 'user_id_1': userId1, 'user_id_2': userId2},
        call: () => _db.from('partnerships').insert(supportsHidden
            ? {
                'id': id,
                'user_id_1': userId1,
                'user_id_2': userId2,
                'hidden_for_1': false,
                'hidden_for_2': false,
              }
            : {
                'id': id,
                'user_id_1': userId1,
                'user_id_2': userId2,
                'active': true,
              }),
      );
    }
  }

  Future<List<String>> getPartnerIds(String userId,
      {bool onlyActive = true}) async {
    final supportsHidden = await _supportsPerSideHidden();
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.getPartnerIds',
      table: 'partnerships',
      op: 'SELECT',
      request: {'user_id': userId, 'only_active': onlyActive},
      call: () => _db
          .from('partnerships')
          .select(supportsHidden
              ? 'user_id_1, user_id_2, hidden_for_1, hidden_for_2'
              : 'user_id_1, user_id_2, active')
          .or('user_id_1.eq.$userId,user_id_2.eq.$userId'),
    );

    return rows.where((r) {
      if (!onlyActive) return true;
      if (!supportsHidden) {
        return r['active'] as bool? ?? true;
      }
      final isUser1 = (r['user_id_1'] as String) == userId;
      final hidden = isUser1
          ? (r['hidden_for_1'] as bool? ?? false)
          : (r['hidden_for_2'] as bool? ?? false);
      return !hidden;
    }).map<String>((r) {
      final u1 = r['user_id_1'] as String;
      final u2 = r['user_id_2'] as String;
      return u1 == userId ? u2 : u1;
    }).toList();
  }

  Future<List<({String id, bool active})>> getPartnershipsWithStatus(
      String userId) async {
    final supportsHidden = await _supportsPerSideHidden();
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.getPartnershipsWithStatus',
      table: 'partnerships',
      op: 'SELECT',
      request: {'user_id': userId},
      call: () => _db
          .from('partnerships')
          .select(supportsHidden
              ? 'user_id_1, user_id_2, hidden_for_1, hidden_for_2'
              : 'user_id_1, user_id_2, active')
          .or('user_id_1.eq.$userId,user_id_2.eq.$userId'),
    );

    return rows.map<({String id, bool active})>((r) {
      final u1 = r['user_id_1'] as String;
      final u2 = r['user_id_2'] as String;
      final isUser1 = u1 == userId;
      if (!supportsHidden) {
        return (id: isUser1 ? u2 : u1, active: r['active'] as bool? ?? true);
      }
      final hidden = isUser1
          ? (r['hidden_for_1'] as bool? ?? false)
          : (r['hidden_for_2'] as bool? ?? false);
      return (id: isUser1 ? u2 : u1, active: !hidden);
    }).toList();
  }

  Future<bool> partnershipExists(String uid1, String uid2) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.partnershipExists',
      table: 'partnerships',
      op: 'SELECT',
      request: {'user_id_1': uid1, 'user_id_2': uid2},
      call: () => _db
          .from('partnerships')
          .select('id')
          .or('and(user_id_1.eq.$uid1,user_id_2.eq.$uid2),and(user_id_1.eq.$uid2,user_id_2.eq.$uid1)'),
    );
    return rows.isNotEmpty;
  }

  /// Sadece isteği yapan kullanıcının tarafındaki gizleme durumunu günceller.
  Future<void> setPartnershipHidden(
      String currentUserId, String partnerId, bool hidden) async {
    final supportsHidden = await _supportsPerSideHidden();
    final row = await _log.log<Map<String, dynamic>?>(
      source: 'SupabaseService.setPartnershipHidden[find]',
      table: 'partnerships',
      op: 'SELECT',
      request: {'current_user': currentUserId, 'partner': partnerId},
      call: () => _db
          .from('partnerships')
          .select('id, user_id_1, user_id_2')
          .or('and(user_id_1.eq.$currentUserId,user_id_2.eq.$partnerId),and(user_id_1.eq.$partnerId,user_id_2.eq.$currentUserId)')
          .maybeSingle(),
    );
    if (row == null) return;

    final user1 = row['user_id_1'];
    if (user1 is! String) return;
    final isUser1 = user1 == currentUserId;
    final field = isUser1 ? 'hidden_for_1' : 'hidden_for_2';
    await _log.log<void>(
      source: 'SupabaseService.setPartnershipHidden[update]',
      table: 'partnerships',
      op: 'UPDATE',
      request: supportsHidden
          ? {'id': row['id'], field: hidden}
          : {'id': row['id'], 'active': !hidden},
      call: () => _db
          .from('partnerships')
          .update(supportsHidden ? {field: hidden} : {'active': !hidden})
          .eq('id', row['id'] as String),
    );
  }

  // Eski imza — geriye dönük uyumluluk için yönlendir
  Future<void> setPartnershipActive(
      String uid1, String uid2, bool active) async {
    await setPartnershipHidden(uid1, uid2, !active);
  }

  Future<void> removePartnership(String uid1, String uid2) async {
    await _log.log<void>(
      source: 'SupabaseService.removePartnership',
      table: 'partnerships',
      op: 'DELETE',
      request: {'user_id_1': uid1, 'user_id_2': uid2},
      call: () => _db.from('partnerships').delete().or(
          'and(user_id_1.eq.$uid1,user_id_2.eq.$uid2),and(user_id_1.eq.$uid2,user_id_2.eq.$uid1)'),
    );
  }

  /// Profiles tablosunda kaydı olmayan ortaklar için partner_invites'tan isim çekip AppUser listesi döner.
  Future<List<AppUser>> resolveNamesFromInvites(
      String currentUserId, List<String> missingPartnerIds) async {
    if (missingPartnerIds.isEmpty) return [];

    final result = <AppUser>[];

    for (final partnerId in missingPartnerIds) {
      Map<String, dynamic>? row;
      try {
        row = await _log.log<Map<String, dynamic>?>(
          source: 'SupabaseService.resolveNamesFromInvites',
          table: 'partner_invites',
          op: 'SELECT',
          request: {'partner_id': partnerId},
          call: () => _db
              .from('partner_invites')
              .select('requester_name, payload, from_user_id, to_user_id')
              .or('from_user_id.eq.$partnerId,to_user_id.eq.$partnerId')
              .order('expires_at', ascending: false)
              .limit(1)
              .maybeSingle(),
        );
      } catch (_) {}

      if (row == null) continue;

      String? name;
      if ((row['to_user_id'] as String?) == partnerId) {
        name = (row['requester_name'] as String?)?.trim();
      }
      if (name == null || name.isEmpty) continue;

      final user = AppUser(
        id: partnerId,
        email: '',
        displayName: name,
        createdAt: DateTime.now(),
      );
      // Profil YAZILMAZ (2026-09-23 denetimi U17): burada ortağın satırına
      // `upsertProfile` çağrılıyordu — başkasının `profiles` kaydını boş
      // e-posta ve `onboarding=false` ile ezmeye çalışan bir yazma. RLS
      // (`auth.uid() = id`) onu her yüklemede 403 ile reddediyor, db_logger
      // her seferinde hata kaydediyordu. İsim yalnızca bellekte, ortak
      // listesini göstermek için gerekiyor; kalıcı kaynak `partner_invites`.
      result.add(user);
    }

    return result;
  }

  // ── Signal Notifications ─────────────────────────────────────────────────

  /// Kullanıcı için son N gün içindeki (default 30) tüm sinyalleri getir.
  // ── Takip listesi ─────────────────────────────────────────────────────────
  //
  // `watchlist` tablosu `assets`'ten AYRIDIR ve öyle kalmalıdır: takip edilen
  // varlık hiçbir portföy toplamına girmez (bkz. `0043_watchlist.sql`).
  // Buradaki hiçbir metot `assets` tablosuna dokunmaz.

  Future<List<WatchlistItem>> fetchWatchlist({required String userId}) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchWatchlist',
      table: 'watchlist',
      op: 'SELECT',
      request: {'user_id': userId},
      call: () => _db
          .from('watchlist')
          .select()
          .eq('user_id', userId)
          .order('added_at', ascending: false),
    );
    return rows.map<WatchlistItem>((r) => WatchlistItem.fromMap(r)).toList();
  }

  /// Takibe alır ve eklenen satırı döndürür.
  ///
  /// Sunucudaki unique index (`watchlist_user_asset_uidx`) aynı varlığın iki
  /// kez eklenmesini engeller; çakışmada PostgREST hata fırlatır ve çağıran
  /// bunu kullanıcıya "zaten takipte" olarak gösterir.
  Future<WatchlistItem> addToWatchlist(WatchlistItem item) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.addToWatchlist',
      table: 'watchlist',
      op: 'INSERT',
      request: {'ticker': item.ticker, 'type': item.type.name},
      call: () => _db.from('watchlist').insert(item.toInsertMap()).select(),
    );
    if (rows.isEmpty) return item;
    return WatchlistItem.fromMap(rows.first);
  }

  Future<void> removeFromWatchlist(String id) async {
    await _log.log<void>(
      source: 'SupabaseService.removeFromWatchlist',
      table: 'watchlist',
      op: 'DELETE',
      request: {'id': id},
      call: () => _db.from('watchlist').delete().eq('id', id),
    );
  }

  Future<List<SignalAlert>> fetchSignalNotifications({
    required String userId,
    int limit = 100,
  }) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchSignalNotifications',
      table: 'signal_notifications',
      op: 'SELECT',
      request: {'user_id': userId, 'limit': limit},
      call: () => _db
          .from('signal_notifications')
          .select()
          .eq('user_id', userId)
          .order('sent_at', ascending: false)
          .limit(limit),
    );
    return rows.map<SignalAlert>((r) => SignalAlert.fromMap(r)).toList();
  }

  /// Aynı asset için gönderilmiş son sinyal (dismissed dahil).
  /// De-dup için: yeni sinyal == son sinyal ise skip.
  Future<SignalAlert?> fetchLastSignalForAsset({
    required String userId,
    required String assetId,
  }) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchLastSignalForAsset',
      table: 'signal_notifications',
      op: 'SELECT',
      request: {'user_id': userId, 'asset_id': assetId},
      call: () => _db
          .from('signal_notifications')
          .select()
          .eq('user_id', userId)
          .eq('asset_id', assetId)
          .order('sent_at', ascending: false)
          .limit(1),
    );
    if (rows.isEmpty) return null;
    return SignalAlert.fromMap(rows.first);
  }

  Future<SignalAlert> insertSignalNotification({
    required String userId,
    required SignalAlert alert,
  }) async {
    final body = alert.toInsertMap(userId);
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.insertSignalNotification',
      table: 'signal_notifications',
      op: 'INSERT',
      request: {
        'user_id': userId,
        'asset_id': alert.assetId,
        'signal': body['signal'],
      },
      call: () =>
          _db.from('signal_notifications').insert(body).select().limit(1),
    );
    if (rows.isEmpty) {
      // Fallback: insert döndürmedi, çekilen değerle devam et
      return alert;
    }
    return SignalAlert.fromMap(rows.first);
  }

  // ── Fiyat alarmı bildirimleri (0065) ──────────────────────────────────────
  //
  // Ayrı tablo, ayrı metotlar: `signal_notifications` teknik sinyale özgü
  // alanlar taşır (bkz. `PriceAlertNotification` sınıf notu). Birleştirme
  // istemcide, sunum katmanında yapılır.

  Future<List<PriceAlertNotification>> fetchPriceAlertNotifications({
    required String userId,
    int limit = 100,
  }) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchPriceAlertNotifications',
      table: 'price_alert_notifications',
      op: 'SELECT',
      request: {'user_id': userId, 'limit': limit},
      call: () => _db
          .from('price_alert_notifications')
          .select()
          .eq('user_id', userId)
          .order('sent_at', ascending: false)
          .limit(limit),
    );
    return rows
        .map<PriceAlertNotification>(PriceAlertNotification.fromMap)
        .toList();
  }

  /// Birden çok alarm bildirimini TEK istekte dismiss eder
  /// (sinyal tarafındaki `dismissSignalNotifications` ile aynı gerekçe).
  Future<void> dismissPriceAlertNotifications(List<String> ids) async {
    if (ids.isEmpty) return;
    await _log.log<void>(
      source: 'SupabaseService.dismissPriceAlertNotifications',
      table: 'price_alert_notifications',
      op: 'UPDATE',
      request: {'ids': ids.length, 'dismissed_at': 'now()'},
      call: () => _db
          .from('price_alert_notifications')
          .update({'dismissed_at': DateTime.now().toIso8601String()})
          .inFilter('id', ids),
    );
  }

  /// Satırları KALICI siler — dismiss'ten farkı, geçmişte de durmamaları.
  Future<void> deletePriceAlertNotifications(List<String> ids) async {
    if (ids.isEmpty) return;
    await _log.log<void>(
      source: 'SupabaseService.deletePriceAlertNotifications',
      table: 'price_alert_notifications',
      op: 'DELETE',
      request: {'ids': ids.length},
      call: () => _db
          .from('price_alert_notifications')
          .delete()
          .inFilter('id', ids),
    );
  }

  // ── Genel bildirimler (0066) ──────────────────────────────────────────────
  //
  // Ortaklık daveti, günlük/haftalık özet, takvim — tek tablo, `type` sütunu.
  // Alarm tarafıyla AYNI sözleşme: yalnızca okuma, dismiss ve silme; satırı
  // edge function yazar.

  Future<List<AppNotification>> fetchAppNotifications({
    required String userId,
    int limit = 100,
  }) async {
    final rows = await _log.log<List<Map<String, dynamic>>>(
      source: 'SupabaseService.fetchAppNotifications',
      table: 'app_notifications',
      op: 'SELECT',
      request: {'user_id': userId, 'limit': limit},
      call: () => _db
          .from('app_notifications')
          .select()
          .eq('user_id', userId)
          .order('sent_at', ascending: false)
          .limit(limit),
    );
    return rows.map<AppNotification>(AppNotification.fromMap).toList();
  }

  Future<void> dismissAppNotifications(List<String> ids) async {
    if (ids.isEmpty) return;
    await _log.log<void>(
      source: 'SupabaseService.dismissAppNotifications',
      table: 'app_notifications',
      op: 'UPDATE',
      request: {'ids': ids.length, 'dismissed_at': 'now()'},
      call: () => _db
          .from('app_notifications')
          .update({'dismissed_at': DateTime.now().toIso8601String()})
          .inFilter('id', ids),
    );
  }

  Future<void> deleteAppNotifications(List<String> ids) async {
    if (ids.isEmpty) return;
    await _log.log<void>(
      source: 'SupabaseService.deleteAppNotifications',
      table: 'app_notifications',
      op: 'DELETE',
      request: {'ids': ids.length},
      call: () =>
          _db.from('app_notifications').delete().inFilter('id', ids),
    );
  }

  Future<void> dismissSignalNotification(String id) async {
    await _log.log<void>(
      source: 'SupabaseService.dismissSignalNotification',
      table: 'signal_notifications',
      op: 'UPDATE',
      request: {'id': id, 'dismissed_at': 'now()'},
      call: () => _db
          .from('signal_notifications')
          .update({'dismissed_at': DateTime.now().toIso8601String()})
          .eq('id', id),
    );
  }

  /// Birden çok bildirimi TEK istekte dismiss eder.
  ///
  /// "Tümünü sil" eskiden satır başına ayrı `update` atıyordu: 20 bildirim =
  /// 20 istek. Yavaş olmasının yanında yarıda kesilmeye de açıktı — bir kısmı
  /// silinip bir kısmı kalabiliyordu. `in_` filtresiyle tek atomik istek.
  Future<void> dismissSignalNotifications(List<String> ids) async {
    if (ids.isEmpty) return;
    await _log.log<void>(
      source: 'SupabaseService.dismissSignalNotifications',
      table: 'signal_notifications',
      op: 'UPDATE',
      request: {'ids': ids.length, 'dismissed_at': 'now()'},
      call: () => _db
          .from('signal_notifications')
          .update({'dismissed_at': DateTime.now().toIso8601String()})
          .inFilter('id', ids),
    );
  }

  /// Birden çok bildirimi TEK istekte KALICI siler.
  ///
  /// [dismissSignalNotifications] yalnızca `dismissed_at` damgalar (kayıt
  /// GEÇMİŞ bölümünde durmaya devam eder); bu metot satırı tamamen kaldırır.
  Future<void> deleteSignalNotifications(List<String> ids) async {
    if (ids.isEmpty) return;
    await _log.log<void>(
      source: 'SupabaseService.deleteSignalNotifications',
      table: 'signal_notifications',
      op: 'DELETE',
      request: {'ids': ids.length},
      call: () =>
          _db.from('signal_notifications').delete().inFilter('id', ids),
    );
  }

  Future<void> deleteSignalNotification(String id) async {
    await _log.log<void>(
      source: 'SupabaseService.deleteSignalNotification',
      table: 'signal_notifications',
      op: 'DELETE',
      request: {'id': id},
      call: () =>
          _db.from('signal_notifications').delete().eq('id', id),
    );
  }

  /// Bu hesap push teşhis RPC'lerini çağırabilir mi (`is_push_admin()`).
  ///
  /// Ayarlar ekranı "GELİŞTİRİCİ → Push Teşhisi" tile'ını yalnızca bu true
  /// dönerse gösterir. Sunucu tarafı koruma (RPC'lerdeki `is_push_admin()`
  /// kontrolü) DEĞİŞMEDİ; bu yalnızca admin olmayan kullanıcıya boş bir
  /// teşhis ekranı göstermemek için. Hata ya da eski migration'da (0055
  /// koşulmamışsa GRANT yok → yetki hatası) sessizce false.
  Future<bool> isPushAdmin() async {
    if (_uid == null) return false;
    try {
      final r = await _db.rpc<dynamic>('is_push_admin').timeout(DbLogger.defaultTimeout);
      return r == true;
    } catch (_) {
      return false;
    }
  }
}

/// Not oyu. `geriAl` oyu kaldırır (NULL); oy hiç gönderilmezse dokunulmaz.
enum NotGeriBildirimi {
  yararli(1),
  yararsiz(-1),
  geriAl(null);

  const NotGeriBildirimi(this.deger);
  final int? deger;
}
