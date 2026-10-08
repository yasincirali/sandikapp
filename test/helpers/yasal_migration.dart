import 'dart:io';

/// Migration'lardaki `yasal_metinler` INSERT'lerinin bir satırı.
class MigrationMetni {
  const MigrationMetni({
    required this.dosya,
    required this.tur,
    required this.surum,
    required this.dil,
    required this.hash,
    required this.govde,
  });

  final String dosya;
  final String tur;
  final String surum;
  final String dil;

  /// INSERT'e yazılmış hash literal'i.
  final String hash;

  /// Dollar-quoted gövde (CRLF → LF; sunucu da `chr(13)`'ü atar).
  final String govde;

  String get anahtar => '$tur/$surum/$dil';
}

String _sql(String s) => s.replaceAll("''", "'");

/// Biçim `YasalMetin.sqlInsert` ile aynı — biri değişirse öteki de.
final _insert = RegExp(
  r"values \('((?:[^']|'')*)', '((?:[^']|'')*)', '((?:[^']|'')*)', "
  r"'(?:[^']|'')*', (?:null|date '[0-9-]+'),\s*"
  r"'([0-9a-f]{64})',\s*"
  r"replace\(\$yasal\$(.*?)\$yasal\$, chr\(13\), ''\)\)",
  dotAll: true,
);

/// Tüm migration dosyalarını ad sırasıyla okur (satır sonu normalize).
List<(String, String)> migrationDosyalari(
    [String dizin = 'supabase/migrations']) {
  final dosyalar = Directory(dizin)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in dosyalar)
      (
        f.uri.pathSegments.last,
        f.readAsStringSync().replaceAll('\r\n', '\n'),
      ),
  ];
}

/// Migration'lardaki bütün yasal metin satırları, dosya sırasıyla.
List<MigrationMetni> migrationMetinleri(
    [String dizin = 'supabase/migrations']) {
  return [
    for (final (ad, metin) in migrationDosyalari(dizin))
      for (final m in _insert.allMatches(metin))
        MigrationMetni(
          dosya: ad,
          tur: _sql(m[1]!),
          surum: _sql(m[2]!),
          dil: _sql(m[3]!),
          hash: m[4]!,
          govde: m[5]!.replaceAll('\r', ''),
        ),
  ];
}

/// `yasal_metinler_tur_check`'in EN SON tanımındaki tür listesi; yoksa null.
List<String>? turCheckListesi([String dizin = 'supabase/migrations']) {
  final desen = RegExp(
    r"constraint yasal_metinler_tur_check\s+check \(tur in \(([^)]*)\)\)",
  );
  List<String>? son;
  for (final (_, metin) in migrationDosyalari(dizin)) {
    for (final m in desen.allMatches(metin)) {
      son = [
        for (final t in RegExp(r"'([a-z_]+)'").allMatches(m[1]!)) t[1]!,
      ];
    }
  }
  return son;
}
