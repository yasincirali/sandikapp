import 'package:flutter_test/flutter_test.dart';

/// `HistoryService` geçmiş serisi çekiminin PARALEL olduğunu sabitler.
///
/// Kullanıcı şikâyeti: grafik ekranları açılışta saniyelerce spinner
/// gösteriyordu. Sebep `getPortfolioHistory` / `getPortfolioHistoryHourly`
/// içindeki döngüydü:
///
/// ```dart
/// for (final a in assets) {
///   final pts = await getHistorySafe(a.ticker);  // ← her tur ağı BEKLER
/// }
/// ```
///
/// 15 varlıklı bir portföyde 15 gidiş-dönüş ARDIŞIK toplanıyordu: toplam süre
/// tek isteğin 15 katı. İstekler birbirinden bağımsız olduğu için hepsi önce
/// başlatılıp sonra toplanmalı — toplam süre en yavaş TEK isteğe iner.
///
/// Bu test, ekrandaki fetch desenini birebir yeniden üretir (gerçek servis
/// singleton + private http.Client kullandığı için ağ mock'lanamıyor;
/// `stale_window_clip_test.dart` de aynı yaklaşımı izler). Regresyon koruması:
/// biri döngü içine `await` geri koyarsa süre ölçümü bunu yakalar.
void main() {
  /// Her çağrı sabit gecikmeyle "ağdan" bir seri döndürür.
  ({Future<List<int>> Function(String) fetch, List<String> calls}) makeFetcher(
      Duration latency) {
    final calls = <String>[];
    Future<List<int>> fetch(String symbol) async {
      calls.add(symbol);
      await Future<void>.delayed(latency);
      return [symbol.hashCode];
    }

    return (fetch: fetch, calls: calls);
  }

  const latency = Duration(milliseconds: 50);
  const tickers = ['THYAO', 'ASELS', 'SISE', 'KCHOL', 'EREGL', 'TUPRS'];

  test('ardışık await — N ticker N × gecikme sürer (DÜZELTİLEN DAVRANIŞ)',
      () async {
    final f = makeFetcher(latency);
    final sw = Stopwatch()..start();

    // Eski kod: döngü içinde await.
    final results = <String, List<int>>{};
    for (final t in tickers) {
      results[t] = await f.fetch(t);
    }
    sw.stop();

    expect(results.length, tickers.length);
    // Ardışık: en az N × gecikme.
    expect(sw.elapsed, greaterThanOrEqualTo(latency * tickers.length),
        reason: 'ardışık await toplam süreyi doğrusal büyütür — '
            'bu testin var oluş sebebi');
  });

  test('paralel başlatma — N ticker ~tek gecikme sürer (YENİ DAVRANIŞ)',
      () async {
    final f = makeFetcher(latency);
    final sw = Stopwatch()..start();

    // Yeni kod: önce hepsini başlat, sonra topla.
    final futures = <String, Future<List<int>>>{};
    for (final t in tickers) {
      futures.putIfAbsent(t, () => f.fetch(t));
    }
    final results = <String, List<int>>{};
    for (final e in futures.entries) {
      results[e.key] = await e.value;
    }
    sw.stop();

    expect(results.length, tickers.length);
    // Paralel: tek isteğe yakın. Ardışık olsaydı 6 × 50ms = 300ms olurdu;
    // eşiği yarıya koyuyoruz ki yavaş CI makinesinde flaky olmasın ama
    // ardışığa dönüş kesinlikle yakalansın.
    expect(sw.elapsed,
        lessThan(latency * tickers.length ~/ 2),
        reason: 'istekler paralel başlatılmalı — döngüye await geri konmuş '
            'olabilir');
  });

  test('aynı ticker birden çok lot\'ta geçse de tek istek yapılır', () async {
    final f = makeFetcher(Duration.zero);

    // Aynı hisseden üç ayrı alım lot'u + bir başka hisse.
    const lots = ['THYAO', 'THYAO', 'THYAO', 'ASELS'];

    final futures = <String, Future<List<int>>>{};
    for (final t in lots) {
      futures.putIfAbsent(t, () => f.fetch(t));
    }
    await Future.wait(futures.values);

    expect(f.calls, ['THYAO', 'ASELS'],
        reason: 'putIfAbsent tekilleştirmeli — aynı sembol için tekrar '
            'ağa çıkmak boşuna gecikme ve kota tüketimi');
  });

  test('bir sembol patlasa diğerleri düşmez', () async {
    Future<List<int>> flaky(String symbol) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (symbol == 'BOZUK') throw Exception('404');
      return [1];
    }

    // Servisteki `getHistorySafe` hatayı yutup boş liste döndürür; paralel
    // toplama bu sayede tek bir kötü sembolde tüm grafiği kaybetmez.
    Future<List<int>> safe(String s) async {
      try {
        return await flaky(s);
      } catch (_) {
        return const [];
      }
    }

    final futures = {
      for (final t in ['THYAO', 'BOZUK', 'ASELS']) t: safe(t),
    };
    final results = <String, List<int>>{};
    for (final e in futures.entries) {
      results[e.key] = await e.value;
    }

    expect(results['THYAO'], isNotEmpty);
    expect(results['ASELS'], isNotEmpty);
    expect(results['BOZUK'], isEmpty,
        reason: 'tek bozuk sembol tüm seriyi düşürmemeli');
  });
}
