import 'package:flutter/material.dart';
import 'package:quorum_app/models/calendar_models.dart';

const calendarTeal = Color(0xFF3DDCC4);

Color calendarEventColor(CalendarEventType type) {
  switch (type) {
    case CalendarEventType.meeting:
      return const Color(0xFF60A5FA);
    case CalendarEventType.deadline:
      return const Color(0xFFFB7185);
    case CalendarEventType.reminder:
      return const Color(0xFFFBBF24);
    case CalendarEventType.general:
      return calendarTeal;
  }
}

bool calendarSameDay(DateTime first, DateTime second) {
  return first.year == second.year && first.month == second.month && first.day == second.day;
}

String calendarTimeLabel(BuildContext context, CalendarEvent event) {
  if (event.isAllDay) return 'All day';
  final localizations = MaterialLocalizations.of(context);
  final start = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(event.startDate),
  );
  final end = event.endDate;
  if (end == null || !end.isAfter(event.startDate)) return start;
  final endLabel = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(end));
  if (calendarSameDay(event.startDate, end)) return '$start - $endLabel';
  return '$start - ${end.day}/${end.month} $endLabel';
}

DateTime calendarDefaultSelection(DateTime month) {
  final now = DateTime.now();
  if (month.year == now.year && month.month == now.month) {
    return DateTime(now.year, now.month, now.day);
  }
  return DateTime(month.year, month.month, 1);
}