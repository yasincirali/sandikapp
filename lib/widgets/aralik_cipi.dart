import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart' show dayKey;

/// Bir getiri yüzdesinin ÖLÇÜLDÜĞÜ aralığı yazan küçük etiket.
///
/// ## Neden var (kullanıcı kararı D2, 2026-10-01)
/// Özet'te üç ayrı yüzde üç ayrı aralığı ölçüyor: ana rakam dönem
/// başından BUGÜNE, reel getiri son açıklanmış TÜFE ayının sonuna, XIRR
/// ilk alımdan bugüne. Aralıklar göreli etiketle ("son 1 yıl") ya da
/// kartın dibinde yazılıyordu ve kullanıcı "+%23" ile "+8,3 puan önde"yi
/// çelişki olarak okudu. Çip aralığı rakamın YANINA koyar: göz rakamı
/// okurken aralığı da okur.
///
/// ## Neden tek widget
/// Üç kart aynı soruyu (bu yüzde hangi aralıkta?) aynı biçimde yanıtlamalı;
/// her kartın kendi etiketi olsaydı biri "→", biri "-", biri ay adı
/// yazardı. Tasarım: `info` tonu — aralık bir BİLGİ, kazanç/kayıp değil
/// (yeşil/kırmızı yön söylerdi), marka amberi de değil (amber eylem/vurgu).
class AralikCipi extends StatelessWidget {
  const AralikCipi(this.metin, {super.key});

  final String metin;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.xs2, vertical: SandikSpace.xxs),
      decoration: BoxDecoration(
        // Zemin tonun kendisi değil, şeffaf bir izi: metin `info` rengiyle
        // okunur (light 5.17:1), zemin yalnızca etiketi gövdeden ayırır.
        color: c.info.withValues(alpha: 0.12),
        borderRadius: SandikRadius.smAll,
      ),
      child: Text(
        metin,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.t.bodySmall
            ?.copyWith(color: c.info, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Çip metinleri — SAF; `BuildContext` almaz ki testler tarihi sabitleyerek
/// sınayabilsin. [dil] `context.tarihDili` ('tr_TR' / 'en_US').
class AralikMetni {
  AralikMetni._();

  static bool _ayniGun(DateTime a, DateTime b) => dayKey(a) == dayKey(b);

  /// Gün çözünürlüklü aralık: "1 Eki 25 - bugün".
  ///
  /// Pencere bugünde bitiyorsa sağ uç "bugün" yazılır: rakam canlı fiyatla
  /// kapanıyor ve tarih yazmak onu dünkü bir ölçüm gibi okuturdu.
  static String gunlu(AppLocalizations l, String dil,
      {required DateTime bas, required DateTime son, required DateTime simdi}) {
    final f = DateFormat('d MMM yy', dil);
    return l.rangeChip(
      f.format(bas),
      _ayniGun(son, simdi) ? l.rangeToday : f.format(son),
    );
  }

  /// Tek günlük pencere (GÜNLÜK): bugünse "Bugün", değilse "29 Eylül"
  /// (hafta sonu son seansı gösterir).
  static String tekGun(AppLocalizations l, String dil,
          {required DateTime gun, required DateTime simdi}) =>
      _ayniGun(gun, simdi)
          ? l.todayWord
          : DateFormat('d MMMM', dil).format(gun);

  /// Ay çözünürlüklü aralık (TÜFE penceresi): "Ağu 25 - Ağu 26"; tek ay
  /// "Ağustos 2026".
  ///
  /// Gün yazılmaz: endeks aylık bir ölçüm ve "31 Ağustos" yazmak, o gün
  /// yapılmış bir ölçüm varmış izlenimi verirdi. [bas]/[bitis] portföy
  /// serisinin uçlarıdır (`InflationWindow.seriBaslangici` / `seriBitisi`:
  /// ayın SON günü); tek ay = "Temmuz sonu → Ağustos sonu" = Ağustos.
  static String aylik(AppLocalizations l, String dil,
      {required DateTime bas, required DateTime bitis}) {
    if (tekAyMi(bas, bitis)) return DateFormat('MMMM yyyy', dil).format(bitis);
    final f = DateFormat('MMM yy', dil);
    return l.rangeChip(f.format(bas), f.format(bitis));
  }

  /// Pencere tek bir TÜFE ayını mı ölçüyor?
  static bool tekAyMi(DateTime bas, DateTime bitis) =>
      (bitis.year - bas.year) * 12 + (bitis.month - bas.month) == 1;

  /// ÖLÇÜLEN ayların aralığı (müşteri testi, 2026-10-01).
  ///
  /// [aylik] uçları yazıyordu: 3A'da "May 26 - Ağu 26" dört ay gibi
  /// okunuyordu, oysa ölçüm Mayıs SONU → Ağustos sonu = Haziran, Temmuz,
  /// Ağustos. Burada ilk ÖLÇÜLEN ay yazılır: "Haz - Ağu 26". Tek ay ay
  /// adıyla ("Ağustos 2026"); on iki ay TÜİK diliyle ("Ağu 25 - Ağu 26")
  /// — kullanıcı yıllık enflasyonu TÜİK'te o uçlarla doğruluyor.
  static String olculenAylar(AppLocalizations l, String dil,
      {required DateTime bas, required DateTime bitis}) {
    final ayAdedi = (bitis.year - bas.year) * 12 + (bitis.month - bas.month);
    if (ayAdedi <= 1) return DateFormat('MMMM yyyy', dil).format(bitis);
    if (ayAdedi == 12) return aylik(l, dil, bas: bas, bitis: bitis);
    final ilkOlculen = DateTime(bas.year, bas.month + 1, 1);
    return l.rangeChip(
      DateFormat('MMM', dil).format(ilkOlculen),
      DateFormat('MMM yy', dil).format(bitis),
    );
  }
}
