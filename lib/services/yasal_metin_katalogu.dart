import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:crypto/crypto.dart';

import '../l10n/generated/app_localizations.dart';
import '../screens/legal_doc_screen.dart';
import '../widgets/zirve_riza_karti.dart';
import 'disclaimer_service.dart';
import 'leaderboard_service.dart';

/// Yasal metin kataloğu — kullanıcıya onaylatılan HER metnin tek kaynağı
/// (kullanıcı isteği 2026-10-04: "bu metinleri de db'de tutup her müşteri
/// hangilerini onaylamış takip edilebilir olmalı").
///
/// ## Neden katalog
/// Onayın ispatı "hangi metni gördü" sorusuna cevap vermeli. Metinler
/// ekranlarda sabit olarak duruyordu (`LegalDocs`, kayıt kutuları,
/// `ZirveRizaKarti`, `disclaimerText`); veritabanında hiçbiri yoktu.
/// Katalog bu sabitleri OKUR (kopyalamaz) ve her birine (tür, sürüm, dil)
/// kimliği verir; gövdenin sha256'sı ÇALIŞMA ANINDA hesaplanır. Ekrandaki
/// metin değişirse hash de değişir.
///
/// ## Kayma kilidi
/// Migration'lar (`yasal_metinler`, 0102+) aynı dörtlüyü (tür, sürüm, dil,
/// hash) ve gövdeyi taşır. `test/yasal_metin_kilidi_test.dart` katalogdaki
/// her dörtlünün migration'larda bulunduğunu doğrular: metin sürüm
/// artırılmadan değişirse test kırılır ve ne yapılacağını söyler (sürümü
/// artır → `tool/yasal_metin_uret_test.dart` ile INSERT üret → yeni
/// migration). Sunucu da `yasal_onay_kaydet`'te hash'i karşılaştırır:
/// kilit atlanıp gönderilse bile yanlış metne onay yazılmaz.
///
/// ## Şablon hâli
/// Veritabanına ve hash'e metnin ŞABLON hâli girer (`{SUPABASE_ULKE}` gibi
/// yer tutucular doldurulmadan). Gösterimde doldurulan değerler onay
/// satırının `degiskenler` alanında durur. Böylece Tokyo'dan Frankfurt'a
/// taşınınca metin sürümü değişmez, ama kimin hangi ülkeyi gördüğü bilinir.
///
/// ## Uydurma çeviri yok
/// Yalnız kullanıcıya gerçekten gösterilen diller girer. Belgeler ve eski
/// iki kayıt kutusu yalnız Türkçe gösteriliyor (İngilizce arayüzde de) →
/// yalnız `tr`. Tek onay kutusu l10n'dan geliyor → `tr` ve `en`.
abstract final class YasalTur {
  /// Kullanım Koşulları (`LegalDocs.terms`).
  static const kosullar = 'kosullar';

  /// Gizlilik Politikası (`LegalDocs.privacy`). Kayıtta "Açık Rıza: Yurt
  /// Dışı Veri Aktarımı" başlığıyla bu belge açılır; ayrı bir açık rıza
  /// belgesi yok — bu yüzden tür belgenin kendi adını taşır.
  static const gizlilik = 'gizlilik_politikasi';

  /// KVKK Aydınlatma Metni (`LegalDocs.kvkk`).
  static const kvkk = 'kvkk_aydinlatma';

  /// Yatırım tavsiyesi reddi (`disclaimerText`, `DisclaimerAcceptanceScreen`).
  /// `disclaimer_acceptances.disclaimer_hash` ile AYNI hash — geri doldurma
  /// bu eşitlikle yapılır.
  static const yatirimUyarisi = 'yatirim_uyarisi';

  /// Kayıt formu, iki kutulu düzen: "Yasal Koşullar" kutusu.
  static const kayitKutuKosullar = 'kayit_kutu_kosullar';

  /// Kayıt formu, iki kutulu düzen: "Açık Rıza: Yurt Dışı Veri Aktarımı".
  static const kayitKutuRiza = 'kayit_kutu_riza';

  /// Kayıt formu, tek kutulu düzen (bayrak `tek_onay_kutusu`).
  static const kayitTekKutu = 'kayit_tek_kutu';

  /// Zirvedeki Portföyler açık rıza kartı (`ZirveRizaKarti`, 0091).
  static const zirveRiza = 'zirve_riza';

  /// 0102'deki `check` listesiyle aynı sıra. Yeni tür = yeni migration'da
  /// check'i genişlet + buraya ekle (kilit testi ikisini karşılaştırır).
  static const hepsi = [
    kosullar,
    gizlilik,
    kvkk,
    yatirimUyarisi,
    kayitKutuKosullar,
    kayitKutuRiza,
    kayitTekKutu,
    zirveRiza,
  ];
}

