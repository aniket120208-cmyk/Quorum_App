import 'dart:math';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/meeting_api.dart';
import 'package:quorum_app/models/calendar_models.dart';
import 'package:quorum_app/screens/home_screen/calendar_helpers.dart';

const _background = Color(0xFF0F101A);
const _card = Color(0xFF14151F);
const _teal = calendarTeal;
const _muted = Color(0xFF9EA3AE);

class CalendarEventForm extends StatefulWidget {
  final CalendarEvent? event;
  final DateTime initialDate;

  const CalendarEventForm({
    super.key,
    this.event,
    required this.initialDate,
  });

  @override
  State<CalendarEventForm> createState() => _CalendarEventFormState();
}

class _CalendarEventFormState extends State<CalendarEventForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _meetingLinkController;
  late final TextEditingController _attendeesController;

  late CalendarEventType _eventType;
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;

  bool _isAllDay = false;
  bool _hasReminder = false;
  bool _creatingLink = false;
  int _reminderMinutes = 15;

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _isEditing => widget.event != null;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final now = DateTime.now();
    final isToday = calendarSameDay(widget.initialDate, now);
    final defaultHour = isToday ? min(now.hour + 1, 22) : 9;
    final start = event?.startDate ??
        DateTime(
          widget.initialDate.year,
          widget.initialDate.month,
          widget.initialDate.day,
          defaultHour,
        );
    final end = event?.endDate ?? start.add(const Duration(hours: 1));

    _titleController = TextEditingController(text: event?.title ?? '');
    _descriptionController =
        TextEditingController(text: event?.description ?? '');
    _meetingLinkController =
        TextEditingController(text: event?.meetingLink ?? '');
    _attendeesController = TextEditingController(
      text: event?.attendeeEmails.join(', ') ?? '',
    );

    _eventType = event?.eventType ?? CalendarEventType.general;
    _startDate = DateTime(start.year, start.month, start.day);
    _startTime = TimeOfDay.fromDateTime(start);
    _endDate = DateTime(end.year, end.month, end.day);
    _endTime = TimeOfDay.fromDateTime(end);
    _isAllDay = event?.isAllDay ?? false;
    _hasReminder = event?.hasReminder ?? false;
    _reminderMinutes = event?.reminderMinutes ?? 15;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _meetingLinkController.dispose();
    _attendeesController.dispose();
    super.dispose();
  }

  DateTime _combine(DateTime date, TimeOfDay time) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _teal,
            surface: _card,
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      if (isStart) {
        _startDate = DateTime(picked.year, picked.month, picked.day);
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = DateTime(picked.year, picked.month, picked.day);
        if (_endDate.isBefore(_startDate)) {
          _startDate = _endDate;
        }
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _teal,
            surface: _card,
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  String _dateLabel(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _timeLabel(TimeOfDay time) {
    return time.format(context);
  }

  Future<void> _createMeetingLink() async {
    if (_creatingLink) return;
    setState(() => _creatingLink = true);
    try {
      final meeting = await MeetingApi.instance.createMeeting();
      if (!mounted) return;
      setState(() => _meetingLinkController.text = meeting.link);
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('Unable to create a meeting link.');
    } finally {
      if (mounted) setState(() => _creatingLink = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  List<String> _parseAttendees() {
    final seen = <String>{};
    final result = <String>[];
    for (final part in _attendeesController.text.split(RegExp(r'[,;\s]+'))) {
      final email = part.trim();
      if (email.isEmpty) continue;
      if (seen.add(email.toLowerCase())) result.add(email);
    }
    return result;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final DateTime start;
    final DateTime end;
    if (_isAllDay) {
      start = DateTime(_startDate.year, _startDate.month, _startDate.day);
      end = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59);
    } else {
      start = _combine(_startDate, _startTime);
      end = _combine(_endDate, _endTime);
    }

    if (end.isBefore(start)) {
      _showMessage('End date cannot be earlier than start date');
      return;
    }

    final description = _descriptionController.text.trim();
    final link = _meetingLinkController.text.trim();

    final event = CalendarEvent(
      id: widget.event?.id ?? '',
      title: _titleController.text.trim(),
      description: description.isEmpty ? null : description,
      eventType: _eventType,
      startDate: start,
      endDate: end,
      isAllDay: _isAllDay,
      meetingLink: link.isEmpty ? null : link,
      attendeeEmails: _parseAttendees(),
      hasReminder: _hasReminder,
      reminderMinutes: _hasReminder ? _reminderMinutes : null,
    );
    Navigator.pop(context, event);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: Text(_isEditing ? 'Edit event' : 'Create event'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle('Event details'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Event title'),
                maxLength: 120,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Enter an event title';
                  if (text.length > 120) {
                    return 'Title must be 120 characters or fewer';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: _inputDecoration('Description (optional)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CalendarEventType>(
                value: _eventType,
                dropdownColor: _card,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Event type'),
                items: CalendarEventType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.label),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _eventType = value);
                  }
                },
              ),
              const SizedBox(height: 24),
              _sectionTitle('Date and time'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'All-day event',
                  style: TextStyle(color: Colors.white),
                ),
                activeColor: _teal,
                value: _isAllDay,
                onChanged: (value) => setState(() => _isAllDay = value),
              ),
              _dateTile(
                label: 'Start date',
                value: _dateLabel(_startDate),
                onTap: () => _pickDate(isStart: true),
              ),
              if (!_isAllDay)
                _dateTile(
                  label: 'Start time',
                  value: _timeLabel(_startTime),
                  onTap: () => _pickTime(isStart: true),
                ),
              _dateTile(
                label: 'End date',
                value: _dateLabel(_endDate),
                onTap: () => _pickDate(isStart: false),
              ),
              if (!_isAllDay)
                _dateTile(
                  label: 'End time',
                  value: _timeLabel(_endTime),
                  onTap: () => _pickTime(isStart: false),
                ),
              const SizedBox(height: 24),
              _sectionTitle('Meeting and attendees'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _meetingLinkController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Meeting link (optional)'),
                keyboardType: TextInputType.url,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return null;
                  final uri = Uri.tryParse(text);
                  final valid = uri != null &&
                      (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
                  return valid ? null : 'Enter a valid link starting with https://';
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _creatingLink ? null : _createMeetingLink,
                  icon: _creatingLink
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _teal,
                          ),
                        )
                      : const Icon(Icons.videocam_rounded, color: _teal, size: 18),
                  label: const Text('Create Quorum meeting link', style: TextStyle(color: _teal),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _attendeesController,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                decoration: _inputDecoration(
                  'Attendee emails, separated by commas',
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final text = value ?? '';
                  for (final part in text.split(RegExp(r'[,;\s]+'))) {
                    final email = part.trim();
                    if (email.isEmpty) continue;
                    if (!_emailPattern.hasMatch(email)) {
                      return '"$email" is not a valid email';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Set a reminder',
                  style: TextStyle(color: Colors.white),
                ),
                activeColor: _teal,
                value: _hasReminder,
                onChanged: (value) => setState(() => _hasReminder = value),
              ),
              if (_hasReminder)
                DropdownButtonFormField<int>(
                  value: _reminderMinutes,
                  dropdownColor: _card,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Remind me before'),
                  items: _reminderOptions(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _reminderMinutes = value);
                    }
                  },
                ),
              const SizedBox(height: 28),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: _background,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),),
                  ),
                  child: Text(
                    _isEditing ? 'Save changes' : 'Create event',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<DropdownMenuItem<int>> _reminderOptions() {
    final options = <int, String>{
      5: '5 minutes',
      10: '10 minutes',
      15: '15 minutes',
      30: '30 minutes',
      60: '1 hour',
      1440: '1 day',
    };
    if (!options.containsKey(_reminderMinutes)) {
      options[_reminderMinutes] = '$_reminderMinutes minutes';
    }
    final keys = options.keys.toList()..sort();
    return [
      for (final key in keys)
        DropdownMenuItem(value: key, child: Text(options[key]!)),
    ];
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _teal,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _muted),
      filled: true,
      fillColor: _card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _teal),
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(label, style: const TextStyle(color: _muted)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(color: Colors.white)),
          const SizedBox(width: 8),
          const Icon(Icons.calendar_month, color: _teal, size: 20),
        ],
      ),
    );
  }
}