import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quorum_app/api/ai_service.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/ai_model.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'ai_history_screen.dart';
import 'ai_widgets.dart';

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({super.key});

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  static const Color darkBg = Color(0xFF0F101A);

  static const Map<AiMode, List<String>> _examples = {
    AiMode.chat: [
      'How do I invite collaborators to a team?',
      'Give me tips for running a sprint review',
    ],
    AiMode.search: [
      'Upcoming deadlines',
      'Recent decisions from meetings',
    ],
  };

  final _inputCtrl = TextEditingController();
  final _contextCtrl = TextEditingController();
  final _scopeIdCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<AiTurn> _turns = [];
  int _nextId = 0;
  bool _pending = false;

  AiMode _mode = AiMode.chat;
  AiScope _scope = AiScope.organization;
  String _timeframe = 'last_7_days';
  String _replyMode = 'replies';
  String _tone = 'professional';
  bool _remember = true;
  bool _showContext = false;
  String? _formError;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _contextCtrl.dispose();
    _scopeIdCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String? _chatContext() {
    final parts = <String>[];
    final manual = _contextCtrl.text.trim();
    if (manual.isNotEmpty) parts.add(manual);

    if (_remember) {
      final prior = _turns
          .where((t) =>
              t.mode == AiMode.chat &&
              t.state == TurnState.done &&
              (t.result?.answer ?? '').isNotEmpty)
          .toList();
      final recent = prior.length > 4 ? prior.sublist(prior.length - 4) : prior;
      for (final t in recent) {
        parts.add('User: ${t.prompt}\nAssistant: ${t.result!.answer}');
      }
    }

    if (parts.isEmpty) return null;
    var joined = parts.join('\n\n');
    if (joined.length > 10000) joined = joined.substring(joined.length - 10000);
    return joined;
  }

  void _submit() {
    if (_pending) return;
    final mode = _mode;
    final text = _inputCtrl.text.trim();
    if (!mode.promptOptional && text.isEmpty) return;

    String scopeId = '';
    if (mode.needsScope) {
      scopeId = _scopeIdCtrl.text.trim();
      if (!aiUuidPattern.hasMatch(scopeId)) {
        setState(() => _formError = 'Enter a valid ${_scope.label.toLowerCase()} ID (UUID format).');
        return;
      }
    }
    setState(() => _formError = null);

    final svc = AiService.instance;
    late Future<AiResult> Function() run;
    String? caption;

    switch (mode) {
      case AiMode.chat:
        final ctx = _chatContext();
        run = () => svc.chat(text, context: ctx);
        break;
      case AiMode.search:
        run = () => svc.search(text);
        break;
      case AiMode.project:
        final scope = _scope;
        run = () => svc.projectAssistance(text, scope, scopeId);
        caption = scope.label;
        break;
      case AiMode.replies:
        final rm = _replyMode;
        final tone = _tone;
        run = () => svc.quickReplies(mode: rm, tone: tone, message: text);
        caption = '${aiReplyModes[rm]} · $tone';
        break;
      case AiMode.update:
        final scope = _scope;
        final tf = _timeframe;
        run = () => svc.projectUpdate(tf, scope, scopeId);
        caption = '${scope.label} · ${aiTimeframes[tf]}';
        break;
    }

    final turn = AiTurn(
      id: _nextId++,
      mode: mode,
      prompt: text,
      caption: caption,
      run: run,
    );
    setState(() => _turns.add(turn));
    _inputCtrl.clear();
    _scrollToEnd();
    _execute(turn);
  }

  void _setTurn(int id, AiTurn Function(AiTurn t) change) {
    if (!mounted) return;
    final i = _turns.indexWhere((t) => t.id == id);
    if (i == -1) return;
    setState(() => _turns[i] = change(_turns[i]));
  }

  Future<void> _execute(AiTurn turn) async {
    if (!mounted) return;
    setState(() => _pending = true);
    _setTurn(turn.id, (t) => t.copyWith(state: TurnState.loading));
    try {
      final result = await turn.run();
      _setTurn(turn.id, (t) => t.copyWith(state: TurnState.done, result: result));
    } catch (e) {
      _setTurn(
        turn.id,
        (t) => t.copyWith(state: TurnState.error, error: errorText(e)),
      );
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pasteScopeId() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    setState(() {
      _scopeIdCtrl.text = text;
      _formError = null;
    });
  }

  InputDecoration _fieldDecoration(String hint, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textSecondary),
      suffixIcon: suffix,
      filled: true,
      fillColor: darkBg,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.surfaceBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }

  Widget _hideCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) => const SizedBox.shrink();

  Widget _modeBar() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: AiMode.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final m = AiMode.values[i];
          final selected = m == _mode;
          return GestureDetector(
            onTap: () => setState(() {
              _mode = m;
              _formError = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.surfaceBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    m.icon,
                    size: 16,
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    m.label,
                    style: TextStyle(
                      color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    final examples = _examples[_mode] ?? const <String>[];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(_mode.icon, color: AppColors.primaryLight, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              _mode.emptyTitle,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _mode.emptyBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            if (examples.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: examples
                    .map(
                      (e) => ActionChip(
                        label: Text(e),
                        labelStyle: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                        ),
                        backgroundColor: AppColors.surface,
                        side: const BorderSide(color: AppColors.surfaceBorder),
                        onPressed: () => setState(() => _inputCtrl.text = e),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _choiceChips<T>(
    Map<T, String> options,
    T selected,
    ValueChanged<T> onSelect,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: options.entries
          .map(
            (e) => ChoiceChip(
              label: Text(e.value),
              selected: e.key == selected,
              showCheckmark: false,
              onSelected: (_) => onSelect(e.key),
              selectedColor: AppColors.primary,
              backgroundColor: Colors.transparent,
              side: BorderSide(
                color: e.key == selected
                    ? AppColors.primary
                    : AppColors.surfaceBorder,
              ),
              labelStyle: TextStyle(
                fontSize: 12,
                color: e.key == selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _scopeControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<AiScope>(
            showSelectedIcon: false,
            segments: AiScope.values
                .map((s) => ButtonSegment<AiScope>(value: s, label: Text(s.label)))
                .toList(),
            selected: {_scope},
            onSelectionChanged: (v) => setState(() {
              _scope = v.first;
              _formError = null;
            }),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              foregroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected)
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected)
                    ? AppColors.primary
                    : Colors.transparent,
              ),
              side: const WidgetStatePropertyAll(
                BorderSide(color: AppColors.surfaceBorder),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _scopeIdCtrl,
          onChanged: (_) {
            if (_formError != null) setState(() => _formError = null);
          },
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: _fieldDecoration(
            '${_scope.label} ID',
            suffix: IconButton(
              tooltip: 'Paste',
              icon: const Icon(Icons.content_paste, size: 18, color: AppColors.textSecondary),
              onPressed: _pasteScopeId,
            ),
          ),
        ),
      ],
    );
  }

  Widget _configPanel() {
    final children = <Widget>[];

    switch (_mode) {
      case AiMode.chat:
        children.add(Row(
          children: [
            Switch(
              value: _remember,
              activeTrackColor: AppColors.primary,
              onChanged: (v) => setState(() => _remember = v),
            ),
            const SizedBox(width: 4),
            const Expanded(
              child: Text(
                'Remember this conversation',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _showContext = !_showContext),
              child: Text(_showContext ? 'Hide context' : 'Add context'),
            ),
          ],
        ));
        if (_showContext) {
          children.add(TextField(
            controller: _contextCtrl,
            maxLength: 10000,
            maxLines: 3,
            minLines: 2,
            buildCounter: _hideCounter,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: _fieldDecoration('Paste a discussion or notes for context'),
          ));
        }
        break;
      case AiMode.search:
        break;
      case AiMode.project:
        children.add(_scopeControls());
        break;
      case AiMode.update:
        children.add(_scopeControls());
        children.add(const SizedBox(height: 8));
        children.add(_choiceChips<String>(
          aiTimeframes,
          _timeframe,
          (v) => setState(() => _timeframe = v),
        ));
        break;
      case AiMode.replies:
        children.add(_choiceChips<String>(
          aiReplyModes,
          _replyMode,
          (v) => setState(() => _replyMode = v),
        ));
        children.add(const SizedBox(height: 4));
        children.add(_choiceChips<String>(
          {for (final t in aiTones) t: t},
          _tone,
          (v) => setState(() => _tone = v),
        ));
        break;
    }

    if (_formError != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          _formError!,
          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
        ),
      ));
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _inputBar() {
    final isUpdate = _mode == AiMode.update;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: _configPanelVisible ? null : const Border(top: BorderSide(color: AppColors.surfaceBorder)),
        ),
        child: isUpdate
            ? SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _pending ? null : _submit,
                  icon: _pending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Generate status update'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: darkBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.surfaceBorder),
                      ),
                      child: TextField(
                        controller: _inputCtrl,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: _mode == AiMode.search ? 1000 : 10000,
                        buildCounter: _hideCounter,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: _mode.inputHint,
                          hintStyle: const TextStyle(color: AppColors.textSecondary),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _pending ? null : _submit,
                    icon: _pending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(Icons.send_rounded, color: AppColors.primary),
                  ),
                ],
              ),
      ),
    );
  }

  bool get _configPanelVisible => _mode != AiMode.search || _formError != null;

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiHistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: darkBg,
        elevation: 0,
        title: const Text(
          'AI Assistant',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Clear conversation',
            icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.textPrimary),
            onPressed: (_turns.isEmpty || _pending)
                ? null
                : () => setState(_turns.clear),
          ),
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history, color: AppColors.textPrimary),
            onPressed: _openHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          _modeBar(),
          Expanded(
            child: _turns.isEmpty
                ? _emptyState()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: _turns.length,
                    itemBuilder: (context, i) {
                      final t = _turns[i];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          UserPromptBubble(turn: t),
                          AiResponseCard(
                            turn: t,
                            onRetry: () {
                              if (!_pending) _execute(t);
                            },
                          ),
                        ],
                      );
                    },
                  ),
          ),
          _configPanel(),
          _inputBar(),
        ],
      ),
    );
  }
}