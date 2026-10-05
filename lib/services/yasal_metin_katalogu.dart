import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:crypto/crypto.dart';

import '../config/yasal_belge_kaynaklari.g.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/legal_block.dart';
import '../widgets/zirve_riza_karti.dart';
import 'disclaimer_service.dart';
import 'leaderboard_service.dart';
import 'yasal_md.dart';

/// Yasal metin kataloğu — kullanıcıya onaylatılan HER metnin tek kaynağı
/// (kullanıcı isteği 2026-10-04: "bu metinleri de db'de tutup her müşteri
/// hangilerini onaylamış takip edilebilir olmalı").
///
/// ## Neden katalog
/// Onayın ispatı "hangi metni gördü" sorusuna cevap vermeli. Katalog
/// ekranların gösterdiği metinleri OKUR (kopyalamaz) ve her birine (tür,
/// sürüm, dil) kimliği verir; gövdenin sha256'sı ÇALIŞMA ANINDA hesaplanır.
/// Ekrandaki metin değişirse hash de değişir.
///
/// ## Belgeler: web tek kaynak (kullanıcı kararı 2026-10-04)
/// *"Webdekiyle de her zaman eşleyelim."* Kullanım Koşulları, Gizlilik
/// Politikası, KVKK Aydınlatma Metni ve Açık Rıza Metni'nin TEK kaynağı
/// `legal/tr/*.md`'dir — web (`docs/`) de uygulama da oradan üretilir.
/// 1.1'e kadar uygulama elle yazılmış, web metninin kısaltılmış bir Dart
/// kopyasını gösteriyordu (Koşullar web'de 19, uygulamada 14 bölüm); iki
/// metin ayrışmıştı ve kullanıcı web'de yayımlanan metne değil kopyaya onay
/// veriyordu. Web metni esas alındı: daha kapsamlı ve yayımlanmış olan o.
///
/// Yöntem — (b) md'den üretilen const Dart + kayma testi, (a) md'yi Flutter
/// asset'i olarak paketleyip çalışma anında okumak yerine:
/// - **Deterministik kanonik metin + hash:** üretilen sabit md'nin kanonik
///   hâlidir (BOM yok, LF, sondaki boşluk kırpılmış — `yasalMdKanonik`).
///   Asset yolunda paketlenen dosya Windows'ta `core.autocrlf` ile CRLF'e
///   dönmüş olabilirdi; normalleştirme her okumada çalışma anında yapılmak
///   zorunda kalırdı. Burada derlemede sabitlenir, `govde_hash` sabittir.
/// - **Çevrimdışı ve senkron açılış:** `rootBundle.loadString` asenkron;
///   katalog, onay servisi, kapı ve kayıt ekranı bugün senkron okuyor.
///   Asset yolu hepsini `Future`'a çevirir ve "belge yüklenemedi" diye yeni
///   bir hata durumu açardı. Sabit metin binary'nin içindedir.
/// - **Test edilebilirlik:** testler belgeyi asset bundle'ı taklit etmeden
///   okur; `test/yasal_web_esleme_test.dart` sabit == md dosyası der.
/// Bedeli tek adım: md değişince `python docs/_build_legal.py` koşulur.
/// Aynı komut web HTML'ini de üretir; unutulursa kilit testi kırılır.
/// Gösterimde md bloklara çevrilir (`yasalMdBloklari`): başlıklar, tablolar,
/// künye (meta) kutusu ve `{SUPABASE_ULKE}` ülke doldurma korunur.
///
/// ## Kayma kilidi
/// Migration'lar (`yasal_metinler`, 0102+) aynı dörtlüyü (tür, sürüm, dil,
/// hash) ve gövdeyi taşır. `test/yasal_metin_kilidi_test.dart` katalogdaki
/// her dörtlünün migration'larda bulunduğunu doğrular; `yasal_web_esleme_
/// test` md == katalog, docs HTML güncel, md sürümü == katalog == migration
/// ve İngilizce çevirinin TR sürümüne bağlılığını kilitler. Sunucu da
/// `yasal_onay_kaydet`'te hash'i karşılaştırır: kilit atlanıp gönderilse
/// bile yanlış metne onay yazılmaz.
///
/// ## Şablon hâli
/// Veritabanına ve hash'e metnin ŞABLON hâli girer (`{SUPABASE_ULKE}` gibi
/// yer tutucular doldurulmadan). Gösterimde doldurulan değerler onay
/// satırının `degiskenler` alanında durur. Böylece Tokyo'dan Frankfurt'a
/// taşınınca metin sürümü değişmez, ama kimin hangi ülkeyi gördüğü bilinir.
/// Web aynı yer tutucuyu kendi ifadesiyle doldurur (`_build_legal.py` →
/// `YER_TUTUCULAR`): "Japonya (AWS Tokyo); Almanya'ya … taşınma sürecinde".
///
/// ## İngilizce: uygulamada gösterilmez (karar 2026-10-04)
/// `legal/en/*.md` web'de yayımlanır ve TR'nin çevirisidir (her dosya
/// "**Source:** TR x" satırıyla hangi TR sürümünü çevirdiğini beyan eder;
/// TR sürümü artıp EN güncellenmezse kilit testi kırılır). Uygulama İngilizce
/// arayüzde de TÜRKÇE belgeyi gösterir ve onay `dil = 'tr'` yazılır:
/// 1. Bağlayıcı metin Türkçedir ("yorum farklılığında Türkçe esastır");
///    onayın ispatı bağlayıcı metne verilmeli.
/// 2. İngilizce takım eksik: KVKK Aydınlatma Metni'nin ve Açık Rıza
///    Metni'nin İngilizcesi YOK. `GDPR_NOTICE.md` KVKK'nın çevirisi DEĞİL,
///    AB/AEA kullanıcıları için ayrı bir hukuk rejiminin bildirimidir. Yarı
///    İngilizce yarı Türkçe bir onay seti tek onayı iki dile bölerdi;
///    eksikleri uydurma çeviriyle doldurmak hukuk işi.
/// 3. İngilizce arayüz BETA. Kapı ekranı "Belgeler Türkçedir." der.
///
/// ## Uydurma çeviri yok
/// Yalnız kullanıcıya gerçekten gösterilen diller girer. Belgeler ve eski
/// iki kayıt kutusu yalnız Türkçe gösteriliyor (İngilizce arayüzde de) →
/// yalnız `tr`. Tek onay kutusu l10n'dan geliyor → `tr` ve `en`.
abstract final class YasalTur {
  /// Kullanım Koşulları (`legal/tr/TERMS_OF_SERVICE.md`).
  static const kosullar = 'kosullar';

