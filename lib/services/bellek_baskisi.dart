import 'package:flutter/widgets.dart';

import 'history_service.dart';
import 'mum_verisi.dart';

/// Sistem bellek uyarısında yeniden üretilebilen bellek önbelleklerini
/// bırakır.
///
/// ## Neden (kaynak kullanımı denetimi, 2026-10-12)
/// Uygulamada `didHaveMemoryPressure` karşılığı yoktu: iOS bellek isterken
/// mum ve seri önbellekleri olduğu gibi kalıyordu. Arka plandaki büyük
/// süreç sistemin ilk öldürdüğü süreçtir; kullanıcı her dönüşte soğuk
/// açılış yaşar.
///
/// **Neler bırakılmaz:** gün içi seri önbelleği (`IntradaySeriesCache` —
/// widget, Live Activity, Bugün kartı ve Performans aynı yuvayı okur;
/// boşaltmak yüzeyleri farklı anlarda yeniden çektirip ayrıştırabilirdi),
/// son iyi seriler ve defter. Bırakılanlar yalnızca bir sonraki istekte
/// aynı kaynaktan yeniden gelen süreli kopyalardır.
class BellekBaskisi with WidgetsBindingObserver {
  BellekBaskisi._();
  static final BellekBaskisi instance = BellekBaskisi._();

  bool _bagli = false;

  void baglan() {
    if (_bagli) return;
    WidgetsBinding.instance.addObserver(this);
    _bagli = true;
  }

  @override
  void didHaveMemoryPressure() => birak();

  /// Test ve elle çağrı için.
  void birak() {
    MumVerisi.instance.bellegiBirak();
    HistoryService.bellekBaskisi();
  }
}
