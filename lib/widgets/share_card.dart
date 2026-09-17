import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/asset_type.dart';
import '../services/analytics_service.dart';
import '../services/crash_reporter.dart';
import '../services/recap_service.dart' show PortfolioCharacter, RecapAsset;
import '../services/review_prompt_service.dart';
import '../services/share_card_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import 'review_prompt_sheet.dart';
import '../l10n/l10n.dart';

/// Paylaşım kartının içeriği — TUTAR YOK.
///
/// Kural (`_PaylasButonu` notu): tutarlı kart paylaşılmaz, tutarsız kart
/// paylaşılır. Yüzde, karakter, enflasyon farkı ve dilim yeter; para
/// miktarı bir kez dışarı çıktı mı geri alınamaz. `share_card_test` bu
/// dosyada para biçimleyici ve lira simgesi bulunmadığını kilitler.
///
/// ## Neden bu kadar alan (2026-09-16)
/// İlk kart dört satırdı: yüzde, karakter, enflasyon, gün. "Paylaşılacak
/// özette daha detaylı ve yararlı istatistikler" isteği üzerine kart, ekranda
/// zaten görünen ölçülerin TUTARSIZ olanlarını taşıyor: reel getiri, en iyi /
/// en zayıf varlık, artıda kapanan gün oranı, XIRR, en derin düşüş, en
/// sabırlı varlık ve tür DAĞILIMI (yalnızca oran). Her alan nullable —
/// eksik veri için kutu çizilmez, kart kendini daraltır.
///
/// [dagilim] TRY değer alır ama kart yalnızca ORANI çizer; `toTRY` ya da
/// para biçimleyici bu dosyaya girmez (kaynak taraması bunu kilitler).
@immutable
class ShareCardData {
  const ShareCardData({
    required this.baslik,
    this.tarihAraligi,
    this.degisimPct,
    this.degisimEtiketi = 'Portföy değişimi',
    this.karakter,
    this.enflasyonPuan,
    this.reelGetiriPct,
    this.enIyi,
    this.enZayif,
    this.gunSayimi,
    this.percentile,
    this.xirrPct,
    this.drawdownPct,
    this.enSabirli,
    this.enSabirliGun,
    this.takipGunu,
    this.dagilim = const {},
  });

  /// "Son 1 yıl", "2026 Özetim".
  final String baslik;

  /// Başlığın altına düşen tarih aralığı ("14 Eyl 2025 – 14 Eyl 2026").
  /// "Bu yıl" takvim yılı mı, son 12 ay mı — bunu yalnızca aralık söyler.
  final String? tarihAraligi;

  final double? degisimPct;
  final String degisimEtiketi;
  final PortfolioCharacter? karakter;
  final double? enflasyonPuan;

  /// Bileşik reel getiri (yüzde). Enflasyon satırının kuyruğuna yazılır.
  final double? reelGetiriPct;

  /// Dönemin en iyi / en zayıf varlığı (ad + yüzde).
  final RecapAsset? enIyi;
  final RecapAsset? enZayif;

  /// Artıda kapanan gün / toplam işlem günü.
  final ({int artida, int toplam})? gunSayimi;

  /// 1 = en üst. "Yatırımcıların %X'inden iyi" kutusu için.
  final int? percentile;

  /// Yıllıklandırılmış getiri (XIRR, yüzde).
  final double? xirrPct;

  /// Tepe→dip gerileme, POZİTİF yüzde (%14,2 → 14.2).
  final double? drawdownPct;

  /// En uzun tutulan varlık ve kaç gündür tutulduğu.
  final String? enSabirli;
  final int? enSabirliGun;

  final int? takipGunu;

  /// Tür dağılımı — yalnızca oran olarak çizilir.
  final Map<AssetType, double> dagilim;

  bool get bos =>
      degisimPct == null &&
      karakter == null &&
      enflasyonPuan == null &&
      (takipGunu ?? 0) <= 0 &&
      percentile == null &&
      enIyi == null &&
      enZayif == null;
}

