import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0167 (zirve varlık ölçümleri 7 gün) sözleşmesi. Davranış yerel
/// Postgres 16'da denendi (3 ve 0 günlük satır kaldı, 30 ve 200 günlük
/// silindi; yarış ve getiri tabloları 365 günde). Burada metin düzeyinde
/// kilitlenenler: kısaltma yalnız `zirve_allocation_snapshots`'a, okuyucular
/// hâlâ 24 saatlik pencerede (7 gün ancak bu sayede güvenli), yeni cron yok.
void main() {
  final dizin = Directory('supabase/migrations');
  String oku(String ad) => File('${dizin.path}/$ad')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  String govde(String sql) => sql
      .split('\n')
      .where((s) => !s.trimLeft().startsWith('--'))
      .join('\n')
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();

  final g = govde(oku('0167_zirve_varlik_saklama_kisa.sql'));

  test('yalnız zirve varlık ölçümleri 7 güne iner', () {
    expect(
        g,
        contains("delete from public.zirve_allocation_snapshots "
            "where created_at < now() - interval '7 days'"));
    for (final t in [
      'user_roi_snapshots',
      'user_allocation_snapshots',
      'zirve_roi_snapshots',
    ]) {
      expect(
          g,
          contains("delete from public.$t "
              "where created_at < now() - interval '365 days'"),
          reason: t);
    }
  });

  test('yeni cron yok, fonksiyon istemciye kapalı, imza aynı', () {
    expect(g, isNot(contains('cron.schedule')));
    expect(g, contains('revoke all on function public.cleanup_leaderboard_snapshots() '
        'from public, anon, authenticated'));
    expect(g, contains('create or replace function public.cleanup_leaderboard_snapshots() returns void'));
  });

  test('zirve_allocation_snapshots okuyan her yer 24 saatlik pencerede', () {
    // 7 gün saklama, okuyucu 24 saatten eskiye bakmadığı için güvenli. Yeni
    // bir okuyucu daha uzun geçmiş isterse bu test kırılır ve saklama
    // yeniden düşünülür.
    final okuyucu = RegExp(
        r'from public\.zirve_allocation_snapshots (\w+) (.{0,400}?)(;|\)\s*select|order by)');
    var sayi = 0;
    for (final f in dizin.listSync().whereType<File>()) {
      final ad = f.uri.pathSegments.last;
      if (!ad.endsWith('.sql')) continue;
      final metin = govde(oku(ad));
      for (final m in okuyucu.allMatches(metin)) {
        // Silmeler (temizlik, rıza geri alma) ve migration doğrulama
        // blokları (`exists (select 1 from ...`) okuyucu değil.
        final once = metin.substring(0, m.start);
        if (once.endsWith('delete ') || once.endsWith('select 1 ')) continue;
        sayi++;
        expect(m.group(2), contains("created_at >= now() - interval '24 hours'"),
            reason: '$ad: ${m.group(0)}');
      }
    }
    expect(sayi, greaterThan(0));
  });
}
