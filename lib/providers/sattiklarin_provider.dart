import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gorunum_kapsami.dart' show portfoyLotlari;
import '../models/kapanis_ozeti.dart';
import 'auth_provider.dart';
import 'portfolio_provider.dart';
import 'portfoy_provider.dart' show portfoyKapsamiProvider;

/// Portföy ekranının "Sattıkların" listesi: kullanıcının kendi defterinde,
/// seçili portföy kapsamında kapanmış pozisyonlar (Premium, 2026-11-12).
///
/// Hesap [kapanmisPozisyonlar]'da (saf); burası yalnız girdiyi seçer ve
/// sonucu önbellekte tutar, ekran `build()` içinde defteri yürümez. Yalnız
/// kullanıcının lotları: durum ortak lotlarını da taşır (Birlikte), ortağın
/// kapattığı pozisyon kullanıcının "sattıkları" değildir. Portföy kapsamı
/// listeyle aynı (`portfoyKapsamiProvider`): "Ana"da başka portföyün
/// satışı görünmez.
///
/// Ekran bunu yalnız "Ben" görünümünde, sekme gerçekten görülünce ve
/// Premium özellikleri görünürken izler: kapsam sağlayıcısı portföy
/// listesini çeker, önceden kurulumda ağ isteği başlamasın.
final sattiklarinProvider = Provider.autoDispose<List<KapanmisPozisyon>>((ref) {
  final uid = ref.watch(authProvider.select((u) => u.valueOrNull?.id));
  final lotlar = ref.watch(
    portfolioProvider.select((s) => s.valueOrNull?.assets),
  );
  if (uid == null || lotlar == null) return const [];
  final kapsam = ref.watch(portfoyKapsamiProvider);
  return kapanmisPozisyonlar(
    portfoyLotlari(
      [
        for (final a in lotlar)
          if (a.userId == uid) a,
      ],
      kapsam.secim,
      kapsam.bilinen,
    ),
  );
});

/// Sattıkların sayfasının başındaki özet ([sattiklarinToplami]); liste
/// değişmedikçe yeniden hesaplanmaz.
final sattiklarinToplamiProvider = Provider.autoDispose<SattiklarinToplami>(
  (ref) => sattiklarinToplami(ref.watch(sattiklarinProvider)),
);
