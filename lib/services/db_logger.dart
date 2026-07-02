import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Her Supabase / DB isteğini loglar.
/// SDK kaynağı, tablo/endpoint, metot, request/response payload ve süreler
/// hem debug konsoluna hem de Supabase'deki `db_logs` tablosuna yazılır.
///
/// Sonsuz döngü koruması: `db_logs` tablosuna yapılan INSERT doğrudan
/// Supabase client üzerinden geçer, `log()` wrapper'ını çağırmaz.
class DbLogger {
  static final DbLogger instance = DbLogger._();
  DbLogger._();

  static const String _sdk = 'supabase_flutter';

  /// Tüm Supabase çağrıları için varsayılan timeout.
  /// Zayıf bağlantıda sonsuz spin yerine TimeoutException ile düşer.
  static const Duration defaultTimeout = Duration(seconds: 15);

  SupabaseClient get _client => Supabase.instance.client;

  /// Tek giriş noktası — her DB çağrısı bu wrapper üzerinden geçer.
  ///
  /// [source]   : hangi servis/metot çağırdı  (ör. "SupabaseService.getProfile")
  /// [table]    : Supabase tablosu veya Edge Function path
  /// [op]       : SELECT / INSERT / UPDATE / DELETE / UPSERT / RPC / FUNCTION
  /// [request]  : gönderilen filtreler veya body (hassas alan varsa maskelenir)
  /// [call]     : asıl Supabase işlemini yapan async lambda
  /// [timeout]  : opsiyonel override (uzun işlemler için)
  Future<T> log<T>({
    required String source,
    required String table,
    required String op,
    required Map<String, dynamic> request,
    required Future<T> Function() call,
    Duration? timeout,
  }) async {
    final requestedAt = DateTime.now();
    Object? error;
    late T result;

    try {
      result = await call().timeout(timeout ?? defaultTimeout);
      return result;
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      final respondedAt = DateTime.now();
      final durationMs = respondedAt.difference(requestedAt).inMilliseconds;
      final isError = error != null;

      final responseSummary = isError
          ? {'error': _sanitizeMessage(error.toString())}
          : _summarize(isError ? null : result);

      _printDebug(
        source: source,
        table: table,
        op: op,
        request: request,
        response: responseSummary,
        requestedAt: requestedAt,
        respondedAt: respondedAt,
        durationMs: durationMs,
        isError: isError,
      );

      // Supabase'e yaz — hata olursa sessizce geç (sonsuz döngü riski yok)
      _persistAsync(
        source: source,
        table: table,
        op: op,
        request: request,
        response: responseSummary,
        requestedAt: requestedAt,
        durationMs: durationMs,
        isError: isError,
      );
    }
  }

  // ── Supabase persist ───────────────────────────────────────────────────────

  void _persistAsync({
    required String source,
    required String table,
    required String op,
    required Map<String, dynamic> request,
    required Map<String, dynamic> response,
    required DateTime requestedAt,
    required int durationMs,
    required bool isError,
  }) {
    // Production'da DB log yazma kapalı (KVKK/PII riski).
    // Sadece hatalar persist edilir; başarılı çağrılar sessiz geçer.
    if (kReleaseMode && !isError) return;

    Future(() async {
      try {
        final uid = _client.auth.currentUser?.id;
        await _client.from('db_logs').insert({
          if (uid != null) 'user_id': uid,
          'ts': requestedAt.toUtc().toIso8601String(),
          'sdk': _sdk,
          'source': source,
          'table_name': table,
          'op': op,
          'request_json': _maskSensitive(request),
          'response_json': response,
          'duration_ms': durationMs,
          'is_error': isError,
        });
      } catch (e) {
        debugPrint('DbLogger persist error: $e');
      }
    });
  }

  /// Hata mesajından PII'yi (email, UUID, JWT, IP) sök.
  /// A5 fix: response_json içinde Supabase hata mesajları kullanıcı verisi
  /// ifşa edebiliyordu.
  static final _emailRx = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
  );
  static final _uuidRx = RegExp(
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
  );
  static final _jwtRx = RegExp(r'\beyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\b');
  static final _bearerRx = RegExp(r'Bearer\s+[A-Za-z0-9._\-]+', caseSensitive: false);
  static final _ipv4Rx = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');

  String _sanitizeMessage(String input) => sanitize(input);

  /// PII regex maskesi — Crashlytics gibi harici servislerden önce çağır.
  static String sanitize(String input) {
    var out = input;
    if (out.length > 500) out = '${out.substring(0, 500)}…';
    out = out.replaceAll(_jwtRx, '***JWT***');
    out = out.replaceAll(_bearerRx, 'Bearer ***');
    out = out.replaceAll(_emailRx, '***@***');
    out = out.replaceAll(_uuidRx, '***UUID***');
    out = out.replaceAll(_ipv4Rx, '***.***.***.***');
    return out;
  }

  /// KVKK kapsamındaki kişisel verileri loglamadan önce maskele.
  static const _sensitiveKeys = {
    'email', 'password', 'token', 'access_token', 'refresh_token',
    'apikey', 'api_key', 'authorization', 'phone', 'tc', 'tcno',
    'display_name', 'displayName',
  };

  Map<String, dynamic> _maskSensitive(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((k, v) {
      if (_sensitiveKeys.contains(k.toLowerCase())) {
        out[k] = '***';
      } else if (v is Map<String, dynamic>) {
        out[k] = _maskSensitive(v);
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _summarize(dynamic value) {
    if (value == null) return {'result': 'null'};
    if (value is List) return {'rows': value.length};
    if (value is Map) return {'keys': value.keys.toList()};
    if (value is String) {
      return {'result': value.length > 80 ? '${value.substring(0, 80)}…' : value};
    }
    if (value is bool || value is int || value is double) return {'result': value};
    return {'type': value.runtimeType.toString()};
  }

  void _printDebug({
    required String source,
    required String table,
    required String op,
    required Map<String, dynamic> request,
    required Map<String, dynamic> response,
    required DateTime requestedAt,
    required DateTime respondedAt,
    required int durationMs,
    required bool isError,
  }) {
    if (!kDebugMode) return;

    final tag = isError ? '🔴 DB ERR' : '🟢 DB    ';
    debugPrint(
      '$tag  [${requestedAt.toIso8601String()}]  ${durationMs}ms\n'
      '  sdk      : $_sdk\n'
      '  source   : $source\n'
      '  table    : $table\n'
      '  op       : $op\n'
      '  request  : $request\n'
      '  response : $response\n'
      '  end      : ${respondedAt.toIso8601String()}',
    );
  }
}
