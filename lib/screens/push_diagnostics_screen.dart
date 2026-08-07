import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/sandik.dart';

/// Push zinciri teşhis ekranı — **yalnızca debug build**.
///
/// Zincir: pg_cron → `trigger_analyze_signals` → net.http_post →
/// analyze-signals edge function → FCM → cihaz.
///
/// Bu ekran zincirin her halkasını ayrı ayrı sorgular; "push çalışmıyor"
/// şikayetinde hangi halkanın koptuğunu tahmin etmek yerine görmeyi sağlar.
/// Sunucu tarafı `0021_cron_health_diagnostics.sql` içindeki admin-only
/// RPC'lerle okunur.
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
  int? _myTokenCount;
  /// Bölüm bazlı hatalar — hepsi patlamadıysa sayfada uyarı olarak gösterilir.
  List<String> _kismiHatalar = const [];
  bool _tetikleniyor = false;

  /// Sinyal geçmişini siler — de-dup'ı sıfırlamak için.
  ///
  /// Edge function aynı varlık için son sinyalle aynı olanı tekrar
  /// göndermez; test ederken eski kayıtlar gönderimi engeller. Silme
  /// kullanıcı verisine dokunduğu için onay ister.
  Future<void> _sinyalGecmisiniTemizle() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sandik.surface2,
        title: const Text('Sinyal geçmişi silinsin mi?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          '${_sinyaller.length} kayıt silinecek. Uygulama içi bildirim '
          'listesi de boşalır. Bu işlem geri alınamaz.',
          style: const TextStyle(color: Sandik.text58, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Sandik.loss),
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
          backgroundColor: Sandik.loss,
          content: Text('Silinemedi: $e'),
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
          backgroundColor: Sandik.loss,
          content: Text('Tetikleme başarısız: $e'),
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
    int? tokenCount;
    List<dynamic> sinyaller = const [];
    List<dynamic> tercihler = const [];
    final uid = db.auth.currentUser?.id;
    if (uid != null) {
      try {
        final rows = await db
            .from('user_push_tokens')
            .select('token')
            .eq('user_id', uid);
        tokenCount = (rows as List).length;
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

    if (!mounted) return;
    setState(() {
      _jobs = jobs;
      _runs = runs;
      _responses = responses;
      _sinyaller = sinyaller;
      _tercihler = tercihler;
      _myTokenCount = tokenCount;
      // Hepsi patladıysa tam hata ekranı; kısmi hata sayfada gösterilir.
      _error = hatalar.length == 4 ? hatalar.join('\n\n') : null;
      _kismiHatalar = hatalar;
      _loading = false;
    });
  }

  /// Toplanan verilerden tek cümlelik teşhis üretir.
  ({String baslik, String detay, Color renk}) _teshis() {
    // Sorgu patladıysa boş liste "yok" anlamına GELMEZ — ayırt edilmezse
    // okunamayan bölüm "cron kurulu değil" gibi yanlış teşhise yol açar.
    if (_kismiHatalar.any((h) => h.startsWith('push_cron_jobs'))) {
      return (
        baslik: 'Teşhis eksik',
        detay: 'Cron job sorgusu okunamadı; aşağıdaki hata detayına bakın.',
        renk: Sandik.amber,
      );
    }
    if (_jobs.isEmpty) {
      return (
        baslik: 'Cron job KURULU DEĞİL',
        detay: 'analyze-signals cron kaydı yok. 0017 migration uygulanmamış '
            'demektir — push hiçbir zaman tetiklenmez.',
        renk: Sandik.loss,
      );
    }
    final pasif = _jobs.where((j) => j['active'] == false).toList();
    if (pasif.isNotEmpty) {
      return (
        baslik: 'Cron job PASİF',
        detay: 'Job kayıtlı ama active=false. Tetiklenmez.',
        renk: Sandik.loss,
      );
    }
    if (_runs.isEmpty) {
      return (
        baslik: 'Cron HİÇ ÇALIŞMAMIŞ',
        detay: 'Job aktif ama çalışma kaydı yok. Yeni kurulmuşsa bir sonraki '
            'slotu (TR 11:00 / 15:00) bekleyin.',
        renk: Sandik.amber,
      );
    }
    final basarisiz =
        _runs.where((r) => (r['status'] as String?) != 'succeeded').toList();
    if (basarisiz.isNotEmpty) {
      return (
        baslik: 'Cron çalıştı ama HATA verdi',
        detay: basarisiz.first['return_message']?.toString() ??
            'Bilinmeyen hata',
        renk: Sandik.loss,
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
        renk: Sandik.loss,
      );
    }
    if (_myTokenCount == 0) {
      return (
        baslik: 'Sunucu tarafı SAĞLAM, cihaz token\'ı yok',
        detay: 'Zincir çalışıyor ama bu hesap için kayıtlı push token yok. '
            'Bildirim izni reddedilmiş olabilir.',
        renk: Sandik.amber,
      );
    }

    // 2xx dönmüş olmak bildirim gittiği anlamına GELMEZ. Gövdedeki sayaçlara
    // bakılmazsa "passed_threshold:1, sent:0" tablosu (eşiği geçen sinyal
    // var ama hiç gönderim yok) sağlıklı sanılır — ilk teşhiste tam olarak
    // bu oldu. En yeni yanıtın gövdesini ayrıştırıp gerçeği söylüyoruz.
    final sonYanit = _responses.isEmpty ? null : _responses.first;
    final govde = sonYanit?['content']?.toString() ?? '';
    final passed = _sayiOku(govde, 'passed_threshold');
    final sent = _sayiOku(govde, 'sent');
    final failed = _sayiOku(govde, 'failed');

    if (failed != null && failed > 0) {
      return (
        baslik: 'FCM gönderimi başarısız ($failed)',
        detay: 'Edge function push atmayı denedi ama FCM reddetti. '
            'Yanıt gövdesindeki hata sebebine bakın (3. bölüm).',
        renk: Sandik.loss,
      );
    }
    if (passed != null && passed > 0 && sent == 0) {
      return (
        baslik: 'Sinyal üretildi ama HİÇ GÖNDERİLMEDİ',
        detay: 'passed_threshold=$passed, sent=0, failed=0 — yani FCM\'e hiç '
            'istek atılmadan atlandı. En olası sebep de-dup: aynı varlık '
            'için son sinyal ile yenisi aynı. 5. bölümdeki geçmişi '
            'temizleyip tekrar deneyin.',
        renk: Sandik.loss,
      );
    }
    if (sent != null && sent > 0) {
      return (
        baslik: 'Zincir çalışıyor — $sent bildirim gönderildi',
        detay: 'Cron, edge function ve FCM sağlıklı. Cihaza düşmüyorsa '
            'bildirim izni / kanal ayarlarına bakın.',
        renk: Sandik.gain,
      );
    }
    return (
      baslik: 'Zincir ayakta, gönderilecek sinyal yok',
      detay: 'Cron çalışıyor ve edge function 2xx dönüyor, ancak hiçbir '
          'varlık eşiği geçmedi (passed_threshold=0). Bu normal olabilir.',
      renk: Sandik.amber,
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
    // Güvenlik ağı: release build'de bu ekran hiç açılmamalı.
    if (!kDebugMode) {
      return const Scaffold(
        backgroundColor: Sandik.background,
        body: Center(
          child: Text('Yalnızca debug build',
              style: TextStyle(color: Sandik.text58)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Sandik.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Push Teşhisi',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Sandik.text58),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Sandik.amber))
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
          const Icon(Icons.error_outline_rounded,
              color: Sandik.loss, size: 40),
          const SizedBox(height: 12),
          Text(
            yetkisiz
                ? 'Bu hesap admin değil.\nTeşhis RPC\'leri yalnızca admin '
                    'e-postasına açıktır.'
                : 'Teşhis okunamadı',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 10),
          SelectableText(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Sandik.text36, fontSize: 11),
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
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.4)),
            ],
          ),
        ),
        if (_kismiHatalar.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Sandik.loss.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(SandikRadius.md),
              border: Border.all(color: Sandik.loss.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bazı bölümler okunamadı',
                    style: TextStyle(
                        color: Sandik.loss,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                SelectableText(_kismiHatalar.join('\n\n'),
                    style: const TextStyle(
                        color: Sandik.text58, fontSize: 10.5, height: 1.4)),
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
        _bolum('4. CİHAZ TOKEN\'I', null, [
          _myTokenCount == null
              ? 'Oturum yok'
              : '$_myTokenCount adet token kayıtlı',
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
              style: TextButton.styleFrom(foregroundColor: Sandik.loss),
              label: const Text('Sinyal geçmişini temizle (de-dup sıfırla)'),
              onPressed: _tetikleniyor ? null : _sinyalGecmisiniTemizle,
            ),
          ),
          const Text(
            'Edge function son kayda bakıp aynı sinyali tekrar göndermez. '
            'Test ederken bu kayıtlar gönderimi engeller.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Sandik.text36, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        const Text('ZİNCİRİ ELLE TETİKLE',
            style: TextStyle(
                color: Sandik.amber,
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
                style: FilledButton.styleFrom(backgroundColor: Sandik.amber),
                onPressed: _tetikleniyor ? null : () => _tetikle(dryRun: false),
                child: const Text('Gerçek push'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Prova yan etki bırakmaz. "Gerçek push" bildirimi cihazına '
          'gönderir — birkaç saniye sonra yenileyip 3. bölüme bakın.',
          style: TextStyle(color: Sandik.text36, fontSize: 11, height: 1.4),
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
              style: const TextStyle(
                  color: Sandik.amber,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Sandik.surface1,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: bosMesaj != null
                ? Text(bosMesaj,
                    style: const TextStyle(
                        color: Sandik.text36,
                        fontSize: 12,
                        fontStyle: FontStyle.italic))
                : SelectableText(
                    satirlar.join('\n'),
                    style: const TextStyle(
                        color: Colors.white70,
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
