/// Mevduat ve BES sözleşmeleri — fiyatlamanın GİRDİSİ, bakiye değil.
///
/// ## Veri nerede durur (kullanıcı sorusu, 2026-09-30)
/// *"Vadeli mevduat ve BES'in hangi fonlarda değerlendiği bilgileri nasıl
/// tutulacak?"*
///
///   · **Bakiye** her türde olduğu gibi `assets` lot defterindedir: para
///     yatırma bir alım lotu, çekim bir satım lotudur. Toplam, dağılım,
///     kâr/zarar ve ortak görünümü o yoldan çalışır.
///   · **Sözleşme** (`sozlesmeler`, 0088) kurumu, başlangıcı ve BES'te katkı
///     planını (aylık tutar, gün, fon dağılımı, devlet katkısı fonu) taşır.
///     Lot `sozlesme_id` ile bağlıdır.
///   · **Mevduat dönemleri** (`mevduat_donemleri`) yenileme zinciridir: her
///     dönemin faizi, stopajı ve vadesi ayrı satırdır. Birim değer bunlardan
///     hesaplanır (`mevduat_hesabi.dart`).
///   · **BES'in fonlardaki payı** lotlardadır: her fon bir `bes` lotu
///     (`TEFAS:KOD`, miktar = pay adedi), devlet katkısı `subCategory = dk`
///     lotu. [Sozlesme.fonDagilimi] yalnızca YENİ katkının nasıl
///     bölüneceğinin talimatıdır.
library;

/// Sözleşme türü — `sozlesmeler.tur`.
enum SozlesmeTuru {
  mevduat,
  bes;

  static SozlesmeTuru fromDb(String v) =>
      v == 'bes' ? SozlesmeTuru.bes : SozlesmeTuru.mevduat;
}

/// BES katkı talimatında tek fon: TEFAS emeklilik fonu kodu + yüzde.
class FonPayi {
  const FonPayi({required this.kod, required this.oran});

  /// Üç harfli TEFAS kodu (`AH5`) — öneksiz.
  final String kod;

  /// Yüzde (60 = %60).
  final double oran;

  Map<String, dynamic> toJson() => {'kod': kod, 'oran': oran};

  static FonPayi? fromJson(Object? j) {
    if (j is! Map) return null;
    final kod = (j['kod'] as String?)?.trim().toUpperCase();
    final oran = (j['oran'] as num?)?.toDouble();
    if (kod == null || kod.isEmpty || oran == null || oran <= 0) return null;
    return FonPayi(kod: kod, oran: oran);
  }
}

/// BES lotunun alt kategorisi: devlet katkısı mı, kendi katkın mı.
///
/// `positionKey` BES'te bunu ANAHTARA katar: aynı fonda (şirket devlet
/// katkısını katılımcının fonlarından birine de yatırabilir) iki birikim
/// tek pozisyonda toplanırsa "senin katkın" ile "devletin" karışırdı.
abstract final class BesAltKategori {
  static const katki = 'katki';
  static const devletKatkisi = 'dk';
}

class Sozlesme {
  Sozlesme({
    required this.id,
    required this.userId,
    required this.tur,
    required this.kurum,
    required this.baslangic,
    this.aylikKatki,
    this.katkiGunu,
    this.fonDagilimi = const [],
    this.dkFonKodu,
    this.kapandi,
    this.olusturuldu,
    this.otomatikKatki = false,
    this.otomatikKatkiSon,
    this.otomatikKatkiBekleyen,
  });

  final String id;
  final String userId;
  final SozlesmeTuru tur;
  final String kurum;

  /// Mevduat: ilk dönemin başı. BES: sisteme giriş (hak ediş buna bağlı).
  final DateTime baslangic;

  final double? aylikKatki;

  /// Ayın kaçında katkı çekilir (1–28).
  final int? katkiGunu;

  final List<FonPayi> fonDagilimi;

  /// Devlet katkısının yatırıldığı TEFAS EMK fonu; bilinmiyorsa `null`.
  final String? dkFonKodu;

