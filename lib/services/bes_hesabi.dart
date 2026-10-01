import '../models/sozlesme.dart';

/// BES kuralları — hak ediş, devlet katkısı oranı ve yıllık sınır.
///
/// Saf fonksiyonlar; ekran ve provider hesap yapmaz, buradan sorar.
///
/// ## Hak ediş (4632 sayılı kanun, 2016 sonrası tablo)
/// Sistemde kalınan süreye göre devlet katkısının çıkışta eline geçen payı:
/// 3 yıldan az %0, 3–6 yıl %15, 6–10 yıl %35, 10 yıl ve üstü %60. 10 yıl +
/// 56 yaş (ya da emeklilik, vefat, maluliyet) %100'dür; doğum tarihi
/// SAKLANMADIĞI için burada %60'ta durur ve ekran bunu söyler.
///
/// ## Devlet katkısı oranı ve sınırı
/// 2026-01-01'den itibaren %20 (Cumhurbaşkanı kararı, RG 2026-01-07;
/// önce %30). Yıllık üst sınır o yılın brüt asgari ücret toplamının oran
/// kadarıdır: 2026'da 396.360 × %20 = ₺79.272. Yeni yılın tutarı Ocak'ta
/// asgari ücretle belli olur; tabloda olmayan yıl için sınır `null` döner —
/// uydurma sınır uygulanmaz, ekran kullanıcıya düzenlenebilir tutar gösterir.
///
/// ## Sunucu parametreleri (2026-10-01, kullanıcı: "elle tanımlamam
/// mantıklı değil")
/// Yıllık sınır ve oran artık sunucudaki `bes_devlet_katkisi` tablosundan
/// gelir (0089; `bes-parametre` her gün EGM'nin resmî sayfasından çeker ve
/// katkı × oran = azami tutarlılığını doğrulamadan yazmaz). İstemci
/// [uzakParametreler] ile yükler; sunucu cevap vermezse aşağıdaki sabit
/// tablo ve oran merdiveni YEDEK olarak kalır.
abstract final class BesHesabi {
  /// Hak ediş basamakları: (tam yıl eşiği, yüzde).
  static const hakEdisBasamaklari = <(int, double)>[
    (0, 0),
    (3, 15),
    (6, 35),
    (10, 60),
  ];

  /// [giris]'ten [simdi]'ye TAM yıl.
  static int tamYil(DateTime giris, DateTime simdi) {
    var y = simdi.year - giris.year;
    final yilDonumu = DateTime(simdi.year, giris.month, giris.day);
    if (simdi.isBefore(yilDonumu)) y--;
    return y < 0 ? 0 : y;
  }

  /// Bugünkü hak ediş yüzdesi.
  static double hakEdisOrani(DateTime giris, DateTime simdi) {
    final y = tamYil(giris, simdi);
    var oran = 0.0;
    for (final (esik, o) in hakEdisBasamaklari) {
      if (y >= esik) oran = o;
    }
    return oran;
  }

  /// Bir sonraki basamak: kaç yıl sonra, yüzde kaç. Son basamaktaysa `null`.
  static ({int yil, double oran})? sonrakiBasamak(
      DateTime giris, DateTime simdi) {
    final y = tamYil(giris, simdi);
    for (final (esik, o) in hakEdisBasamaklari) {
      if (esik > y) return (yil: esik - y, oran: o);
    }
    return null;
  }

  /// [tarih]'te yapılan katkıya uygulanan devlet katkısı yüzdesi.
  static double devletKatkisiOrani(DateTime tarih) {
    final uzak = _uzak[tarih.year]?.oran;
    if (uzak != null) return uzak;
    if (!tarih.isBefore(DateTime(2026))) return 20;
    if (!tarih.isBefore(DateTime(2022))) return 30;
    return 25;
  }

  /// Yedek sınır tablosu — sunucu parametresi yüklenemezse (çevrimdışı ilk
  /// açılış). Yeni yıl buraya ELLE eklenmez; sunucu getirir.
  static const Map<int, double> yillikSinirTablosu = {2026: 79272};

  /// Sunucudan gelen parametreler: yıl → (azami devlet katkısı TL, oran %).
  static final Map<int, ({double sinir, double oran})> _uzak = {};

