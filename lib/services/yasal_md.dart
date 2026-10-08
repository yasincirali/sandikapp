import '../models/legal_block.dart';

/// `legal/*.md` → uygulama içi yasal belge (kullanıcı kararı 2026-10-04:
/// "Webdekiyle de her zaman eşleyelim").
///
/// Saf fonksiyonlar; Flutter'a bağlı değil. Web aynı md'yi
/// `docs/_build_legal.py` ile (python-markdown) HTML'e çevirir; burada
/// yalnız uygulamanın çizdiği blok türleri üretilir (başlık, paragraf,
/// tablo, meta kutusu, ayraç). Satır içi işaretler (`**kalın**`, `` `kod` ``,
/// `*italik*`) düz metne iner: uygulama gövdeyi tek stille çizer, metnin
/// kendisi değişmez.
///
/// Eşleme kuralları (web'in görünümüne sadık, uygulamanın dokunuşlarıyla):
/// - `#` → h1, `##` → h2, `###` ve altı → h3.
/// - `---` → ayraç. (python-markdown'da hemen üstünde metin olan `---` bir
///   başlık olurdu; `yasal_web_esleme_test` md'de öyle bir satır olmadığını
///   kilitler.)
/// - `| … |` satırları → tablo; ikinci satır ayraçtır, atlanır.
/// - `> …` → meta kutusu.
/// - Her satırı künye satırı (`**Sürüm:** 1.2`, `**Yürürlük tarihi:** …`)
///   olan paragraf ve baştan sona `*italik*` paragraf → meta kutusu
///   (uygulamadaki eski "Yürürlük tarihi · Sürüm" ve dipnot kutusu).
/// - Liste maddesi `- x` → `· x`; numaralı maddeler olduğu gibi. Paragraf
///   içi satır sonları korunur (web onları boşluğa çevirir; telefonda
///   madde madde okunur — metin aynı).

/// Kanonik metin: BOM yok, satır sonu LF, sondaki boşluk kırpılmış.
/// `docs/_build_legal.py` → `kanonik()` ile BİREBİR; değişirse bütün belge
/// hash'leri değişir (yeni sürüm demektir).
String yasalMdKanonik(String md) {
  var s = md;
  while (s.startsWith('\uFEFF')) {
    s = s.substring(1);
  }
  return s.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimRight();
}

final _baslik = RegExp(r'^(#{1,6})\s+(.*?)\s*#*$');
final _ayrac = RegExp(r'^(?:-{3,}|\*{3,}|_{3,})$');
final _tabloAyrac = RegExp(r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?$');

/// Belge künyesi satırları. Yalnız bu anahtarlar meta kutusuna gider:
/// "**İstisnalar:** …" gibi kalın etiketli tek satırlık paragraf gövde
/// metnidir, künye değil.
const _kunyeAnahtarlari = {
  'Yürürlük tarihi', 'Son güncelleme', 'Sürüm', 'Onay sürümü', 'Tarih', //
  'IP', 'Platform', //
  'Effective date', 'Last updated', 'Version', 'Consent version', 'Source',
};
final _anahtarDeger = RegExp(r'^\*\*([^*]+):\*\*');
bool _kunyeSatiri(String s) =>
    _kunyeAnahtarlari.contains(_anahtarDeger.firstMatch(s.trim())?[1]);
final _madde = RegExp(r'^[-*+]\s+');

String _satirIci(String s) => s
    .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m[1]!)
    .replaceAllMapped(
        RegExp(r'(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])'), (m) => m[1]!)
    .replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)'), (m) => '${m[1]} (${m[2]})')
    .replaceAll(r'\|', '|')
    .trim();

List<String> _hucreler(String satir) {
  var s = satir.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|') && !s.endsWith(r'\|')) s = s.substring(0, s.length - 1);
  return [for (final c in s.split(RegExp(r'(?<!\\)\|'))) _satirIci(c)];
}

LegalBlock _paragraf(List<String> satirlar) {
  if (satirlar.every(_kunyeSatiri)) {
    return LegalBlock.meta(satirlar.map(_satirIci).join('\n'));
  }
  final butun = satirlar.join('\n').trim();
  if (butun.length > 2 &&
      butun.startsWith('*') &&
      !butun.startsWith('**') &&
      butun.endsWith('*') &&
      !butun.endsWith('**')) {
    return LegalBlock.meta(_satirIci(butun.substring(1, butun.length - 1)));
  }
  return LegalBlock.p([
    for (final s in satirlar)
      _madde.hasMatch(s.trim())
          ? '· ${_satirIci(s.trim().replaceFirst(_madde, ''))}'
          : _satirIci(s),
  ].join('\n'));
}

