import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/home_widget_service.dart';

/// Ana ekrana widget yerleştirme kapısı (Ar-Ge 7 Kas 14:30 #5).
///
/// Varsayılan gerçek servis; testte sahte kapıyla ezilir ki Ayarlar satırının
/// "destek var/yok" görünürlüğü platform kanalı olmadan sınanabilsin.
final widgetSabitleyiciProvider =
    Provider<WidgetSabitleyici>((_) => HomeWidgetService.instance);

/// Launcher desteği bir kez sorulur; cevap gelene kadar ve hata olursa satır
/// görünmez (servis hatayı non-fatal kaydedip `false` döner).
final widgetSabitlemeDestegiProvider = FutureProvider<bool>(
    (ref) => ref.watch(widgetSabitleyiciProvider).sabitlemeDestekleniyorMu());
