import 'package:flutter/material.dart';

extension NavigationExtension on BuildContext {
  /// Push a new route
  Future<T?> push<T>(Widget page) =>
      Navigator.push<T>(this, MaterialPageRoute(builder: (_) => page));

  /// Replace current route
  Future<T?> pushReplacement<T>(Widget page) => Navigator.pushReplacement<T, T>(
    this,
    MaterialPageRoute(builder: (_) => page),
  );

  /// Pop the current route
  void pop<T extends Object?>([T? result]) => Navigator.pop(this, result);

  /// Push and remove all previous routes
  Future<T?> pushAndRemoveAll<T>(Widget page) =>
      Navigator.pushAndRemoveUntil<T>(
        this,
        MaterialPageRoute(builder: (_) => page),
        (route) => false,
      );
}
