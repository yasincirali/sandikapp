import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/position.dart';
import '../models/varlik_kimligi.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import 'add_asset_screen.dart';
import 'asset_detail_screen.dart';

/// Varlık sayfası ile SAHİPLİK dünyası arasındaki tek kapı.
///
/// ## Neden ayrı dosya
/// Varlık sayfası (`varlik_sayfasi.dart`) `Asset` tipini bilmez ve
/// `AssetDetailScreen`'i açmaz (`varlik_sayfasi_test` kilitler): sahte bir
/// `Asset` üretmek takip/önizleme verisinin portföy toplamına sızma yoludur.
/// Ama portföyde OLAN bir varlık arandığında kullanıcıyı gerçek pozisyonuna
/// götürmek gerekir. Bu dosya o geçişi yapar — elindeki `Asset` sunucudan
/// gelen gerçek kayıttır, burada hiçbir `Asset` kurulmaz.

/// [kimlik] bugün portföyde mi? Kapanmış (tamamı satılmış) pozisyon sayılmaz
/// — `aktifLotlar` kuralı (CLAUDE.md "Kapanmış pozisyon").
bool portfoydeMi(WidgetRef ref, VarlikKimligi kimlik) =>
    _eslesenLot(ref.watch(portfolioProvider).valueOrNull?.assets, kimlik) !=
    null;

/// Portföy henüz yüklenmedi mi? Yüklenirken "portföyünde değil" demek,
/// sahip olunan varlıkta "Portföye ekle" gösterir ve ikinci bir kayıt açtırır
/// (Karşılaştır ekranındaki `_actionRow` hatasının aynısı).
bool portfoyYukleniyor(WidgetRef ref) =>
    ref.watch(portfolioProvider).valueOrNull == null;

Asset? _eslesenLot(List<Asset>? assets, VarlikKimligi kimlik) {
  if (assets == null) return null;
  for (final a in aktifLotlar(assets)) {
    if (varlikAnahtari(
            type: a.type, ticker: a.ticker, subCategory: a.subCategory) ==
        kimlik.key) {
      return a;
    }
  }
  return null;
}

/// Portföydeki pozisyonun detayını açar — portföy listesiyle AYNI nesne
/// (`pozisyonGorunumu`), aynı rota (`adaptiveRoute` + `pushGuarded`).
void pozisyonuAc(BuildContext context, WidgetRef ref, VarlikKimligi kimlik) {
  final assets = ref.read(portfolioProvider).valueOrNull?.assets;
  final lot = _eslesenLot(assets, kimlik);
  if (assets == null || lot == null) return;
  final gorunum = pozisyonGorunumu(assets, lot);
  pushGuarded(
    context,
    adaptiveRoute<void>(
      builder: (_) => AssetDetailScreen(
        asset: gorunum?.asset ?? lot,
        lots: gorunum?.lots ?? [lot],
        showBackButton: true,
      ),
    ),
  );
}

/// "Portföyüme ekle" — ekleme formu sembol, ad ve türle ön doldurulur;
/// takip listesi satırı ve Karşılaştır ile AYNI ön doldurma.
void portfoyeEkleAc(BuildContext context, VarlikKimligi kimlik) {
  pushGuarded(
    context,
    adaptiveRoute<void>(
      builder: (_) => AddAssetScreen(
        prefillTicker: kimlik.ticker,
        prefillName: kimlik.name,
        prefillType: kimlik.type,
      ),
    ),
  );
}
