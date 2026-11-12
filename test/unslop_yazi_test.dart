import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// unslop kararları (yasin 5 Kas 2026, "tüm işleri yap"): bölüm başlıkları
/// ve etiketler cümle düzeninde, ağırlık tavanı w600, tur rozetleri sade.
/// Kilit, geri dönüşü yakalar.
void main() {
  test('w800/w900 yalnız oyun sahnelerinde ve toplam kartında', () {
    const istisna = {
      'lib/widgets/yaris_sahnesi.dart',
      'lib/widgets/duello_arenasi.dart',
      'lib/widgets/leaderboard_hero_card.dart',
      'lib/widgets/portfolio_summary_widget.dart',
    };
    final ihlal = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final yol = f.path.replaceAll('\\', '/');
      if (istisna.contains(yol) || yol.contains('/generated/')) continue;
      final k = f.readAsStringSync();
      if (k.contains('FontWeight.w800')) ihlal.add(yol);
    }
    expect(ihlal, isEmpty, reason: 'w800 geri geldi: $ihlal');
  });

  test('.arb metinleri BÜYÜK HARF değil (kısaltmalar hariç)', () {
    final tr = jsonDecode(File('lib/l10n/app_tr.arb').readAsStringSync())
        as Map<String, dynamic>;
    const kisaltma = {
      'BIST 100',
      'BIST',
      'ABD',
      'BES',
      'TÜFE',
      'TÜİK TÜFE',
      'PDF',
      'JSON'
    };
    final buyuk = <String>[];
    tr.forEach((k, v) {
      if (k.startsWith('@') || v is! String || kisaltma.contains(v)) return;
      final harf = v
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .split('')
          .where((c) => c.toLowerCase() != c.toUpperCase())
          .toList();
      if (harf.length >= 3 && harf.every((c) => c == c.toUpperCase())) {
        buyuk.add('$k: $v');
      }
    });
    // TEFAS · {tarih} ve OHLC kısaltma satırı bilinçli.
    buyuk.removeWhere(
        (s) => s.startsWith('xrKaynakTefas') || s.startsWith('chartOhlcLine'));
    expect(buyuk, isEmpty, reason: 'büyük harf metin: $buyuk');
  });

  // Baş Harfi Büyük etiket ratchet'i (Ar-Ge 2026-11-07 #4). Yukarıdaki
  // kilit yalnız TAMAMI BÜYÜK metni yakalıyordu; "Giriş Yap", "Varlık
  // Ekle", "Fiyat Alarmları" gibi etiketler kalmıştı ve ekranlar arasında
  // karışık görünüyordu. 63 etiket cümle düzenine geçti; sayı yalnız
  // azalabilir (şu an 0). İngilizce .arb'a dokunulmaz: Title Case orada
  // doğal.
  //
  // Kural: en çok 5 kelimelik (etiket boyu) değerde, bir parçanın
  // (·:.!?,› ile ayrılır) ilk kelimesinden sonraki bir kelime büyük harfle
  // başlıyorsa — kısaltma (BIST, TL, tek harf), özel ad ve belge adı hariç.
  test('Baş Harfi Büyük etiket sayısı yalnız azalabilir', () {
    // Özel adlar, markalar, belge ve kurum adları: büyük harfle kalır.
    const ozelIfade = [
      'Sandık Premium',
      'Fon X-Ray',
      'Portföy X-Ray',
      'X-Ray',
      'Kullanım Koşulları',
      'Gizlilik Politikası',
      'KVKK Aydınlatma Metni',
      'KVKK Metni',
      'Açık Rıza Metni',
      'Yatırım Uyarısı',
      'Yatırım Tavsiyesi Reddi',
      // Yasal metin başlıkları: `tekOnayBaslik` onay metninin hash'ine girer
      // (`yasal_metin_katalogu`), değişirse kayıtlı onaylar eşleşmez;
      // "Yasal Uyarı" katalogdaki belgenin adı.
      'Yasal Koşullar',
      'Yasal Uyarı',
      // Özelliğin adı; yasal metinler de bu adla anar.
      'Zirvedeki Portföyler',
      'Borsa İstanbul',
      'Ziraat Bankası',
      'Garanti BBVA',
      'Anadolu Hayat',
      'Petrol (Brent)',
      'Yahoo Finance',
      'KAP Portföy Dağılım Raporu',
      'Pine Script',
      'Para Politikası Kurulu',
      'App Store',
      'Google Play',
    ];
    // Tek kelimelik özel adlar; "Ayarlar" uygulamadaki ekranın adı
    // ("Ayarlar › Görünüm" yol tarifi).
    const ozelKelime = {
      'Premium',
      'Excel',
      'Türkçedir',
      'Sandık',
      'Enpara',
      'Pine',
      'Ayarlar',
      'Apple',
      'Google',
      // Kurum adı (Diyanet İşleri Başkanlığı; zekât hesabı, 2026-11-12).
      'Diyanet',
    };
    const tavan = 0;
    final harf = RegExp(r'[^\W\d_]', unicode: true);
    final tr = jsonDecode(File('lib/l10n/app_tr.arb').readAsStringSync())
        as Map<String, dynamic>;
    final ihlal = <String>[];
    tr.forEach((k, v) {
      if (k.startsWith('@') || v is! String) return;
      var t = v.replaceAll(RegExp(r'\{[^}]*\}'), ' ');
      for (final p in ozelIfade) {
        t = t.replaceAll(p, ' ');
      }
      final kelimeler =
          t.split(RegExp(r'\s+')).where((w) => harf.hasMatch(w)).toList();
      if (kelimeler.length > 5) return;
      for (final parca in t.split(RegExp(r'[·:.!?,›]'))) {
        final ws = parca
            .split(RegExp(r'[\s/&+\-–—]+'))
            // Yalnız baştaki/sondaki tırnak ve parantez: iç kesme işareti
            // ("Premium'da") kökü ayırmak için aşağıda kullanılır.
            .map((w) => w.replaceAll(
                RegExp('^["\'“”‘’(«]+|["\'“”‘’)»]+\$'), ''))
            .where((w) => harf.hasMatch(w))
            .toList();
        final buyukBaslayan = ws.skip(1).where((w) {
          final kok = w.split(RegExp("['’]")).first;
          if (kok.isEmpty) return false;
          final ilk = kok.substring(0, 1);
          if (ilk.toLowerCase() == ilk) return false;
          if (kok.toUpperCase() == kok) return false; // kısaltma, tek harf
          return !ozelKelime.contains(kok);
        });
        if (buyukBaslayan.isNotEmpty) {
          ihlal.add('$k: $v');
          break;
        }
      }
    });
    expect(ihlal.length, lessThanOrEqualTo(tavan),
        reason: 'Baş Harfi Büyük etiket (cümle düzenine çevir ya da özel '
            'adsa listeye ekle): $ihlal');
  });

  // Ağırlık tavanı w600 kararı (yasin 2026-11-05) yeni kodda uygulanıyor
  // ama lib/'de yüzlerce eski w700 duruyor; hepsini tek seferde çevirmek
  // tutar/rakam vurgularını da düzleştirirdi (onlar bilerek kalın). Bu
  // yüzden toptan değişiklik yerine cırcır: sayı yalnız AZALABİLİR, etiket
  // ve başlık çevrildikçe tavan düşürülür (2026-11-08: Ayarlar ve Sinyal
  // ayarları satır/başlık etiketleri w600'e indi, 307 → 292; 2026-11-10:
  // sözleşme tarih alanının tarihi, 292 → 291; işlem notu Kaydet, 291 → 290;
  // 2026-11-11: numSmall token'ı + Portföy ve varlık sayfasındaki ham w700'ler
  // w600'e, Yarış/Zirve'de token yerine açık w700 (istisna korunur), 290 → 269;
  // 2026-11-12: temettü tahmini satır tutarı, 269 → 268; Takip ve
  // Hareketler ekranlarının ham w700'leri w600'e, 268 → 254).
  // 2026-11-12: Varlık Ekle ve seçici sayfaları (tür ızgarası, tutar alanları,
  // seçici sayfaları, sözleşme seçicileri, başlık) w600'e, 268 → 240; ikisi birlikte 226).
  // w800/w900 sayılmaz: yarış/düello sahneleri ve ana sayfa toplam kartı
  // istisnası yukarıdaki testte ayrıca kilitli. Tüm lib/ dizini tarandığı
  // için part dosyaları zaten dahil (`ekranKaynagiSync` tek ekran içindir).
  test('FontWeight.w700 sayısı artmaz (cırcır)', () {
    const tavan = 226;
    var sayi = 0;
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final yol = f.path.replaceAll('\\', '/');
      if (yol.contains('lib/l10n/generated/')) continue;
      sayi += 'FontWeight.w700'.allMatches(f.readAsStringSync()).length;
    }
    expect(sayi, lessThanOrEqualTo(tavan),
        reason: 'Yeni w700 eklendi ($sayi > $tavan). Etiket/başlık için '
            'w600 kullan; tutar vurgusuysa mevcut stili yeniden kullan.');
    if (sayi < tavan) {
      // ignore: avoid_print
      print('w700 sayısı $sayi; tavanı $tavan → $sayi düşür.');
    }
  });

  test('bölüm başlığı w600, harf aralıksız', () {
    final k = File('lib/theme/sandik.dart').readAsStringSync();
    final bas = k.indexOf('class SandikSectionHeader');
    final govde = k.substring(bas, k.indexOf('class ', bas + 10));
    expect(govde, isNot(contains('letterSpacing')));
    expect(govde, contains('FontWeight.w600'));
  });

  test('turda "YENİ" rozeti ve parıltı yok', () {
    final k = File('lib/screens/onboarding_screen.dart').readAsStringSync();
    expect(k, isNot(contains("rozet: 'YENİ'")));
    final bas = k.indexOf('class _Rozet');
    final govde = k.substring(bas);
    expect(govde.substring(0, govde.indexOf('\n}\n')),
        isNot(anyOf(contains('auto_awesome'), contains('Gradient'))));
  });
}