/// md → bloklar. Yer tutucular (`{SUPABASE_ULKE}`) olduğu gibi kalır;
/// doldurma gösterimde (`LegalDocs.bloklar`).
List<LegalBlock> yasalMdBloklari(String md) {
  final satirlar = yasalMdKanonik(md).split('\n');
  final cikti = <LegalBlock>[];
  final paragraf = <String>[];
  void bosalt() {
    if (paragraf.isEmpty) return;
    cikti.add(_paragraf(paragraf));
    paragraf.clear();
  }

  var i = 0;
  while (i < satirlar.length) {
    final t = satirlar[i].trim();
    if (t.isEmpty) {
      bosalt();
      i++;
      continue;
    }
    final b = _baslik.firstMatch(t);
    if (b != null) {
      bosalt();
      final metin = _satirIci(b[2]!);
      cikti.add(switch (b[1]!.length) {
        1 => LegalBlock.h1(metin),
        2 => LegalBlock.h2(metin),
        _ => LegalBlock.h3(metin),
      });
      i++;
      continue;
    }
    if (_ayrac.hasMatch(t)) {
      bosalt();
      cikti.add(const LegalBlock.divider());
      i++;
      continue;
    }
    if (t.startsWith('|')) {
      bosalt();
      final tablo = <String>[];
      while (i < satirlar.length && satirlar[i].trim().startsWith('|')) {
        tablo.add(satirlar[i].trim());
        i++;
      }
      cikti.add(LegalBlock.tableHeader(_hucreler(tablo.first)));
      for (final satir in tablo.skip(1)) {
        if (_tabloAyrac.hasMatch(satir)) continue;
        cikti.add(LegalBlock.tableRow(_hucreler(satir)));
      }
      continue;
    }
    if (t.startsWith('>')) {
      bosalt();
      final alinti = <String>[];
      while (i < satirlar.length && satirlar[i].trim().startsWith('>')) {
        alinti.add(satirlar[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
        i++;
      }
      cikti.add(LegalBlock.meta(alinti.map(_satirIci).join('\n')));
      continue;
    }
    paragraf.add(satirlar[i]);
    i++;
  }
  bosalt();
  return cikti;
}

/// İlk h1, " — sandık" eki olmadan ("Kullanım Koşulları").
String yasalMdBaslik(String md) {
  for (final b in yasalMdBloklari(md)) {
    if (b.type == LegalBlockType.h1) {
      // \u2014 = uzun tire; kaynakta harfi yazılmaz (uzun_tire_yok_test).
      return b.text.replaceFirst(RegExp(r'\s+\u2014\s+sandık$'), '');
    }
  }
  throw StateError('yasal md: h1 yok');
}

/// `**[etiket]:** değer` satırlarının değerleri, sırasıyla (ör. etiket
/// `Sürüm` → ["1.2", "1.2"]; açık rıza metninde iki kez yazar).
List<String> yasalMdAlan(String md, String etiket) => [
      for (final m in RegExp(
        '^\\*\\*${RegExp.escape(etiket)}:\\*\\*[ \\t]*(.+?)[ \\t]*\$',
        multiLine: true,
      ).allMatches(yasalMdKanonik(md)))
        m[1]!,
    ];

/// "Sürüm" satırı. Belgede birden çok kez yazıyorsa hepsi aynı olmalı.
String yasalMdSurum(String md, {String etiket = 'Sürüm'}) {
  final hepsi = yasalMdAlan(md, etiket).toSet();
  if (hepsi.length != 1) {
    throw StateError('yasal md: "$etiket" satırı tek değer değil: $hepsi');
  }
  return hepsi.single;
}

/// "Onay sürümü" satırı: kullanıcının onaylamış olması gereken EN ESKİ
/// sürüm (son esaslı değişiklik). Satır yoksa [yasalMdSurum] — her sürüm
/// artışı yeniden sorar (eski davranış).
///
/// Kullanıcı kararı (2026-10-08): *"her geliştirmeden neden kvkk değişiyor
/// generic bişey yapmaz mıyız"*. Metin her değiştiğinde sürüm artar (web,
/// uygulama ve veritabanı aynı sayıyı taşır, hash ispatı buna bağlı), ama
/// kişisel veri işleyişini değiştirmeyen bir düzeltme herkese yeniden onay
/// kapısı açmamalı. Esaslı değişiklikte (yeni kişisel veri, yeni alıcı,
/// yeni amaç ya da saklama) "Onay sürümü" = "Sürüm" yazılır; yazım ya da
/// kişisel veri içermeyen değişiklikte yalnız "Sürüm" artar.
String yasalMdOnaySurumu(String md) {
  final alan = yasalMdAlan(md, 'Onay sürümü').toSet();
  if (alan.isEmpty) return yasalMdSurum(md);
  if (alan.length != 1) {
    throw StateError('yasal md: "Onay sürümü" satırı tek değer değil: $alan');
  }
  return alan.single;
}

const _aylar = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', //
  'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

/// "Yürürlük tarihi: 4 Ekim 2026" → `2026-10-04`; satır yoksa null (tarih
/// uydurulmaz).
String? yasalMdYururluk(String md) {
  final alan = yasalMdAlan(md, 'Yürürlük tarihi');
  if (alan.isEmpty) return null;
  final m = RegExp(r'^(\d{1,2}) (\S+) (\d{4})$').firstMatch(alan.first);
  final ay = m == null ? -1 : _aylar.indexOf(m[2]!);
  if (m == null || ay < 0) {
    throw StateError('yasal md: yürürlük tarihi okunamadı: ${alan.first}');
  }
  String iki(int n) => n.toString().padLeft(2, '0');
  return '${m[3]}-${iki(ay + 1)}-${iki(int.parse(m[1]!))}';
}

/// Metindeki yer tutucuların adları (`{SUPABASE_ULKE}` → `SUPABASE_ULKE`).
Set<String> yasalMdYerTutuculari(String metin) => {
      for (final m in RegExp(r'\{([A-Z][A-Z0-9_]*)\}').allMatches(metin)) m[1]!,
    };
