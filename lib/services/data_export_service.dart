import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'crash_reporter.dart';
import 'db_logger.dart';

/// Kullanıcının tüm verisini JSON formatında dışa aktarır.
///
/// Yasal dayanak: KVKK Madde 11(b/c) (bilgi alma + erişim) ve
/// GDPR Article 20 (data portability — taşınabilirlik hakkı).
///
/// Akış:
/// 1. Tüm tablolardaki kullanıcı kayıtlarını paralel olarak çek
/// 2. Tek bir JSON dokümanına derle (versiyon + meta + payload)
/// 3. Geçici dosyaya yaz
/// 4. share_plus ile sistem paylaş sheet'ini aç
class DataExportService {
  static final DataExportService instance = DataExportService._();
  DataExportService._();

  /// Dosya biçimi sürümü — yeni tablo eklenince artırılır; içe aktarım
  /// (gelecek) bununla ayrışır.
  static const String exportVersion = '1.0';

  /// Dışa aktarılan tablolar: (tablo, süzgeç sütunu, dosyadaki anahtar).
  ///
  /// 2026-09 denetimi: GDPR 20 / KVKK 11 "tam döküm" dört tabloyu
  /// atlıyordu. Hepsi kullanıcının kendi girdisi ya da ona ait kayıt.
  /// `partnerships` bu listede DEĞİL — iki sütundan birine eşleşir,
  /// [_fetchPartnerships] ayrı çeker; belge anahtarı `partnerships`.
  static const List<(String, String, String)> tablolar = [
    ('profiles', 'id', 'profile'),
    ('assets', 'user_id', 'assets'),
    ('snapshots', 'user_id', 'snapshots'),
    ('partner_invites', 'from_user_id', 'partner_invites_sent'),
    ('user_push_tokens', 'user_id', 'push_tokens'),
    ('disclaimer_acceptances', 'user_id', 'disclaimer_acceptances'),
    ('watchlist', 'user_id', 'watchlist'),
    ('price_alerts', 'user_id', 'price_alerts'),
    ('signal_preferences', 'user_id', 'signal_preferences'),
    ('signal_notifications', 'user_id', 'signal_notifications'),
    ('milestones', 'user_id', 'milestones'),
    ('live_activity_sessions', 'user_id', 'live_activity_sessions'),
  ];

  /// Bir tablo çekilemediğinde dosyaya giden yer tutucu.
  ///
  /// Ham hata metni dosyaya gitmez (2026-09 L8): PostgREST mesajları
  /// tablo/sütun adı ve URL taşır; kullanıcı dosyayı paylaşabilir.
  static const List<Map<String, dynamic>> tabloHatasi = [
    {'_export_error': 'Bu tablo dışa aktarılamadı.'}
  ];

  /// Dışa aktarım belgesini kurar — saf, test edilir.
  ///
  /// [veri] anahtarları [tablolar]'daki üçüncü alan + `partnerships`.
  static Map<String, dynamic> belgeKur({
    required String userId,
    required String? email,
    required Map<String, List<Map<String, dynamic>>> veri,
    required DateTime simdi,
  }) =>
      {
        'export_version': exportVersion,
        'exported_at': simdi.toUtc().toIso8601String(),
        'app': 'sandık',
        'app_version': '1.0.0+1',
        'user': {'id': userId, 'email': email},
        'note': 'Bu dosya tüm kişisel verilerinizi içerir. KVKK Madde 11 ve '
            'GDPR Madde 20 kapsamında veri taşınabilirlik hakkınızla '
            'oluşturulmuştur. Lütfen güvenli bir yerde saklayın; e-posta '
            'veya bulut üzerinden paylaşırken şifreleme kullanın.',
        'data': veri,
      };

  /// Dosya adı — iki nokta dosya sisteminde sorun çıkarır, milisaniye
  /// gereksiz.
  static String dosyaAdi(DateTime simdi) {
    final stamp =
        simdi.toIso8601String().replaceAll(':', '-').split('.').first;
    return 'sandik-veri-export-$stamp.json';
  }

