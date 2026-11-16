import 'package:flutter/material.dart';

const Color _frontShade = Color(0xFF16183A);
const Color _farShade = Color(0xFF7480F2);

Color cardShade(double depth, {double step = 0.13, double max = 0.85}) {
  final t = (depth * step).clamp(0.0, max);
  return Color.lerp(_frontShade, _farShade, t)!;
}

Color cardShadeEnd(double depth) => Color.lerp(cardShade(depth), Colors.black, 0.2)!;