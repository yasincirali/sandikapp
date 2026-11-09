part of '../asset_detail_screen.dart';

/// Kurulu fiyat alarmı ana grafikte (Ar-Ge 29 Eki 20:45 #2, yasin onayı).
///
/// Neden: alarm şeridi "₺4.300" yazıyordu ama kişi o fiyatın grafikte
/// nerede, bugünkü fiyata ne kadar yakın olduğunu göremiyordu; çizgi yalnız
/// tam ekran grafikte, yatay çizimden kurulmuş alarmda vardı (#256).
///
/// Kurallar (hesap `grafikAlarmCizgileri`, model katmanı):
/// - Yalnız ETKİN FİYAT alarmı, en çok 3. Yüzde, gösterge ve çizgi
///   alarmları çizilmez: seviyeleri sabit bir fiyat değil, grafikte yanıltır.
/// - Y ekseni genişletilmez; aralık dışındaki hedefin çizgisi yok, etiketi
///   "grafiğin üstünde/altında" der.
/// - LOG ve Karşılaştır'da ne çizgi ne etiket: Y dönüştürülmüştür (log10 /
///   %), çizgi fiyatı göstermez. Etiketin işi çizgiyi açıklamak; çizgisiz
///   etiket "çizgi bir yerde" diye okunurdu. Alarmlar şeritte zaten yazılı.
/// - Etiket çizim alanına girmez (2026-10-12): kartın üst boşluğunda, dönem
///   başı açıklamasıyla aynı satırın sağında (`GrafikStili.donemBasiUstte`).
extension _AlarmCizgileri on _AssetDetailScreenState {
  /// Grafikte gösterilmeye aday fiyat alarmları — LOG/Karşılaştır'da ve
  /// alarm kurulamayan varlıkta (mevduat, BES; `_alarmSembolu`) boş.
  List<PriceAlert> _grafikAlarmAdaylari({
    required bool compareOn,
    required bool logOn,
  }) {
    final sembol = _alarmSembolu;
    if (sembol == null || compareOn || logOn) return const [];
    // Ortak özetten (`sembolAlarmlariProvider`; `sembol_alarmlari_test`
    // ekranın listeyi kendisi okumasını kilitler). Yalnız fiyat türü.
    return [
      for (final a in ref.watch(sembolAlarmlariProvider(sembol)).fiyat)
        if (a.isActive) a,
    ];
  }

  /// Çizim alanındaki kesikli çizgiler — yalnız görünen Y aralığındakiler.
  List<HorizontalLine> _alarmYatayCizgileri(
          List<GrafikAlarmCizgisi> cizgiler) =>
      [
        for (final a in cizgiler)
          if (a.cizilir)
            GrafikStili.alarmCizgisi(context, a.alarm.targetPrice,
                yukari: a.alarm.isAbove),
      ];

  /// Grafikteki ortalama maliyet (Ar-Ge 1 Kas 08:45 #1, yasin "yap").
  ///
  /// Neden: varlığa giren kişinin ikinci sorusu "kârda mıyım, başa baş ne
  /// kadar uzakta". Rakam fiyatın altında yazıyordu; çizgi bunu grafikte
  /// bir bakışta söyler. Hesap alarm sayfasının "maliyetime göre"
  /// çipleriyle AYNI kaynaktan ([alarmMaliyeti]): tek maliyet tanımı.
  ///
  /// Kurallar (alarm çizgisiyle aynı, [maliyetCizgiKonumu]):
  /// - Yalnız KENDİ açık pozisyonunda ([isOwnAsset] && `_canli.acik`).
  /// - Maliyet bilinmiyorsa (`maliyetBilinmiyor`, karışık para birimi) yok.
  /// - Yalnız TL varlıkta: grafik ve alarm hedefleri kaynak fiyat
  ///   biriminde, [alarmMaliyeti] varlığın kendi para biriminde. Dövizli
  ///   varlıkta iki ölçeğin aynı olduğunu bu katman garanti edemez; yanlış
  ///   yerde çizgi uydurma sayıdır (fiyat kaynağı kuralı 2).
  /// - LOG ve Karşılaştır'da yok: Y dönüştürülmüştür.
  double? _grafikMaliyeti({
    required bool isOwnAsset,
    required bool compareOn,
    required bool logOn,
  }) {
    if (!isOwnAsset || !_canli.acik || compareOn || logOn) return null;
    if (_canli.asset.currency != 'TRY') return null;
    return alarmMaliyeti(_canli.lots);
  }

  /// Maliyetin kesikli çizgisi — yalnız görünen Y aralığındaysa.
  List<HorizontalLine> _maliyetYatayCizgisi(double? maliyet,
          {required double minY, required double maxY}) =>
      [
        if (maliyetCizgiKonumu(maliyet, minY: minY, maxY: maxY) ==
            AlarmCizgiKonumu.icinde)
          GrafikStili.maliyetCizgisi(context, maliyet!),
      ];

  /// Kartın üst boşluğundaki maliyet ve alarm açıklaması. Yakınlaştırma/
  /// kaydırma Y aralığını değiştirir; etiket ana grafiğin X penceresini
  /// (`_ozelGorunum`, alt panellerle aynı) dinler ve [bant] ile çizimle
  /// AYNI aralığı hesaplar — "çizgi yok ama etiket içeride diyor"
  /// ayrışması olmasın. Pencere henüz bildirilmediyse [tamPencere].
  ///
  /// Sıra: önce maliyet (kişinin kendi parası, hep aynı yerde), sonra
  /// alarm. İkisi birden varken alarm kısa yazılır (fiyat + yön; "+N"
  /// kalır): satır tek; ikinci satır kart boyunu değiştirirdi
  /// (`donemBasiUstte`). Yer yetmezse alarm `…` ile kısalır, maliyet değil.
  Widget? _alarmUstEtiketi({
    required List<PriceAlert> adaylar,
    required double? maliyet,
    required ({double min, double max}) tamPencere,
    required ({double minY, double maxY, double interval}) Function(
            double minX, double maxX)
        bant,
    required double guncelFiyat,
  }) {
    if (adaylar.isEmpty && maliyet == null) return null;
    return ValueListenableBuilder<({double min, double max})?>(
      valueListenable: _ozelGorunum,
      builder: (context, gorunum, _) {
        final p = gorunum ?? tamPencere;
        final b = bant(p.min, p.max);
        final konum = maliyetCizgiKonumu(maliyet, minY: b.minY, maxY: b.maxY);
        final maliyetYazisi = konum == null
            ? null
            : GrafikStili.maliyetEtiketi(context,
                maliyet: maliyet!, konum: konum, guncelFiyat: guncelFiyat);
        final alarmYazisi = GrafikStili.alarmEtiketi(
          context,
          grafikAlarmCizgileri(adaylar,
              minY: b.minY, maxY: b.maxY, guncelFiyat: guncelFiyat),
          kisa: maliyetYazisi != null,
        );
        if (maliyetYazisi == null) {
          return alarmYazisi ?? const SizedBox.shrink();
        }
        if (alarmYazisi == null) return maliyetYazisi;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // İkisi de esner: dar ekranda önce uzun olan kırpılır, satır
            // taşmaz.
            Flexible(child: maliyetYazisi),
            const SizedBox(width: SandikSpace.sm),
            Flexible(child: alarmYazisi),
          ],
        );
      },
    );
  }
}
