import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// "Bir iş = bir kelime" kilidi (2026-11-11).
///
/// Vazgeçme düğmesi ~88 yerde "Vazgeç", ~6 yerde "İptal" diyordu; aynı iş
/// için iki kelime kullanıcıya iki ayrı iş gibi okunur. iOS'un Türkçe sistem
/// diyalogları da "Vazgeç" der. Aynı turda aynı düğme kelimesini taşıyan kopya
/// anahtarlar (`ozgKaydet`, `hsnKapat`, `iktKotaVazgec`…) ortak anahtara
/// birleşti; kopya anahtar bir gün birinin çevirisi kayınca iki düğmeyi
/// ayrıştırıyordu.
///
/// "İptal" kelimesinin ABONELİK İPTALİ anlamı ayrı bir iştir (mağazada
/// aboneliği sonlandırmak), düğme değildir; o yüzden yasak değil, aşağıdaki
/// izin listesinde gerekçesiyle durur.
void main() {
  Map<String, dynamic> arb(String dil) =>
      jsonDecode(File('lib/l10n/app_$dil.arb').readAsStringSync())
          as Map<String, dynamic>;

  /// Büyük harfli "İptal" geçebilen anahtarlar — gerekçesiyle. Yeni anahtar
  /// eklemek "bu bir düğme değil, abonelik iptali" demektir.
  const iptalIzinli = {
    'prmIptalIpucu': 'abonelik iptali ipucu (mağaza sayfası), düğme değil',
  };

  test('app_tr.arb: hiçbir metin vazgeçme anlamında "İptal" demez', () {
    final ihlal = <String>[
      for (final e in arb('tr').entries)
        if (!e.key.startsWith('@') &&
            e.value is String &&
            (e.value as String).contains('İptal') &&
            !iptalIzinli.containsKey(e.key))
          '${e.key}: ${e.value}',
    ];
    expect(ihlal, isEmpty,
        reason: 'Vazgeçme düğmesi "Vazgeç" der (context.l10n.cancel). '
            'Abonelik iptali gibi ayrı bir anlamsa iptalIzinli\'ye gerekçeyle ekle.');
  });

  /// Aynı düğme kelimesi tek anahtarda. Kelime → izinli anahtarlar.
  /// `dividendRecordAction`: TR "Kaydet" ama EN "Record" — temettüyü deftere
  /// işler, formu kaydetmez; İngilizcede ayrı fiil, birleşirse EN bozulur.
  /// `deleteAction`: kaydırma eylemi etiketi; bu turun kapsamı dışında kaldı,
  /// ortak `delete`'e birleşmesi ayrı iş.
  const tekAnahtar = {
    'Vazgeç': {'cancel'},
    'Kaydet': {'save', 'dividendRecordAction'},
    'Kapat': {'close'},
    'Sil': {'delete', 'deleteAction'},
    'Paylaş': {'shareWord'},
  };

  test('app_tr.arb: düğme kelimeleri kopya anahtar taşımaz', () {
    final sozluk = arb('tr');
    final ihlal = <String>[
      for (final e in sozluk.entries)
        if (!e.key.startsWith('@') &&
            tekAnahtar.containsKey(e.value) &&
            !tekAnahtar[e.value]!.contains(e.key))
          '${e.key}: ${e.value} → ortak anahtarı kullan '
              '(${tekAnahtar[e.value]!.first})',
    ];
    expect(ihlal, isEmpty);
  });

  test('ortak anahtarlar iki dilde de beklenen kelime', () {
    final tr = arb('tr'), en = arb('en');
    expect(tr['cancel'], 'Vazgeç');
    expect(en['cancel'], 'Cancel');
    expect(tr['save'], 'Kaydet');
    expect(tr['close'], 'Kapat');
    expect(tr['delete'], 'Sil');
    expect(tr['shareWord'], 'Paylaş');
  });

  test('lib/: ham "İptal" düğme literali yok', () {
    // Üretilmiş dosyalar dışarıda: l10n çıktısı arb'dan gelir (yukarıda
    // taranır), yasal belge metni legal/*.md'den gelir ve "İptal" orada
    // abonelik iptali başlığıdır.
    final dosyalar = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.dart') &&
            !f.path.endsWith('.g.dart') &&
            !f.path.contains('/l10n/generated/'));
    final literal = RegExp('[\'"]İptal[\'"]');
    final ihlal = <String>[];
    for (final f in dosyalar) {
      final satirlar = ekranKaynagiSync(f.path).split('\n');
      for (var i = 0; i < satirlar.length; i++) {
        final s = satirlar[i].trimLeft();
        // Yorumlar karar kaydıdır; eski düğme adını anmaları serbest.
        if (s.startsWith('//')) continue;
        if (literal.hasMatch(s)) ihlal.add('${f.path}:${i + 1}: $s');
      }
    }
    expect(ihlal, isEmpty,
        reason: 'Ham literal yerine context.l10n.cancel ("Vazgeç").');
  });

  test('Material diyaloglarının kendi düğmesi de "Vazgeç"', () {
    // Flutter'ın Türkçesi "İptal"; metnini vermeyen Material diyaloğu
    // (saat seçici vb.) onu gösterirdi. Ezme SenMaterialLocalizationTr'de.
    final k = File('lib/l10n/sen_material_localizations.dart')
        .readAsStringSync();
    expect(k, contains("String get cancelButtonLabel => 'Vazgeç';"));
  });
}
