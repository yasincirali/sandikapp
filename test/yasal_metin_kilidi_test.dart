import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/legal_doc_screen.dart';
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
      '(1) metnin sürümünü artır (belgeler: YasalMetinKatalogu.belgeSurumu + '
      'belgeYururluk + LegalDocs meta satırı "Yürürlük tarihi: … · Sürüm: …" '
      '+ kapının "Neler değişti" notu yasalKapiDegisiklikNotu; kutular: '
      'YasalMetinKatalogu.kutuSurumu; Zirve: LeaderboardService.'
      'zirveRizaMetniSurumu), (2) `flutter test --run-skipped --tags arac '
      'tool/yasal_metin_uret_test.dart` ile INSERT üret, (3) çıktıyı YENİ bir '
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
    for (final k in [
      YasalMetinKatalogu.gizlilik(),
      YasalMetinKatalogu.kvkk(),
      YasalMetinKatalogu.kayitKutuRiza(),
      for (final d in YasalMetinKatalogu.tekKutuDilleri)
        YasalMetinKatalogu.kayitTekKutu(d),
    ]) {
      expect(k.govde, contains('{SUPABASE_ULKE}'), reason: k.anahtar);
      for (final ulke in ['Almanya', 'Japonya', 'Germany', 'Japan']) {
        expect(k.govde, isNot(contains(ulke)), reason: k.anahtar);
      }
    }
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
    for (final tek in [false, true]) {
      final ogeler = KayitOnayBaglami(
        tekKutu: tek,
        dil: 'en',
        kutuUlkesi: 'Almanya (AB)',
        belgeDegiskenleri: const {'SUPABASE_ULKE': 'Almanya (AB)'},
        kosulBelgesiAcildi: false,
        rizaBelgesiAcildi: false,
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

  test('belge meta satırı katalog sürümü ve yürürlük tarihiyle aynı', () {
    // Ekranda yazan "Sürüm" ile veritabanına giden sürüm ayrışmasın:
    // 2026-10-04'e kadar metinler değişti ama "Sürüm: 1.0" kaldı.
    const aylar = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz',
      'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    final t = DateTime.parse(YasalMetinKatalogu.belgeYururluk);
    final beklenen = 'Yürürlük tarihi: ${t.day} ${aylar[t.month - 1]} '
        '${t.year}  ·  Sürüm: ${YasalMetinKatalogu.belgeSurumu}';
    for (final (ad, bloklar) in [
      ('Koşullar', LegalDocs.terms),
      ('Gizlilik', LegalDocs.privacySablonu),
      ('KVKK', LegalDocs.kvkkSablonu),
    ]) {
      expect(bloklar[1].type, LegalBlockType.meta, reason: ad);
      expect(bloklar[1].text, beklenen, reason: '$ad. $nasil');
    }
  });

  test('belgelerin ilk veritabanı sürümü 1.1; "1.0" arşivi uydurulmadı', () {
    for (final tur in [YasalTur.kosullar, YasalTur.gizlilik, YasalTur.kvkk]) {
      expect(migration.where((m) => m.tur == tur && m.surum == '1.0'), isEmpty,
          reason: '1.0 adıyla birden çok metin yayımlandı, hiçbiri onaya '
              'bağlı değildi; git geçmişinden arşiv satırı yazılmaz');
    }
  });

  test('saklama politikası metni ile şema aynı şeyi söyler', () {
    // Gizlilik §7 / KVKK §6: onay kayıtları silmeden sonra 3 yıl; Zirve
    // rızası kaydı hesapla birlikte silinir (§5.1). 0102 bunu uygular.
    final gizlilik = YasalMetinKatalogu.gizlilik().govde;
    final kvkk = YasalMetinKatalogu.kvkk().govde;
    expect(gizlilik, contains('Yasal metin onay kayıtları'));
    expect(gizlilik, contains('Hesap silindikten sonra 3 yıl'));
    expect(kvkk, contains('Yasal metin onay kayıtları'));
    expect(kvkk, contains('Hesap silinmesinden sonra 3 yıl'));
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
