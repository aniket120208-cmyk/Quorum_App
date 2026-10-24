import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/calendar_repository.dart';
import 'package:quorum_app/api/notification_service.dart';
import 'package:quorum_app/models/calendar_models.dart';
import 'package:quorum_app/models/notification_models.dart';
import 'package:quorum_app/screens/home_screen/calendar_helpers.dart';
import 'package:quorum_app/screens/home_screen/calendar_screen.dart';
import 'package:quorum_app/screens/video_call_screen/meeting_launcher.dart';

const _card = Color(0xFF14151F);
const _cardBorder = Color(0x1AFFFFFF);
const _teal = calendarTeal;
const _muted = Color(0xFF9EA3AE);

class CalendarCard extends StatefulWidget {
  const CalendarCard({super.key});

  @override
  State<CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> with WidgetsBindingObserver {
  static const _months = [
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
  static const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  late DateTime _visibleMonth;
  late DateTime _selected;
  List<CalendarEvent> _events = [];
  List<CalendarEvent> _selectedEvents = [];
  bool _loading = true;
  String? _error;
  int _requestId = 0;
  StreamSubscription<NotificationItem>? _notificationSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    _notificationSub = NotificationService.instance.incoming.listen((item) {
      if (item.type == NotificationType.eventReminder) {
        _loadMonth(silent: true);
      }
    });

    _loadMonth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMonth(silent: true);
    }
  }

  Future<void> _loadMonth({bool silent = false}) async {
    final requestId = ++_requestId;
    final month = _visibleMonth;
    final selected = _selected;

    if (!silent) {
      setState(() {
        _loading = true;
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
        _events = events;
        _selectedEvents =
            events.where((event) => event.occursOn(selected)).toList();
        _error = null;
      });

      final dayEvents = await CalendarRepository.instance.getDay(
        selected,
        known: events,
      );

      if (!mounted || requestId != _requestId) return;

      setState(() {
        _selectedEvents = dayEvents;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        if (!silent) {
          _error = e is ApiException && e.statusCode == 401
              ? 'Your session may have expired. Please sign in again.'
              : 'Unable to load calendar events.';
        }
      });
    }
  }

  Future<void> _loadSelectedDate() async {
    final requestId = ++_requestId;
    final selected = _selected;

    try {
      final dayEvents = await CalendarRepository.instance.getDay(
        selected,
        known: _events,
      );

      if (!mounted || requestId != _requestId) return;

      setState(() {
        _selectedEvents = dayEvents;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _selectedEvents =
            _events.where((event) => event.occursOn(selected)).toList();
        _loading = false;
      });
    }
  }