  /// `bes_devlet_katkisi` satırlarını yükler (bkz. `BesParametreleri`).
  /// Önceki yükleme tamamen değiştirilir.
  static void uzakParametreler(Map<int, ({double sinir, double oran})> m) {
    _uzak
      ..clear()
      ..addAll(m);
  }

  /// Yıllık devlet katkısı üst sınırı (TL): önce sunucu, sonra yedek tablo;
  /// ikisinde de yoksa `null` (uydurma sınır yok).
  static double? yillikSinir(int yil) =>
      _uzak[yil]?.sinir ?? yillikSinirTablosu[yil];

  /// [katki] TL'lik katkının devlet katkısı; yılın kalan sınırına kırpılır.
  ///
  /// [buYilAlinan] bu yıl bu sözleşmeye zaten yazılmış devlet katkısı.
  /// Sınır bilinmiyorsa kırpılmaz (`sinirBilinmiyor: true`) — ekran tutarı
  /// düzenlenebilir gösterir.
  static ({double tutar, bool sinirDoldu, bool sinirBilinmiyor})
      devletKatkisi({
    required double katki,
    required DateTime tarih,
    required double buYilAlinan,
  }) {
    if (katki <= 0) {
      return (tutar: 0, sinirDoldu: false, sinirBilinmiyor: false);
    }
    final ham = katki * devletKatkisiOrani(tarih) / 100;
    final sinir = yillikSinir(tarih.year);
    if (sinir == null) {
      return (tutar: ham, sinirDoldu: false, sinirBilinmiyor: true);
    }
    final kalan = sinir - buYilAlinan;
    if (kalan <= 0) {
      return (tutar: 0, sinirDoldu: true, sinirBilinmiyor: false);
    }
    return (
      tutar: ham < kalan ? ham : kalan,
      sinirDoldu: ham >= kalan,
      sinirBilinmiyor: false,
    );
  }

  /// [tutar]'ı fon dağılımına böler: `{kod: TL}`.
  ///
  /// Oranlar toplamı 100 değilse ORANLANIR (toplam korunur); boş dağılım
  /// boş harita döner. Son fon kuruş farkını üstlenir — Σ parça == bütün.
  static Map<String, double> katkiyiBol(
      double tutar, List<FonPayi> dagilim) {
    final toplamOran = dagilim.fold<double>(0, (s, f) => s + f.oran);
    if (tutar <= 0 || toplamOran <= 0) return const {};
    final out = <String, double>{};
    var dagitilan = 0.0;
    for (var i = 0; i < dagilim.length; i++) {
      final f = dagilim[i];
      final pay = i == dagilim.length - 1
          ? tutar - dagitilan
          : tutar * f.oran / toplamOran;
      out[f.kod] = (out[f.kod] ?? 0) + pay;
      dagitilan += pay;
    }
    return out;
  }

