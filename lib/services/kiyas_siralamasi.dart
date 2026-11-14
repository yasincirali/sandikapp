import '../l10n/generated/app_localizations.dart';
import '../utils/tr_format.dart';
import 'symbol_search_service.dart' show PortfolioSeries, TufeSeries;

/// Karşılaştır'daki tek seri: sembol, cümlede görünen ad, dönem getirisi.
/// Getiri rozetin sayısıdır (`NormalizedSeries.totalReturnPct`).
typedef KiyasGetirisi = ({String ticker, String ad, double pct});

/// "Bu dönemde sıralama" cümlesi (Ar-Ge 14 Kas 2026 22:03, YAP 3).
///
/// Ekranın sorusu "portföyüm BIST 100'ü / doları / altını yendi mi"; cevap
/// beş rozeti gözle kıyaslamakla çıkıyordu. Grafiğin altında tek cümle, en
/// az ÜÇ seride (iki seride rozetler zaten tek bakışta okunur).
///
/// **Ek uyumu yok.** Türkçede adın arkasına gelen ek (BIST 100'ün, altının)
/// adın son ünlüsüne ve okunuşuna bağlı; kullanıcı sembollerinde (THYAO.IS,
/// fon kodları) bunu doğru kuracak bir yardımcı yok. Cümle eki ada değil
/// sabit kelimelere bağlar: "BIST 100 karşısında 3,1 puan önde", "Önde
/// gram altın: +%12,40". "TÜFE'nin" sabit bir addır, ekiyle .arb'da.
///
/// Dil nötr: kazanan/kaybeden, "yendin" yok; sıra ve puan farkı.
class KiyasSiralamasi {
  const KiyasSiralamasi._({
    required this.sirali,
    required this.portfoySirasi,
    required this.ustundeki,
    required this.altindaki,
    required this.tufeninUstunde,
  });

  /// En yüksek getiriden en düşüğe; eşitlikte seçim sırası korunur.
  final List<KiyasGetirisi> sirali;

  /// "Portföyüm"ün 1'den başlayan sırası; seçili değilse null.
  final int? portfoySirasi;

  /// Portföyün hemen üstündeki / altındaki seri (yoksa null).
  final KiyasGetirisi? ustundeki;
  final KiyasGetirisi? altindaki;

  /// Portföy TÜFE'nin üstünde mi (eşitlik üstünde sayılmaz). TÜFE ya da
  /// portföy yoksa, ya da TÜFE portföyün komşusuysa (cümle onu zaten puanla
  /// söylüyor) null.
  final bool? tufeninUstunde;

  KiyasGetirisi get lider => sirali.first;

  /// Puan farkı bunun altındaysa "başa baş": "0,0 puan önde" yön uydururdu.
  static const _basabasEsigi = 0.05;

  String cumle(AppLocalizations l) {
    final out = <String>[];
    final sira = portfoySirasi;
    if (sira == null) {
      out.add(l.cmpSiraLider(lider.ad, fmtPctIsaretli(lider.pct)));
      out.add(l.cmpSiraListe(sirali.map((s) => s.ad).join(', ')));
      return out.join(' ');
    }
    final portfoy = sirali[sira - 1];
    final parcalar = <String>[
      if (altindaki case final a?) _fark(l, portfoy, a),
      if (ustundeki case final u?) _fark(l, portfoy, u),
    ];
    if (sira == 1) {
      out.add(l.cmpSiraLiderPortfoy(fmtPctIsaretli(portfoy.pct)));
      // Parça cümle başına geçer; İngilizcede küçük harfle başlayan
      // "level with" büyür. Türkçe parçalar adla başlar, dokunulmaz.
      final govde = parcalar.join(', ');
      out.add('${govde[0].toUpperCase()}${govde.substring(1)}.');
    } else {
      out.add(l.cmpSiraLider(lider.ad, fmtPctIsaretli(lider.pct)));
      out.add('${l.cmpSiraPortfoy(sira)}: ${parcalar.join(', ')}.');
    }
    if (tufeninUstunde case final ust?) {
      out.add(ust ? l.cmpSiraTufeUstunde : l.cmpSiraTufeAltinda);
    }
    return out.join(' ');
  }

  static String _fark(AppLocalizations l, KiyasGetirisi p, KiyasGetirisi o) {
    final fark = p.pct - o.pct;
    if (fark.abs() < _basabasEsigi) return l.cmpSiraBasabas(o.ad);
    final puan = fmtNum(fark.abs(), digits: 1);
    return fark > 0 ? l.cmpSiraOnde(o.ad, puan) : l.cmpSiraGeride(o.ad, puan);
  }
}

/// Getirisi olan serilerden sıralama; üçten az seride null (cümle yok).
///
/// Çağıran yalnız serisi GELMİŞ satırları verir: eksik seri cümleye girmez,
/// yerine 0 yazılmaz (fiyat kaynağı sözleşmesi §3).
KiyasSiralamasi? kiyasSiralamasiKur(List<KiyasGetirisi> seriler) {
  final temiz = [
    for (final s in seriler)
      if (s.pct.isFinite) s,
  ];
  if (temiz.length < 3) return null;
  final idx = {for (var i = 0; i < temiz.length; i++) temiz[i].ticker: i};
  final sirali = [...temiz]..sort((a, b) {
      final c = b.pct.compareTo(a.pct);
      return c != 0 ? c : idx[a.ticker]!.compareTo(idx[b.ticker]!);
    });
  final pi = sirali.indexWhere((s) => s.ticker == PortfolioSeries.mine);
  if (pi < 0) {
    return KiyasSiralamasi._(
        sirali: sirali,
        portfoySirasi: null,
        ustundeki: null,
        altindaki: null,
        tufeninUstunde: null);
  }
  final ust = pi > 0 ? sirali[pi - 1] : null;
  final alt = pi < sirali.length - 1 ? sirali[pi + 1] : null;
  final tufe = sirali.where((s) => TufeSeries.isTufe(s.ticker)).firstOrNull;
  final tufeKomsu = tufe != null &&
      (tufe.ticker == ust?.ticker || tufe.ticker == alt?.ticker);
  return KiyasSiralamasi._(
    sirali: sirali,
    portfoySirasi: pi + 1,
    ustundeki: ust,
    altindaki: alt,
    tufeninUstunde:
        tufe == null || tufeKomsu ? null : sirali[pi].pct > tufe.pct,
  );
}
