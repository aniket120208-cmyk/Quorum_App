enum CalendarEventType {
  reminder,
  meeting,
  deadline,
  general;

  String get apiValue {
    switch (this) {
      case CalendarEventType.reminder:
        return 'REMINDER';
      case CalendarEventType.meeting:
        return 'MEETING';
      case CalendarEventType.deadline:
        return 'DEADLINE';
      case CalendarEventType.general:
        return 'GENERAL';
    }
  }

  String get label {
    switch (this) {
      case CalendarEventType.reminder:
        return 'Reminder';
      case CalendarEventType.meeting:
        return 'Meeting';
      case CalendarEventType.deadline:
        return 'Deadline';
      case CalendarEventType.general:
        return 'General';
    }
  }

  static CalendarEventType fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'REMINDER':
        return CalendarEventType.reminder;
      case 'MEETING':
        return CalendarEventType.meeting;
      case 'DEADLINE':
        return CalendarEventType.deadline;
      default:
        return CalendarEventType.general;
    }
  }
}

class CalendarEvent {
  final String id;
  final String title;
  final String? description;
  final CalendarEventType eventType;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isAllDay;
  final String? meetingLink;
  final List<String> attendeeEmails;
  final bool hasReminder;
  final int? reminderMinutes;

  const CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    required this.eventType,
    required this.startDate,
    this.endDate,
    this.isAllDay = false,
    this.meetingLink,
    this.attendeeEmails = const [],
    this.hasReminder = false,
    this.reminderMinutes,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    final link = json['meetingLink']?.toString().trim();
    final description = json['description']?.toString();
    return CalendarEvent(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: description == null || description.trim().isEmpty ? null : description,
      eventType: CalendarEventType.fromString(json['eventType']?.toString()),
      startDate: DateTime.parse(json['startDate'].toString()).toLocal(),
      endDate: json['endDate'] == null
          ? null
          : DateTime.tryParse(json['endDate'].toString())?.toLocal(),
      isAllDay: json['isAllDay'] == true,
      meetingLink: link == null || link.isEmpty ? null : link,
      attendeeEmails: (json['attendeeEmails'] as List<dynamic>? ?? [])
          .map((email) => email.toString())
          .toList(),
      hasReminder: json['hasReminder'] == true,
      reminderMinutes: (json['reminderMinutes'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'title': title,
      'eventType': eventType.apiValue,
      'startDate': startDate.toUtc().toIso8601String(),
      'isAllDay': isAllDay,
      'hasReminder': hasReminder,
    };
    if (description != null && description!.trim().isNotEmpty) {
      map['description'] = description;
    }
    if (endDate != null) {
      map['endDate'] = endDate!.toUtc().toIso8601String();
    }
    if (meetingLink != null && meetingLink!.trim().isNotEmpty) {
      map['meetingLink'] = meetingLink;
    }
    if (attendeeEmails.isNotEmpty) {
      map['attendeeEmails'] = attendeeEmails;
    }
    if (hasReminder) {
      map['reminderMinutes'] = reminderMinutes ?? 15;
    }
    return map;
  }

  Map<String, dynamic> changesFrom(CalendarEvent old) {
    final changes = <String, dynamic>{};
    if (title != old.title) changes['title'] = title;
    if ((description ?? '') != (old.description ?? '')) {
      changes['description'] = description;
    }
    if (eventType != old.eventType) changes['eventType'] = eventType.apiValue;
    if (!startDate.isAtSameMomentAs(old.startDate)) {
      changes['startDate'] = startDate.toUtc().toIso8601String();
    }
    final endChanged = (endDate == null) != (old.endDate == null) ||
        (endDate != null && !endDate!.isAtSameMomentAs(old.endDate!));
    if (endChanged) {
      changes['endDate'] = endDate?.toUtc().toIso8601String();
    }
    if (isAllDay != old.isAllDay) changes['isAllDay'] = isAllDay;
    if ((meetingLink ?? '') != (old.meetingLink ?? '')) {
      changes['meetingLink'] = meetingLink;
    }
    if (!_sameEmails(attendeeEmails, old.attendeeEmails)) {
      changes['attendeeEmails'] = attendeeEmails;
    }
    if (hasReminder != old.hasReminder) changes['hasReminder'] = hasReminder;
    if (hasReminder && reminderMinutes != old.reminderMinutes) {
      changes['reminderMinutes'] = reminderMinutes ?? 15;
    }
    return changes;
  }

  static bool _sameEmails(List<String> a, List<String> b) {
    final first = a.map((e) => e.toLowerCase()).toSet();
    final second = b.map((e) => e.toLowerCase()).toSet();
    return first.length == second.length && first.containsAll(second);
  }

  DateTime get effectiveEnd => endDate ?? startDate.add(const Duration(hours: 1));

  bool get hasMeetingLink => meetingLink != null && meetingLink!.isNotEmpty;

  bool get isPast => effectiveEnd.isBefore(DateTime.now());

  bool occursOn(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = DateTime(date.year, date.month, date.day + 1);
    final end = endDate ?? startDate;

    if (!end.isAfter(startDate)) {
      return !startDate.isBefore(dayStart) && startDate.isBefore(dayEnd);
    }
    return startDate.isBefore(dayEnd) && end.isAfter(dayStart);
  }

  static int compare(CalendarEvent a, CalendarEvent b) {
    if (a.isAllDay != b.isAllDay) return a.isAllDay ? -1 : 1;
    return a.startDate.compareTo(b.startDate);
  }
}