  /// Tabloları [cek] ile toplar; bir tablo hata verirse belge o tabloda
  /// [tabloHatasi] taşır, diğerleri eksiksiz gelir — export tek bir tablo
  /// hatasında durmasın.
  static Future<Map<String, List<Map<String, dynamic>>>> topla({
    required String userId,
    required Future<List<Map<String, dynamic>>> Function(
            String table, String filterColumn)
        cek,
    required Future<List<Map<String, dynamic>>> Function() ortakliklariCek,
    void Function(Object e, StackTrace st, String reason)? raporla,
  }) async {
    Future<List<Map<String, dynamic>>> guvenli(
        String reason, Future<List<Map<String, dynamic>>> Function() f) async {
      try {
        return await f();
      } catch (e, st) {
        raporla?.call(e, st, reason);
        return tabloHatasi;
      }
    }

    final sonuclar = await Future.wait([
      for (final (tablo, sutun, _) in tablolar)
        guvenli('DataExportService.$tablo', () => cek(tablo, sutun)),
      guvenli('DataExportService.partnerships', ortakliklariCek),
    ]);
    return {
      for (var i = 0; i < tablolar.length; i++) tablolar[i].$3: sonuclar[i],
      'partnerships': sonuclar[tablolar.length],
    };
  }

  SupabaseClient get _db => Supabase.instance.client;
  final _log = DbLogger.instance;

  /// Tüm verileri JSON olarak indirip cihazın paylaş sheet'ini açar.
  /// Hata olursa [Exception] fırlatır.
  Future<void> exportAndShare() async {
    final user = _db.auth.currentUser;
    if (user == null) {
      throw Exception('Oturum açık değil.');
    }

    // 1. Tüm tabloları paralel olarak çek
    final veri = await topla(
      userId: user.id,
      cek: (tablo, sutun) => _fetchTable(tablo, sutun, user.id),
      ortakliklariCek: () => _fetchPartnerships(user.id),
      raporla: (e, st, reason) => CrashReporter.report(e, st, reason: reason),
    );

    // 2. JSON dokümanını oluştur
    final simdi = DateTime.now();
    final export = belgeKur(
      userId: user.id,
      email: user.email,
      veri: veri,
      simdi: simdi,
    );
    final pretty = const JsonEncoder.withIndent('  ').convert(export);

    // 3. Geçici dosyaya yaz
    final dir = await getTemporaryDirectory();
    final ad = dosyaAdi(simdi);
    final file = File('${dir.path}/$ad');
    await file.writeAsString(pretty);

    // 4. Share sheet
    try {
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'sandık veri export',
        text: 'sandık uygulamasındaki kişisel verilerimin tam dökümü '
            '(${ad.replaceAll('sandik-veri-export-', '').replaceAll('.json', '')}).',
      );
    } finally {
      // E3 fix: PII içeren JSON cihazın geçici klasöründe kalmasın.
      // Share işlemi bitti veya iptal edildi — dosyayı sil.
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Silinemezse de geçici klasör OS tarafından temizlenir.
      }
    }
  }

  /// Tek bir tabloyu user_id veya id'ye göre çeker; hata [topla]'da yutulur.
  Future<List<Map<String, dynamic>>> _fetchTable(
    String table,
    String filterColumn,
    String userId,
  ) =>
      _log.log<List<Map<String, dynamic>>>(
        source: 'DataExportService.$table',
        table: table,
        op: 'SELECT',
        request: {filterColumn: userId, 'export': true},
        call: () => _db.from(table).select().eq(filterColumn, userId),
      );

  /// Partnerships tablosu özel: user_id_1 VEYA user_id_2 eşleşmeli.
  Future<List<Map<String, dynamic>>> _fetchPartnerships(String userId) =>
      _log.log<List<Map<String, dynamic>>>(
        source: 'DataExportService.partnerships',
        table: 'partnerships',
        op: 'SELECT',
        request: {'user': userId, 'export': true},
        call: () => _db
            .from('partnerships')
            .select()
            .or('user_id_1.eq.$userId,user_id_2.eq.$userId'),
      );
}