  /// Gizlilik Politikası (`legal/tr/PRIVACY_POLICY.md`). 1.1'e kadar kayıtta
  /// "Açık Rıza: Yurt Dışı Veri Aktarımı" başlığıyla bu belge açılıyordu;
  /// 1.2'den beri açık rıza kendi belgesidir ([acikRiza]).
  static const gizlilik = 'gizlilik_politikasi';

  /// KVKK Aydınlatma Metni (`legal/tr/KVKK_AYDINLATMA_METNI.md`).
  static const kvkk = 'kvkk_aydinlatma';

  /// Yatırım tavsiyesi reddi (`disclaimerText`, `DisclaimerAcceptanceScreen`).
  /// `disclaimer_acceptances.disclaimer_hash` ile AYNI hash — geri doldurma
  /// bu eşitlikle yapılır.
  static const yatirimUyarisi = 'yatirim_uyarisi';

  /// Kayıt formu, iki kutulu düzen: "Yasal Koşullar" kutusu.
  static const kayitKutuKosullar = 'kayit_kutu_kosullar';

  /// Kayıt formu, iki kutulu düzen: "Açık Rıza: Yurt Dışı Veri Aktarımı".
  static const kayitKutuRiza = 'kayit_kutu_riza';

  /// Kayıt formunun ve yeniden onay kapısının tek kutusu. 1.0 (2026-10-04):
  /// Koşullar + KVKK + 18+ + yurt dışı aktarım AÇIK RIZASI tek cümlede.
  /// 1.1 (2026-10-05, okuma sadeleştirme): Koşulların kabulü + 18+ +
  /// Gizlilik ve KVKK ile "bilgilendirildim"; açık rıza ÇIKTI (yalnız Açık
  /// Rıza Metni'nin sonunda verilir). Tür aynı kaldı — bkz.
  /// [YasalMetinKatalogu.kutuSurumu].
  static const kayitTekKutu = 'kayit_tek_kutu';

  /// Zirvedeki Portföyler açık rıza kartı (`ZirveRizaKarti`, 0091).
  static const zirveRiza = 'zirve_riza';

