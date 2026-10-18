import 'package:flutter/material.dart';

const _card = Color(0xFF14151F);
const _cardBorder = Color(0x1AFFFFFF);
const _teal = Color(0xFF3DDCC4);
const _muted = Color(0xFF9EA3AE);

class CalendarCard extends StatefulWidget {
  const CalendarCard({super.key});

  @override
  State<CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  late DateTime _visibleMonth;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _resetToToday();
  }

  void _resetToToday() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month);
      _selected = DateTime(now.year, now.month, now.day);
    });
  }

  bool _isTodaySelected() {
    final now = DateTime.now();
    return _selected.year == now.year &&
        _selected.month == now.month &&
        _selected.day == now.day;
  }

  void _changeMonth(int delta) {
    setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta));
  }

  Future<void> _pickMonth() async {
    int year = _visibleMonth.year;
    bool isPickingYear = false;

    final result = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _navButton(Icons.chevron_left, () {
                          setSheet(() => year--);
                        }),
                        GestureDetector(
                          onTap: () {
                            setSheet(() => isPickingYear = !isPickingYear);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isPickingYear ? const Color(0xFF16302F) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isPickingYear ? _teal : Colors.white24,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$year',
                                  style: TextStyle(
                                    color: isPickingYear ? _teal : Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  isPickingYear ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                                  color: isPickingYear ? _teal : Colors.white70,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                        _navButton(Icons.chevron_right, () {
                          setSheet(() => year++);
                        }),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (isPickingYear)
                      SizedBox(
                        height: 190,
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.9,
                          ),
                          itemCount: 51,
                          itemBuilder: (context, idx) {
                            final itemYear = 2000 + idx;
                            final isCurrent = itemYear == year;
                            return GestureDetector(
                              onTap: () {
                                setSheet(() {
                                  year = itemYear;
                                  isPickingYear = false;
                                });
                              },
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isCurrent ? const Color(0xFF3FA79A) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isCurrent ? _teal : _cardBorder),
                                ),
                                child: Text(
                                  '$itemYear',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    else
                      GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.9,
                        children: List.generate(12, (i) {
                          final isCurrent = year == _visibleMonth.year && i + 1 == _visibleMonth.month;
                          return GestureDetector(
                            onTap: () => Navigator.pop(ctx, DateTime(year, i + 1)),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isCurrent ? const Color(0xFF3FA79A) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isCurrent ? _teal : _cardBorder),
                              ),
                              child: Text(
                                _months[i].substring(0, 3),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
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
    if (result != null) {
      setState(() => _visibleMonth = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offset = DateTime(_visibleMonth.year, _visibleMonth.month, 1).weekday % 7;
    final isToday = _isTodaySelected();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Calendar',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _pickMonth,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_months[_visibleMonth.month - 1].substring(0, 3)} ${_visibleMonth.year}',
                        style: const TextStyle(color: _teal, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.keyboard_arrow_down, color: _teal, size: 16),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _resetToToday,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isToday ? const Color(0xFF16302F) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isToday ? _teal : Colors.white24,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'Today',
                    style: TextStyle(
                      color: isToday ? _teal : _muted.withAlpha(140),
                      fontSize: 11,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _navButton(Icons.chevron_left, () => _changeMonth(-1)),
              const SizedBox(width: 6),
              _navButton(Icons.chevron_right, () => _changeMonth(1)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: _weekdays
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d, style: const TextStyle(color: _muted, fontSize: 11)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: List.generate(42, (i) {
              final date = DateTime(_visibleMonth.year, _visibleMonth.month, 1 - offset + i);
              final inMonth = date.month == _visibleMonth.month;
              final isSelected = date.year == _selected.year && date.month == _selected.month && date.day == _selected.day;
              return GestureDetector(
                onTap: () => setState(() => _selected = date),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF3FA79A) : Colors.transparent,
                    shape: BoxShape.circle,
                    border: isSelected ? Border.all(color: _teal, width: 1.5) : null,
                  ),
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      color: isSelected ? Colors.white : inMonth ? Colors.white : Colors.white24,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, color: Colors.white70, size: 18),
        ),
      );
}