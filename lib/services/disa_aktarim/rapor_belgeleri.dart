import 'package:intl/intl.dart';

import '../../models/asset.dart';
import '../../models/position.dart';
import '../../utils/tr_format.dart';
import '../varlik_masraflari.dart' show abdTemettuStopajOrani;
import '../yillik_rapor.dart';
import 'rapor_belgesi.dart';

/// Premium dışa aktarımlarının İÇERİĞİ (2026-10-10). Biçimden bağımsız:
/// aynı [RaporBelgesi] Excel'e de PDF'e de yazılır.
///
/// Belgeler Türkçedir: alıcısı çoğunlukla mali müşavir ve sütun adları
/// Türk vergi diline göre seçildi (Gerçekleşen kâr/zarar, Stopaj). Saf.

/// Yıllık kâr, temettü ve masraf raporu.
RaporBelgesi yillikRaporBelgesi(
  YillikRapor r, {
  required String kim,
  required DateTime olusturma,
  required double? bistStopajOrani,
}) {
  final stopaj = r.stopajTry;
  return RaporBelgesi(
    baslik: 'sandık · ${r.yil} yıllık kâr, temettü ve masraf raporu',
    altBaslik: '$kim · oluşturma ${DateFormat('dd.MM.yyyy HH:mm').format(olusturma)}',
    dosyaAdi: 'sandik-${r.yil}-yillik-rapor',
    ozet: [
      ('Gerçekleşen kâr/zarar (satışlar)', TlTutar(r.gerceklesenKarTry)),
      if (r.yurtDisiVar)
        ('  bunun yurt dışı (ABD) hisse kısmı', TlTutar(r.yurtDisiKarTry)),
      ('Temettü (net, ele geçen)', TlTutar(r.temettuNetTry)),
      ('Temettü stopajı', stopaj == null ? 'oran bilinmiyor' : TlTutar(stopaj)),
      ('İşlem masrafları (komisyon)', TlTutar(r.masrafTry)),
      ('Satış sayısı', '${r.satislar.length}'),
      ('Temettü sayısı', '${r.temettuler.length}'),
    ],
    tablolar: [
      RaporTablosu(
        baslik: 'Satışlar',
        sutunlar: const [
          'Tarih',
          'Varlık',
          'Sembol',
          'Miktar',
          'Satış (TL)',
          'Maliyet (TL)',
          'Komisyon (TL)',
          'Kâr/zarar (TL)',
          'Yurt dışı',
        ],
        satirlar: [
          for (final s in r.satislar)
            [
              s.tarih,
              s.ad,
              sadeSembol(s.ticker),
              s.miktar,
              TlTutar(s.satisTry),
              TlTutar(s.maliyetTry),
              TlTutar(s.komisyonTry),
              TlTutar(s.karTry),
              s.yurtDisi ? 'Evet' : 'Hayır',
            ],
        ],
        toplam: r.satislar.isEmpty
            ? null
            : [
                'Toplam',
                null,
                null,
                null,
                TlTutar(r.satislar.fold(0.0, (t, s) => t + s.satisTry)),
                TlTutar(r.satislar.fold(0.0, (t, s) => t + s.maliyetTry)),
                TlTutar(r.satisKomisyonuTry),
                TlTutar(r.gerceklesenKarTry),
                null,
              ],
      ),
      RaporTablosu(
        baslik: 'Temettüler',
        sutunlar: const [
          'Tarih',
          'Varlık',
          'Sembol',
          'Net (TL)',
          'Stopaj oranı',
          'Brüt (TL)',
          'Stopaj (TL)',
        ],
        satirlar: [
          for (final t in r.temettuler)
            [
              t.tarih,
              t.ad,
              sadeSembol(t.ticker),
              TlTutar(t.netTry),
              t.stopajOrani == null
                  ? 'bilinmiyor'
                  : fmtPct(t.stopajOrani! * 100, digits: 0),
              t.brutTry == null ? null : TlTutar(t.brutTry!),
              t.stopajTry == null ? null : TlTutar(t.stopajTry!),
            ],
        ],
        toplam: r.temettuler.isEmpty
            ? null
            : [
                'Toplam',
                null,
                null,
                TlTutar(r.temettuNetTry),
                null,
                null,
                stopaj == null ? null : TlTutar(stopaj),
              ],
      ),
    ],
    dipnotlar: [
      'Bu rapor sandık\'a girdiğin kayıtlardan hazırlandı. Vergi beyannamesi '
          'ya da vergi tavsiyesi değildir; beyan için mali müşavirine danış.',
      'Satış kârı: satış tutarı (kayıtlıysa satış günü kuruyla) − ağırlıklı '
          'ortalama alış maliyeti (alış kuruyla) − satış komisyonu.',
      'Temettünün net tutarı kayıtlıdır. Brüt ve stopaj geri hesaplanır: '
          'BIST hisselerinde ${bistStopajOrani == null ? 'oran bilinmiyor' : fmtPct(bistStopajOrani * 100, digits: 0)}, '
          'ABD hisselerinde ${fmtPct(abdTemettuStopajOrani * 100, digits: 0)} '
          '(W-8BEN, Türkiye–ABD anlaşması).',
      if (r.yurtDisiVar)
        'Yurt dışı hisse kazançlarının beyanı Türkiye\'deki hisse '
            'kazançlarından farklı kurallara bağlıdır.',
      if (r.fiyatsizSatis > 0)
        'Satış fiyatı kayıtlı olmayan ${r.fiyatsizSatis} eski satış rapora '
            'alınmadı.',
      'Yalnız senin kayıtların; ortak portföydeki ortağının işlemleri dahil değil.',
    ],
  );
}