  /// Açık Rıza Metni (`legal/tr/ACIK_RIZA_METNI.md`, 0103). Web'de 2026-05'ten
  /// beri ayrı bir belgeydi; uygulama yerine Gizlilik Politikası'nı
  /// açıyordu. Kayıttaki ve kapıdaki "açık rıza" bağlantısı artık bunu açar.
  static const acikRiza = 'acik_riza_metni';

  /// Migration'daki `yasal_metinler_tur_check` listesiyle aynı sıra (0102,
  /// 0103 sona ekledi). Yeni tür = yeni migration'da check'i genişlet +
  /// buraya ekle (kilit testi ikisini karşılaştırır).
  static const hepsi = [
    kosullar,
    gizlilik,
    kvkk,
    yatirimUyarisi,
    kayitKutuKosullar,
    kayitKutuRiza,
    kayitTekKutu,
    zirveRiza,
    acikRiza,
  ];
}

/// Uygulamada gösterilen ve onaylatılan yasal belgeler — her biri bir
/// `legal/tr/*.md`. Sıra: kapı ekranındaki ve Ayarlar'daki sıra.
///
/// Sürüm, yürürlük tarihi ve başlık md'nin KENDİSİNDEN okunur ("**Sürüm:**
/// 1.2" satırı): web, uygulama ve veritabanı aynı sayıyı taşır, ayrı bir
/// Dart sabiti yoktur. Çerez ve Yerel Depolama Politikası
/// (`COKEZ_VE_DEPOLAMA.md`) uygulamada hiçbir yere bağlı değil ve onay
/// istemez → burada yok; yalnız web'de.
enum YasalBelge {
  kosullar(YasalTur.kosullar, 'legal/tr/TERMS_OF_SERVICE.md'),
  gizlilik(YasalTur.gizlilik, 'legal/tr/PRIVACY_POLICY.md'),
  kvkk(YasalTur.kvkk, 'legal/tr/KVKK_AYDINLATMA_METNI.md'),
  acikRiza(YasalTur.acikRiza, 'legal/tr/ACIK_RIZA_METNI.md');

  const YasalBelge(this.tur, this.kaynak);

  final String tur;

  /// Depo köküne göre md yolu — `yasalBelgeKaynaklari` anahtarı.
  final String kaynak;

  /// Kanonik md (şablon; yer tutucular doldurulmamış).
  String get md {
    final m = yasalBelgeKaynaklari[kaynak];
    if (m == null) {
      throw StateError('$kaynak üretilmemiş: python docs/_build_legal.py');
    }
    return m;
  }

  String get surum => yasalMdSurum(md);
  String? get yururluk => yasalMdYururluk(md);
  String get baslik => yasalMdBaslik(md);

  /// Kayıtta ve kapıda sonuna kadar okunup EN SONUNDA onaylanan belge mi?
  ///
  /// Kullanıcı kararı (2026-10-05): *"Tüm hepsini içinden onaylatmak çok
  /// uzun bir process gibi oldu."* 1.3'te dört belgenin dördü sonuna kadar
  /// okutuluyordu. 1.4'ten beri YALNIZ Açık Rıza Metni:
  /// - rıza en sıkı tutulması gereken metindir (KVKK m.3: "belirli bir
  ///   konuya ilişkin, bilgilendirilmeye dayanan ve özgür iradeyle
  ///   açıklanan") ve kısadır; rıza metnin sonundaki düğmeyle verilir,
  ///   başka hiçbir beyanla paketlenmez;
  /// - Kullanım Koşulları sözleşmedir: kabul tek açık eylemle (kutu)
  ///   alınır, okuma şartı kabulün geçerliliğini artırmıyordu;
  /// - Gizlilik Politikası ve KVKK Aydınlatma Metni bilgilendirmedir: KVKK
  ///   Kurumu aydınlatmanın rıza gibi "onaylatılmasını" önermez — sunulur,
  ///   kutu cümlesi "bilgilendirildim" der.
  /// Diğer üçü bağlantıdır, salt okunur açılır ([nitelik]).
  bool get sonunaKadarOkunur => this == acikRiza;

  /// Onay kaydının `degiskenler.nitelik` alanı — kaydın neyin kanıtı
  /// olduğunu kendisi söylesin: `kabul` (sözleşme, kutuyla), `bilgilendirme`
  /// (sunuldu; onaya bağlı değil), `acik_riza` (metnin sonunda verildi).
  String get nitelik => switch (this) {
        kosullar => 'kabul',
        gizlilik || kvkk => 'bilgilendirme',
        acikRiza => 'acik_riza',
      };