/// Paylaşılan görsel. Boyut SABİT (4:5 — Instagram/WhatsApp kartı) ve renk
/// paleti KOYU: alıcı uygulamanın temasını bilmez, marka dark-first.
/// `context.c` burada bilerek kullanılmıyor — light temadaki kullanıcı da
/// aynı koyu kartı paylaşır; tipografi yine `context.t`'den (DM Sans).
///
/// ## Yerleşim (yukarıdan aşağı)
/// 1. Wordmark + dönem adı (+ tarih aralığı) — kimlik satırı.
/// 2. KAHRAMAN: büyük yüzde + karakter rozeti; altında enflasyon cümlesi.
///    Yüzde yoksa (snapshot'sız yıllık özet) karakter kahraman olur.
/// 3. En çok DÖRT istatistik kutusu (öncelik sırası [_kutular]'da): kart
///    boşlukla değil bilgiyle dolar ama altı kutu 320 px'te okunmaz.
/// 4. Dağılım şeridi + açıklama — kartın "kimlik" parçası; iki kişinin
///    kartı aynı yüzdeyle bile farklı görünür.
/// 5. Alt bilgi — "sandık ile takip ediyorum" + tarih.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.data, this.tarih});

  final ShareCardData data;

  /// Kartın altındaki tarih; test için enjekte edilir.
  final DateTime? tarih;

  static const width = 320.0;
  static const height = 400.0;

  /// Kenar boşluğu. `md` (16): dört kutu + dağılım şeridi 4:5 karta ancak
  /// böyle sığıyor (bütçe: 368 px iç yükseklik, tam veriyle ~372 — kalan
  /// %1'i orta bölümün FittedBox'ı emer). Daha geniş boşluk kartı
  /// küçültüp sağda ölü alan bırakıyordu (ölçüm 2026-09-16).
  static const kenar = SandikSpace.md;

  /// Kenar boşluğu düşülmüş iç genişlik — rozet gibi esnek olmayan
  /// parçaların üst sınırı buradan türetilir.
  static const icGenislik = width - 2 * kenar;

  /// Kutu öncelik sırası — en çok [maxKutu] tanesi çizilir.
  ///
  /// Sıra bir tercih: dönemin varlıkları (en iyi / en zayıf) kişisel ve
  /// paylaşmaya değer; gün oranı ve yüzdelik dilim onları izler; XIRR,
  /// düşüş ve sabır İleri seviyenin ölçüleri, en sona; takip günü yalnızca
  /// başka bir şey yoksa yer bulur.
  static const maxKutu = 4;

  List<_Kutu> _kutular(BuildContext context) {
    const p = SandikPalette.dark;
    final d = data;
    final l = context.l10n;
    final out = <_Kutu>[];

    if (d.enIyi != null) {
      out.add(_Kutu(
        etiket: l.shareCardBest,
        deger: _isaretli(d.enIyi!.changePct),
        renk: d.enIyi!.changePct >= 0 ? p.gain : p.loss,
        alt: d.enIyi!.name,
      ));
    }
    if (d.enZayif != null) {
      out.add(_Kutu(
        etiket: l.shareCardWorst,
        deger: _isaretli(d.enZayif!.changePct),
        renk: d.enZayif!.changePct >= 0 ? p.gain : p.loss,
        alt: d.enZayif!.name,
      ));
    }
    final g = d.gunSayimi;
    if (g != null && g.toplam > 0) {
      final oran = g.artida / g.toplam;
      out.add(_Kutu(
        etiket: l.shareCardUpDays,
        deger: l.shareCardUpDaysValue(g.artida, g.toplam),
        renk: oran >= 0.5 ? p.gain : p.loss,
        alt: '%${fmtNum(oran * 100, digits: 0)}',
      ));
    }
    if (d.percentile != null) {
      out.add(_Kutu(
        etiket: l.shareCardInvestors,
        deger: l.shareCardBetterThanPct(100 - d.percentile!),
        renk: p.info,
      ));
    }
    if (d.xirrPct != null) {
      out.add(_Kutu(
        etiket: l.shareCardXirr,
        deger: _isaretli(d.xirrPct!),
        renk: d.xirrPct! >= 0 ? p.gain : p.loss,
      ));
    }
    if (d.drawdownPct != null) {
      out.add(_Kutu(
        etiket: l.shareCardDrawdown,
        deger: '−%${fmtNum(d.drawdownPct!.abs(), digits: 1)}',
        renk: p.loss,
      ));
    }
    if (d.enSabirli != null && (d.enSabirliGun ?? 0) > 0) {
      out.add(_Kutu(
        etiket: l.shareCardPatient,
        deger: l.nDays(d.enSabirliGun!),
        renk: p.amberText,
        alt: d.enSabirli,
      ));
    }
    if ((d.takipGunu ?? 0) > 0) {
      out.add(_Kutu(
        etiket: l.shareCardTracked,
        deger: l.nDays(d.takipGunu!),
        renk: p.text58,
      ));
    }
    return out.take(maxKutu).toList();
  }

  @override
  Widget build(BuildContext context) {
    const p = SandikPalette.dark;
    final d = data;
    final pct = d.degisimPct;
    final pozitif = (pct ?? 0) >= 0;
    final tarih = this.tarih ?? DateTime.now();
    final kutular = _kutular(context);
    final dagilim = _oranlar(d.dagilim);

    // Kart bir DIŞA AKTARIMDIR (sabit 320×400): sistemin metin ölçeği
    // burada yok sayılmaz (HIG — `touch_target_size_test` bunu kilitler)
    // ama SINIRLANIR: 1,3× üstü sabit kutuda taşar ve alıcı görseli zaten
    // kendi ekranında kendi ölçeğiyle görür. Önizleme sayfasının başlığı ve
    // düğmeleri tam ölçeğe uyar; yalnızca kart sınırlıdır.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(kenar),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [p.background, p.surface1],
          ),
          borderRadius: BorderRadius.circular(SandikRadius.lg),
        ),
        child: DefaultTextStyle(
          style: context.t.bodyMedium!.copyWith(color: p.text90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Baslik(data: d),
              // Orta bölüm ölçeğe dayanıklı: içerik sabit kutuya sığmazsa
              // (büyük metin ölçeği, dört kutu + dağılım) bütün olarak
              // küçülür; sığıyorsa doğal boyutunda, dikeyde ortalı.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, kutu) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: kutu.maxWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: SandikSpace.smd),
                          if (pct != null)
                            _Kahraman(
                              etiket: d.degisimEtiketi,
                              deger: _isaretli(pct, digits: 2),
                              renk: pozitif ? p.gain : p.loss,
                              karakter: d.karakter,
                            )
                          else if (d.karakter != null)
                            // Yüzde yoksa kimlik kahraman olur: boş bir
                            // kutu yerine "Altıncı" büyük yazılır.
                            _Kahraman(
                              etiket: d.karakter!.tagline,
                              deger: d.karakter!.label,
                              renk: p.gold,
                            ),
                          if (d.enflasyonPuan != null) ...[
                            const SizedBox(height: SandikSpace.xs2),
                            _EnflasyonSatiri(
                              puan: d.enflasyonPuan!,
                              reelPct: d.reelGetiriPct,
                            ),
                          ],
                          if (kutular.isNotEmpty) ...[
                            const SizedBox(height: SandikSpace.sm2),
                            _KutuIzgarasi(kutular: kutular),
                          ],
                          if (dagilim.isNotEmpty) ...[
                            const SizedBox(height: SandikSpace.sm2),
                            _DagilimSeridi(oranlar: dagilim),
                          ],
                          const SizedBox(height: SandikSpace.sm),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Divider(color: p.hairline, height: 1),
              const SizedBox(height: SandikSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.trackingWithSandik,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall?.copyWith(color: p.text58),
                    ),
                  ),
                  const SizedBox(width: SandikSpace.sm),
                  Text(
                    DateFormat('d MMM yyyy', 'tr_TR').format(tarih),
                    maxLines: 1,
                    style: context.t.bodySmall?.copyWith(color: p.text36),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// İşaretli yüzde: "+%12,4" / "−%3,1" (tipografik eksi, U+2212).
  static String _isaretli(double v, {int digits = 1}) =>
      '${v >= 0 ? '+' : '−'}%${fmtNum(v.abs(), digits: digits)}';

  /// Tür → pay (0..1), büyükten küçüğe. Sıfır/negatif ve toplamı sıfır olan
  /// dağılım boş döner — şerit çizilmez.
  static List<({AssetType tur, double pay})> _oranlar(
      Map<AssetType, double> dagilim) {
    final toplam = dagilim.values.where((v) => v > 0).fold(0.0, (a, b) => a + b);
    if (toplam <= 0) return const [];
    final out = [
      for (final e in dagilim.entries)
        if (e.value > 0) (tur: e.key, pay: e.value / toplam),
    ]..sort((a, b) => b.pay.compareTo(a.pay));
    return out;
  }
}

class _Baslik extends StatelessWidget {
  const _Baslik({required this.data});
  final ShareCardData data;

  @override
  Widget build(BuildContext context) {
    const p = SandikPalette.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'sandık',
          style: context.t.titleLarge?.copyWith(
            color: p.gold,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(width: SandikSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                data.baslik,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: context.t.labelLarge?.copyWith(
                  color: p.text58,
                  letterSpacing: 0.4,
                ),
              ),
              if (data.tarihAraligi != null)
                Text(
                  data.tarihAraligi!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: context.t.bodySmall?.copyWith(color: p.text36),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Etiket satırı (+ varsa karakter rozeti) ve büyük sayı.
///
/// Rozet ETİKET satırında, sayının yanında değil: 1,3× metin ölçeğinde
/// "Fon Yatırımcısı" rozeti tek başına 290 px'i buluyor ve sayının yanına
/// sığmıyordu (ölçüm 2026-09-16). Etiket satırı zaten yarı boş; rozet
/// orada iç genişliğin en çok %62'sini alır, gerisi üç noktayla kırpılır.
class _Kahraman extends StatelessWidget {
  const _Kahraman({
    required this.etiket,
    required this.deger,
    required this.renk,
    this.karakter,
  });

  final String etiket;
  final String deger;
  final Color renk;
  final PortfolioCharacter? karakter;

  @override
  Widget build(BuildContext context) {
    const p = SandikPalette.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                ustHarf(etiket, context.l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelLarge?.copyWith(
                  color: p.text58,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            if (karakter != null) ...[
              const SizedBox(width: SandikSpace.sm),
              ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: ShareCard.icGenislik * 0.62),
                child: _KarakterRozeti(karakter: karakter!),
              ),
            ],
          ],
        ),
        const SizedBox(height: SandikSpace.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            deger,
            style: context.t.numLarge.copyWith(
              // 44: eski kartta 56 idi; dört kutu + şeritle 4:5'e sığması
              // için küçüldü. Hâlâ karttaki en büyük öğe — odak bozulmadı.
              fontSize: 44,
              height: 1,
              color: renk,
              letterSpacing: -1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// "✦ Dengeli" — amber zemin, marka rengi. Rozet ZEMİN olduğundan
/// `amberFill` (metin token'ı `amberText` zemin olamaz —
/// `design_token_leak_test`).
class _KarakterRozeti extends StatelessWidget {
  const _KarakterRozeti({required this.karakter});
  final PortfolioCharacter karakter;

  @override
  Widget build(BuildContext context) {
    const p = SandikPalette.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.sm2, vertical: SandikSpace.xs2),
      decoration: BoxDecoration(
        color: p.amberFill.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        border: Border.all(color: p.amberFill.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 14, color: p.gold),
          const SizedBox(width: SandikSpace.xs),
          Flexible(
            child: Text(
              karakter.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.labelLarge?.copyWith(
                color: p.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnflasyonSatiri extends StatelessWidget {
  const _EnflasyonSatiri({required this.puan, this.reelPct});
  final double puan;
  final double? reelPct;

  @override
  Widget build(BuildContext context) {
    const p = SandikPalette.dark;
    final l = context.l10n;
    final onde = puan >= 0;
    final metin = onde
        ? l.aheadOfInflationPts(fmtNum(puan, digits: 1))
        : l.behindInflationPts(fmtNum(puan.abs(), digits: 1));
    final reel = reelPct == null
        ? ''
        : ' · ${l.shareCardReal(ShareCard._isaretli(reelPct!))}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_moon_rounded, size: 16, color: onde ? p.gain : p.loss),
        const SizedBox(width: SandikSpace.sm),
        Expanded(
          child: Text(
            '$metin$reel',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.t.bodySmall?.copyWith(color: p.text90, height: 1.3),
          ),
        ),
      ],
    );
  }
}

/// Tek istatistik kutusunun verisi.
@immutable
class _Kutu {
  const _Kutu({
    required this.etiket,
    required this.deger,
    required this.renk,
    this.alt,
  });
  final String etiket;
  final String deger;
  final Color renk;

  /// Değerin altına düşen küçük satır (varlık adı, oran).
  final String? alt;
}

/// İki sütunlu ızgara; tek kalan kutu satırın yarısını alır (genişlemez —
/// diğer satırla hizası bozulmasın).
class _KutuIzgarasi extends StatelessWidget {
  const _KutuIzgarasi({required this.kutular});
  final List<_Kutu> kutular;

  @override
  Widget build(BuildContext context) {
    final satirlar = <Widget>[];
    for (var i = 0; i < kutular.length; i += 2) {
      if (i > 0) satirlar.add(const SizedBox(height: SandikSpace.sm));
      // `IntrinsicHeight`: kart yüksekliği ölçek için sınırsız (FittedBox
      // altında) — çıplak `stretch` orada patlar; iki kutu yine aynı boyda.
      satirlar.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _KutuGorunumu(kutu: kutular[i])),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: i + 1 < kutular.length
                  ? _KutuGorunumu(kutu: kutular[i + 1])
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ));
    }
    return Column(children: satirlar);
  }
}

class _KutuGorunumu extends StatelessWidget {
  const _KutuGorunumu({required this.kutu});
  final _Kutu kutu;

  @override
  Widget build(BuildContext context) {
    const p = SandikPalette.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.sm2, vertical: SandikSpace.sm),
      decoration: BoxDecoration(
        color: p.surface2.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ustHarf(kutu.etiket, context.l10n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.labelSmall?.copyWith(
              color: p.text58,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: SandikSpace.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              kutu.deger,
              maxLines: 1,
              style: context.t.numMedium.copyWith(
                color: kutu.renk,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
          ),
          if (kutu.alt != null) ...[
            const SizedBox(height: SandikSpace.xxs),
            Text(
              kutu.alt!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodySmall?.copyWith(
                color: p.text58,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tür dağılımı: tek parça yatay şerit + renk noktalı açıklama.
///
/// Renkler `AssetType.color` — kategori kimliği uygulamanın grafikleriyle
/// aynı (amber = hisse, mavi = fon…). Koyu zemin için seçilmiş tonlar,
/// kart da koyu; light varyanta gerek yok.
class _DagilimSeridi extends StatelessWidget {
  const _DagilimSeridi({required this.oranlar});
  final List<({AssetType tur, double pay})> oranlar;

  @override
  Widget build(BuildContext context) {
    const p = SandikPalette.dark;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ayrı bir "DAĞILIM" başlığı yok: açıklama satırı (Hisse %60 …)
        // zaten ne olduğunu söylüyor; başlık 4:5'te 19 px'e mal oluyordu.
        // Erişilebilirlik için etiket `Semantics`'te.
        Semantics(
          label: l.shareCardAllocation,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SandikRadius.sm),
            child: SizedBox(
              height: SandikSpace.xs2,
              child: Row(
                children: [
                  for (final o in oranlar)
                    Expanded(
                      // Flex tam sayı ister; binde birlik çözünürlük yeter.
                      flex: (o.pay * 1000).round().clamp(1, 1000),
                      // `SizedBox.expand`: çocuğu olmayan ColoredBox en
                      // küçük boyuta (0 yükseklik) çöker ve şerit hiç
                      // çizilmez — ilk PNG'de görülüp düzeltildi.
                      child: SizedBox.expand(
                        child: ColoredBox(color: o.tur.color),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: SandikSpace.xs),
        Wrap(
          spacing: SandikSpace.sm2,
          runSpacing: SandikSpace.xxs,
          children: [
            for (final o in oranlar)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: SandikSpace.sm,
                    height: SandikSpace.sm,
                    decoration: BoxDecoration(
                      color: o.tur.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: SandikSpace.xs),
                  Text(
                    '${o.tur.labelOf(l)} %${fmtNum(o.pay * 100, digits: 0)}',
                    style: context.t.bodySmall?.copyWith(
                      color: p.text90,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Önizleme + iki paylaşım yolu.
///
/// Eskiden "Özetini paylaş" doğrudan dört satırlık metni sistem sayfasına
/// veriyordu — kullanıcı ne paylaştığını görmüyordu ve sonuç "arkası boş"
/// hissi veriyordu (2026-09-14 geri bildirimi). Şimdi kart önce gösterilir;
/// görsel varsayılan yol, metin yedek (görsel almayan hedefler için).
Future<void> showShareSheet(
  BuildContext context, {
  required ShareCardData data,
  required String metin,
  required String subject,
  required String analyticsPeriod,
}) async {
  final key = GlobalKey();
  // Sheet içinde bir paylaşım GERÇEKLEŞTİ mi — değerlendirme istemi bunu
  // sheet kapandıktan sonra sorar. Sheet'in üstüne açmak iki katman
  // modal olurdu; kullanıcı kartı kapatınca, ekranına dönmüşken sorulur.
  var paylasildi = false;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.c.surface1,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => _ShareSheet(
      boundaryKey: key,
      data: data,
      metin: metin,
      subject: subject,
      analyticsPeriod: analyticsPeriod,
      onPaylasildi: () => paylasildi = true,
    ),
  );
  // Paylaşmak "gördüğümü göstermek istiyorum" demektir — memnuniyetin
  // en somut işareti. Karar ve sıklık `ReviewPromptService`'te.
  if (paylasildi && context.mounted) {
    await ReviewPromptSheet.belkiGoster(context, ReviewAni.paylasim);
  }
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.boundaryKey,
    required this.data,
    required this.metin,
    required this.subject,
    required this.onPaylasildi,
    required this.analyticsPeriod,
  });

  final GlobalKey boundaryKey;
  final ShareCardData data;
  final String metin;
  final String subject;
  final String analyticsPeriod;

  /// Görsel ya da metin paylaşımı hatasız tamamlandığında çağrılır.
  final VoidCallback onPaylasildi;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _mesgul = false;

  /// Düğmelerin anahtarları: `sharePositionOrigin` dokunulan düğmeden
  /// üretilir (bkz. `ShareCardService.originOf`). iPad'de bu dikdörtgen
  /// olmadan share_plus fırlatıyordu — 2026-09-16'daki "paylaş hata
  /// veriyor" bildiriminin kök nedeni.
  final _gorselKey = GlobalKey();
  final _metinKey = GlobalKey();

  Future<void> _gorsel() async {
    if (_mesgul) return;
    // Dikdörtgen setState'ten ÖNCE alınır: düğme "Hazırlanıyor…" hâline
    // geçince genişliği değişebilir ama yeri değişmez; yine de ölçüm
    // kararlı hâlden yapılır.
    final origin = ShareCardService.originOf(_gorselKey.currentContext);
    setState(() => _mesgul = true);
    try {
      final png = await ShareCardService.renderPng(widget.boundaryKey);
      await AnalyticsService.instance
          .logRecapShared(period: widget.analyticsPeriod, channel: 'image');
      await ShareCardService.shareImage(
        png,
        text: widget.metin,
        subject: widget.subject,
        origin: origin,
      );
      widget.onPaylasildi();
    } catch (e, st) {
      // Crashlytics'e BİLDİR — yoksa hata yalnızca kullanıcının ekranında
      // bir saniye görünüp kayboluyordu. `friendlyError` tanımadığı
      // hataları genel bir cümleye çeviriyor, yani gerçek sebep (PNG
      // üretimi mi, sistem paylaşım sayfası mı, geçici dosya yazımı mı)
      // hiçbir yere yazılmıyordu. Sahadan "paylaş butonu hata veriyor"
      // bildirimi geldiğinde elde tek bir iz bile yoktu (2026-09-16).
      CrashReporter.report(e, st, reason: 'share image');
      if (mounted) {
        sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _metin() async {
    // ## Neden burada da try/catch var
    // Yoktu. Metin yolu görsel yolundan daha basit diye korumasız
    // bırakılmıştı, ama `Share.share` da platform kanalından geçiyor ve
    // fırlatabiliyor. Fırlattığında hata hiçbir yere gitmiyordu:
    // kullanıcı butona basıyor, hiçbir şey olmuyor, tek satır iz yok.
    // İki yol artık AYNI sözleşmeyi taşıyor.
    final origin = ShareCardService.originOf(_metinKey.currentContext);
    try {
      await AnalyticsService.instance
          .logRecapShared(period: widget.analyticsPeriod, channel: 'text');
      await ShareCardService.shareText(
        widget.metin,
        subject: widget.subject,
        origin: origin,
      );
      widget.onPaylasildi();
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'share text');
      if (mounted) {
        sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.lg, SandikSpace.smd, SandikSpace.lg, SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.text20,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: SandikSpace.md),
            Text(
              'Özetini paylaş',
              style: context.t.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: c.text90,
              ),
            ),
            const SizedBox(height: SandikSpace.xs),
            Text(
              context.l10n.shareCardNoAmounts,
              style: context.t.bodySmall?.copyWith(color: c.text58),
            ),
            const SizedBox(height: SandikSpace.md),
            // Kart gerçek boyutunda çizilir (PNG bu ağaçtan alınır), dar
            // ekranda yalnızca önizleme küçültülür — piksel boyutu değişmez.
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RepaintBoundary(
                  key: widget.boundaryKey,
                  child: ShareCard(data: widget.data),
                ),
              ),
            ),
            const SizedBox(height: SandikSpace.lg),
            FilledButton.icon(
              key: _gorselKey,
              onPressed: _mesgul ? null : _gorsel,
              icon: const Icon(Icons.image_rounded, size: 18),
              label: Text(_mesgul ? context.l10n.preparingEllipsis : context.l10n.shareAsImage),
            ),
            const SizedBox(height: SandikSpace.sm),
            TextButton.icon(
              key: _metinKey,
              onPressed: _mesgul ? null : _metin,
              icon: const Icon(Icons.notes_rounded, size: 18),
              label: Text(context.l10n.shareAsText),
            ),
          ],
        ),
      ),
    );
  }
}
