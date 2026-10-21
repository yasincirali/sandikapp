import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../services/seni_ilgilendiren_gunler.dart';
import '../services/temettu_gecmisi.dart' show trGunu;
import 'auth_provider.dart';
import 'ozellik_onerisi_provider.dart';
import 'portfolio_provider.dart';
import 'preferences_provider.dart';
import 'temettu_tahmini_provider.dart';
import 'veri_kalitesi_provider.dart';

export '../services/seni_ilgilendiren_gunler.dart';

/// Kullanıcının kendi bugünkü BIST hisselerinin geçen yılki hak günleri:
/// sembol → günler. Kaynak temettü tahmininin kendisi
/// (`temettuTahminiProvider`; aynı `aktifLotlar` süzgeci, aynı sembol
/// kararı, sembol başına 6 saat önbellek) — ikinci bir temettü yolu yok.
/// Tahmin ekranı Premium; buradan yalnız gün okunur, tutar okunmaz.
/// Yüklenirken ya da hata → boş: satır makro takvimle yetinir.
final temettuHakGunleriProvider =
    Provider.autoDispose<Map<String, List<DateTime>>>((ref) {
  final t = ref.watch(temettuTahminiProvider).valueOrNull;
  if (t == null) return const {};
  return {for (final s in t.satirlar) s.sembol: s.hakGunleri};
});

/// Önümüzdeki [listePenceresiGun] günün kapatılmamış olayları (sayfa).
///
/// Varlık yoksa boş: boş portföyde ana sayfanın işi ilk varlık; "seni
/// ilgilendiren" demek için ilgilenilen bir şey olmalı.
final yaklasanGunlerProvider = Provider.autoDispose<List<GunOlayi>>((ref) {
  final uid = ref.watch(authProvider).valueOrNull?.id;
  if (uid == null) return const [];
  final lotlar = ref.watch(
      portfolioProvider.select((s) => s.valueOrNull?.assets ?? const []));
  if (aktifLotlar(lotlar.where((a) => a.userId == uid)).isEmpty) {
    return const [];
  }
  final bugun = trGunu(ref.watch(veriKalitesiSaatProvider)());
  return yaklasanOlaylar(
    [
      ...makroTakvim,
      ...temettuGunleri(ref.watch(temettuHakGunleriProvider), bugun: bugun),
    ],
    bugun: bugun,
    kapatilanlar: ref.watch(gunlerKapatilanProvider),
  );
});

/// Satırdaki olay: iki gün içindeki ilk olay ya da null.
final takvimSatiriProvider = Provider.autoDispose<GunOlayi?>((ref) {
  final bugun = trGunu(ref.watch(veriKalitesiSaatProvider)());
  return satirOlayi(ref.watch(yaklasanGunlerProvider),
      bugun: bugun, kapatilanlar: const {});
});

/// Ana sayfa tek dürtü yuvası: bilgi eksik > takvim > öneri. Yalnız ana
/// sayfa okur; Portföy sekmesindeki öneri kartı bu sıraya bağlı değil.
final anaSayfaDurtusuProvider = Provider.autoDispose<AnaSayfaDurtusu?>((ref) {
  final eksik = veriSeridiGorunur(ref.watch(veriEksikleriProvider),
      ref.watch(veriKalitesiKapatilanProvider));
  return anaSayfaDurtusu(
    bilgiEksikGorunur: eksik,
    // Eksik satırı görünürken takvim hesaplanmaz bile (temettü ağı yok).
    takvimOlayi: eksik ? null : ref.watch(takvimSatiriProvider),
    oneriVar: ref.watch(ozellikOnerisiProvider) != null,
  );
});
