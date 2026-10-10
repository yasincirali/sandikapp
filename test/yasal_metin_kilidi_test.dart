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
        YasalMetinKatalogu.belgeDegiskenleri(
            YasalMetinKatalogu.kosullar(), tum),
        isEmpty);
    expect(
        YasalMetinKatalogu.belgeDegiskenleri(
            YasalMetinKatalogu.gizlilik(), tum),
        tum);
    expect(YasalMetinKatalogu.belgeDegiskenleri(YasalMetinKatalogu.kvkk(), tum),
        {'SUPABASE_ULKE': 'Japonya'});
    expect(
        YasalMetinKatalogu.belgeDegiskenleri(
            YasalMetinKatalogu.acikRiza(), tum),
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
        // Açık Rıza Metni yalnız sonuna kadar okunup onaylanınca girer.
        sonunaKadarOkunanlar: {if (zorunlu) YasalTur.acikRiza},
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
    for (final ad in [
      'Kullanım Koşulları',
      'Gizlilik Politikası',
      'KVKK Aydınlatma Metni',
      'Açık Rıza Metni'
    ]) {
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

  test('0105: süresiz iki kaydın süresi metinde ve şemada aynı', () {
    // Kullanıcı kararı 2026-10-05: Supabase Auth güvenlik kaydı 90 gün,
    // anonim hesap silme kaydı 3 yıl; ikisi de günlük cron'la silinir.
    final gizlilik = YasalMetinKatalogu.gizlilik().govde;
    final kvkk = YasalMetinKatalogu.kvkk().govde;
    for (final (ad, metin) in [('Gizlilik', gizlilik), ('KVKK', kvkk)]) {
      expect(metin, isNot(contains('otomatik silme süresi tanımlamamıştır')),
          reason: '$ad: 1.2 ifadesi kalkmalı');
      expect(
          metin,
          contains('| Oturum açma güvenlik kaydı (IP, cihaz/tarayıcı; '
              'Supabase Auth güvenlik kaydı) | 90 gün; eskileri her gün '
              'otomatik silinir |'),
          reason: ad);
      expect(metin, contains('| Anonim hesap silme kaydı'), reason: ad);
    }
    expect(gizlilik, contains('| Silmeden sonra **3 yıl** (TBK Madde 146'));
    expect(kvkk, contains('| Hesap silinmesinden sonra **3 yıl**; süresi'));

    final (dosya, sql) = migrationDosyalari()
        .lastWhere((d) => d.$2.contains('auth_guvenlik_kaydi_saklama_temizle'));
    expect(dosya, startsWith('0105_'));
    expect(
        sql,
        contains('delete from auth.audit_log_entries\n'
            "   where created_at < now() - interval '90 days';"));
    expect(
        sql,
        contains('delete from public.account_deletion_log\n'
            "   where deleted_at < now() - interval '3 years';"));
    expect(sql, contains("cron.schedule('auth-guvenlik-kaydi-saklama'"));
    expect(sql, contains("cron.schedule('hesap-silme-kaydi-saklama'"));
    // auth şemasında yalnız DELETE: tablo/şema değişmez.
    expect(sql,
        isNot(contains(RegExp(r'(alter|drop|create)\s+\w*\s*\w*\s*auth\.'))));
  });

  test(
      '1.4: yalnız Açık Rıza Metni sonuna kadar okunur; Koşullar kutuyla, '
      'Gizlilik ve KVKK bilgilendirme (okuma sadeleştirme 2026-10-05)', () {
    // 1.3'ün "her metin tam gösterilir, sonuna kadar okunur, onay en altta
    // verilir" cümleleri uygulamanın yeni davranışında yanlış olurdu.
    final kosullar = YasalMetinKatalogu.kosullar().govde;
    final gizlilik = YasalMetinKatalogu.gizlilik().govde;
    final kvkk = YasalMetinKatalogu.kvkk().govde;
    final riza = YasalMetinKatalogu.acikRiza().govde;
    expect(
        kosullar,
        isNot(
            contains('her birini sonuna kadar okuyup en altta onaylarsınız')));
    expect(kosullar, isNot(contains('Onay kutuları ancak bundan sonra')));
    // Koşullar Gizlilik/KVKK/Açık Rıza'yı "kabul" diye paketlemez.
    expect(kosullar,
        isNot(contains('okuduğunuzu, anladığınızı ve kabul ettiğinizi')));
    expect(
        kosullar, contains('Bu Koşulları tek bir onay kutusunu işaretleyerek'));
    expect(kosullar, contains('Onay kutusu açık rıza içermez.'));
    expect(kvkk, isNot(contains('sonuna kadar okuyup en altta onaylayarak')));
    expect(kvkk, contains('size bağlantı olarak sunulur'));
    expect(kvkk, contains('onayınıza bağlı değildir'));
    expect(gizlilik,
        contains('bilgilendirme amaçlıdır ve kabulünüze bağlı değildir'));
    expect(riza, isNot(contains('onay kutusunu işaretlersiniz')));
    expect(riza, isNot(contains('onay kutusuyla verilir')));
    expect(riza, contains('Rıza yalnız bu düğmeyle verilir'));
    // Yatırım uyarısı hâlâ tam metniyle okunup onaylanır (§3 / §12 aynen).
    for (final m in [kosullar, gizlilik]) {
      expect(m, contains('Bu uyarının tam metni kayıt sırasında'));
    }
    // 0120'den beri Koşullar/Gizlilik/KVKK 1.5; Açık Rıza 1.4'te kaldı.
    for (final b in YasalBelge.values) {
      expect(YasalOnayService.surumKarsilastir(b.surum, '1.4'),
          greaterThanOrEqualTo(0),
          reason: b.kaynak);
    }
  });

  test(
      '1.5: varlık notları (Anthropic, kişisel veri gitmez), geri bildirim ve '
      'Premium hakkı metinde (0116, 0117)', () {
    final kosullar = YasalMetinKatalogu.kosullar().govde;
    final gizlilik = YasalMetinKatalogu.gizlilik().govde;
    final kvkk = YasalMetinKatalogu.kvkk().govde;
    for (final m in [kosullar, gizlilik, kvkk]) {
      expect(m, contains('Anthropic'));
    }
    expect(
        gizlilik, contains('### 5.3 Yapay Zekâ ile Hazırlanan Varlık Notları'));
    expect(gizlilik, contains('Kişisel veri gönderilmez'));
    for (final m in [gizlilik, kvkk]) {
      expect(m, contains('Varlık notlarına geri bildirim'));
      expect(m, contains('Premium hakkı'));
      expect(m, contains('500 karakter'));
    }
    expect(kosullar, contains('yapay zekâ ile hazırlanan varlık notları'));
    // Kişisel veri yurt dışına yeni bir alıcıya gitmez: rıza metni 1.5'te
    // değişmedi (1.5'i 0127'de RevenueCat ilerletti, Anthropic değil).
    expect(YasalOnayService.surumKarsilastir(YasalBelge.acikRiza.surum, '1.4'),
        greaterThanOrEqualTo(0));
    expect(YasalMetinKatalogu.acikRiza().govde, isNot(contains('Anthropic')));
    // 1.6 (0122) yalnız Gizlilik ve KVKK'yı ilerletti; Koşullar 1.5'te kaldı
    // (1.6'ya 0127'de Premium maddesiyle çıktı).
    expect(YasalOnayService.surumKarsilastir(YasalBelge.kosullar.surum, '1.5'),
        greaterThanOrEqualTo(0));
    for (final b in [YasalBelge.gizlilik, YasalBelge.kvkk]) {
      expect(
          YasalOnayService.surumKarsilastir(b.surum, '1.5'), greaterThan(0),
          reason: b.kaynak);
    }
  });

  test(
      '1.6: ekstre AI sütun eşleme — yalnız anonim iskelet, isteğe bağlı, '
      'kayıt 40 gün (0121, 0122)', () {
    final gizlilik = YasalMetinKatalogu.gizlilik().govde;
    final kvkk = YasalMetinKatalogu.kvkk().govde;
    expect(gizlilik,
        contains('### 5.4 Ekstre Sütunlarının Yapay Zekâ ile Eşlenmesi'));
    expect(gizlilik, contains('siz basmadıkça'));
    expect(gizlilik, contains('maskelenmemiş rakam içeren bir iskeleti'));
    for (final m in [gizlilik, kvkk]) {
      expect(m, contains('Yapay zekâyla eşle'));
      expect(m, contains('anonim iskelet'));
      expect(m, contains('40 gün'));
    }
    // İskelet kişisel veri değil: rıza metni ve Koşullar o turda aynı kaldı
    // (sürümleri yalnız ileri gider).
    expect(YasalOnayService.surumKarsilastir(YasalBelge.acikRiza.surum, '1.4'),
        greaterThanOrEqualTo(0));
    expect(YasalOnayService.surumKarsilastir(YasalBelge.kosullar.surum, '1.5'),
        greaterThanOrEqualTo(0));
    // 1.7 (0125) ikisini yine ilerletti; 1.6 metni korunur, sürüm geri gitmez.
    for (final b in [YasalBelge.gizlilik, YasalBelge.kvkk]) {
      expect(
          YasalOnayService.surumKarsilastir(b.surum, '1.6'),
          greaterThanOrEqualTo(0),
          reason: b.kaynak);
    }
  });

  test(
      '1.7 → 1.8: fiyat kaynakları tek tek sayılmaz — kişisel veri almayan '
      'kaynak metni değiştirmez (0125, 0127)', () {
    final gizlilik = YasalMetinKatalogu.gizlilik().govde;
    final kvkk = YasalMetinKatalogu.kvkk().govde;
    // Kullanıcı (2026-10-08): "her geliştirmeden neden kvkk değişiyor".
    // KVKK m.10 alıcı GRUBUNU ister; kaynak adı yazılırsa her yeni kaynak
    // yeni sürüm demektir.
    for (final m in [gizlilik, kvkk]) {
      expect(m, contains('amuya açık piyasa verisi sağlayıcı'));
      expect(m, contains('ISIN'));
      expect(m, contains('IP adresini görür'));
      for (final ad in [
        'Yahoo', 'Binance', 'truncgil', 'Börse Frankfurt', 'Ziraat', //
        'open.er-api', 'EVDS',
      ]) {
        expect(m, isNot(contains(ad)), reason: ad);
      }
    }
    for (final m in [
      YasalMetinKatalogu.kosullar().govde,
      YasalMetinKatalogu.acikRiza().govde,
    ]) {
      for (final ad in ['Yahoo', 'Binance', 'truncgil']) {
        expect(m, isNot(contains(ad)), reason: ad);
      }
    }
  });

  test(
      '1.8: Premium abonelik — RevenueCat kişisel veri alıcısı olarak '
      'Gizlilik, KVKK ve Açık Rıza\'da; Koşullar §2A (0127)', () {
    final kosullar = YasalMetinKatalogu.kosullar().govde;
    final gizlilik = YasalMetinKatalogu.gizlilik().govde;
    final kvkk = YasalMetinKatalogu.kvkk().govde;
    final riza = YasalMetinKatalogu.acikRiza().govde;
    expect(kosullar, contains('## 2A. Premium Abonelik'));
    expect(kosullar, contains('Satın alımı geri yükle'));
    // Fiyat uydurulmaz: tutar mağazadan okunur.
    expect(kosullar, isNot(contains('49')));
    expect(kosullar, isNot(contains('399')));
    expect(gizlilik, contains('### 3.6 Abonelik Verileri'));
    for (final m in [gizlilik, kvkk, riza]) {
      expect(m, contains('RevenueCat'), reason: 'yurt dışı alıcı');
    }
    // 1.9 (0137): hesap silme RevenueCat kaydının silinmesini ister
    // (`delete-account` → revenueCatKaydiniSil); metin bunu ve mağaza
    // aboneliğinin kendiliğinden bitmediğini söyler. Eski "saklama
    // süresince kalır" cümlesi artık gerçek değil.
    for (final m in [gizlilik, kvkk]) {
      expect(m, contains("RevenueCat'teki abone kaydınızın silinmesi"));
      expect(m, contains('mağaza aboneliğini iptal etmez'));
      expect(m, isNot(contains("RevenueCat'in saklama süresince")));
    }
  });

  test('kutu 1.1: metnin TAMAMI açık rıza içermez (rıza paketlenmez)', () {
    for (final d in YasalMetinKatalogu.tekKutuDilleri) {
      final k = YasalMetinKatalogu.kayitTekKutu(d);
      expect(k.surum, '1.1');
      final g = k.govde.toLowerCase();
      for (final yasak in ['açık rıza', 'açık rızan', 'explicit consent']) {
        expect(g, isNot(contains(yasak)), reason: '${k.anahtar}: $yasak');
      }
    }
    // 1.0 satırı (rıza içeren eski kutu) DB'de değişmeden durur.
    expect(migrationda['kayit_tek_kutu/1.0/tr']?.govde,
        contains('açık rıza veriyorum'));
  });
}