/// Kayıt formundaki iki kutunun metinleri — `RegisterScreen` bunları
/// GÖSTERİR, katalog bunları HASH'LER. Eskiden ekranda literal'di; kilit
/// ancak tek kaynakla çalışır.
abstract final class KayitKutuMetni {
  static const kosulBaslik = 'Yasal Koşullar';
  static const kosulGovde = '• 18 yaşından büyük olduğunu beyan edersin.\n'
      '• Uygulama yatırım tavsiyesi değildir; gösterilen '
      'fiyatlar ve teknik analiz bilgi amaçlıdır.\n'
      '• Kayıt ile Kullanım Koşulları, KVKK Aydınlatma '
      'Metni ve Gizlilik Politikası\'nı kabul etmiş '
      'sayılırsın.';
  static const kosulCumle = 'Yasal Koşulları, KVKK Aydınlatma Metni\'ni ve '
      '18+ olduğumu kabul ediyorum.';

  static const rizaBaslik = 'Açık Rıza: Yurt Dışı Veri Aktarımı';

  /// [ulke] bağlanılan Supabase projesinin ülkesi (köprü sürümü — bkz.
  /// `LegalDocs._ulke`); bilinmiyorsa [rizaUlkeBilinmiyor].
  static String rizaGovde(String ulke) =>
      'Verilerin Supabase ($ulke) ve Firebase (ABD/Küresel) '
      'üzerinde saklanacak. KVKK Madde 9(1) gereği açık rıza '
      'gerekir. İstediğin zaman geri çekebilirsin (hesap silme).';
  static const rizaUlkeBilinmiyor = 'yurt dışı';
  static const rizaCumle =
      'Verilerimin yurt dışına aktarılmasına açık rıza veriyorum.';
}

/// Katalogdaki bir metin: kimliği (tür, sürüm, dil) + şablon gövdesi.
class YasalMetin {
  const YasalMetin({
    required this.tur,
    required this.surum,
    required this.dil,
    required this.baslik,
    required this.govde,
    this.yururlukTarihi,
  });

  final String tur;
  final String surum;
  final String dil;
  final String baslik;

  /// Kanonik, yer tutucuları doldurulmamış düz metin.
  final String govde;

  /// Metnin KENDİSİNDE yazan yürürlük tarihi (`yyyy-mm-dd`). Metin tarih
  /// yazmıyorsa null — tarih uydurulmaz.
  final String? yururlukTarihi;

  /// sha256(utf8(govde)), küçük harf hex. Sunucudaki
  /// `encode(sha256(convert_to(govde, 'UTF8')), 'hex')` ile aynı.
  String get hash => sha256.convert(utf8.encode(govde)).toString();

  String get anahtar => '$tur/$surum/$dil';

  /// `yasal_onay_kaydet` RPC'sinin bir öğesi.
  Map<String, dynamic> rpcOgesi([Map<String, Object?> degiskenler = const {}]) =>
      {
        'tur': tur,
        'surum': surum,
        'dil': dil,
        'hash': hash,
        'degiskenler': degiskenler,
      };

  /// Migration'a girecek INSERT — `tool/yasal_metin_uret_test.dart` üretir,
  /// `test/yasal_metin_kilidi_test.dart` aynı biçimi okur. Gövde dollar-
  /// quoting ile birebir; `replace(..., chr(13), '')` Windows'ta CRLF'e
  /// dönen checkout'ta hash'in kaymasını önler (gövdede `\r` yoktur).
  String sqlInsert() {
    const etiket = r'$yasal$';
    if (govde.contains(etiket)) {
      throw StateError('$anahtar gövdesi $etiket içeremez');
    }
    if (govde.contains('\r')) {
      throw StateError('$anahtar gövdesinde CR var; kanonik metin LF olmalı');
    }
    String q(String s) => "'${s.replaceAll("'", "''")}'";
    final tarih = yururlukTarihi == null ? 'null' : "date '$yururlukTarihi'";
    return 'insert into public.yasal_metinler\n'
        '  (tur, surum, dil, baslik, yururluk_tarihi, govde_hash, govde)\n'
        'values (${q(tur)}, ${q(surum)}, ${q(dil)}, ${q(baslik)}, $tarih,\n'
        "  '$hash',\n"
        '  replace($etiket$govde$etiket, chr(13), \'\'))\n'
        'on conflict (tur, surum, dil) do nothing;\n';
  }
}

abstract final class YasalMetinKatalogu {
  /// Belgelerin sürümü — metinlerin meta satırındaki "Sürüm: 1.0".
  static const belgeSurumu = '1.0';
  static const belgeYururluk = '2026-05-11';

  /// Kayıt kutularının sürümü. Kutu başlığında `v$disclaimerVersion`
  /// görünüyor; kullanıcının gördüğü etiketle aynı kalsın diye o sayı.
  static const kutuSurumu = disclaimerVersion;

