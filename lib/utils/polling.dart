import 'dart:async';

import 'package:flutter/widgets.dart';

/// Ekran açıkken periyodik yenileme; uygulama arka plana gidince DURUR,
/// öne gelince hemen bir tur atıp yeniden kurulur.
///
/// 2026-09 denetimi: profil ve ortaklık istekleri ekranları 5 saniyede bir
/// Supabase turu atıyordu ve uygulama arka planda kalsa da sürüyordu. Bir
/// tur tamamlanmadan yenisi başlamaz (`_busy`); yavaş ağda istekler
/// üst üste binmez.
class ForegroundPoller with WidgetsBindingObserver {
  ForegroundPoller({required this.interval, required this.onTick});

  final Duration interval;
  final Future<void> Function() onTick;

  Timer? _timer;
  bool _busy = false;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      await onTick();
    } finally {
      _busy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
      _arm();
    } else {
      _timer?.cancel();
    }
  }

  void dispose() {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }
}

/// Bir sonucu bekleyen yoklama — aralık her turda büyür, tavana dayanır,
/// toplam süre dolunca kendini kapatır.
///
/// Profildeki "davet kabul edildi mi" yoklaması sabit 3 saniyeydi ve
/// karşı taraf hiç yanıt vermezse ekran kapanana kadar sürüyordu. Şimdi:
/// 3 → 5 → 8 → 12 → 15 sn (tavan), en fazla [maxTotal] boyunca.
class BackoffPoller {
  BackoffPoller({
    required this.check,
    this.initial = const Duration(seconds: 3),
    this.max = const Duration(seconds: 15),
    this.factor = 1.6,
    this.maxTotal = const Duration(minutes: 10),
    this.onGiveUp,
  });

  /// `true` dönerse yoklama biter (sonuç geldi).
  final Future<bool> Function() check;
  final Duration initial;
  final Duration max;
  final double factor;
  final Duration maxTotal;
  final VoidCallback? onGiveUp;

  Timer? _timer;
  Duration _current = Duration.zero;
  Duration _elapsed = Duration.zero;
  bool _cancelled = false;

  void start() {
    _cancelled = false;
    _current = initial;
    _elapsed = Duration.zero;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_cancelled) return;
    if (_elapsed >= maxTotal) {
      onGiveUp?.call();
      return;
    }
    _timer = Timer(_current, () async {
      if (_cancelled) return;
      _elapsed += _current;
      final done = await check();
      if (done || _cancelled) return;
      final next = Duration(milliseconds: (_current.inMilliseconds * factor).round());
      _current = next > max ? max : next;
      _schedule();
    });
  }

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
  }
}
