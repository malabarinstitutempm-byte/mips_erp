import 'dart:async';
import 'package:flutter/material.dart';

class InactivityService {
  static final InactivityService instance = InactivityService._internal();
  InactivityService._internal();

  static const Duration timeoutDuration = Duration(days: 5);
  Timer? _inactivityTimer;
  VoidCallback? _onTimeoutCallback;
  bool _isActive = false;

  void start({required VoidCallback onTimeout}) {
    _onTimeoutCallback = onTimeout;
    _isActive = true;
    resetTimer();
  }

  void stop() {
    _isActive = false;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  void resetTimer() {
    if (!_isActive) return;
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(timeoutDuration, () {
      if (_isActive && _onTimeoutCallback != null) {
        _onTimeoutCallback!();
      }
    });
  }
}

/// Widget that wraps interactive screens to detect pointer or keyboard input
class InactivityWatcher extends StatelessWidget {
  final Widget child;

  const InactivityWatcher({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => InactivityService.instance.resetTimer(),
      onPointerMove: (_) => InactivityService.instance.resetTimer(),
      onPointerHover: (_) => InactivityService.instance.resetTimer(),
      child: child,
    );
  }
}
