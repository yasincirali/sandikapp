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
  final karVarlik =
      _topla([for (final s in r.satislar) (_kisaAd(s.ticker, s.ad), s.karTry)]);
  final temettuVarlik =
      _topla([for (final t in r.temettuler) (_kisaAd(t.ticker, t.ad), t.netTry)]);
  return RaporBelgesi(
    belgeTuru: 'Yıllık rapor',
    kampanya: 'yillik_rapor',
    oneCikanlar: _yillikOneCikanlar(r, karVarlik, temettuVarlik),
    grafikler: [
      if (karVarlik.isNotEmpty)
        RaporGrafigi(
          baslik: 'Varlık bazında gerçekleşen kâr/zarar',
          tur: RaporGrafikTuru.cubuk,
          kalemler: karVarlik,
          not: 'satışlar, TL',
        ),
      if (temettuVarlik.isNotEmpty)
        RaporGrafigi(
          baslik: 'Varlık bazında net temettü',
          tur: RaporGrafikTuru.cubuk,
          kalemler: temettuVarlik,
          not: 'ele geçen, TL',
        ),
    ],
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
          '(W-8BEN, Türkiye-ABD anlaşması).',
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

  final turDegeri = _topla([
    for (final p in pozisyonlar) (p.representative.type.label, deger(p)),
  ]);
  return RaporBelgesi(
    belgeTuru: 'Portföy dökümü',
    kampanya: 'portfoy_dokumu',
    oneCikanlar: _portfoyOneCikanlar(
        pozisyonlar, deger, turDegeri, toplamDeger, toplamMaliyet),
    grafikler: [
      if (turDegeri.length > 1)
        RaporGrafigi(
          baslik: 'Varlık türlerine göre dağılım',
          tur: RaporGrafikTuru.dagilim,
          kalemler: turDegeri,
          not: 'güncel değer',
        ),
      if (pozisyonlar.isNotEmpty)
        RaporGrafigi(
          baslik: 'Varlık bazında kâr/zarar',
          tur: RaporGrafikTuru.cubuk,
          kalemler: [
            for (final p in pozisyonlar)
              (
                _kisaAd(p.representative.ticker, p.representative.name),
                deger(p) - p.totalCostTRY
              ),
          ]..sort((a, b) => b.$2.compareTo(a.$2)),
          not: 'açık pozisyonlar, TL',
        ),
    ],
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

/// Grafik ve cümlede kısa ad: borsa sembolü okunur (THYAO, AK3), teknik
/// anahtar okunmaz (`ALTIN_GRAM`, `USDTRY=X`) — onlarda varlığın adı.
String _kisaAd(String ticker, String ad) {
  final s = sadeSembol(ticker);
  return teknikSembolMu(s) ? ad : s;
}

/// Kullanıcıya gösterilmeyen iç anahtar mı (`ALTIN_GRAM`, `USDTRY=X`)?
/// PDF tablosu bunları adın altına yazmaz.
bool teknikSembolMu(String s) => s.contains('_') || s.contains('=');

/// Ekranda gösterilen sembol: `TEFAS:AFT` → AFT, `THYAO.IS` → THYAO.
String sadeSembol(String ticker) {
  var t = ticker.trim();
  if (t.contains(':')) t = t.substring(t.lastIndexOf(':') + 1);
  if (t.endsWith('.IS')) t = t.substring(0, t.length - 3);
  return t;
}

/// Aynı etiketi toplar; büyükten küçüğe (mutlak değere göre değil, işaretli)
/// sıralı. Sıra sabit: eşitlikte ilk görülen önde.
List<(String, double)> _topla(List<(String, double)> kalemler) {
  final m = <String, double>{};
  for (final (k, v) in kalemler) {
    m[k] = (m[k] ?? 0) + v;
  }
  return [for (final e in m.entries) (e.key, e.value)]
    ..sort((a, b) => b.$2.compareTo(a.$2));
}

/// "+₺1.234" / "−₺368" — uygulamanın tutar dili (U+2212).
String _isaretliTl(double v) {
  final m = fmtTRY(v.abs());
  if (v.round() == 0) return m;
  return '${v > 0 ? '+' : '\u2212'}$m';
}

/// Yıllık raporun öne çıkanları: ölçüm, tavsiye değil. Boş yıl → boş.
List<String> _yillikOneCikanlar(YillikRapor r, List<(String, double)> karVarlik,
    List<(String, double)> temettuVarlik) {
  final out = <String>[];
  if (r.satislar.isNotEmpty) {
    out.add('${r.yil} yılında ${r.satislar.length} satışın gerçekleşen '
        'kâr/zararı ${_isaretliTl(r.gerceklesenKarTry)}.');
    final (enAd, enKar) = karVarlik.first;
    if (karVarlik.length > 1 && enKar > 0) {
      out.add('En büyük katkı $enAd: ${_isaretliTl(enKar)}.');
    }
    final (sonAd, sonKar) = karVarlik.last;
    if (sonKar < 0) {
      out.add('Zararla kapanan: $sonAd, ${_isaretliTl(sonKar)}.');
    }
  }
  if (temettuVarlik.isNotEmpty) {
    final (ad, net) = temettuVarlik.first;
    out.add('Temettüden net ${fmtTRY(r.temettuNetTry)} geldi'
        '${temettuVarlik.length > 1 ? '; en çok $ad (${fmtTRY(net)})' : ''}.');
  }
  if (r.masrafTry > 0) {
    final kazanc = r.gerceklesenKarTry + r.temettuNetTry;
    out.add('İşlem masrafı ${fmtTRY(r.masrafTry)}'
        '${kazanc > 0 ? '; kâr ve temettü toplamına oranı ${fmtPct(r.masrafTry / kazanc * 100, digits: 1)}' : ''}.');
  }
  return out;
}

/// Portföy dökümünün öne çıkanları (açık pozisyonlar, oluşturma anı).
List<String> _portfoyOneCikanlar(
  List<Position> pozisyonlar,
  double Function(Position) deger,
  List<(String, double)> turDegeri,
  double toplamDeger,
  double toplamMaliyet,
) {
  if (pozisyonlar.isEmpty || toplamDeger <= 0) return const [];
  String pay(double v) => fmtPct(v / toplamDeger * 100, digits: 1);
  final out = <String>[];
  final (tur, turV) = turDegeri.first;
  if (turDegeri.length > 1) {
    // Yüzdeye ek ("'i/'ü") okunuşa göre değişir; ek gerektirmeyen kalıp.
    out.add('En büyük pay $tur: ${pay(turV)}. Portföy '
        '${turDegeri.length} varlık türüne yayılıyor.');
  }
  final enBuyuk = pozisyonlar.first;
  out.add('En büyük tek varlık ${enBuyuk.representative.name}, payı '
      '${pay(deger(enBuyuk))}.');
  final getirili = [
    for (final p in pozisyonlar)
      if (p.totalCostTRY > 0) (p, (deger(p) / p.totalCostTRY - 1) * 100),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  if (getirili.length > 1) {
    final (iyi, iyiPct) = getirili.first;
    final (zayif, zayifPct) = getirili.last;
    out.add('En çok kazandıran '
        '${_kisaAd(iyi.representative.ticker, iyi.representative.name)} '
        '(${fmtPctIsaretli(iyiPct, digits: 1)}), en zayıf '
        '${_kisaAd(zayif.representative.ticker, zayif.representative.name)} '
        '(${fmtPctIsaretli(zayifPct, digits: 1)}).');
  }
  if (toplamMaliyet > 0) {
    out.add('Açık pozisyonların toplam kâr/zararı '
        '${_isaretliTl(toplamDeger - toplamMaliyet)} '
        '(${fmtPctIsaretli((toplamDeger / toplamMaliyet - 1) * 100, digits: 1)}).');
  }
  return out;
}