  /// Kutuyla kabul edilen ya da kutuda "bilgilendirildim" denen belgeler
  /// (Koşullar, Gizlilik, KVKK). Bunlardan biri eksikse kapı kutuyu sorar.
  static List<YasalBelge> get kutuylaAlinanlar =>
      [for (final b in values) if (!b.sonunaKadarOkunur) b];

  static final Map<YasalBelge, List<LegalBlock>> _bloklar = {};

  /// Şablon bloklar (yer tutucular doldurulmamış), süreç başına bir kez.
  List<LegalBlock> get sablonBloklari =>
      _bloklar[this] ??= List.unmodifiable(yasalMdBloklari(md));

  static YasalBelge? turden(String tur) {
    for (final b in values) {
      if (b.tur == tur) return b;
    }
    return null;
  }
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
  /// `LegalDocs.yerTutucuDegerleri`); bilinmiyorsa [rizaUlkeBilinmiyor].
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

  /// Kanonik, yer tutucuları doldurulmamış metin. Belgelerde (1.2+) md'nin
  /// kendisi; 1.1 belge satırları eski blok biçimindeydi (0102), onlara
  /// dokunulmaz.
  final String govde;

  /// Metnin KENDİSİNDE yazan yürürlük tarihi (`yyyy-mm-dd`). Metin tarih
  /// yazmıyorsa null — tarih uydurulmaz.
  final String? yururlukTarihi;

  /// sha256(utf8(govde)), küçük harf hex. Sunucudaki
  /// `encode(sha256(convert_to(govde, 'UTF8')), 'hex')` ile aynı.
  String get hash => sha256.convert(utf8.encode(govde)).toString();

  String get anahtar => '$tur/$surum/$dil';

  /// Gövdede geçen yer tutucuların adları (`SUPABASE_ULKE`…).
  Set<String> get yerTutuculari => yasalMdYerTutuculari(govde);

