import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/legal_block.dart';
import 'package:portfoy_takip/services/disclaimer_service.dart';
import 'package:portfoy_takip/services/yasal_metin_katalogu.dart';
import 'package:portfoy_takip/services/yasal_onay_service.dart';

import 'helpers/yasal_migration.dart';

/// Yasal metin kayma kilidi (0102, 2026-10-04).
///
/// Kullanıcıya gösterilen yasal metin ile veritabanındaki (`yasal_metinler`)
/// metin AYNI olmalı; aksi hâlde onay kaydı yanlış bir metnin ispatı olur.
/// Ekrandaki metin değişip sürüm artırılmazsa burası kırılır.
void main() {
  final katalog = YasalMetinKatalogu.tumu();
  final migration = migrationMetinleri();
  final migrationda = {for (final m in migration) m.anahtar: m};

  // Süreç `yasal_metin_katalogu.dart` başındaki karar kaydında ("Metin
  // değişince ne yapılır"); mesaj onu adım adım söyler.
  const nasil =
      'Ne yapmalı (yasal_metin_katalogu.dart → "Metin değişince ne yapılır"): '
      '(1) metnin sürümünü artır — belgeler: legal/tr/<BELGE>.md künyesi '
      '("**Sürüm:**", "**Yürürlük tarihi:**", "**Son güncelleme:**"), '
      'çevirisi varsa legal/en/<BELGE>.md ("**Version:**", "**Source:** TR x") '
      've kapının "Neler değişti" notu yasalKapiDegisiklikNotu (iki .arb + '
      'flutter gen-l10n); kutular: YasalMetinKatalogu.kutuSurumu; Zirve: '
      'LeaderboardService.zirveRizaMetniSurumu, (2) belgelerde `python '
      'docs/_build_legal.py` (web HTML + lib/config/yasal_belge_kaynaklari.'
      'g.dart), (3) `flutter test --run-skipped --tags arac '
      'tool/yasal_metin_uret_test.dart` ile INSERT üret, (4) çıktıyı YENİ bir '
      'migration\'a koy (iki sunucuya birlikte). Eski satırı DEĞİŞTİRME — '
      'eski onaylar o metni gösteriyor; eski sürümü onaylayan kullanıcı '
      'yeniden onay kapısında yenisini görür.';

  test('katalogdaki her metin migration\'da aynı hash ile var', () {
    for (final k in katalog) {
      final m = migrationda[k.anahtar];
      expect(m, isNotNull,
          reason: '${k.anahtar} hiçbir migration\'da yok. $nasil');
      expect(m!.hash, k.hash,
          reason: '${k.anahtar} metni DEĞİŞMİŞ ama sürümü aynı '
              '(migration: ${m.dosya}). $nasil');
    }
  });

  test('migration gövdeleri kendi hash\'leriyle tutarlı', () {
    // Sunucu bunu check ile de zorlar; burada dağıtımdan önce yakalanır.
    expect(migration, isNotEmpty);
    for (final m in migration) {
      expect(sha256.convert(utf8.encode(m.govde)).toString(), m.hash,
          reason: '${m.dosya} ${m.anahtar}: gövde elle düzenlenmiş. $nasil');
    }
  });

  test('aynı (tür, sürüm, dil) iki kez eklenmez', () {
    final gorulen = <String>{};
    for (final m in migration) {
      expect(gorulen.add(m.anahtar), isTrue,
          reason: '${m.anahtar} ikinci kez (${m.dosya}); ilk satır kazanır, '
              'bu satır sessizce yok sayılır');
    }
    expect({for (final k in katalog) k.anahtar}, hasLength(katalog.length));
  });

  test('tür listesi migration check\'iyle aynı', () {
    expect(turCheckListesi(), YasalTur.hepsi);
  });

  test('yatırım uyarısı eski kayıtla aynı hash (geri doldurma buna dayanır)',
      () {
    expect(YasalMetinKatalogu.yatirimUyarisi().hash, disclaimerHash);
    expect(YasalMetinKatalogu.yatirimUyarisi().surum, disclaimerVersion);
  });

  test('gövdeler şablon hâlinde: ülke yer tutucusu doldurulmamış', () {
    for (final (k, yer) in [
      (YasalMetinKatalogu.gizlilik(), '{SUPABASE_ULKE}'),
      (YasalMetinKatalogu.gizlilik(), '{SUPABASE_ULKEDE}'),
      (YasalMetinKatalogu.kvkk(), '{SUPABASE_ULKE}'),
      (YasalMetinKatalogu.acikRiza(), '{SUPABASE_ULKEDE}'),
      (YasalMetinKatalogu.kayitKutuRiza(), '{SUPABASE_ULKE}'),
      for (final d in YasalMetinKatalogu.tekKutuDilleri)
        (YasalMetinKatalogu.kayitTekKutu(d), '{SUPABASE_ULKE}'),
    ]) {
      expect(k.govde, contains(yer), reason: k.anahtar);
      for (final ulke in ['Almanya', 'Japonya', 'Germany', 'Japan']) {
        expect(k.govde, isNot(contains(ulke)), reason: k.anahtar);
      }
    }
  });

  test('onay değişkenleri yalnız belgede geçen yer tutucular', () {
    const tum = {'SUPABASE_ULKE': 'Japonya', 'SUPABASE_ULKEDE': "Japonya'da"};
    expect(
        YasalMetinKatalogu.belgeDegiskenleri(YasalMetinKatalogu.kosullar(), tum),
        isEmpty);
    expect(YasalMetinKatalogu.belgeDegiskenleri(YasalMetinKatalogu.gizlilik(), tum),
        tum);
    expect(YasalMetinKatalogu.belgeDegiskenleri(YasalMetinKatalogu.kvkk(), tum),
        {'SUPABASE_ULKE': 'Japonya'});
    expect(YasalMetinKatalogu.belgeDegiskenleri(YasalMetinKatalogu.acikRiza(), tum),
        {'SUPABASE_ULKEDE': "Japonya'da"});
  });

  test('tek kutu yalnız gösterilen dillerde; çeviri uydurulmaz', () {
    final diller = {
      for (final k in katalog)
        if (k.tur == YasalTur.kayitTekKutu) k.dil
    };
    expect(diller, {'tr', 'en'});
    final tr = YasalMetinKatalogu.kayitTekKutu('tr').govde;
    final en = YasalMetinKatalogu.kayitTekKutu('en').govde;
    expect(tr, isNot(en));
    expect(en, contains('I accept'));
    // Belgeler ve eski kutular yalnız Türkçe gösteriliyor.
    for (final k in katalog.where((k) => k.tur != YasalTur.kayitTekKutu)) {
      expect(k.dil, 'tr', reason: k.anahtar);
    }
  });

  test('kayıt öğeleri RPC sınırına (12) sığar ve katalogda var', () {
    // Kayıt yalnız tek kutulu (bayrak `tek_onay_kutusu` 2026-10-05'te
    // kalktı; iki kutulu düzenin öğe kümesi artık kurulmaz).
    for (final zorunlu in [false, true]) {
      final ogeler = KayitOnayBaglami(
        dil: 'en',
        kutuUlkesi: 'Almanya (AB)',
        belgeDegiskenleri: const {'SUPABASE_ULKE': 'Almanya (AB)'},
        kosulBelgesiAcildi: false,
        rizaBelgesiAcildi: false,
        // Zorunlu okuma: yatırım uyarısı da kayıt öğesi olur (0104).
        yatirimUyarisiOnaylandi: zorunlu,
      ).ogeler();
      expect(ogeler.length, lessThanOrEqualTo(12));
      for (final o in ogeler) {
        expect(migrationda['${o['tur']}/${o['surum']}/${o['dil']}']?.hash,
            o['hash']);
      }
    }
  });

  test('RPC kanal listesi servisle aynı', () {
    final (_, sql) = migrationDosyalari()
        .lastWhere((d) => d.$2.contains('function public.yasal_onay_kaydet('));
    for (final kanal in [
      'kayit',
      'yatirim_uyarisi_ekrani',
      'zirve',
      'yeniden_onay',
    ]) {
      expect(sql, contains("p_kanal = '$kanal'"), reason: kanal);
    }
  });

  test('RPC kanal-tür eşlemesi: kayıt ve kapı her belgeyi yazabilir', () {
    // Kayıt ve yeniden onay kapısı dört belgenin dördünü yazar
    // (`KayitOnayBaglami.ogeler`, `YasalOnayService.kapiOgeleri`). Yeni bir
    // belge türü eklenip RPC'nin eşlemesine girmezse sunucu "tur … bu
    // kanalda kaydedilemez" der ve onay hiç yazılmaz.
    final (dosya, sql) = migrationDosyalari()
        .lastWhere((d) => d.$2.contains('function public.yasal_onay_kaydet('));
    String kol(String kanal) {
      final i = sql.indexOf("(p_kanal = '$kanal' and v_tur in (");
      expect(i, isNonNegative, reason: '$dosya: $kanal kolu yok');
      return sql.substring(i, sql.indexOf('))', i));
    }

    for (final kanal in ['kayit', 'yeniden_onay']) {
      for (final b in YasalBelge.values) {
        expect(kol(kanal), contains("'${b.tur}'"),
            reason: '$dosya: $kanal kanalı ${b.tur} türünü yazamıyor');
      }
    }

    // İstemcinin bu kanallara gönderebileceği HER tür eşlemede olmalı; RPC
    // tek işlemdir, tek bir yabancı tür bütün kaydı düşürür. Zorunlu okuma
    // (bayrak `zorunlu_okuma`) kayıtta yatırım uyarısını da gönderir → 0104.
    final kayitTurleri = {
      for (final o in KayitOnayBaglami(
        dil: 'tr',
        kutuUlkesi: 'x',
        belgeDegiskenleri: const {},
        kosulBelgesiAcildi: true,
        rizaBelgesiAcildi: true,
        sonunaKadarOkunanlar: {
          for (final b in YasalBelge.values) b.tur,
          YasalTur.yatirimUyarisi,
        },
        yatirimUyarisiOnaylandi: true,
      ).ogeler())
        o['tur'] as String,
    };
    expect(kayitTurleri, contains(YasalTur.yatirimUyarisi));
    for (final t in kayitTurleri) {
      expect(kol('kayit'), contains("'$t'"),
          reason: '$dosya: kayit kanalı $t türünü yazamıyor');
    }
    final kapiTurleri = {
      for (final o in YasalOnayService.kapiOgeleri(
        durum: YasalKapiDurumu.tamam,
        belgeDegiskenleri: const {},
        acilanBelgeler: const {},
        kutu: const KapiKutuBaglami(dil: 'tr', kutuUlkesi: 'x'),
        yatirimUyarisiDahil: true,
      ))
        o['tur'] as String,
    };
    for (final t in kapiTurleri) {
      expect(kol('yeniden_onay'), contains("'$t'"),
          reason: '$dosya: yeniden_onay kanalı $t türünü yazamıyor');
    }
  });

  test('belgenin ekrandaki künyesi katalog sürümü ve yürürlüğüyle aynı', () {
    // Ekranda yazan "Sürüm" ile veritabanına giden sürüm ayrışmasın:
    // 2026-10-04'e kadar metinler değişti ama "Sürüm: 1.0" kaldı. 1.2'den
    // beri sürüm md'nin kendisinden okunur; burada ekranda gösterilen
    // künye kutusunun da onu yazdığı kilitlenir.
    for (final b in YasalBelge.values) {
      final m = YasalMetinKatalogu.belge(b);
      final kunye = b.sablonBloklari[1];
      expect(kunye.type, LegalBlockType.meta, reason: b.kaynak);
      expect(kunye.text, contains('Sürüm: ${m.surum}'),
          reason: '${b.kaynak}. $nasil');
      expect(m.yururlukTarihi, isNotNull, reason: b.kaynak);
      final t = DateTime.parse(m.yururlukTarihi!);
      expect(kunye.text, contains('Yürürlük tarihi: ${t.day} '),
          reason: b.kaynak);
    }
  });

  test('belgelerin ilk veritabanı sürümü 1.1; "1.0" arşivi uydurulmadı', () {
    for (final tur in [YasalTur.kosullar, YasalTur.gizlilik, YasalTur.kvkk]) {
      expect(migration.where((m) => m.tur == tur && m.surum == '1.0'), isEmpty,
          reason: '1.0 adıyla birden çok metin yayımlandı, hiçbiri onaya '
              'bağlı değildi; git geçmişinden arşiv satırı yazılmaz');
    }
    // Açık Rıza Metni ayrı tür olarak 1.2 ile başlar (0103); web'deki "1.0"
    // etiketli eski metin hiçbir onaya bağlı değildi.
    expect(
        migration
            .where((m) => m.tur == YasalTur.acikRiza)
            .map((m) => m.surum)
            .first,
        '1.2');
  });

  test('saklama politikası metni ile şema aynı şeyi söyler', () {
    // Gizlilik §7 / KVKK §6: onay kayıtları silmeden sonra 3 yıl; Zirve
    // rızası kaydı hesapla birlikte silinir (§5.1). 0102 bunu uygular.
    final gizlilik = YasalMetinKatalogu.gizlilik().govde;
    final kvkk = YasalMetinKatalogu.kvkk().govde;
    expect(gizlilik, contains('Yasal metin onay kayıtları'));
    expect(gizlilik, contains('Hesap silindikten sonra **3 yıl**'));
    expect(kvkk, contains('Yasal metin onay kayıtları'));
    expect(kvkk, contains('Hesap silinmesinden sonra **3 yıl**'));
    // Saklama satırı onaylatılan her belgeyi adıyla anar (Açık Rıza Metni
    // 1.2'de ayrı belge oldu).
    for (final ad in ['Kullanım Koşulları', 'Gizlilik Politikası',
        'KVKK Aydınlatma Metni', 'Açık Rıza Metni']) {
      expect(gizlilik, contains(ad), reason: ad);
      expect(kvkk, contains(ad), reason: ad);
    }
    expect(gizlilik, contains('Hesabınızı sildiğinizde bu kayıtlar'));
    final (_, sql) = migrationDosyalari()
        .lastWhere((d) => d.$2.contains('yasal_onaylar_hesap_silindi'));
    expect(sql, contains("interval '3 years'"));
    expect(sql, contains("m.tur = 'zirve_riza'"));
    expect(sql, contains('before delete on auth.users'));
    // FK yok: cascade ispatı hesapla birlikte silerdi.
    expect(sql, contains('user_id         uuid not null,\n'));
  });
}