  /// LegalBlock listesi → düz metin. Biçim kararlıdır: değiştirmek BÜTÜN
  /// belge hash'lerini değiştirir (yeni sürüm demektir).
  static String bloklardanMetin(List<LegalBlock> bloklar) {
    String satir(LegalBlock b) => switch (b.type) {
          LegalBlockType.h1 => '# ${b.text}',
          LegalBlockType.h2 => '## ${b.text}',
          LegalBlockType.h3 => '### ${b.text}',
          LegalBlockType.paragraph => b.text,
          LegalBlockType.meta => '> ${b.text}',
          LegalBlockType.divider => '---',
          LegalBlockType.tableHeader =>
            '| ${b.cells.join(' | ')} |\n|${' --- |' * b.cells.length}',
          LegalBlockType.tableRow => '| ${b.cells.join(' | ')} |',
        };
    return bloklar.map(satir).join('\n\n');
  }

  static YasalMetin kosullar() => YasalMetin(
        tur: YasalTur.kosullar,
        surum: belgeSurumu,
        dil: 'tr',
        baslik: 'Kullanım Koşulları',
        govde: bloklardanMetin(LegalDocs.terms),
        yururlukTarihi: belgeYururluk,
      );

  static YasalMetin gizlilik() => YasalMetin(
        tur: YasalTur.gizlilik,
        surum: belgeSurumu,
        dil: 'tr',
        baslik: 'Gizlilik Politikası',
        govde: bloklardanMetin(LegalDocs.privacySablonu),
        yururlukTarihi: belgeYururluk,
      );

  static YasalMetin kvkk() => YasalMetin(
        tur: YasalTur.kvkk,
        surum: belgeSurumu,
        dil: 'tr',
        baslik: 'KVKK Aydınlatma Metni',
        govde: bloklardanMetin(LegalDocs.kvkkSablonu),
        yururlukTarihi: belgeYururluk,
      );

  /// Gövde `disclaimerText`'in KENDİSİ (sarmalama yok): hash
  /// `disclaimerHash` ile aynı olmalı ki eski kayıtlar eşleşsin.
  static YasalMetin yatirimUyarisi() => const YasalMetin(
        tur: YasalTur.yatirimUyarisi,
        surum: disclaimerVersion,
        dil: 'tr',
        baslik: 'Yasal Uyarı',
        govde: disclaimerText,
      );

  static YasalMetin kayitKutuKosullar() => const YasalMetin(
        tur: YasalTur.kayitKutuKosullar,
        surum: kutuSurumu,
        dil: 'tr',
        baslik: KayitKutuMetni.kosulBaslik,
        govde: '${KayitKutuMetni.kosulBaslik}\n\n'
            '${KayitKutuMetni.kosulGovde}\n\n'
            '${KayitKutuMetni.kosulCumle}',
      );

  static YasalMetin kayitKutuRiza() => YasalMetin(
        tur: YasalTur.kayitKutuRiza,
        surum: kutuSurumu,
        dil: 'tr',
        baslik: KayitKutuMetni.rizaBaslik,
        govde: '${KayitKutuMetni.rizaBaslik}\n\n'
            '${KayitKutuMetni.rizaGovde('{SUPABASE_ULKE}')}\n\n'
            '${KayitKutuMetni.rizaCumle}',
      );

  /// Tek onay kutusu — gösterildiği dilde (l10n). Kutu cümlesi bağlantı
  /// metinleriyle birlikte, ekranda okunduğu gibi.
  static YasalMetin kayitTekKutu(String dil) {
    final l = lookupAppLocalizations(Locale(dil));
    return YasalMetin(
      tur: YasalTur.kayitTekKutu,
      surum: kutuSurumu,
      dil: l.localeName,
      baslik: l.tekOnayBaslik,
      govde: '${l.tekOnayBaslik}\n\n'
          '${l.tekOnayAciklama('{SUPABASE_ULKE}')}\n\n'
          '${l.tekOnayCumle(l.tekOnayKosullarBaglanti, l.tekOnayRizaBaglanti)}',
    );
  }

  /// Zirve açık rıza kartı — kartın gösterdiği sırayla.
  static YasalMetin zirveRiza() => YasalMetin(
        tur: YasalTur.zirveRiza,
        surum: LeaderboardService.zirveRizaMetniSurumu,
        dil: 'tr',
        baslik: ZirveRizaKarti.baslik,
        govde: [
          ZirveRizaKarti.baslik,
          ZirveRizaKarti.aciklama,
          for (final (b, m) in ZirveRizaKarti.maddeler) '$b\n$m',
          ZirveRizaKarti.hukukNotu,
          ZirveRizaKarti.katilEtiketi,
        ].join('\n\n'),
      );

  /// Tek onay kutusunun gösterildiği diller (`app_*.arb`).
  static const tekKutuDilleri = ['tr', 'en'];

  /// Kataloğun tamamı — kilit testi ve INSERT üreteci bunu dolaşır.
  static List<YasalMetin> tumu() => [
        kosullar(),
        gizlilik(),
        kvkk(),
        yatirimUyarisi(),
        kayitKutuKosullar(),
        kayitKutuRiza(),
        for (final d in tekKutuDilleri) kayitTekKutu(d),
        zirveRiza(),
      ];
}
