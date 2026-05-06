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

  SupabaseClient get _client => Supabase.instance.client;

  /// Tek giriş noktası — her DB çağrısı bu wrapper üzerinden geçer.
  ///
  /// [source]   : hangi servis/metot çağırdı  (ör. "SupabaseService.getProfile")
  /// [table]    : Supabase tablosu veya Edge Function path
  /// [op]       : SELECT / INSERT / UPDATE / DELETE / UPSERT / RPC / FUNCTION
  /// [request]  : gönderilen filtreler veya body (hassas alan varsa maskelenir)
  /// [call]     : asıl Supabase işlemini yapan async lambda
  Future<T> log<T>({
    required String source,
    required String table,
    required String op,
    required Map<String, dynamic> request,
    required Future<T> Function() call,
  }) async {
    final requestedAt = DateTime.now();
    Object? error;
    late T result;

    try {
      result = await call();
      return result;
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      final respondedAt = DateTime.now();
      final durationMs = respondedAt.difference(requestedAt).inMilliseconds;
      final isError = error != null;

      final responseSummary = isError
          ? {'error': error.toString()}
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
    // fire-and-forget — await yok, hata loglamayı bloklamasın
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
          'request_json': request,
          'response_json': response,
          'duration_ms': durationMs,
          'is_error': isError,
        });
      } catch (e) {
        // Loglama altyapısı düşse de uygulamayı etkilemesin
        debugPrint('DbLogger persist error: $e');
      }
    });
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
