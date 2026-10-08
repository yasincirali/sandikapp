import 'package:flutter/foundation.dart';

import 'yasal_metin_katalogu.dart';
import 'yasal_onay_service.dart';

/// Kayıt ekranının ve yeniden onay kapısının ADIM düzeni — saf, test edilir
/// (`yasal_adim_plani_test`).
///
/// ## Karar (kullanıcı, 2026-10-05: seçenek "C · Adım adım")
/// Okunması zorunlu metin, bilgi amaçlı belgelerle aynı listede tek satır
/// olarak kayboluyordu. Artık zorunlu olan her şey numaralı bir ADIM:
/// 1. Yatırım Uyarısı — sonuna kadar oku, onayla;
/// 2. Açık Rıza Metni — sonuna kadar oku, rızanı metnin sonunda ver;
/// 3. Tek kutu (`kayit_tek_kutu` 1.1) — Koşulların kabulü + 18+ +
///    Gizlilik/KVKK ile "bilgilendirildim". Metni değişmedi; yalnız akışın
///    son adımı oldu.
/// Sıra her yüzeyde aynı: uyarı → Açık Rıza → kutu. Bilgi amaçlı belgeler
/// (Koşullar, Gizlilik, KVKK; rızası geçerliyse Açık Rıza) adım değildir,
/// katlanır "Diğer belgeler" bölümünde bağlantıdır.
///
/// ## Yalnız eksik olan görünür
/// Ekranda yalnız kullanıcının GÜNCEL sürümünü onaylamadığı metinlerin
/// adımı vardır; onaylanmış olan hiç gösterilmez. Hangi türün eksik
/// olduğuna bu sınıf karar VERMEZ — [YasalKapiDurumu] (sunucudaki etkin
/// onaylar) ve `_AuthGate`'in yatırım uyarısı kararı verir; burası yalnız
/// o kümeyi adımlara çevirir. Kayıt ve onay YAZIMI değişmedi (aynı RPC,
/// aynı `degiskenler`): adım düzeni yalnız gösterimdir.
enum YasalAdimTuru {
  yatirimUyarisi(YasalTur.yatirimUyarisi),
  acikRiza(YasalTur.acikRiza),
  kutu(YasalOnayService.kutuAnahtari);

  const YasalAdimTuru(this.anahtar);

  /// Ekranın tuttuğu "onaylananlar" kümesindeki anahtar (okunan metinler
  /// için `YasalTur`; kutu için [YasalOnayService.kutuAnahtari]).
  final String anahtar;

  /// Sonuna kadar okunup metnin sonunda onaylanan adım mı (kutu değil).
  bool get okunur => this != kutu;
}

/// Bir adımın ekrandaki hâli.
enum YasalAdimDurumu {
  /// Tamamlandı: yeşil onay dairesi.
  tamam,

  /// Sıradaki (ilk eksik) adım: amber numara + açıklama + eylem.
  aktif,

  /// Sırası gelmedi: sönük numara, yalnız başlık.
  bekliyor,
}

/// Kapı ekranının başlığı.
enum YasalKapiBasligi {
  /// Hiç önceki onay yok (Apple/Google ile ilk giriş, 0102 öncesi hesap):
  /// "Yasal belgeler".
  ilk,

  /// Tek belge güncellendi: "Güncellenen belge".
  tekBelge,

  /// Birden çok belge: "Güncellenen belgeler".
  cokBelge,
}

@immutable
class YasalAdim {
  const YasalAdim(this.tur, {this.guncellenenler = const []});

  final YasalAdimTuru tur;

  /// Yalnız kutu adımında: kutuyla alınan belgelerden (Koşullar, Gizlilik,
  /// KVKK) eski sürümü onaylı olup güncel sürümü eksik olanlar. Boşsa adım
  /// "Kullanım Koşulları'nı kabul et" der (kayıt, ilk kez); doluysa
  /// "`belge` güncellendi" der, belge adı kutu cümlesinde vurgulanır ve
  /// adımın içinde bağlantı olur (okumak zorunlu değil).
  final List<YasalBelge> guncellenenler;
}

@immutable
class YasalAdimPlani {
  const YasalAdimPlani._({
    required this.adimlar,
    required this.digerBelgeler,
    this.kapiBasligi,
  });

  /// Sırayla: uyarı → Açık Rıza → kutu (yalnız gerekenler).
  final List<YasalAdim> adimlar;

  /// Katlanır "Diğer belgeler (bilgi amaçlı)" bölümünün bağlantıları —
  /// adımda (ya da kutu adımının "güncellendi" bağlantısında) olmayan
  /// belgeler, [YasalBelge] sırasıyla.
  final List<YasalBelge> digerBelgeler;

  /// Kapı başlığı; kayıtta `null`.
  final YasalKapiBasligi? kapiBasligi;