  /// `yasal_onay_kaydet` RPC'sinin bir öğesi.
  Map<String, dynamic> rpcOgesi(
          [Map<String, Object?> degiskenler = const {}]) =>
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

/// ## Metin değişince ne yapılır (sürüm artırma süreci, 2026-10-04)
/// Kullanıcı kararı: *"Metin değişirse her user'ın onayladığı rıza metni
/// neyse o şekilde tutulması. Metin değiştikçe eski rıza metinleri de DB'de
/// tutulmalı. Eski rıza metnini onaylayanlar için ilk login'de güncel
/// doküman sunulup onay istenmeli."* ve *"Webdekiyle de her zaman
/// eşleyelim."* Bunun için:
///
/// **Metin gerçeği yazar (kullanıcı kuralı 2026-10-04):** *"mahkemeye bişey
/// sormayacağız, yeni bir versiyon geldiğinde sürüm güncelleyip bunu
/// müşteriye onaylatacağız. Ve sözleşmeler ve rızalarda uygulamada ne varsa
/// uyumlu olmalı."* Gerçeğin kaynağı kod ve migration'lardır. Yeni veri
/// işleme, üçüncü taraf ya da saklama süresi ekleyen her değişiklik AYNI
/// değişiklikte ilgili md'yi günceller ve aşağıdaki adımları izler. 1.2,
/// yayımlanmış web metninin uygulamaya karşı denetlenmiş hâlidir (0103).
///
/// **Belgeler** (Koşullar, Gizlilik, KVKK, Açık Rıza):
/// 1. `legal/tr/<BELGE>.md`'yi düzenle VE künyesini güncelle: "**Sürüm:**"
///    satırını artır (açık rıza metninde iki yerde), "**Yürürlük tarihi:**"
///    ve "**Son güncelleme:**" o günün tarihi. Çevirisi olan belgelerde
///    `legal/en/<BELGE>.md`'yi de çevir; "**Version:**" ve "**Source:** TR
///    x" satırları yeni TR sürümünü yazsın. Kapının "Neler değişti" notunu
///    (`yasalKapiDegisiklikNotu`, iki .arb + `flutter gen-l10n`) yaz.
/// 2. `python docs/_build_legal.py` → web HTML'i + `lib/config/
///    yasal_belge_kaynaklari.g.dart` (uygulamanın sabiti).
/// 3. `flutter test --run-skipped --tags arac tool/yasal_metin_uret_test.dart`
///    → `build/yasal_metin_ekleri.sql`.
/// 4. Çıktıyı YENİ bir migration'a koy (iki sunucuya birlikte). Eski satıra
///    DOKUNMA: `yasal_metinler` değişmezdir, eski onaylar o metni gösterir.
/// 5. `flutter test test/yasal_metin_kilidi_test.dart
///    test/yasal_web_esleme_test.dart` yeşil olmalı.
/// 6. Dağıtım sırası: migration iki sunucuda → `sema_esitlik.py` → ancak
///    sonra bu istemci yayına (ters sırada yeni istemcinin onayı "yasal
///    metin yok" diye reddedilir ve kapı her açılışta yeniden sorar). Web
///    `main`'e girince Pages'te yayınlanır. Yeni sürüm yayına çıkınca eski
///    sürümü onaylamış her kullanıcı bir sonraki açılışta yeniden onay
///    kapısını (`YasalOnayKapisiScreen`, bayrak `yasal_kapi_en_yeni`)
///    görür; eski onay satırı ve eski metin satırı DB'de aynen kalır.
///
/// **Kutu / Zirve:** kutu metni değişirse [YasalMetinKatalogu.kutuSurumu],
/// Zirve kartı değişirse `LeaderboardService.zirveRizaMetniSurumu`; sonra
/// 3–6.
///
/// ⚠️ Geçmiş: 2026-05-11 ile 2026-10-04 arasında belgeler "Sürüm: 1.0"
/// etiketiyle BİRDEN ÇOK kez değişti (Zirve bölümleri, sunucu ülkesi).
/// O metinler hiçbir onaya bağlı değildi; git geçmişinden "1.0" diye
/// arşiv satırı UYDURULMADI — DB'deki ilk belge sürümü 1.1'dir (uygulamanın
/// kısaltılmış kopyası). 1.2 (0103): web'deki tam metin; Açık Rıza Metni
/// ayrı tür olarak 1.2 ile başlar. Web'in "1.0" etiketli eski metinleri de
/// arşivlenmedi (onaya bağlı değillerdi). 1.3 (0105, 2026-10-05): Auth
/// güvenlik kaydı 90 gün + anonim silme kaydı 3 yıl (ikisi de cron'la
/// silinir) ve zorunlu okumanın gerçeği ("her metin tam gösterilir,
/// sonuna kadar okunur, en altta onaylanır"); dört belge birlikte arttı.
/// 1.4 (0109, 2026-10-05, okuma sadeleştirme): yalnız Açık Rıza Metni
/// sonuna kadar okunur ([YasalBelge.sonunaKadarOkunur]); Koşullar kutuyla
/// kabul edilir, Gizlilik ve KVKK bilgilendirme olarak sunulur. Dört
/// belgenin dördü bunu anlatan cümlelerle arttı; kutu 1.1.
/// 1.5 (0120, 2026-10-05, varlık notları): Koşullar, Gizlilik ve KVKK —
/// not geri bildirimi (0117), Premium hakkı (0116) ve Anthropic (yalnız
/// piyasa ölçümü, kişisel veri gitmez). Kişisel veri yeni bir alıcıya
/// aktarılmadığı için Açık Rıza Metni 1.4'te kaldı; kapı rızayı yeniden
/// okutmaz.
abstract final class YasalMetinKatalogu {
  /// Tek kutunun sürümü — kutu cümlesi değişince artar.
  ///
  /// 1.0'a kadar `disclaimerVersion`'a bağlıydı (kutu başlığı `v1.0`
  /// yazıyordu, yatırım uyarısıyla aynı sayı). 1.1'de (2026-10-05) kutu
  /// cümlesi değişti — açık rıza çıktı, Gizlilik/KVKK "bilgilendirildim"
  /// oldu — ama yatırım uyarısı değişmedi; `disclaimerVersion`'ı artırmak
  /// `disclaimer_acceptances` kapısını herkese yeniden açardı. Ayrıldı.
  ///
  /// ## Karar: aynı tür (`kayit_tek_kutu`), yeni sürüm; 1.0 tamam SAYILMAZ
  /// - Aynı tür: kutu aynı yerde aynı işi görür (kayıt/kapı taahhüdü). Tür
  ///   check'i ve RPC'nin kanal–tür eşlemesi değişmez (fonksiyon gövdesine
  ///   dokunulmaz); her sürümün metni `yasal_metinler`'de kendi satırında
  ///   durduğu için 1.0'ın rıza içerdiği, 1.1'in içermediği kayıttan okunur.
  ///   Eski istemci de doğru davranır: `>=` kuralıyla 1.1'i kendi 1.0'ının
  ///   yerine sayar; sunucuda 1.1'i görünce `uygulamaEski` kapıyı açmaz.
  /// - 1.0 tamam sayılmaz: Koşullar 1.4'ün kabulü bu kutuyla verilir, kapı
  ///   1.4 için herkese zaten bir kez açılacak ve kutuyu o tek seferde
  ///   sorar — ek yük yok, çift onay yok (iki ayrı ekran olmaz). 1.0'ı
  ///   tamam saymak, kutusu 1.0 olan bir hesabın Koşullar 1.4 kabulünü
  ///   kutusuz bırakabilirdi (ör. belgeleri başka yoldan 1.4'e gelen).
  static const kutuSurumu = '1.1';

