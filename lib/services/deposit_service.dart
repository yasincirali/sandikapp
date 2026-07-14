import 'dart:math' as math;

import '../models/asset.dart';
import '../models/asset_type.dart';

/// Vadeli mevduat hesaplamaları.
///
/// Storage: Asset.subCategory bir key=value listesi tutar. Migration'sız
/// çalışmak için tek string'e sığdırıldı:
///   "mevduat|s=<startEpochMs>|e=<endEpochMs>|r=<yıllıkFaiz%>|t=<simple|compound>|w=<stopaj%>"
///
/// `purchasePrice = 1` sabit tutulur; `quantity` = anapara. Böylece Asset
/// modelinin toplam/maliyet mantığı bozulmadan çalışır ve `currentPrice`
/// her açılışta hesaplanan birim değeri temsil eder (1 TL anaparanın şu
/// anki net değeri).
class DepositService {
  DepositService._();

  static const double defaultTaxRate = 15.0; // TR default stopaj

  /// Yeni bir mevduat kaydı için `subCategory` string üret.
  static String encode({
    required DateTime start,
    required DateTime end,
    required double annualRatePct,
    required DepositInterestType interestType,
    required double taxRatePct,
  }) {
    return 'mevduat'
        '|s=${start.millisecondsSinceEpoch}'
        '|e=${end.millisecondsSinceEpoch}'
        '|r=${annualRatePct.toStringAsFixed(4)}'
        '|t=${interestType.name}'
        '|w=${taxRatePct.toStringAsFixed(2)}';
  }

  /// Var olan Asset'ten mevduat parametrelerini çıkar. Bozuk / eksik ise null.
  static DepositTerms? decode(Asset asset) {
    if (asset.type != AssetType.mevduat) return null;
    final raw = asset.subCategory;
    if (raw == null || !raw.startsWith('mevduat')) return null;
    try {
      final parts = raw.split('|');
      int? sMs, eMs;
      double? rate, tax;
      DepositInterestType type = DepositInterestType.simple;
      for (final p in parts.skip(1)) {
        final kv = p.split('=');
        if (kv.length != 2) continue;
        switch (kv[0]) {
          case 's':
            sMs = int.tryParse(kv[1]);
            break;
          case 'e':
            eMs = int.tryParse(kv[1]);
            break;
          case 'r':
            rate = double.tryParse(kv[1]);
            break;
          case 't':
            type = kv[1] == 'compound'
                ? DepositInterestType.compound
                : DepositInterestType.simple;
            break;
          case 'w':
            tax = double.tryParse(kv[1]);
            break;
        }
      }
      if (sMs == null || eMs == null || rate == null) return null;
      return DepositTerms(
        start: DateTime.fromMillisecondsSinceEpoch(sMs),
        end: DateTime.fromMillisecondsSinceEpoch(eMs),
        annualRatePct: rate,
        interestType: type,
        taxRatePct: tax ?? defaultTaxRate,
        taxWasProvided: tax != null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Şu ana kadar birikmiş **birim (1 TL anapara başına)** net değer.
  /// Asset.currentPrice bu değerle güncellenir → totalValue = quantity × unitValue
  /// otomatik doğru sonucu verir. Vade sonundan sonra sabit kalır (banka
  /// kapatana kadar bileşik faiz işlemez varsayımı).
  static double currentUnitValue(DepositTerms t, {DateTime? now}) {
    final n = now ?? DateTime.now();
    if (!n.isAfter(t.start)) return 1.0;
    final effectiveNow = n.isAfter(t.end) ? t.end : n;
    final elapsedDays = effectiveNow.difference(t.start).inDays;
    if (elapsedDays <= 0) return 1.0;
    final grossPerUnit = _grossPerUnit(t, elapsedDays);
    final interest = grossPerUnit - 1.0;
    final netInterest = interest * (1.0 - t.taxRatePct / 100.0);
    return 1.0 + netInterest;
  }

  /// Vade sonundaki birim net değer.
  static double maturityUnitValue(DepositTerms t) {
    final termDays = t.end.difference(t.start).inDays;
    if (termDays <= 0) return 1.0;
    final gross = _grossPerUnit(t, termDays);
    final interest = gross - 1.0;
    final netInterest = interest * (1.0 - t.taxRatePct / 100.0);
    return 1.0 + netInterest;
  }

  /// Vadeye kalan gün (negatif → vade dolmuş).
  static int daysToMaturity(DepositTerms t, {DateTime? now}) {
    final n = now ?? DateTime.now();
    return t.end.difference(n).inDays;
  }

  /// Vade doldu mu?
  static bool isMatured(DepositTerms t, {DateTime? now}) {
    final n = now ?? DateTime.now();
    return !n.isBefore(t.end);
  }

  /// 1 TL anapara başına brüt getiri katsayısı (basit veya bileşik).
  static double _grossPerUnit(DepositTerms t, int elapsedDays) {
    final r = t.annualRatePct / 100.0;
    if (t.interestType == DepositInterestType.simple) {
      final years = elapsedDays / 365.0;
      return 1.0 + r * years;
    }
    // Bileşik: (1 + r/365)^days (günlük kapitalizasyon — TR banka standardı)
    final dailyRate = r / 365.0;
    return math.pow(1.0 + dailyRate, elapsedDays).toDouble();
  }
}

/// Basit / Bileşik faiz.
enum DepositInterestType {
  simple('Basit Faiz'),
  compound('Bileşik Faiz (günlük)');

  final String label;
  const DepositInterestType(this.label);
}

/// Bir mevduatın çözümlenmiş parametreleri.
class DepositTerms {
  final DateTime start;
  final DateTime end;
  final double annualRatePct;
  final DepositInterestType interestType;
  final double taxRatePct;

  /// Kullanıcı stopajı elle girmediyse false → UI "default stopaj kullanıldı"
  /// bilgilendirmesi göstermeli.
  final bool taxWasProvided;

  const DepositTerms({
    required this.start,
    required this.end,
    required this.annualRatePct,
    required this.interestType,
    required this.taxRatePct,
    required this.taxWasProvided,
  });

  int get termDays => end.difference(start).inDays;
}