  static YasalAdimPlani _kur({
    required bool uyari,
    required bool riza,
    required bool kutu,
    List<YasalBelge> guncellenenler = const [],
    YasalKapiBasligi? kapiBasligi,
  }) {
    final adimlar = [
      if (uyari) const YasalAdim(YasalAdimTuru.yatirimUyarisi),
      if (riza) const YasalAdim(YasalAdimTuru.acikRiza),
      if (kutu) YasalAdim(YasalAdimTuru.kutu, guncellenenler: guncellenenler),
    ];
    return YasalAdimPlani._(
      adimlar: List.unmodifiable(adimlar),
      digerBelgeler: List.unmodifiable([
        for (final b in YasalBelge.values)
          if (!(riza && b == YasalBelge.acikRiza) &&
              !(kutu && guncellenenler.contains(b)))
            b,
      ]),
      kapiBasligi: kapiBasligi,
    );
  }

  /// Yeni kayıt: üç adım — uyarı, Açık Rıza, kutu.
  factory YasalAdimPlani.kayit() =>
      _kur(uyari: true, riza: true, kutu: true);

  /// Yeniden onay kapısı: yalnız eksik olanlar.
  ///
  /// - Uyarı: [yatirimUyarisiDahil] (`disclaimer_acceptances` kapısı;
  ///   `_AuthGate` karar verir, iki yasal ekran art arda gelmesin diye
  ///   buraya girer).
  /// - Açık Rıza: [YasalKapiDurumu.rizaEksik].
  /// - Kutu: [YasalKapiDurumu.kutuGerekli] (kutu ya da kutuyla alınan bir
  ///   belge eksik) — Koşulların kabulü ve "bilgilendirildim" belge sonunda
  ///   değil kutuyla verilir; kutusuz kapı onları onaysız yazardı.
  factory YasalAdimPlani.kapi(
    YasalKapiDurumu durum, {
    required bool yatirimUyarisiDahil,
  }) {
    final guncellenenler = [
      if (durum.guncellemeMi)
        for (final b in YasalBelge.kutuylaAlinanlar)
          if (durum.eksik.contains(b.tur) &&
              durum.oncekiSurum.containsKey(b.tur))
            b,
    ];
    // Başlıktaki tekil/çoğul: güncel sürümü onaylanacak belge sayısı
    // (yatırım uyarısı dahil). Yalnız kutu cümlesi güncellendiyse (belge
    // yok) de tek "belge" sayılır — sorulan tek bir metin var.
    final belgeSayisi =
        YasalBelge.values.where((b) => durum.eksik.contains(b.tur)).length +
            (yatirimUyarisiDahil ? 1 : 0);
    return _kur(
      uyari: yatirimUyarisiDahil,
      riza: durum.rizaEksik,
      kutu: durum.kutuGerekli,
      guncellenenler: guncellenenler,
      kapiBasligi: !durum.guncellemeMi
          ? YasalKapiBasligi.ilk
          : (belgeSayisi > 1
              ? YasalKapiBasligi.cokBelge
              : YasalKapiBasligi.tekBelge),
    );
  }

  /// Adım [a] tamamlandı mı: okunan metin [onaylananlar]'da (sonuna kadar
  /// okunup sonunda onaylandı), kutu [kutuIsaretli].
  static bool tamamMi(
    YasalAdim a, {
    required Set<String> onaylananlar,
    required bool kutuIsaretli,
  }) =>
      a.tur == YasalAdimTuru.kutu
          ? kutuIsaretli
          : onaylananlar.contains(a.tur.anahtar);

  /// Her adımın durumu: tamamlananlar [YasalAdimDurumu.tamam], ilk eksik
  /// [YasalAdimDurumu.aktif], sonrakiler [YasalAdimDurumu.bekliyor].
  /// Eylem yalnız aktif adımda olduğundan adımlar sırayla tamamlanır.
  List<YasalAdimDurumu> durumlar({
    required Set<String> onaylananlar,
    required bool kutuIsaretli,
  }) {
    var aktifVar = false;
    final sonuc = <YasalAdimDurumu>[];
    for (final a in adimlar) {
      if (tamamMi(a, onaylananlar: onaylananlar, kutuIsaretli: kutuIsaretli)) {
        sonuc.add(YasalAdimDurumu.tamam);
      } else if (!aktifVar) {
        aktifVar = true;
        sonuc.add(YasalAdimDurumu.aktif);
      } else {
        sonuc.add(YasalAdimDurumu.bekliyor);
      }
    }
    return sonuc;
  }

  /// Tamamlanmamış adımlar, sırayla.
  List<YasalAdim> eksikler({
    required Set<String> onaylananlar,
    required bool kutuIsaretli,
  }) =>
      [
        for (final a in adimlar)
          if (!tamamMi(a, onaylananlar: onaylananlar, kutuIsaretli: kutuIsaretli))
            a,
      ];

  /// Son eylem ("Kayıt Ol" / "Okudum, kabul ediyorum") yalnız bu `true`
  /// iken çalışır.
  bool hepsiTamam({
    required Set<String> onaylananlar,
    required bool kutuIsaretli,
  }) =>
      eksikler(onaylananlar: onaylananlar, kutuIsaretli: kutuIsaretli).isEmpty;

  bool get kutuVar => adimlar.any((a) => a.tur == YasalAdimTuru.kutu);

  bool get rizaVar => adimlar.any((a) => a.tur == YasalAdimTuru.acikRiza);

  bool get uyariVar =>
      adimlar.any((a) => a.tur == YasalAdimTuru.yatirimUyarisi);
}
