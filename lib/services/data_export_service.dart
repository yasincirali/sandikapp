import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  static const String _exportVersion = '1.0';

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
    final results = await Future.wait([
      _fetchTable('profiles', 'id', user.id),
      _fetchTable('assets', 'user_id', user.id),
      _fetchTable('snapshots', 'user_id', user.id),
      _fetchTable('partner_invites', 'from_user_id', user.id),
      _fetchPartnerships(user.id),
      _fetchTable('user_push_tokens', 'user_id', user.id),
      _fetchTable('disclaimer_acceptances', 'user_id', user.id),
    ]);

    // 2. JSON dokümanını oluştur
    final export = {
      'export_version': _exportVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'app': 'sandık',
      'app_version': '1.0.0+1',
      'user': {
        'id': user.id,
        'email': user.email,
      },
      'note':
          'Bu dosya tüm kişisel verilerinizi içerir. KVKK Madde 11 ve '
          'GDPR Madde 20 kapsamında veri taşınabilirlik hakkınızla '
          'oluşturulmuştur. Lütfen güvenli bir yerde saklayın; e-posta '
          'veya bulut üzerinden paylaşırken şifreleme kullanın.',
      'data': {
        'profile': results[0],
        'assets': results[1],
        'snapshots': results[2],
        'partner_invites_sent': results[3],
        'partnerships': results[4],
        'push_tokens': results[5],
        'disclaimer_acceptances': results[6],
      },
    };

    final pretty = const JsonEncoder.withIndent('  ').convert(export);

    // 3. Geçici dosyaya yaz
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/sandik-veri-export-$stamp.json');
    await file.writeAsString(pretty);

    // 4. Share sheet
    try {
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'sandık veri export',
        text:
            'sandık uygulamasındaki kişisel verilerimin tam dökümü '
            '($stamp).',
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

  /// Tek bir tabloyu user_id veya id'ye göre çeker, başarısızlıkta sessizce
  /// boş liste döner — export tek bir tablo hatasında durmasın.
  Future<List<Map<String, dynamic>>> _fetchTable(
    String table,
    String filterColumn,
    String userId,
  ) async {
    try {
      return await _log.log<List<Map<String, dynamic>>>(
        source: 'DataExportService.$table',
        table: table,
        op: 'SELECT',
        request: {filterColumn: userId, 'export': true},
        call: () =>
            _db.from(table).select().eq(filterColumn, userId),
      );
    } catch (e) {
      return [
        {'_export_error': e.toString()}
      ];
    }
  }

  /// Partnerships tablosu özel: user_id_1 VEYA user_id_2 eşleşmeli.
  Future<List<Map<String, dynamic>>> _fetchPartnerships(String userId) async {
    try {
      return await _log.log<List<Map<String, dynamic>>>(
        source: 'DataExportService.partnerships',
        table: 'partnerships',
        op: 'SELECT',
        request: {'user': userId, 'export': true},
        call: () => _db
            .from('partnerships')
            .select()
            .or('user_id_1.eq.$userId,user_id_2.eq.$userId'),
      );
    } catch (e) {
      return [
        {'_export_error': e.toString()}
      ];
    }
  }
}
