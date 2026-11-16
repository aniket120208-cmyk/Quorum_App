import 'package:flutter/material.dart';

const int kNameMaxLength = 150;
const int kEmailMaxLength = 150;
const int kPasswordMinLength = 8;
const int kPasswordMaxLength = 16;
const int kCharLimitWarnThreshold = 20;

Widget? charLimitCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) {
  if (maxLength == null || maxLength <= kCharLimitWarnThreshold) return null;
  final left = maxLength - currentLength;
  if (left > kCharLimitWarnThreshold) return null;
  return Semantics(
    liveRegion: true,
    child: Text(
      left <= 0 ? 'Limit reached ($maxLength)' : '$left of $maxLength characters left',
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: Color(0xFFEF4444),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}