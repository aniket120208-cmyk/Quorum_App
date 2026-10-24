import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/calendar_repository.dart';
import 'package:quorum_app/api/notification_service.dart';
import 'package:quorum_app/models/calendar_models.dart';
import 'package:quorum_app/models/notification_models.dart';
import 'package:quorum_app/screens/home_screen/calendar_event_form.dart';
import 'package:quorum_app/screens/home_screen/calendar_helpers.dart';
import 'package:quorum_app/screens/video_call_screen/meeting_launcher.dart';

const _background = Color(0xFF0F101A);
const _card = Color(0xFF14151F);
const _border = Color(0x1AFFFFFF);
const _teal = calendarTeal;
const _muted = Color(0xFF9EA3AE);

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  List<CalendarEvent> _monthEvents = [];
  List<CalendarEvent> _dayEvents = [];
  bool _loading = true;
  bool _dayLoading = false;
  String? _error;
  int _requestId = 0;
  StreamSubscription<NotificationItem>? _notificationSub;

  static const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  void initState() {
    super.initState();
    _notificationSub = NotificationService.instance.incoming.listen((item) {
      if (item.type == NotificationType.eventReminder) {
        _loadMonth(silent: true);
      }
    });
    _loadMonth();
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMonth({bool silent = false}) async {
    final requestId = ++_requestId;
    final month = _month;
    final selected = _selectedDate;

    if (mounted && !silent) {
      setState(() {
        _loading = true;
        _dayLoading = true;
        _error = null;
      });
    }

    try {
      final events = await CalendarRepository.instance.getMonth(
        year: month.year,
        month: month.month,
      );

      if (!mounted || requestId != _requestId) return;
      setState(() {
        _monthEvents = events;
        _dayEvents = events.where((e) => e.occursOn(selected)).toList();
        _loading = false;
      });

      final dayEvents = await CalendarRepository.instance.getDay(
        selected,
        known: events,
      );

      if (!mounted || requestId != _requestId) return;
      setState(() {
        _dayEvents = dayEvents;
        _dayLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _dayLoading = false;
        if (!silent) _error = _errorMessage(e);
      });
    }
  }

  Future<void> _loadDay() async {
    final requestId = ++_requestId;
    final selected = _selectedDate;

    setState(() {
      _dayLoading = true;
      _dayEvents = _monthEvents.where((e) => e.occursOn(selected)).toList();
    });

    try {
      final events = await CalendarRepository.instance.getDay(
        selected,
        known: _monthEvents,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _dayEvents = events;
        _dayLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _dayLoading = false;
        _error = _errorMessage(e);
      });
    }
  }

  String _errorMessage(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 401) {
        return 'Your session may have expired. Please sign in again.';
      }
      if (error.statusCode != null && error.statusCode! < 500) {
        return error.message;
      }
    }
    return 'Unable to load calendar events. Please try again.';
  }

  void _changeMonth(int delta) {
    final month = DateTime(_month.year, _month.month + delta);
    setState(() {
      _month = month;
      _selectedDate = calendarDefaultSelection(month);
      _dayEvents = [];
    });
    _loadMonth();
  }

  void _selectDate(DateTime date) {
    final monthChanged =
        date.year != _month.year || date.month != _month.month;

    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
      if (monthChanged) {
        _month = DateTime(date.year, date.month);
        _dayEvents = [];
      }
    });

    if (monthChanged) {
      _loadMonth();
    } else {
      _loadDay();
    }
  }

  bool _sameDay(DateTime first, DateTime second) {
    return calendarSameDay(first, second);
  }

  bool _hasEventOn(DateTime date) {
    return _monthEvents.any((event) => event.occursOn(date));
  }

  String _monthLabel(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _dateLabel(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _openEventForm({CalendarEvent? event}) async {
    final result = await Navigator.push<CalendarEvent>(
      context,
      MaterialPageRoute(
        builder: (_) => CalendarEventForm(
          event: event,
          initialDate: _selectedDate,
        ),
      ),
    );

    if (result == null || !mounted) return;

    try {
      if (event == null) {
        await CalendarRepository.instance.create(result);
      } else {
        final changes = result.changesFrom(event);
        if (changes.isEmpty) return;
        await CalendarRepository.instance.update(event.id, changes);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(event == null ? 'Event created' : 'Event updated'),
        ),
      );

      final target = result.startDate;
      setState(() {
        _month = DateTime(target.year, target.month);
        _selectedDate = DateTime(target.year, target.month, target.day);
      });

      await _loadMonth();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(e))),
      );
    }
  }

  Future<void> _joinEvent(CalendarEvent event) async {
    final link = event.meetingLink;
    if (link == null) return;
    final opened = await MeetingLauncher.join(link, title: event.title);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the meeting link.')),
      );
    }
  }

  Future<void> _deleteEvent(CalendarEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _card,
        title: const Text(
          'Delete event?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Delete "${event.title}"?',
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: _muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await CalendarRepository.instance.delete(event.id);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event deleted')),
      );

      await _loadMonth();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(e))),
      );
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Select a date in the month',
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
      _month = DateTime(picked.year, picked.month);
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
      _dayEvents = [];
    });

    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text('Calendar'),
        actions: [
          IconButton(
            onPressed: () => _loadMonth(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh calendar',
          ),
          IconButton(
            onPressed: () => _openEventForm(),
            icon: const Icon(Icons.add, color: _teal),
            tooltip: 'Create event',
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: _teal,
          onRefresh: () => _loadMonth(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _buildCalendar(),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _dateLabel(_selectedDate),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openEventForm(),
                    icon: const Icon(Icons.add, color: _teal, size: 18),
                    label: const Text(
                      'Add event',
                      style: TextStyle(color: _teal),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_dayLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(color: _teal),
                  ),
                )
              else if (_error != null && _dayEvents.isEmpty)
                _messageCard(_error!, action: () => _loadMonth())
              else if (_dayEvents.isEmpty)
                _messageCard('No events scheduled for this day.')
              else
                ..._dayEvents.map(_eventTile),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    final offset = DateTime(_month.year, _month.month, 1).weekday % 7;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _pickMonth,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          _monthLabel(_month),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down,
                        color: _teal,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _changeMonth(-1),
                icon: const Icon(
                  Icons.chevron_left,
                  color: Colors.white,
                ),
              ),
              IconButton(
                onPressed: () => _changeMonth(1),
                icon: const Icon(
                  Icons.chevron_right,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          if (_loading)
            const LinearProgressIndicator(color: _teal)
          else if (_error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFF8A80)),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: _weekdays
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            itemCount: 42,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 4,
            ),
            itemBuilder: (context, index) {
              final date = DateTime(
                _month.year,
                _month.month,
                1 - offset + index,
              );
              final inMonth = date.month == _month.month;
              final selected = _sameDay(date, _selectedDate);
              final today = _sameDay(date, DateTime.now());
              final hasEvent = _hasEventOn(date);

              return InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _selectDate(date),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF246B63)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? _teal
                              : today
                                  ? _teal.withAlpha(120)
                                  : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          color: inMonth ? Colors.white : Colors.white24,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: hasEvent ? _teal : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: _teal,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Scheduled events',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  final now = DateTime.now();
                  _selectDate(DateTime(now.year, now.month, now.day));
                },
                child: const Text(
                  'Today',
                  style: TextStyle(color: _teal),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _eventTile(CalendarEvent event) {
    final time = calendarTimeLabel(context, event);
    final canJoin = event.hasMeetingLink && !event.isPast;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 52,
            decoration: BoxDecoration(
              color: calendarEventColor(event.eventType),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$time · ${event.eventType.label}',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                if ((event.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    event.description!,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
                if (event.attendeeEmails.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.people_outline, color: _muted, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.attendeeEmails.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                if (event.hasReminder && event.reminderMinutes != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.notifications_none_rounded,
                        color: _muted,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _reminderLabel(event.reminderMinutes!),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ],
                if (event.hasMeetingLink) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (canJoin)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _teal,
                            foregroundColor: _background,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            minimumSize: const Size(0, 32),
                          ),
                          onPressed: () => _joinEvent(event),
                          icon: const Icon(Icons.videocam_rounded, size: 16),
                          label: const Text(
                            'Join meeting',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (canJoin) const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.meetingLink!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _teal, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            color: _card,
            iconColor: _muted,
            onSelected: (value) {
              if (value == 'edit') {
                _openEventForm(event: event);
              } else if (value == 'delete') {
                _deleteEvent(event);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: Text(
                  'Edit',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFFF8A80)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _reminderLabel(int minutes) {
    if (minutes % 1440 == 0) {
      final days = minutes ~/ 1440;
      return 'Reminder $days ${days == 1 ? 'day' : 'days'} before';
    }
    if (minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return 'Reminder $hours ${hours == 1 ? 'hour' : 'hours'} before';
    }
    return 'Reminder $minutes min before';
  }

  Widget _messageCard(String message, {Future<void> Function()? action}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted),
          ),
          if (action != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: action,
              child: const Text(
                'Retry',
                style: TextStyle(color: _teal),
              ),
            ),
          ],
        ],
      ),
    );
  }
}