/// Portföy dökümü: bugünkü pozisyonlar + bütün işlem geçmişi.
///
/// [lotlar] kullanıcının KENDİ ham defteri (silinenler hariç). Pozisyonlar
/// `aggregatePositions` ile (ekranla aynı); TL değeri [tlYap] (durumun
/// `toTRY`'si, canlı kur) ile.
RaporBelgesi portfoyBelgesi({
  required List<Asset> lotlar,
  required double Function(double tutar, String paraBirimi) tlYap,
  required String kim,
  required DateTime olusturma,
}) {
  final aktif = [for (final a in lotlar) if (a.isActive) a];
  final pozisyonlar = aggregatePositions(aktif)
    ..sort((a, b) => tlYap(b.totalValue, b.representative.currency)
        .compareTo(tlYap(a.totalValue, a.representative.currency)));
  double deger(Position p) => tlYap(p.totalValue, p.representative.currency);
  final toplamDeger = pozisyonlar.fold(0.0, (t, p) => t + deger(p));
  final toplamMaliyet = pozisyonlar.fold(0.0, (t, p) => t + p.totalCostTRY);
  final islemler = [
    for (final a in aktif)
      if (!a.isDeleteLog) a
  ]..sort((x, y) => y.addedDate.compareTo(x.addedDate));

  String islemAdi(Asset a) => switch (a.kind) {
        AssetKind.buy => 'Alış',
        AssetKind.sell => 'Satış',
        AssetKind.dividend => 'Temettü',
        AssetKind.deleteLog => 'Silme',
      };

  return RaporBelgesi(
    baslik: 'sandık · portföy dökümü',
    altBaslik: '$kim · ${DateFormat('dd.MM.yyyy HH:mm').format(olusturma)} itibarıyla',
    dosyaAdi: 'sandik-portfoy-${DateFormat('yyyy-MM-dd').format(olusturma)}',
    ozet: [
      ('Toplam değer', TlTutar(toplamDeger)),
      ('Toplam maliyet', TlTutar(toplamMaliyet)),
      ('Kâr/zarar (açık pozisyonlar)', TlTutar(toplamDeger - toplamMaliyet)),
      ('Varlık sayısı', '${pozisyonlar.length}'),
      ('İşlem sayısı', '${islemler.length}'),
    ],
    tablolar: [
      RaporTablosu(
        baslik: 'Varlıklar',
        sutunlar: const [
          'Varlık',
          'Sembol',
          'Tür',
          'Miktar',
          'Para birimi',
          'Ort. alış fiyatı',
          'Güncel fiyat',
          'Değer (TL)',
          'Maliyet (TL)',
          'Kâr/zarar (TL)',
        ],
        satirlar: [
          for (final p in pozisyonlar)
            [
              p.representative.name,
              sadeSembol(p.representative.ticker),
              p.representative.type.label,
              p.totalQuantity,
              p.representative.currency,
              p.weightedPurchasePrice,
              p.representative.currentPrice,
              TlTutar(deger(p)),
              TlTutar(p.totalCostTRY),
              TlTutar(deger(p) - p.totalCostTRY),
            ],
        ],
        toplam: pozisyonlar.isEmpty
            ? null
            : [
                'Toplam',
                null,
                null,
                null,
                null,
                null,
                null,
                TlTutar(toplamDeger),
                TlTutar(toplamMaliyet),
                TlTutar(toplamDeger - toplamMaliyet),
              ],
      ),
      RaporTablosu(
        baslik: 'İşlemler',
        sutunlar: const [
          'Tarih',
          'İşlem',
          'Varlık',
          'Sembol',
          'Miktar',
          'Fiyat',
          'Para birimi',
          'Kur',
          'Komisyon',
          'Temettü (net)',
        ],
        satirlar: [
          for (final a in islemler)
            [
              a.addedDate,
              islemAdi(a),
              a.name,
              sadeSembol(a.ticker),
              a.isDividend ? null : a.quantity,
              a.isSell ? a.sellPrice : (a.isDividend ? null : a.purchasePrice),
              a.currency,
              a.isSell ? a.satisKuru : a.purchaseFxRate,
              a.commission == 0 ? null : a.commission,
              a.isDividend ? a.dividendAmount : null,
            ],
        ],
      ),
    ],
    dipnotlar: [
      'Değerler oluşturma anındaki fiyat ve kurla; maliyet alış kuruyla.',
      'Yalnız senin kayıtların; ortak portföydeki ortağının varlıkları dahil değil.',
      'Tüm verilerinin makine okunur tam kopyası Ayarlar › Verilerini indir '
          '(JSON) yolundadır.',
    ],
  );
}

/// Ekranda gösterilen sembol: `TEFAS:AFT` → AFT, `THYAO.IS` → THYAO.
String sadeSembol(String ticker) {
  var t = ticker.trim();
  if (t.contains(':')) t = t.substring(t.lastIndexOf(':') + 1);
  if (t.endsWith('.IS')) t = t.substring(0, t.length - 3);
  return t;
}
