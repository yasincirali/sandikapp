import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Supabase 30 Ekim 2026: `public`'te yeni tabloya/görünüme otomatik GRANT
/// yok (0161). Bu kilit, izni unutulan tablonun canlıda "permission denied"
/// ile ilk kez görülmesini önler: 0161'den SONRAKİ her migration, yarattığı
/// her `public` tablosu/görünümü için aynı dosyada açık GRANT yazar ve
/// tabloda RLS'i açar. 0161 ve öncesi otomatik izinle yaratıldı; 0000'daki
/// taze-yığın bloğu o izinleri geri kurar, bu yüzden onlar muaf.
void main() {
  const sonOtomatik = 161;
  final dosyalar = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  int no(File f) =>
      int.parse(RegExp(r'(\d{4})_').firstMatch(f.uri.pathSegments.last)![1]!);

  // Yorumlar atılmış, boşluklar tekleştirilmiş, küçük harf gövde.
  String govde(File f) => f
      .readAsStringSync()
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((s) => s.replaceFirst(RegExp(r'--.*$'), ''))
      .join('\n')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('"', '')
      .toLowerCase();

  test('kilit izinsiz tabloyu yakalar, izinliyi geçirir', () {
    expect(eksikIzinler('x.sql', 'create table public.a (id int);'),
        hasLength(2));
    expect(
      eksikIzinler(
        'x.sql',
        'create table if not exists public.a (id int); '
            'alter table public.a enable row level security; '
            'grant select on table public.a to authenticated;',
      ),
      isEmpty,
    );
    expect(eksikIzinler('x.sql', 'create view public.v as select 1;'),
        ['x.sql: v için GRANT yok']);
    expect(eksikIzinler('x.sql', 'create table cron.j (id int);'), isEmpty);
  });

  test('0161 sonrası her yeni public tablo/görünüm açık GRANT taşır', () {
    final eksik = [
      for (final f in dosyalar.where((f) => no(f) > sonOtomatik))
        ...eksikIzinler(f.uri.pathSegments.last, govde(f)),
    ];
    expect(
      eksik,
      isEmpty,
      reason: 'Yeni tabloyu yaratan migration, hangi rolün ne yapacağını '
          'açıkça yazar (CLAUDE.md "Sunucu"; örnek 0145/0147):\n'
          '  revoke all on table public.x from public, anon, authenticated;\n'
          '  grant select on table public.x to authenticated;      -- istemci okuyorsa\n'
          '  grant select, insert, update, delete on table public.x to service_role;\n'
          'serial/bigserial kolon varsa dizi için de: '
          'grant usage, select on sequence public.x_id_seq to <yazan rol>;',
    );
  });

  test('taze yığın canlıyla aynı izinlere çıkar (0000 + 0161 birlikte)', () {
    final taban = govde(dosyalar.firstWhere((f) => no(f) == 0));
    // Yalnız taze yığında: canlıda otomatik izni geri açmamalı.
    expect(taban, contains("if to_regclass('public.profiles') is null then"));
    for (final nesne in ['tables', 'sequences', 'functions']) {
      expect(
        taban,
        contains(' on $nesne to anon, authenticated, service_role'),
        reason: '0000 taze yığında eski $nesne varsayılanını geri kurmalı',
      );
    }
    final kapanis = govde(dosyalar.firstWhere((f) => no(f) == sonOtomatik));
    expect(
      kapanis,
      contains('revoke select, insert, update, delete on tables '
          'from anon, authenticated, service_role'),
    );
    expect(
      kapanis,
      contains('revoke usage, select on sequences '
          'from anon, authenticated, service_role'),
    );
    // Fonksiyon varsayılanı canlıda açık; 0161 onu kapatmaz.
    expect(kapanis, isNot(contains('on functions')));
  });
}

final _yaratma = RegExp(
  r'create (?:or replace )?(table|view|materialized view) '
  r'(?:if not exists )?(?:([a-z_][a-z0-9_]*)\.)?([a-z_][a-z0-9_]*)\b',
);

/// `govde`: yorumsuz, tek boşluklu, küçük harf SQL.
List<String> eksikIzinler(String dosya, String govde) {
  final eksik = <String>[];
  for (final m in _yaratma.allMatches(govde)) {
    final tur = m[1]!;
    final sema = m[2];
    final ad = m[3]!;
    // public dışı şema (cron, vault, private…) Data API'ye açılmaz.
    if (sema != null && sema != 'public') continue;
    final grant = RegExp(
      r'grant [a-z, ]+ on (?:table )?(?:public\.)?' + ad + r'\b[^;]* to ',
    );
    if (!grant.hasMatch(govde)) eksik.add('$dosya: $ad için GRANT yok');
    if (tur == 'table' &&
        !RegExp(r'alter table (?:if exists )?(?:only )?(?:public\.)?' +
                ad +
                r' enable row level security')
            .hasMatch(govde)) {
      eksik.add('$dosya: $ad için RLS açılmamış');
    }
  }
  return eksik;
}