  void _resetToToday() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month);
      _selected = DateTime(now.year, now.month, now.day);
    });
    _loadMonth();
  }

  bool _isTodaySelected() => calendarSameDay(_selected, DateTime.now());

  bool _hasEvent(DateTime date) {
    return _events.any((event) => event.occursOn(date));
  }

  void _changeMonth(int delta) {
    final month = DateTime(_visibleMonth.year, _visibleMonth.month + delta);

    setState(() {
      _visibleMonth = month;
      _selected = calendarDefaultSelection(month);
      _selectedEvents = [];
    });

    _loadMonth();
  }

  void _selectDate(DateTime date) {
    final monthChanged = date.year != _visibleMonth.year ||
        date.month != _visibleMonth.month;

    setState(() {
      _selected = DateTime(date.year, date.month, date.day);

      if (monthChanged) {
        _visibleMonth = DateTime(date.year, date.month);
        _selectedEvents = [];
      } else {
        _selectedEvents =
            _events.where((event) => event.occursOn(_selected)).toList();
      }
    });

    if (monthChanged) {
      _loadMonth();
    } else {
      _loadSelectedDate();
    }
  }

  Future<void> _pickMonth() async {
    int year = _visibleMonth.year;

    final result = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _navButton(
                          Icons.chevron_left,
                          () => setSheet(() => year--),
                        ),
                        Text(
                          '$year',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        _navButton(
                          Icons.chevron_right,
                          () => setSheet(() => year++),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.8,
                      children: List.generate(12, (index) {
                        final month = index + 1;
                        final selected = year == _visibleMonth.year && month == _visibleMonth.month;

                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Navigator.pop(
                            sheetContext,
                            DateTime(year, month),
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? const Color(0xFF16302F) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected ? _teal : _cardBorder,
                              ),
                            ),
                            child: Text(
                              _months[index].substring(0, 3),
                              style: TextStyle(
                                color: selected ? _teal : Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    setState(() {
      _visibleMonth = result;
      _selected = calendarDefaultSelection(result);
      _selectedEvents = [];
    });
    _loadMonth();
  }

  Future<void> _openFullCalendar() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CalendarScreen(),
      ),
    );

    if (mounted) {
      _loadMonth(silent: true);
    }
  }

  Future<void> _joinEvent(CalendarEvent event) async {
    final link = event.meetingLink;
    if (link == null) return;
    final opened = await MeetingLauncher.join(link, title: event.title);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Unable to open the meeting link.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final offset = DateTime(_visibleMonth.year, _visibleMonth.month, 1).weekday % 7;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Calendar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: GestureDetector(
                  onTap: _pickMonth,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '${_months[_visibleMonth.month - 1].substring(0, 3)} ${_visibleMonth.year}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _teal,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        color: _teal,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _resetToToday,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _isTodaySelected()
                        ? const Color(0xFF16302F)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isTodaySelected() ? _teal : Colors.white24,
                    ),
                  ),
                  child: Text(
                    'Today',
                    style: TextStyle(
                      color: _isTodaySelected() ? _teal : _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _navButton(
                Icons.chevron_left,
                () => _changeMonth(-1),
              ),
              const SizedBox(width: 6),
              _navButton(
                Icons.chevron_right,
                () => _changeMonth(1),
              ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              color: _teal,
              minHeight: 2,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFFF8A80),
                fontSize: 12,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _loadMonth,
                child: const Text(
                  'Retry',
                  style: TextStyle(color: _teal),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: _weekdays
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 11,
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
              crossAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              final date = DateTime(
                _visibleMonth.year,
                _visibleMonth.month,
                1 - offset + index,
              );

              final inMonth = date.month == _visibleMonth.month;
              final selected = calendarSameDay(date, _selected);
              final today = calendarSameDay(date, DateTime.now());
              final hasEvent = _hasEvent(date);

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
                            ? const Color(0xFF3FA79A)
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
                          color: selected
                              ? Colors.white
                              : inMonth
                                  ? Colors.white
                                  : Colors.white24,
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.w500,
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_months[_selected.month - 1].substring(0, 3)} ${_selected.day} · ${_selectedEvents.length} ${_selectedEvents.length == 1 ? 'event' : 'events'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _openFullCalendar,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View calendar',
                      style: TextStyle(
                        color: _teal,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward,
                      color: _teal,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!_loading && _selectedEvents.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No events for this day.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ),
            ),
          ..._selectedEvents.take(3).map(_eventRow),
          if (_selectedEvents.length > 3)
            GestureDetector(
              onTap: _openFullCalendar,
              child: Text(
                '+${_selectedEvents.length - 3} more events',
                style: const TextStyle(color: _teal, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _eventRow(CalendarEvent event) {
    final canJoin = event.hasMeetingLink && !event.isPast;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(
              color: calendarEventColor(event.eventType),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openFullCalendar,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${calendarTimeLabel(context, event)} · ${event.eventType.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (canJoin) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _joinEvent(event),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF16302F),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _teal),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_rounded, color: _teal, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Join',
                      style: TextStyle(
                        color: _teal,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(
          icon,
          color: Colors.white70,
          size: 18,
        ),
      ),
    );
  }
}