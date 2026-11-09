import '../config/magaza.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/asset_type.dart';
import '../utils/tr_format.dart';
import 'share_card.dart';
import 'tam_ekran/grafik_paylasimi.dart' show grafikPaylasimKisaBaglanti;

/// Bugün kartından "yalnız yüzde" paylaşımı (müşteri raporu 30 Eki 17:15
/// §1, yasin "yap").
///
/// ## Neden saf fonksiyon
/// İki kural testle kilitli (`bugun_paylasimi_test`): (1) tutar yok —
/// görsel ve metin yalnız günün yüzdesini, tür ADLARINI ve tarihi taşır;
/// payı bile yazmaz ([ShareCardData.dagilimOranGizli]); (2) tavsiye dili
/// yok, "Yatırım tavsiyesi değildir" her iki yüzde de durur. Mağaza
/// bağlantısı öteki paylaşımlarla aynı kapıdan, kanal etiketi `bugun`.
///
/// Eksi günde de aynı kart: düğme gizlenmez, görsel teselli cümlesi
/// eklemez; yalnız yüzde ve tarih (rapor: "uygulama paylaşmaya teşvik
/// etmesin, düğme yalnız durur").
ShareCardData bugunPaylasimKarti(
  AppLocalizations l, {
  required double degisimPct,
  required Map<AssetType, double> dagilim,
}) =>
    ShareCardData(
      baslik: l.todayTitle,
      degisimPct: degisimPct,
      degisimEtiketi: l.todayShareLabel,
      dagilim: dagilim,
      dagilimOranGizli: true,
      dipnotlar: [grafikPaylasimKisaBaglanti(), l.notInvestmentAdvice],
    );

/// Paylaşım metni: yüzde + tarih, uyarı, imza ve indirme bağlantısı.
String bugunPaylasimMetni(
  AppLocalizations l, {
  required double degisimPct,
  required String tarih,
}) =>
    [
      l.todayShareText(fmtPctIsaretli(degisimPct), tarih),
      l.notInvestmentAdvice,
      '',
      l.trackingWithSandik,
      Magaza.indirBaglantisi(kaynak: 'bugun_karti', kampanya: 'bugun'),
    ].join('\n');
