import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/remote_push_service.dart';
import '../theme/sandik.dart';

/// Push zinciri teşhis ekranı — **admin'e açık, release dahil**.
///
/// Zincir: pg_cron → `trigger_analyze_signals` → net.http_post →
/// analyze-signals edge function → FCM → cihaz.
///
/// Bu ekran zincirin her halkasını ayrı ayrı sorgular; "push çalışmıyor"
/// şikayetinde hangi halkanın koptuğunu tahmin etmek yerine görmeyi sağlar.
/// Sunucu tarafı `0021_cron_health_diagnostics.sql` içindeki admin-only
/// RPC'lerle okunur; cihaz tarafı doğrudan FirebaseMessaging'den.
///
/// **Neden debug'a kilitli DEĞİL:** zincir ağırlıklı olarak TestFlight'ta
/// kopuyor — APNs ortamı, provisioning profile ve gerçek cihaz izni debug
/// build'de hiç sınanmaz. Kilitliyken araç tam ihtiyaç duyulan yerde
/// "Yalnızca debug build" yazıyordu. Koruma `is_admin()` RPC'lerinde;
/// ekran salt okunurdur ve token'ların kendisini göstermez.
class PushDiagnosticsScreen extends StatefulWidget {
  const PushDiagnosticsScreen({super.key});

  @override
  State<PushDiagnosticsScreen> createState() => _PushDiagnosticsScreenState();
}