  final DateTime? kapandi;

  /// Kaydın yazıldığı an (`created_at`). BES'te bu **açılış anıdır**:
  /// kullanıcı o güne kadarki ana parayı ve getiriyi o an girdi. Açılıştan
  /// önceki geçmiş fon serisinden değil, açılış değerinde DÜZ çizilir
  /// (bkz. `BesAcilis`). Sunucu doldurur; istemcide yeni yazılan kayıtta
  /// `besAc` aynı anı verir. Eski satırda da dolu (sütun 0088'den beri var).
  final DateTime? olusturuldu;

  /// Katkı günü gelince aylık katkı otomatik yazılır (0096; kullanıcı
  /// isteği 2026-10-01). Yazma `SozlesmeNotifier.otomatikKatkilariIsle`'de,
  /// hangi günlerin yazılacağı `BesHesabi.otomatikKatkiGunleri`'nde.
  final bool otomatikKatki;

  /// Otomatik işlemin baktığı son gün (imleç). Bu günden SONRAKİ katkı
  /// günleri yazılır; kullanıcı otomatik katkıyı silerse geri gelmez.
  final DateTime? otomatikKatkiSon;

  /// Otomatik yazılan, kullanıcının henüz onaylamadığı katkının günü.
  /// Kart "tutarı güncellemek ister misin" sorusunu buna bakarak sorar.
  final DateTime? otomatikKatkiBekleyen;

  bool get acik => kapandi == null;

  /// Aynı sözleşme, kapanış tarihiyle. Diğer alanlar (açılış anı dahil)
  /// korunur — eskiden kapanış yeni bir nesne kuruyor, eklenen alanlar
  /// unutulunca sessizce düşüyordu.
  Sozlesme kopya({
    DateTime? kapandi,
    List<FonPayi>? fonDagilimi,
    double? aylikKatki,
    bool? otomatikKatki,
    DateTime? otomatikKatkiSon,
    // Kayıt: `null` "değiştirme" demek; bekleyeni SİLMEK için
    // [bekleyenSil].
    DateTime? otomatikKatkiBekleyen,
    bool bekleyenSil = false,
  }) =>
      Sozlesme(
        id: id,
        userId: userId,
        tur: tur,
        kurum: kurum,
        baslangic: baslangic,
        aylikKatki: aylikKatki ?? this.aylikKatki,
        katkiGunu: katkiGunu,
        fonDagilimi: fonDagilimi ?? this.fonDagilimi,
        dkFonKodu: dkFonKodu,
        kapandi: kapandi ?? this.kapandi,
        olusturuldu: olusturuldu,
        otomatikKatki: otomatikKatki ?? this.otomatikKatki,
        otomatikKatkiSon: otomatikKatkiSon ?? this.otomatikKatkiSon,
        otomatikKatkiBekleyen: bekleyenSil
            ? null
            : otomatikKatkiBekleyen ?? this.otomatikKatkiBekleyen,
      );

  Map<String, dynamic> toSupabase() => {
        'id': id,
        'user_id': userId,
        'tur': tur.name,
        'kurum': kurum.trim(),
        'baslangic': gunMetni(baslangic),
        'para_birimi': 'TRY',
        'aylik_katki': aylikKatki,
        'katki_gunu': katkiGunu,
        'fon_dagilimi': tur == SozlesmeTuru.bes && fonDagilimi.isNotEmpty
            ? [for (final f in fonDagilimi) f.toJson()]
            : null,
        'dk_fon_kodu': dkFonKodu,
        'kapandi': kapandi == null ? null : gunMetni(kapandi!),
        // 0096 sütunları YALNIZ kullanılıyorsa gönderilir: migration iki
        // sunucuya gitmeden yayınlanan istemci, sütunu olmayan şemaya
        // yazınca her BES/mevduat açılışı PGRST204 ile düşerdi. Kapatma
        // (true → false) imleç dolu olduğu için yine gönderilir.
        if (otomatikKatki ||
            otomatikKatkiSon != null ||
            otomatikKatkiBekleyen != null) ...{
          'otomatik_katki': otomatikKatki,
          'otomatik_katki_son':
              otomatikKatkiSon == null ? null : gunMetni(otomatikKatkiSon!),
          'otomatik_katki_bekleyen': otomatikKatkiBekleyen == null
              ? null
              : gunMetni(otomatikKatkiBekleyen!),
        },
      };

