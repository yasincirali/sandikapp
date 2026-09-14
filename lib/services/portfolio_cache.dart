import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/pref_keys.dart';
import '../models/asset.dart';

/// Son bilinen varlık defteri — çevrimdışı açılış için.
///
/// Değerlendirme (2026-09) §5.7: tek önbellek 45 saniyelik bellek içi fiyat
/// önbelleğiydi; uçakta uygulama açılamıyordu. Burada yalnızca DEFTER
/// (assets satırları, `toSupabase` biçiminde) saklanır; fiyatlar satırların
/// içindeki `current_price` ile gelir — yani "son görülen fiyatlar". Bu
/// bilinçli: fiyat önbelleği ayrı bir iş, ve bayat fiyatı taze diye
/// göstermek yerine ekranda "çevrimdışı" şeridi çıkar.
///
/// Kullanıcı kimliğine bağlı anahtar: aynı cihazda iki hesap birbirinin
/// defterini görmez. Çıkışta silinir (`clear`).
abstract final class PortfolioCache {
  static String _key(String userId) =>
      '${PrefKeys.portfolioCachePrefix}$userId';

  static Future<void> write(String userId, List<Asset> assets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'v': 1,
        'at': DateTime.now().toUtc().toIso8601String(),
        'assets': assets.map((a) => a.toSupabase()).toList(),
      });
      await prefs.setString(_key(userId), payload);
    } catch (e) {
      // Önbellek yazımı asla ana akışı bozmaz.
      if (kDebugMode) debugPrint('[PortfolioCache] yazılamadı: $e');
    }
  }

  static Future<List<Asset>?> read(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final rows = (map['assets'] as List).cast<Map<String, dynamic>>();
      return rows.map(Asset.fromSupabase).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[PortfolioCache] okunamadı: $e');
      return null;
    }
  }

  static Future<void> clear(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
    } catch (_) {}
  }
}