  /// Fon değişikliği planı: bugünkü birikimi [hedef] dağılıma taşır.
  ///
  /// [mevcut] fon başına elde kalan pay ve ana para (maliyet), [fiyatlar]
  /// bugünkü TEFAS fiyatı. Dönen satırlar: azalan fonda SATIŞ (pay, serbest
  /// kalan ana para), artan fonda ALIŞ (pay, taşınan ana para).
  ///
  /// ## Neden ana para taşınır, kâr realize edilmez
  /// Gerçek BES'te fon değişikliği bir satış değildir: birikim el
  /// değiştirmez, vergi doğmaz, "ödediğin katkı" aynı kalır. Satıştan
  /// serbest kalan ana para, alınan fonlara DEĞER oranında dağıtılır;
  /// böylece değişim anında Σ ana para ve Σ değer aynı kalır, kâr da.
  /// Ekran satış lotunu maliyet fiyatından yazar (gerçekleşen kâr 0) —
  /// eski sürümler de kârı çift saymaz.
  ///
  /// [esik] TL'den küçük kaymalar yok sayılır (kuruş gürültüsü yeni lot
  /// açmasın). Değişecek bir şey yoksa boş liste.
  static List<({String kod, double pay, double maliyet, bool satis})>
      fonDegisimPlani({
    required Map<String, ({double pay, double maliyet})> mevcut,
    required Map<String, double> fiyatlar,
    required List<FonPayi> hedef,
    double esik = 1,
  }) {
    final toplamOran = hedef.fold<double>(0, (t, f) => t + f.oran);
    if (toplamOran <= 0) return const [];
    var toplam = 0.0;
    final deger = <String, double>{};
    for (final e in mevcut.entries) {
      final f = fiyatlar[e.key];
      if (f == null || f <= 0 || e.value.pay <= 0) continue;
      deger[e.key] = e.value.pay * f;
      toplam += e.value.pay * f;
    }
    if (toplam <= 0) return const [];
    final hedefDeger = <String, double>{};
    for (final f in hedef) {
      hedefDeger[f.kod] =
          (hedefDeger[f.kod] ?? 0) + toplam * f.oran / toplamOran;
    }
    final kodlar = {...deger.keys, ...hedefDeger.keys};
    final satislar = <({String kod, double pay, double maliyet, bool satis})>[];
    final alimFarki = <String, double>{};
    var serbestMaliyet = 0.0;
    var serbestDeger = 0.0;
    for (final k in kodlar) {
      final fark = (hedefDeger[k] ?? 0) - (deger[k] ?? 0);
      if (fark.abs() < esik && hedefDeger.containsKey(k)) continue;
      if (fark < 0) {
        final m = mevcut[k]!;
        // Fon dağılımdan çıktıysa payın TAMAMI (kuruş artığı kalmasın).
        final pay = hedefDeger.containsKey(k)
            ? -fark / fiyatlar[k]!
            : m.pay;
        final maliyet = m.maliyet * pay / m.pay;
        serbestMaliyet += maliyet;
        serbestDeger += pay * fiyatlar[k]!;
        satislar.add((kod: k, pay: pay, maliyet: maliyet, satis: true));
      } else if (fark > 0) {
        alimFarki[k] = fark;
      }
    }
    final alimToplam = alimFarki.values.fold<double>(0, (t, x) => t + x);
    if (satislar.isEmpty || alimToplam <= 0) return const [];
    // Alımlar satıştan serbest kalan DEĞERE ölçeklenir: eşik altında
    // atlanan kuruş kaymaları Σ alım ≠ Σ satış yapmasın (değer korunur).
    final olcek = serbestDeger / alimToplam;
    return [
      ...satislar,
      for (final e in alimFarki.entries)
        (
          kod: e.key,
          pay: e.value * olcek / fiyatlar[e.key]!,
          maliyet: serbestMaliyet * e.value / alimToplam,
          satis: false,
        ),
    ];
  }

  /// Bu yıl yapılan fon değişikliği sayısı — katılımcının yılda 12 hakkı
  /// var (BES Yönetmeliği). [satisAnlari] sözleşmenin satış lotlarının
  /// anları; aynı dakikadaki satışlar tek değişikliktir. Yalnızca BİLGİ:
  /// sınır uygulamaya kurala bağlanmaz, şirket uygular.
  static int buYilFonDegisikligi(Iterable<DateTime> satisAnlari, int yil) => {
        for (final t in satisAnlari)
          if (t.year == yil)
            DateTime(t.year, t.month, t.day, t.hour, t.minute),
      }.length;

  /// Dağılım geçerli mi: en az bir fon, oranlar toplamı %100 (±0,01).
  static bool dagilimGecerli(List<FonPayi> dagilim) {
    if (dagilim.isEmpty) return false;
    final t = dagilim.fold<double>(0, (s, f) => s + f.oran);
    return (t - 100).abs() < 0.01;
  }

  /// Bu ayın katkısı bekleniyor mu: aylık tutar ve gün tanımlı, bugün o
  /// günü geçti ve bu takvim ayında sözleşmeye katkı lotu yazılmadı.
  static bool katkiBekleniyor({
    required Sozlesme s,
    required DateTime simdi,
    required Iterable<DateTime> katkiTarihleri,
  }) {
    final gun = s.katkiGunu;
    if (s.aylikKatki == null || gun == null || !s.acik) return false;
    if (simdi.day < gun) return false;
    return !katkiTarihleri
        .any((t) => t.year == simdi.year && t.month == simdi.month);
  }
}
