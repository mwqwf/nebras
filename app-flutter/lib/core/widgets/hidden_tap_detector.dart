import 'dart:async';

import 'package:flutter/material.dart';

class HiddenTapDetector extends StatefulWidget {
  const HiddenTapDetector({
    super.key,
    required this.ontriggered,
    required this.child,
    required this.requiredTaps,
  });
  final VoidCallback ontriggered;
  final Widget child;
  final int requiredTaps;
  @override
  State<HiddenTapDetector> createState() => _HiddenTapDetectorState();
}

class _HiddenTapDetectorState extends State<HiddenTapDetector> {
  int _tapCount = 0;
  Timer? _resetTimer;

  void _registerTap() {
    _tapCount++;
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      _tapCount = 0;
    });

    if (_tapCount >= widget.requiredTaps) {
      _tapCount = 0;
      widget.ontriggered();
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _registerTap,
      child: widget.child,
    );
  }
}