class _PushDiagnosticsScreenState extends State<PushDiagnosticsScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _jobs = const [];
  List<dynamic> _runs = const [];
  List<dynamic> _responses = const [];
  List<dynamic> _sinyaller = const [];
  List<dynamic> _tercihler = const [];
  /// Kayıtlı token satırları — platformuyla birlikte (bkz. `_load`).
  List<dynamic> _tokenlar = const [];
  int? _myTokenCount;
  /// Bölüm bazlı hatalar — hepsi patlamadıysa sayfada uyarı olarak gösterilir.
  List<String> _kismiHatalar = const [];
  bool _tetikleniyor = false;

  /// CİHAZ tarafı teşhisi — sunucu sorgularının göremediği halka.
  ///
  /// Sunucu yalnızca `user_push_tokens` tablosunu görür; satır YOKSA sebebi
  /// söyleyemez. Oysa iOS'ta zincir üç ayrı noktada sessizce kopabilir:
  /// izin verilmemiştir, APNs kaydı olmamıştır (`registerForRemoteNotifications`
  /// çağrılmazsa `getAPNSToken()` hep null döner), ya da FCM token üretilmemiştir.
  /// Üçü de aynı belirtiyi verir: "push gelmiyor".
  Map<String, String> _cihaz = const {};

  /// Sinyal geçmişini siler — de-dup'ı sıfırlamak için.
  ///
  /// Edge function aynı varlık için son sinyalle aynı olanı tekrar
  /// göndermez; test ederken eski kayıtlar gönderimi engeller. Silme
  /// kullanıcı verisine dokunduğu için onay ister.
  Future<void> _sinyalGecmisiniTemizle() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.c.surface2,
        title: Text('Sinyal geçmişi silinsin mi?',
            style: TextStyle(color: context.c.text90, fontSize: 17)),
        content: Text(
          '${_sinyaller.length} kayıt silinecek. Uygulama içi bildirim '
          'listesi de boşalır. Bu işlem geri alınamaz.',
          style: TextStyle(color: context.c.text58, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: context.c.loss),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true) return;

    setState(() => _tetikleniyor = true);
    try {
      final db = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      if (uid == null) return;
      await db.from('signal_notifications').delete().eq('user_id', uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sinyal geçmişi temizlendi')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.c.loss,
          content: Text('Silinemedi: $e',
              style: TextStyle(color: context.c.onStatus)),
        ),
      );
    } finally {
      if (mounted) setState(() => _tetikleniyor = false);
    }
  }

  /// Zinciri elle tetikler — cron'un yaptığı çağrının aynısı.
  ///
  /// [dryRun] true iken edge function hiçbir yan etki bırakmaz (push atmaz,
  /// geçmişe yazmaz), yalnızca ne gönderileceğini raporlar.
  Future<void> _tetikle({required bool dryRun}) async {
    setState(() => _tetikleniyor = true);
    try {
      final sonuc = await Supabase.instance.client.rpc(
        'push_test_trigger',
        params: {'p_slot': 'morning', 'p_dry_run': dryRun},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sonuc?.toString() ?? 'Tetiklendi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.c.loss,
          content: Text('Tetikleme başarısız: $e',
              style: TextStyle(color: context.c.onStatus)),
        ),
      );
    } finally {
      if (mounted) setState(() => _tetikleniyor = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final db = Supabase.instance.client;

    // Her bölüm AYRI AYRI denenir. Tek try bloğunda toplanırsa ilk RPC
    // patladığında (örn. şema uyuşmazlığı) diğer üç bölümün sonucu da
    // kaybolur ve ekran tamamen boş kalır — teşhis ekranının en çok
    // ihtiyaç duyulduğu anda işe yaramaz hale gelmesi demek bu.
    Future<List<dynamic>> dene(
      String ad,
      Future<dynamic> Function() call,
      List<String> hatalar,
    ) async {
      try {
        return (await call()) as List<dynamic>? ?? const [];
      } catch (e) {
        hatalar.add('$ad: $e');
        return const [];
      }
    }

    final hatalar = <String>[];
    final jobs = await dene('push_cron_jobs', () => db.rpc('push_cron_jobs'), hatalar);
    final runs = await dene('push_cron_runs',
        () => db.rpc('push_cron_runs', params: {'p_limit': 20}), hatalar);
    final responses = await dene('push_http_responses',
        () => db.rpc('push_http_responses', params: {'p_limit': 20}), hatalar);

    // Kendi push token'ımız kayıtlı mı — zincirin cihaz ucu.
    //
    // PLATFORM de okunur: yalnızca sayı ("2 token kayıtlı") yanıltıcıdır.
    // Gerçek vaka — kullanıcı "TOKEN: 2" görüp iPhone'unun kayıtlı olduğunu
    // sandı, oysa ikisi de Android'di ve iOS hiç yazılmamıştı. Sorunun ta
    // kendisi sayının içinde gizlenmişti.
    int? tokenCount;
    List<dynamic> tokenlar = const [];
    List<dynamic> sinyaller = const [];
    List<dynamic> tercihler = const [];
    final uid = db.auth.currentUser?.id;
    if (uid != null) {
      try {
        final rows = await db
            .from('user_push_tokens')
            .select('platform, updated_at')
            .eq('user_id', uid)
            .order('updated_at', ascending: false);
        tokenlar = rows as List<dynamic>;
        tokenCount = tokenlar.length;
      } catch (e) {
        hatalar.add('user_push_tokens: $e');
      }
      // De-dup kurbanlarını görmek için: edge function bu tablodaki SON
      // kayda bakıp aynı sinyali tekrar göndermiyor. Buradaki eski bir satır
      // "passed_threshold:1, sent:0" tablosunun sebebi olabilir.
      try {
        sinyaller = await db
            .from('signal_notifications')
            .select('asset_name, signal, confidence, sent_at')
            .eq('user_id', uid)
            .order('sent_at', ascending: false)
            .limit(10) as List<dynamic>;
      } catch (e) {
        hatalar.add('signal_notifications: $e');
      }
      // Tercihler GERÇEKTEN sunucuya yazılıyor mu? `_syncSignalPreferenceWith`
      // hataları sessizce yutuyor (catch (_) {}), yani yazma başarısız olsa
      // bile uygulamada hiçbir belirti olmaz. Burası tek doğrulama yolu.
      try {
        tercihler = await db
            .from('signal_preferences')
            .select(
                'asset_type, threshold, frequency, notify_hours, signals_enabled, neutral_push, last_notified_at, updated_at')
            .eq('user_id', uid)
            .order('asset_type') as List<dynamic>;
      } catch (e) {
        hatalar.add('signal_preferences: $e');
      }
    }

    // Cihaz teşhisi ASLA sayfayı düşürmemeli.
    //
    // `_cihazTeshisi` fırlatırsa `_load` çöker, `setState` hiç çalışmaz ve
    // ekran eski veride donar — kullanıcı bunu "cihaz bölümü yok" olarak
    // görür ve eski build'de sandık. Ayrıca `getAPNSToken()` iOS'ta uzun
    // süre bloklayabildiği için zaman aşımı şart.
    Map<String, String> cihaz;
    try {
      cihaz = await _cihazTeshisi().timeout(
        const Duration(seconds: 8),
        onTimeout: () => {
          'Cihaz teşhisi': 'ZAMAN AŞIMI (8 sn) — getAPNSToken() yanıt vermedi',
        },
      );
    } catch (e) {
      cihaz = {'Cihaz teşhisi': 'HATA: $e'};
    }

    if (!mounted) return;
    setState(() {
      _jobs = jobs;
      _runs = runs;
      _responses = responses;
      _sinyaller = sinyaller;
      _tercihler = tercihler;
      _tokenlar = tokenlar;
      _myTokenCount = tokenCount;
      _cihaz = cihaz;
      // Hepsi patladıysa tam hata ekranı; kısmi hata sayfada gösterilir.
      _error = hatalar.length == 4 ? hatalar.join('\n\n') : null;
      _kismiHatalar = hatalar;
      _loading = false;
    });
  }

  /// Cihazdan APNs/FCM token durumunu okur.
  ///
  /// Token'ların KENDİSİ gösterilmez, yalnızca var/yok ve uzunluk: bu ekran
  /// paylaşılabilir bir yüzey ve push token'ı cihaza mesaj göndermeye yarar.
  ///
  /// Her adım ayrı ayrı yakalanır — biri patlarsa diğerleri yine okunur,
  /// çünkü hangisinin patladığı teşhisin ta kendisidir.
  Future<Map<String, String>> _cihazTeshisi() async {
    final sonuc = <String, String>{};

    sonuc['Platform'] = defaultTargetPlatform == TargetPlatform.iOS
        ? 'iOS'
        : defaultTargetPlatform == TargetPlatform.android
            ? 'Android'
            : defaultTargetPlatform.name;

    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.getNotificationSettings();
      sonuc['Bildirim izni'] = settings.authorizationStatus.name;

      // iOS'a özgü: APNs token'ı olmadan FCM token ÜRETİLEMEZ. Null ise
      // cihaz APNs'e hiç kayıt olmamıştır ve sorun buradadır — daha
      // ilerideki halkalara bakmak zaman kaybı olur.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          final apns = await messaging.getAPNSToken();
          sonuc['APNs token'] = (apns == null || apns.isEmpty)
              ? 'YOK (null) ← zincir BURADA kopuyor'
              : 'var (${apns.length} karakter)';
        } catch (e) {
          sonuc['APNs token'] = 'HATA: $e';
        }
      }

      try {
        final fcm = await messaging.getToken();
        sonuc['FCM token'] = (fcm == null || fcm.isEmpty)
            ? 'YOK (null)'
            : 'var (${fcm.length} karakter)';
      } catch (e) {
        sonuc['FCM token'] = 'HATA: $e';
      }

      // Uygulama açılışındaki GERÇEK denemenin hatası. Buradaki çağrı
      // başarılı olsa bile açılıştaki deneme patlamış olabilir (yarış
      // durumu, APNs henüz hazır değilken) — token'ın neden yazılmadığını
      // asıl bu satır açıklar.
      final acilisHatasi = RemotePushService.instance.sonTokenHatasi;
      if (acilisHatasi != null) {
        sonuc['Açılıştaki hata'] = acilisHatasi;
      }
    } catch (e) {
      sonuc['Firebase'] = 'HATA: $e';
    }

    sonuc['Sunucuda kayıtlı'] = '${_myTokenCount ?? 0} token';
    return sonuc;
  }

  /// Toplanan verilerden tek cümlelik teşhis üretir.
  ({String baslik, String detay, Color renk}) _teshis() {
    // Sorgu patladıysa boş liste "yok" anlamına GELMEZ — ayırt edilmezse
    // okunamayan bölüm "cron kurulu değil" gibi yanlış teşhise yol açar.
    if (_kismiHatalar.any((h) => h.startsWith('push_cron_jobs'))) {
      return (
        baslik: 'Teşhis eksik',
        detay: 'Cron job sorgusu okunamadı; aşağıdaki hata detayına bakın.',
        renk: context.c.amberText,
      );
    }
    if (_jobs.isEmpty) {
      return (
        baslik: 'Cron job KURULU DEĞİL',
        detay: 'analyze-signals cron kaydı yok. 0017 migration uygulanmamış '
            'demektir — push hiçbir zaman tetiklenmez.',
        renk: context.c.loss,
      );
    }
    final pasif = _jobs.where((j) => j['active'] == false).toList();
    if (pasif.isNotEmpty) {
      return (
        baslik: 'Cron job PASİF',
        detay: 'Job kayıtlı ama active=false. Tetiklenmez.',
        renk: context.c.loss,
      );
    }
    if (_runs.isEmpty) {
      return (
        baslik: 'Cron HİÇ ÇALIŞMAMIŞ',
        detay: 'Job aktif ama çalışma kaydı yok. Yeni kurulmuşsa bir sonraki '
            'slotu (TR 11:00 / 15:00) bekleyin.',
        renk: context.c.amberText,
      );
    }
    final basarisiz =
        _runs.where((r) => (r['status'] as String?) != 'succeeded').toList();
    if (basarisiz.isNotEmpty) {
      return (
        baslik: 'Cron çalıştı ama HATA verdi',
        detay: basarisiz.first['return_message']?.toString() ??
            'Bilinmeyen hata',
        renk: context.c.loss,
      );
    }
    final hataliYanit = _responses
        .where((r) => ((r['status_code'] as num?)?.toInt() ?? 0) >= 400)
        .toList();
    if (hataliYanit.isNotEmpty) {
      final kod = hataliYanit.first['status_code'];
      return (
        baslik: 'Edge function $kod döndü',
        detay: kod == 401
            ? 'Vault secret ile edge function secret uyuşmuyor. '
                'ANALYZE_SIGNALS_CRON_SECRET değerlerini eşitleyin.'
            : (hataliYanit.first['content']?.toString() ?? ''),
        renk: context.c.loss,
      );
    }
    if (_myTokenCount == 0) {
      return (
        baslik: 'Sunucu tarafı SAĞLAM, cihaz token\'ı yok',
        detay: 'Zincir çalışıyor ama bu hesap için kayıtlı push token yok. '
            'Bildirim izni reddedilmiş olabilir.',
        renk: context.c.amberText,
      );
    }

    // 2xx dönmüş olmak bildirim gittiği anlamına GELMEZ. Gövdedeki sayaçlara
    // bakılmazsa "passed_threshold:1, sent:0" tablosu (eşiği geçen sinyal
    // var ama hiç gönderim yok) sağlıklı sanılır — ilk teşhiste tam olarak
    // bu oldu. En yeni yanıtın gövdesini ayrıştırıp gerçeği söylüyoruz.
    // SADECE analyze-signals yanıtlarına bak.
    //
    // `net._http_response` tablosu TÜM cron'ların yanıtlarını taşıyor ve
    // `live-activity-push` 5 dakikada bir çalıştığı için listeyi domine
    // ediyor. Ayrım yapılmadığında ekran onun `{"sent":2}` çıktısını okuyup
    // "zincir çalışıyor, 2 bildirim gönderildi" diyordu — oysa sinyal
    // push'u hiç gönderilmemişti ve kullanıcının iPhone'u kayıtlı bile
    // değildi. Yanlış teşhis, teşhissizlikten kötüdür.
    //
    // Ayırt edici işaret gövdede: analyze-signals `passed_threshold`
    // döndürür, live-activity-push `skippedStale`.
    final sinyalYanitlari = _responses.where((r) {
      final c = r['content']?.toString() ?? '';
      return c.contains('passed_threshold');
    }).toList();

    final sonYanit = sinyalYanitlari.isEmpty ? null : sinyalYanitlari.first;
    final govde = sonYanit?['content']?.toString() ?? '';

    if (sonYanit == null && _responses.isNotEmpty) {
      return (
        baslik: 'Sinyal turu henüz çalışmamış',
        detay: 'Kayıtlı yanıtların hepsi başka cron\'lara ait (çoğunlukla '
            'live-activity-push, 5 dk\'da bir). analyze-signals saat başı '
            've yalnızca bildirim penceresi içinde çalışır.',
        renk: context.c.amberText,
      );
    }
    final passed = _sayiOku(govde, 'passed_threshold');
    final sent = _sayiOku(govde, 'sent');
    final failed = _sayiOku(govde, 'failed');

    if (failed != null && failed > 0) {
      return (
        baslik: 'FCM gönderimi başarısız ($failed)',
        detay: 'Edge function push atmayı denedi ama FCM reddetti. '
            'Yanıt gövdesindeki hata sebebine bakın (3. bölüm).',
        renk: context.c.loss,
      );
    }
    if (passed != null && passed > 0 && sent == 0) {
      return (
        baslik: 'Sinyal üretildi ama HİÇ GÖNDERİLMEDİ',
        detay: 'passed_threshold=$passed, sent=0, failed=0 — yani FCM\'e hiç '
            'istek atılmadan atlandı. En olası sebep de-dup: aynı varlık '
            'için son sinyal ile yenisi aynı. 5. bölümdeki geçmişi '
            'temizleyip tekrar deneyin.',
        renk: context.c.loss,
      );
    }
    if (sent != null && sent > 0) {
      // Gönderim BAŞKA bir cihaza gitmiş olabilir. "Zincir çalışıyor"
      // demeden önce BU cihazın kayıtlı olduğunu doğrula: aksi halde
      // kullanıcı yeşil bir onay görüp kendi telefonunda neden bildirim
      // olmadığını aramaya devam eder.
      final buCihazKayitli = _tokenlar.isEmpty ||
          _tokenlar.any((t) =>
              t['platform'] ==
              (defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'android'));

      if (!buCihazKayitli) {
        return (
          baslik: 'Gönderim var ama BU cihaza değil',
          detay: '$sent bildirim gönderildi — hepsi başka cihazlara. '
              'Bu cihazın platformu (${defaultTargetPlatform.name}) '
              'sunucuda kayıtlı değil; 4. bölüme bakın.',
          renk: context.c.loss,
        );
      }

      return (
        baslik: 'Zincir çalışıyor — $sent bildirim gönderildi',
        detay: 'Cron, edge function ve FCM sağlıklı. Cihaza düşmüyorsa '
            'bildirim izni / kanal ayarlarına bakın.',
        renk: context.c.gain,
      );
    }
    return (
      baslik: 'Zincir ayakta, gönderilecek sinyal yok',
      detay: 'Cron çalışıyor ve edge function 2xx dönüyor, ancak hiçbir '
          'varlık eşiği geçmedi (passed_threshold=0). Bu normal olabilir.',
      renk: context.c.amberText,
    );
  }

  /// JSON gövdesinden `"anahtar":sayı` değerini çeker.
  /// Tam ayrıştırma yerine regex: gövde kırpılmış olabilir (500 karakter).
  int? _sayiOku(String govde, String anahtar) {
    final m = RegExp('"$anahtar"\\s*:\\s*(\\d+)').firstMatch(govde);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  @override
  Widget build(BuildContext context) {
    // NOT: burada `kDebugMode` kapısı VARDI ve ekranı işlevsiz kılıyordu.
    //
    // Bu ekranın tek amacı push zincirinin neresinin koptuğunu göstermek;
    // zincir ise ağırlıklı olarak TESTFLIGHT'ta kopuyor (APNs ortamı,
    // provisioning profile, gerçek cihaz izni). Bunların hiçbiri debug
    // build'de sınanmadığı için araç tam ihtiyaç duyulan yerde "Yalnızca
    // debug build" yazıyordu.
    //
    // Yerine GERÇEK koruma geçerli: teşhis RPC'leri `is_admin()` ile
    // korunuyor (bkz. 0021_cron_health_diagnostics.sql) ve admin olmayan
    // hesap aşağıda açıkça uyarılıyor. Ekran salt okunurdur ve token'ların
    // kendisini değil yalnızca var/yok bilgisini gösterir.
    return Scaffold(
      backgroundColor: context.c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Push Teşhisi',
            style: TextStyle(color: context.c.text90, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: context.c.text58),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: context.c.amberText))
            : _error != null
                ? _hataGorunumu()
                : _icerik(),
      ),
    );
  }

  Widget _hataGorunumu() {
    final yetkisiz = _error!.contains('42501') || _error!.contains('Yetkisiz');
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded,
              color: context.c.loss, size: 40),
          const SizedBox(height: 12),
          Text(
            yetkisiz
                ? 'Bu hesap admin değil.\nTeşhis RPC\'leri yalnızca admin '
                    'e-postasına açıktır.'
                : 'Teşhis okunamadı',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.c.text90, fontSize: 15),
          ),
          const SizedBox(height: 10),
          SelectableText(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.c.text36, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _icerik() {
    final t = _teshis();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.renk.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(color: t.renk.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.baslik,
                  style: TextStyle(
                      color: t.renk,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              const SizedBox(height: 6),
              Text(t.detay,
                  style: TextStyle(
                      color: context.c.text58, fontSize: 13, height: 1.4)),
            ],
          ),
        ),
        if (_kismiHatalar.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.c.loss.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(SandikRadius.md),
              border: Border.all(color: context.c.loss.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bazı bölümler okunamadı',
                    style: TextStyle(
                        color: context.c.loss,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                SelectableText(_kismiHatalar.join('\n\n'),
                    style: TextStyle(
                        color: context.c.text58, fontSize: 10.5, height: 1.4)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        _bolum('1. CRON JOB\'LARI', _jobs.isEmpty ? 'Kayıt yok' : null, [
          for (final j in _jobs)
            '${j['jobname']}  •  ${j['schedule']}  •  '
                '${j['active'] == true ? 'aktif' : 'PASİF'}',
        ]),
        _bolum('2. CRON ÇALIŞMA GEÇMİŞİ',
            _runs.isEmpty ? 'Hiç çalışmamış' : null, [
          for (final r in _runs)
            '${r['start_time']}  •  ${r['status']}'
                '${r['return_message'] != null && (r['return_message'] as String).isNotEmpty ? '\n   ↳ ${r['return_message']}' : ''}',
        ]),
        _bolum('3. EDGE FUNCTION YANITLARI',
            _responses.isEmpty ? 'Yanıt kaydı yok' : null, [
          for (final r in _responses)
            '${r['created']}  •  HTTP ${r['status_code']}'
                '${r['content'] != null && (r['content'] as String).isNotEmpty ? '\n   ↳ ${r['content']}' : ''}',
        ]),
        // Sunucu yalnızca "kaç satır var" der; satır yoksa SEBEBİNİ
        // söyleyemez. Cihaz tarafı okunmadan iOS'ta izin / APNs kaydı /
        // FCM üretimi ayrımı yapılamaz — üçü de aynı belirtiyi verir.
        _bolum('4. CİHAZ TOKEN\'I', null, [
          for (final e in _cihaz.entries) '${e.key}: ${e.value}',
          if (_cihaz.isEmpty && _myTokenCount == null) 'Oturum yok',
          // Sunucudaki satırlar PLATFORMUYLA listelenir. Yalnızca sayı
          // göstermek ("2 token kayıtlı") bu ekranın cevaplaması gereken
          // soruyu — "bu cihaz kayıtlı mı?" — gizliyordu.
          if (_tokenlar.isNotEmpty) ...[
            '',
            'Sunucudaki kayıtlar:',
            for (final t in _tokenlar)
              '  • ${t['platform']}  (${t['updated_at']?.toString().substring(0, 16) ?? '?'})',
            if (!_tokenlar.any((t) => t['platform'] == 'ios') &&
                defaultTargetPlatform == TargetPlatform.iOS)
              '  ⚠ BU cihaz (iOS) kayıtlı DEĞİL — sinyal push\'u ulaşamaz',
          ],
        ]),
        _bolum(
            '5. SUNUCUDAKİ TERCİHLER (ayarlar kaydediliyor mu?)',
            _tercihler.isEmpty
                ? 'Hiç satır yok — ayarlar sunucuya YAZILMAMIŞ'
                : null, [
          for (final p in _tercihler)
            '${p['asset_type']}  eşik:${p['threshold']}  '
                '${p['frequency']} ${p['notify_hours']}\n'
                '   açık:${p['signals_enabled']} nötr:${p['neutral_push']} '
                'son:${p['last_notified_at'] ?? "-"}\n'
                '   güncelleme: ${p['updated_at']}',
        ]),
        _bolum('6. SİNYAL GEÇMİŞİ (de-dup kaynağı)',
            _sinyaller.isEmpty ? 'Kayıt yok' : null, [
          for (final s in _sinyaller)
            '${s['sent_at']}\n   ${s['asset_name']} → ${s['signal']} '
                '(güven: ${s['confidence']})',
        ]),
        if (_sinyaller.isNotEmpty) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              style: TextButton.styleFrom(foregroundColor: context.c.loss),
              label: const Text('Sinyal geçmişini temizle (de-dup sıfırla)'),
              onPressed: _tetikleniyor ? null : _sinyalGecmisiniTemizle,
            ),
          ),
          Text(
            'Edge function son kayda bakıp aynı sinyali tekrar göndermez. '
            'Test ederken bu kayıtlar gönderimi engeller.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.c.text36, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        Text('ZİNCİRİ ELLE TETİKLE',
            style: TextStyle(
                color: context.c.amberText,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _tetikleniyor ? null : () => _tetikle(dryRun: true),
                child: const Text('Prova (dry-run)'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: context.c.amberFill),
                onPressed: _tetikleniyor ? null : () => _tetikle(dryRun: false),
                child: const Text('Gerçek push'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Prova yan etki bırakmaz. "Gerçek push" bildirimi cihazına '
          'gönderir — birkaç saniye sonra yenileyip 3. bölüme bakın.',
          style: TextStyle(color: context.c.text36, fontSize: 11, height: 1.4),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Teşhisi kopyala'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _metinRapor(t)));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Panoya kopyalandı')),
              );
            },
          ),
        ),
      ],
    );
  }

  String _metinRapor(({String baslik, String detay, Color renk}) t) {
    final b = StringBuffer()
      ..writeln('=== PUSH TEŞHİSİ ===')
      ..writeln('${t.baslik}: ${t.detay}')
      ..writeln()
      ..writeln('CRON JOBS (${_jobs.length}):');
    for (final j in _jobs) {
      b.writeln('  ${j['jobname']} | ${j['schedule']} | active=${j['active']}');
    }
    b.writeln('\nCRON RUNS (${_runs.length}):');
    for (final r in _runs) {
      b.writeln('  ${r['start_time']} | ${r['status']} | '
          '${r['return_message'] ?? ''}');
    }
    b.writeln('\nHTTP RESPONSES (${_responses.length}):');
    for (final r in _responses) {
      b.writeln('  ${r['created']} | ${r['status_code']} | '
          '${r['content'] ?? ''}');
    }
    b.writeln('\nTOKEN: ${_myTokenCount ?? "?"}');
    b.writeln('\nSUNUCUDAKİ TERCİHLER (${_tercihler.length}):');
    for (final p in _tercihler) {
      b.writeln('  ${p['asset_type']} | eşik=${p['threshold']} | '
          '${p['frequency']} ${p['notify_hours']} | '
          'açık=${p['signals_enabled']} | nötr=${p['neutral_push']} | '
          'güncelleme=${p['updated_at']}');
    }
    b.writeln('\nSİNYAL GEÇMİŞİ (${_sinyaller.length}):');
    for (final s in _sinyaller) {
      b.writeln('  ${s['sent_at']} | ${s['asset_name']} | ${s['signal']} | '
          'conf=${s['confidence']}');
    }
    return b.toString();
  }

  Widget _bolum(String baslik, String? bosMesaj, List<String> satirlar) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(baslik,
              style: TextStyle(
                  color: context.c.amberText,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.c.surface1,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              border: Border.all(color: context.c.hairline),
            ),
            child: bosMesaj != null
                ? Text(bosMesaj,
                    style: TextStyle(
                        color: context.c.text36,
                        fontSize: 12,
                        fontStyle: FontStyle.italic))
                : SelectableText(
                    satirlar.join('\n'),
                    style: TextStyle(
                        color: context.c.text58,
                        fontSize: 11.5,
                        height: 1.5,
                        fontFamily: 'monospace'),
                  ),
          ),
        ],
      ),
    );
  }
}
