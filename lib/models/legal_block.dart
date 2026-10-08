/// Yasal belgenin bir bloğu — `LegalDocScreen` çizer, `legal/tr/*.md`
/// ayrıştırıcısı (`yasal_md.dart`) üretir.
///
/// 2026-10-04'e kadar bu model `legal_doc_screen.dart` içindeydi ve
/// belgeler elle yazılmış `const` listelerdi. Belgeler artık md'den
/// ayrıştırıldığı için model bir servisin de kullandığı yere taşındı
/// (servis → ekran bağımlılığı kalmasın); ekran dosyası bunu yeniden
/// dışa aktarır, eski importlar çalışır.
library;

enum LegalBlockType {
  h1,
  h2,
  h3,
  paragraph,
  tableRow,
  tableHeader,
  divider,
  meta
}

class LegalBlock {
  final LegalBlockType type;
  final String text;
  final List<String> cells;

  const LegalBlock.p(this.text)
      : type = LegalBlockType.paragraph,
        cells = const [];
  const LegalBlock.h1(this.text)
      : type = LegalBlockType.h1,
        cells = const [];
  const LegalBlock.h2(this.text)
      : type = LegalBlockType.h2,
        cells = const [];
  const LegalBlock.h3(this.text)
      : type = LegalBlockType.h3,
        cells = const [];
  const LegalBlock.meta(this.text)
      : type = LegalBlockType.meta,
        cells = const [];
  const LegalBlock.divider()
      : type = LegalBlockType.divider,
        text = '',
        cells = const [];
  const LegalBlock.tableHeader(this.cells)
      : type = LegalBlockType.tableHeader,
        text = '';
  const LegalBlock.tableRow(this.cells)
      : type = LegalBlockType.tableRow,
        text = '';
  const LegalBlock._(this.type, this.text, this.cells);

  /// Yer tutucuları doldurulmuş kopya — `LegalDocs.bloklar`.
  LegalBlock doldur(String Function(String) f) =>
      LegalBlock._(type, f(text), [for (final c in cells) f(c)]);

  @override
  String toString() =>
      'LegalBlock(${type.name}, ${cells.isEmpty ? text : cells.join(' | ')})';
}
