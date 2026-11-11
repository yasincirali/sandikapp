import 'package:flutter/material.dart';

import '../theme/sandik.dart';

/// Aşağı çekip yenile — uygulamadaki TEK sarmalayıcı (2026-11-11).
///
/// ## Neden ortak bileşen
/// Çekip yenileme ~13 ekranda ayrı ayrı `RefreshIndicator.adaptive` olarak
/// yazılmıştı; "eşikte hafif tık" gibi bir davranış her ekrana tek tek
/// eklenmek zorunda kalırdı ve biri unutulunca ekranlar birbirinden farklı
/// hissederdi. Artık her ekran bunu kullanır; kilit
/// `test/sandik_yenile_test.dart` (lib/ altında başka `RefreshIndicator`
/// kalmaz).
///
/// ## Eşikte tık
/// Kullanıcı yenileme eşiğini geçtiği an (bıraksa yenilenecek) BİR kez
/// [SandikHaptic.selection] verilir — iOS'un kendi yenileme kontrolündeki
/// "artık bırakabilirsin" tıkının karşılığı. Ölçeğin en hafif tonu seçildi:
/// günde çok kez yapılan, sonucu kalıcı olmayan bir jest.
///
/// Eşik tespiti kendi kaydırma hesabımızla değil, Flutter'ın KENDİ
/// "bırakınca yenilenir" kararıyla yapılır: [RefreshIndicatorStatus.armed].
/// `RefreshIndicator.adaptive` bu durumu dışarı vermiyor (`onStatusChange`
/// yalnız `RefreshIndicator.noSpinner`'da var), bu yüzden çocuğun hemen
/// üstüne göstergesiz bir `noSpinner` eşi konur: aynı kaydırma
/// bildirimlerini aynı eşikle işler, armed'a göstergeyle aynı karede geçer;
/// kendi `onRefresh`'i boştur (asıl iş dıştaki adaptive'de). Kopyalanmış bir
/// eşik sayısı (görüntü yüksekliği / 6) Flutter değişince sessizce
/// kayardı; eş gösterge kaymaz. `RefreshIndicator` bir çekişte armed'a en
/// fazla bir kez geçer (armed → drag dönüşü yok; geri çekmek çekişi
/// `canceled` ile bitirir), dolayısıyla "çekiş başına bir tık" ayrıca sayaç
/// gerektirmez.
///
/// Davranış sözleşmesi: [onRefresh] ve görünüm parametreleri
/// `RefreshIndicator.adaptive`'e aynen geçer; sarmalayıcı sonucu yorumlamaz,
/// hatayı yutmaz.
class SandikYenile extends StatelessWidget {
  const SandikYenile({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color,
    this.backgroundColor,
    this.displacement = 40.0,
    this.edgeOffset = 0.0,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.triggerMode = RefreshIndicatorTriggerMode.onEdge,
    this.semanticsLabel,
    this.semanticsValue,
    this.onStatusChange,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final Color? color;
  final Color? backgroundColor;
  final double displacement;
  final double edgeOffset;
  final ScrollNotificationPredicate notificationPredicate;
  final RefreshIndicatorTriggerMode triggerMode;
  final String? semanticsLabel;
  final String? semanticsValue;

  /// Çağıranın da durumu izlemesi gerekirse; tık bundan bağımsız verilir.
  final ValueChanged<RefreshIndicatorStatus?>? onStatusChange;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator.adaptive(
      onRefresh: onRefresh,
      color: color,
      backgroundColor: backgroundColor,
      displacement: displacement,
      edgeOffset: edgeOffset,
      notificationPredicate: notificationPredicate,
      triggerMode: triggerMode,
      semanticsLabel: semanticsLabel,
      semanticsValue: semanticsValue,
      child: RefreshIndicator.noSpinner(
        onRefresh: _bos,
        notificationPredicate: notificationPredicate,
        triggerMode: triggerMode,
        onStatusChange: (RefreshIndicatorStatus? durum) {
          if (durum == RefreshIndicatorStatus.armed) {
            SandikHaptic.selection.perform();
          }
          onStatusChange?.call(durum);
        },
        child: child,
      ),
    );
  }

  static Future<void> _bos() async {}
}
