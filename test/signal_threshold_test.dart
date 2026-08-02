import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/technical_signal.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';

/// `summarize().confidence` ile eşik karşılaştırmasının aynı ölçekte
/// olduğunu doğrular.
///
/// Bulunan hata: `summarize` oran (0..1) döndürüyordu, `signal_provider`
/// ise 50/70/85 ile karşılaştırıyordu → `confidence < threshold` her zaman
/// doğru → HİÇBİR sinyal eşiği geçemiyordu.
void main() {
  TechnicalIndicator ind(SignalType s) =>
      TechnicalIndicator(name: 'x', value: 0, signal: s, description: '');

  test('confidence 0-100 ölçeğinde döner (0-1 değil)', () {
    // 5 göstergenin 5'i de buy → tam mutabakat.
    final all = List.generate(5, (_) => ind(SignalType.buy));
    final s = TechnicalAnalysisService.summarize(all);

    expect(s.signal, SignalType.buy);
    // Oran 1.0 değil, yüzde 100 olmalı — eşikler (50/70/85) yüzde.
    expect(s.confidence, 100.0,
        reason: 'eşikler yüzde ölçeğinde; confidence de yüzde olmalı');
  });

  test('kısmi mutabakat doğru yüzdeyi verir', () {
    // 3 buy + 2 neutral = %60 buy → tam olarak BUY eşiğinde.
    final mixed = [
      ind(SignalType.buy),
      ind(SignalType.buy),
      ind(SignalType.buy),
      ind(SignalType.neutral),
      ind(SignalType.neutral),
    ];
    final s = TechnicalAnalysisService.summarize(mixed);

    expect(s.signal, SignalType.buy);
    expect(s.confidence, closeTo(60.0, 0.001));
  });

  test('varsayılan eşik (70) gerçekten geçilebilir olmalı', () {
    // 4/5 buy = %80 → varsayılan 70 eşiğini geçmeli.
    final strong = [
      ind(SignalType.buy),
      ind(SignalType.buy),
      ind(SignalType.buy),
      ind(SignalType.buy),
      ind(SignalType.sell),
    ];
    final s = TechnicalAnalysisService.summarize(strong);

    expect(s.confidence, closeTo(80.0, 0.001));
    expect(s.confidence >= kSignalThresholdDefault, isTrue,
        reason: 'güçlü sinyal varsayılan eşiği geçemiyorsa push hiç gitmez');
  });

  test('zayıf sinyal eşiği geçmez', () {
    // 2 buy + 3 neutral = %40 → 70 eşiğinin altında.
    final weak = [
      ind(SignalType.buy),
      ind(SignalType.buy),
      ind(SignalType.neutral),
      ind(SignalType.neutral),
      ind(SignalType.neutral),
    ];
    final s = TechnicalAnalysisService.summarize(weak);

    expect(s.confidence, closeTo(40.0, 0.001));
    expect(s.confidence >= kSignalThresholdDefault, isFalse);
  });
}

/// `preferences_provider.dart` ile aynı değer — test bağımlılığı azaltmak
/// için burada tekrar tanımlı.
const kSignalThresholdDefault = 70;