  factory Sozlesme.fromSupabase(Map<String, dynamic> m) => Sozlesme(
        id: m['id'] as String,
        userId: (m['user_id'] as String?) ?? '',
        tur: SozlesmeTuru.fromDb(m['tur'] as String),
        kurum: (m['kurum'] as String?) ?? '',
        baslangic: gunOku(m['baslangic'] as String),
        aylikKatki: (m['aylik_katki'] as num?)?.toDouble(),
        katkiGunu: (m['katki_gunu'] as num?)?.toInt(),
        fonDagilimi: [
          for (final j in (m['fon_dagilimi'] as List?) ?? const [])
            if (FonPayi.fromJson(j) case final f?) f,
        ],
        dkFonKodu: m['dk_fon_kodu'] as String?,
        kapandi: m['kapandi'] == null ? null : gunOku(m['kapandi'] as String),
        olusturuldu: m['created_at'] == null
            ? null
            : DateTime.tryParse(m['created_at'] as String)?.toLocal(),
        otomatikKatki: m['otomatik_katki'] == true,
        otomatikKatkiSon: m['otomatik_katki_son'] == null
            ? null
            : gunOku(m['otomatik_katki_son'] as String),
        otomatikKatkiBekleyen: m['otomatik_katki_bekleyen'] == null
            ? null
            : gunOku(m['otomatik_katki_bekleyen'] as String),
      );
}

/// Mevduatın tek dönemi — yenileme zincirinin halkası.
class MevduatDonemi {
  const MevduatDonemi({
    required this.id,
    required this.sozlesmeId,
    required this.baslangic,
    required this.vadeSonu,
    required this.yillikFaiz,
    required this.stopaj,
  });

  final String id;
  final String sozlesmeId;
  final DateTime baslangic;

  /// `null` = vadesiz / günlük faizli hesap.
  final DateTime? vadeSonu;

  /// Yıllık brüt faiz, yüzde.
  final double yillikFaiz;

  /// Stopaj, yüzde.
  final double stopaj;

  bool get vadesiz => vadeSonu == null;

  /// Vadeli dönemin gün sayısı; vadesizde `null`.
  int? get gun => vadeSonu?.difference(baslangic).inDays;

  Map<String, dynamic> toSupabase(String userId) => {
        'id': id,
        'sozlesme_id': sozlesmeId,
        'user_id': userId,
        'baslangic': gunMetni(baslangic),
        'vade_sonu': vadeSonu == null ? null : gunMetni(vadeSonu!),
        'yillik_faiz': yillikFaiz,
        'stopaj': stopaj,
      };

  factory MevduatDonemi.fromSupabase(Map<String, dynamic> m) => MevduatDonemi(
        id: m['id'] as String,
        sozlesmeId: m['sozlesme_id'] as String,
        baslangic: gunOku(m['baslangic'] as String),
        vadeSonu:
            m['vade_sonu'] == null ? null : gunOku(m['vade_sonu'] as String),
        yillikFaiz: (m['yillik_faiz'] as num).toDouble(),
        stopaj: (m['stopaj'] as num).toDouble(),
      );
}

/// `date` sütunu biçimi: `2026-09-30`. Saat YOK — mevduat günle işler ve
/// saat dilimi kayması (UTC'ye çevrilen yerel gece yarısı bir önceki güne
/// düşer) vade gününü kaydırırdı.
String gunMetni(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// `2026-09-30` → yerel gece yarısı.
DateTime gunOku(String s) {
  final p = s.split('T').first.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}
