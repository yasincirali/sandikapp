import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/asset_type.dart';
import '../services/technical_analysis_service.dart';

/// Kullanıcı tercihleri (tema, bildirim, vb.) için merkezi state.
/// SharedPreferences ile kalıcı.
///
/// Kullanım:
///   ref.watch(themeModeProvider) → ThemeMode
///   ref.read(themeModeProvider.notifier).set(ThemeMode.light)

const _kThemeModeKey = 'pref_theme_mode'; // 'system' | 'light' | 'dark'
const _kSignalNotificationsKey = 'pref_signal_notifications';
const _kPartnerNotificationsKey = 'pref_partner_notifications';
const _kBalanceHiddenKey = 'pref_balance_hidden';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.dark; // sandık dark-first
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kThemeModeKey);
      switch (raw) {
        case 'system':
          state = ThemeMode.system;
          break;
        case 'light':
          state = ThemeMode.light;
          break;
        case 'dark':
          state = ThemeMode.dark;
          break;
      }
    } catch (_) {}
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeModeKey, _toString(mode));
    } catch (_) {}
  }

  String _toString(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Bildirim kategorileri için tek tip notifier
class _BoolPrefNotifier extends Notifier<bool> {
  final String key;
  final bool defaultValue;

  _BoolPrefNotifier(this.key, this.defaultValue);

  @override
  bool build() {
    _load();
    return defaultValue;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(key);
      if (v != null) state = v;
    } catch (_) {}
  }

  Future<void> set(bool value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }
}

final signalNotificationsProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kSignalNotificationsKey, true));

final partnerNotificationsProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kPartnerNotificationsKey, true));

final balanceHiddenProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kBalanceHiddenKey, false));

// ─── Premium (in-app purchase stub) ───────────────────────────────────────────
// Şimdilik SharedPreferences ile local toggle. Gerçek IAP entegrasyonu
// yapılana kadar test amaçlı Ayarlar ekranından açılıp kapatılabilir.

const _kPremiumUnlockedKey = 'pref_premium_unlocked';

final premiumUnlockedProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kPremiumUnlockedKey, false));

// ─── Per-category göstergeler ─────────────────────────────────────────────────
// Kullanıcı her varlık türü için hangi göstergelerin sinyal üretmesini istediğini
// seçebilir. Kalıcı: SharedPreferences.

const _kIndicatorPrefsKey = 'pref_indicators_by_type_v1';

class IndicatorPrefsNotifier
    extends Notifier<Map<AssetType, Set<String>>> {
  @override
  Map<AssetType, Set<String>> build() {
    _load();
    // Varsayılan: her tür için tüm temel göstergeler açık
    return {
      for (final t in AssetType.values)
        t: TechnicalAnalysisService.defaultEnabledFor(t),
    };
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_kIndicatorPrefsKey);
      if (raw == null) return;
      // Format: "typeName:id1,id2,id3"
      final next = <AssetType, Set<String>>{};
      for (final entry in raw) {
        final parts = entry.split(':');
        if (parts.length != 2) continue;
        final type = AssetType.fromString(parts[0]);
        final ids = parts[1]
            .split(',')
            .where((s) => s.isNotEmpty && IndicatorId.all.contains(s))
            .toSet();
        next[type] = ids;
      }
      // Eksik türler için varsayılan
      for (final t in AssetType.values) {
        next.putIfAbsent(
            t, () => TechnicalAnalysisService.defaultEnabledFor(t));
      }
      state = next;
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = state.entries
          .map((e) => '${e.key.name}:${e.value.join(',')}')
          .toList();
      await prefs.setStringList(_kIndicatorPrefsKey, entries);
    } catch (_) {}
  }

  Future<void> toggle(AssetType type, String indicatorId) async {
    final current = Set<String>.from(state[type] ?? <String>{});
    if (current.contains(indicatorId)) {
      current.remove(indicatorId);
    } else {
      current.add(indicatorId);
    }
    state = {...state, type: current};
    await _persist();
  }

  Future<void> setForType(AssetType type, Set<String> ids) async {
    state = {...state, type: ids};
    await _persist();
  }

  Set<String> forType(AssetType type) =>
      state[type] ?? TechnicalAnalysisService.defaultEnabledFor(type);
}

final indicatorPrefsProvider =
    NotifierProvider<IndicatorPrefsNotifier, Map<AssetType, Set<String>>>(
  IndicatorPrefsNotifier.new,
);