  /// Eski iki kutunun (`kayit_kutu_kosullar`, `kayit_kutu_riza`) sürümü —
  /// 2026-10-04'te kalktılar; metinleri onları onaylamış kullanıcıların
  /// kayıtları için katalogda ve DB'de durur. Değişmez.
  static const eskiKutuSurumu = disclaimerVersion;

  /// Bir belgenin katalog kaydı — gövde md'nin kendisi (şablon).
  static YasalMetin belge(YasalBelge b) => YasalMetin(
        tur: b.tur,
        surum: b.surum,
        dil: 'tr',
        baslik: b.baslik,
        govde: b.md,
        yururlukTarihi: b.yururluk,
      );

  static YasalMetin kosullar() => belge(YasalBelge.kosullar);
  static YasalMetin gizlilik() => belge(YasalBelge.gizlilik);
  static YasalMetin kvkk() => belge(YasalBelge.kvkk);
  static YasalMetin acikRiza() => belge(YasalBelge.acikRiza);

  /// Onay satırının `degiskenler`'i için: [tum] gösterim değerlerinden
  /// yalnız [m]'nin gövdesinde geçen yer tutucular. Koşullar ülke yazmıyor;
  /// ona ülke yazmak "bu metinde ülke gösterildi" diye yanlış ispat olurdu.
  static Map<String, Object?> belgeDegiskenleri(
          YasalMetin m, Map<String, String> tum) =>
      {
        for (final ad in m.yerTutuculari)
          if (tum.containsKey(ad)) ad: tum[ad],
      };

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
        surum: eskiKutuSurumu,
        dil: 'tr',
        baslik: KayitKutuMetni.kosulBaslik,
        govde: '${KayitKutuMetni.kosulBaslik}\n\n'
            '${KayitKutuMetni.kosulGovde}\n\n'
            '${KayitKutuMetni.kosulCumle}',
      );

  static YasalMetin kayitKutuRiza() => YasalMetin(
        tur: YasalTur.kayitKutuRiza,
        surum: eskiKutuSurumu,
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
          '${tekKutuCumlesi(l)}',
    );
  }

  /// Tek kutunun cümlesi, ekranda okunduğu düz hâliyle (üç belge adı
  /// ekranda bağlantıdır). Kutu 1.1 (2026-10-05): "Kullanım Koşulları'nı
  /// kabul ediyorum ve 18 yaşından büyüğüm. Gizlilik Politikası ve KVKK
  /// Aydınlatma Metni ile bilgilendirildim." — açık rıza İÇERMEZ (rıza
  /// başka beyanla paketlenmez; `test/zorunlu_okuma_test` kilitler). 1.0
  /// cümlesi Koşullar + KVKK'yı "kabul" ediyor ve aynı cümlede yurt dışı
  /// aktarıma açık rıza veriyordu (metni DB'de, `kayit_tek_kutu/1.0`).
  static String tekKutuCumlesi(AppLocalizations l) => l.tekOnayCumle(
      l.tekOnayKosullarBaglanti,
      l.tekOnayGizlilikBaglanti,
      l.tekOnayKvkkBaglanti);

  /// Yeniden onay kapısının aradığı belgeler — katalogdaki GÜNCEL sürümleri.
  /// Dördü de aranır (bilgilendirme belgeleri de: sunulduklarının kaydı
  /// tutulur); NASIL alındıkları [YasalBelge.sonunaKadarOkunur]'a bağlı.
  static List<YasalMetin> zorunluBelgeler() =>
      [for (final b in YasalBelge.values) belge(b)];

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
        ...zorunluBelgeler(),
        yatirimUyarisi(),
        kayitKutuKosullar(),
        kayitKutuRiza(),
        for (final d in tekKutuDilleri) kayitTekKutu(d),
        zirveRiza(),
      ];
}
