import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:quorum_app/api/ai_service.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/api/socket_service.dart' show SocketService, asMap;
import 'package:quorum_app/api/quorumbot_service.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/models/quorumbot_models.dart';
import 'package:quorum_app/screens/video_call_screen/meeting_launcher.dart';
import 'package:quorum_app/widgets/incoming_call_dialog.dart';

enum UltronMode { command, ask }

class UltronController extends ChangeNotifier {
  UltronController._();
  static final UltronController instance = UltronController._();

  final List<UltronMessage> messages = [];
  List<Organization> organizations = [];
  Organization? selectedOrg;
  UltronMode mode = UltronMode.command;
  UltronMode thinkingMode = UltronMode.command;
  bool active = false;
  bool open = false;
  bool thinking = false;
  int _seq = 0;
  bool _listening = false;
  bool handsFree = true;
  bool listening = false;
  String transcript = '';
  bool _voiceHandled = false;
  final SpeechToText _speech = SpeechToText();
  final Set<String> _awaiting = {};
  final Map<String, DateTime> _launched = {};

  void activate() {
    if (active) return;
    active = true;
    _bind();
    _loadOrgs();
    notifyListeners();
  }

  void deactivate() {
    _cancelVoice();
    active = false;
    open = false;
    thinking = false;
    messages.clear();
    organizations = [];
    selectedOrg = null;
    _unbind();
    notifyListeners();
  }

  void _bind() {
    if (_listening) return;
    _listening = true;
    SocketService.instance.on('workflow:completed', _onCompleted);
    SocketService.instance.on('call:ready', _onCallReady);
    SocketService.instance.on('meeting:started', _onMeetingStarted);
    SocketService.instance.on('meeting:incoming-call', _onIncomingCall);
  }

  void _unbind() {
    if (!_listening) return;
    _listening = false;
    SocketService.instance.off('workflow:completed', _onCompleted);
    SocketService.instance.off('call:ready', _onCallReady);
    SocketService.instance.off('meeting:started', _onMeetingStarted);
    SocketService.instance.off('meeting:incoming-call', _onIncomingCall);
  }

  bool _claimLaunch(String code) {
    final now = DateTime.now();
    _launched.removeWhere((_, t) => now.difference(t) > const Duration(minutes: 2));
    if (_launched.containsKey(code)) return false;
    _launched[code] = now;
    return true;
  }

  void _launchMeeting(String code, String title, {bool host = true}) {
    if (code.isEmpty || !_claimLaunch(code)) return;
    if (open) {
      open = false;
      notifyListeners();
    }
    MeetingLauncher.joinCode(code, title: title, isHost: host);
  }

  void _autoLaunch(UltronExecution exec) {
    final step = exec.meetingStep;
    if (step == null) return;
    _launchMeeting(step.meetingCode!, step.title);
  }

  void _onCallReady(dynamic data) {
    final m = asMap(data);
    if (m == null) return;
    final title = (m['title'] ?? '').toString();
    _launchMeeting((m['meetingCode'] ?? '').toString(), title.isEmpty ? 'Video call' : title);
  }

  void _onMeetingStarted(dynamic data) {
    final m = asMap(data);
    if (m == null) return;
    final host = (m['hostId'] ?? m['hostUserId'] ?? m['startedBy'] ?? m['createdBy'] ?? '').toString();
    if (host.isEmpty || host != CurrentUser.id) return;
    final title = (m['title'] ?? '').toString();
    _launchMeeting((m['meetingCode'] ?? '').toString(), title.isEmpty ? 'Video call' : title);
  }

  void _onIncomingCall(dynamic data) {
    final m = asMap(data);
    if (m == null) return;
    final code = (m['meetingCode'] ?? '').toString();
    if (code.isEmpty || _launched.containsKey(code)) return;
    final host = (m['hostName'] ?? '').toString();
    final title = (m['title'] ?? '').toString();
    IncomingCall.show(
      hostName: host.isEmpty ? 'Someone' : host,
      title: title.isEmpty ? 'Video call' : title,
      onAccept: () => _launchMeeting(code, title.isEmpty ? 'Video call' : title, host: false),
    );
  }

  void _onCompleted(dynamic data) {
    final m = asMap(data);
    if (m == null || m.isEmpty) return;
    final planId = (m['planId'] ?? '').toString();
    _awaiting.remove(planId);
    final known = messages.any((e) => e.plan?.planId == planId && (e.settled || e.busy)) ||
        (planId.isNotEmpty && messages.any((e) => e.execution?.planId == planId));
    if (known) return;
    final exec = UltronExecution.fromJson(m);
    messages.add(UltronMessage(id: ++_seq, kind: UltronMessageKind.execution, execution: exec));
    notifyListeners();
    _autoLaunch(exec);
  }

  Future<void> _loadOrgs() async {
    try {
      organizations = await OrganizationRepository.instance.organizations(limit: 50);
      if (organizations.isNotEmpty && selectedOrg == null) selectedOrg = organizations.first;
      notifyListeners();
    } catch (_) {}
  }

  void toggle() {
    open = !open;
    notifyListeners();
  }

  void close() {
    if (!open) return;
    _cancelVoice();
    open = false;
    notifyListeners();
  }

  void setMode(UltronMode m) {
    if (mode == m) return;
    _cancelVoice();
    mode = m;
    notifyListeners();
  }

  List<UltronMessage> messagesFor(UltronMode m) =>
      messages.where((e) => e.ask == (m == UltronMode.ask)).toList();

  void selectOrg(Organization? o) {
    selectedOrg = o;
    notifyListeners();
  }

  void setHandsFree(bool value) {
    if (handsFree == value) return;
    handsFree = value;
    notifyListeners();
  }

  void _cancelVoice() {
    if (!listening) return;
    listening = false;
    transcript = '';
    _voiceHandled = true;
    _speech.cancel();
  }

  void _voiceFailed(String text) {
    listening = false;
    transcript = '';
    messages.add(UltronMessage(id: ++_seq, kind: UltronMessageKind.error, text: text));
    notifyListeners();
  }

  Future<void> toggleListening() async {
    if (listening) {
      await _speech.stop();
      return;
    }
    if (thinking) return;
    final ready = await _speech.initialize(
      onError: (e) {
        if (!listening) return;
        _voiceHandled = true;
        final quiet = e.errorMsg == 'error_no_match' || e.errorMsg == 'error_speech_timeout';
        if (quiet) {
          listening = false;
          transcript = '';
          notifyListeners();
        } else {
          _voiceFailed('Voice input failed. Please try again.');
        }
      },
      onStatus: (s) {
        if (!listening || (s != 'done' && s != 'notListening')) return;
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (!listening || _voiceHandled) return;
          _voiceHandled = true;
          final text = transcript.trim();
          listening = false;
          transcript = '';
          notifyListeners();
          if (text.isNotEmpty) _dispatchVoice(text);
        });
      },
    );
    if (!ready) {
      _voiceFailed('Voice input is not available. Allow microphone and speech access, then try again.');
      return;
    }
    transcript = '';
    _voiceHandled = false;
    listening = true;
    notifyListeners();
    await _speech.listen(
      onResult: (r) {
        if (!listening || _voiceHandled) return;
        transcript = r.recognizedWords;
        if (r.finalResult) {
          _voiceHandled = true;
          final text = transcript.trim();
          listening = false;
          transcript = '';
          notifyListeners();
          if (text.isNotEmpty) _dispatchVoice(text);
          return;
        }
        notifyListeners();
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
    );
  }

  void _dispatchVoice(String text) {
    send(text, autoExecute: mode == UltronMode.command && handsFree);
  }

  void clearChat() {
    final ask = mode == UltronMode.ask;
    messages.removeWhere((e) => e.ask == ask);
    notifyListeners();
  }

  int _indexOf(int id) => messages.indexWhere((m) => m.id == id);

  Future<void> send(String raw, {bool autoExecute = false}) async {
    final text = raw.trim();
    if (text.isEmpty || thinking) return;
    final isAsk = mode == UltronMode.ask;
    messages.add(UltronMessage(id: ++_seq, kind: UltronMessageKind.user, text: text, ask: isAsk));
    thinking = true;
    thinkingMode = mode;
    notifyListeners();
    try {
      if (mode == UltronMode.command && autoExecute) {
        await _runHandsFree(text, organizations.length > 1 ? selectedOrg?.id : null);
      } else if (mode == UltronMode.command) {
        final plan = await UltronService.instance.plan(
          text,
          organizationId: organizations.length > 1 ? selectedOrg?.id : null,
        );
        if (plan.steps.isEmpty) {
          messages.add(UltronMessage(
            id: ++_seq,
            kind: UltronMessageKind.text,
            text: plan.summary.isEmpty ? 'I could not turn that into actions. Try rephrasing it.' : plan.summary,
          ));
        } else {
          messages.add(UltronMessage(id: ++_seq, kind: UltronMessageKind.plan, plan: plan));
        }
      } else {
        final r = await AiService.instance.chat(text);
        messages.add(UltronMessage(
          id: ++_seq,
          ask: true,
          kind: UltronMessageKind.text,
          text: r.answer.isEmpty ? 'I have nothing to add to that.' : r.answer,
        ));
      }
    } catch (e) {
      messages.add(UltronMessage(id: ++_seq, kind: UltronMessageKind.error, text: errorText(e), ask: isAsk));
    } finally {
      thinking = false;
      notifyListeners();
    }
  }

  Future<void> _runHandsFree(String text, String? organizationId) async {
    final out = await UltronService.instance.run(text, organizationId: organizationId);
    final exec = out.execution;
    if (exec != null) {
      messages.add(UltronMessage(id: ++_seq, kind: UltronMessageKind.execution, execution: exec));
      _autoLaunch(exec);
      return;
    }
    if (out.plan.steps.isEmpty) {
      messages.add(UltronMessage(
        id: ++_seq,
        kind: UltronMessageKind.text,
        text: out.plan.summary.isEmpty ? 'I could not turn that into actions. Try rephrasing it.' : out.plan.summary,
      ));
      return;
    }
    final planId = out.plan.planId;
    final count = out.plan.steps.length;
    _awaiting.add(planId);
    messages.add(UltronMessage(
      id: ++_seq,
      kind: UltronMessageKind.text,
      text: 'Running $count ${count == 1 ? 'step' : 'steps'}…',
    ));
    Timer(const Duration(seconds: 30), () {
      if (!active || !_awaiting.remove(planId)) return;
      messages.add(UltronMessage(
        id: ++_seq,
        kind: UltronMessageKind.text,
        text: 'This is taking longer than expected. I will show the result here when it finishes.',
      ));
      notifyListeners();
    });
  }

  Future<void> confirm(int messageId) async {
    final i = _indexOf(messageId);
    if (i < 0) return;
    final msg = messages[i];
    final plan = msg.plan;
    if (plan == null || msg.busy || msg.settled) return;
    if (plan.isExpired) {
      messages[i] = msg.copyWith(settled: true);
      messages.add(UltronMessage(
        id: ++_seq,
        kind: UltronMessageKind.error,
        text: 'That plan expired. Send the command again.',
      ));
      notifyListeners();
      return;
    }
    messages[i] = msg.copyWith(busy: true);
    thinking = true;
    thinkingMode = UltronMode.command;
    notifyListeners();
    try {
      final exec = await UltronService.instance.execute(plan.planId);
      final j = _indexOf(messageId);
      if (j >= 0) messages[j] = messages[j].copyWith(busy: false, settled: true);
      messages.add(UltronMessage(id: ++_seq, kind: UltronMessageKind.execution, execution: exec));
      _autoLaunch(exec);
    } catch (e) {
      final j = _indexOf(messageId);
      final settled = e is ApiException && (e.statusCode == 400 || e.statusCode == 404);
      if (j >= 0) messages[j] = messages[j].copyWith(busy: false, settled: settled);
      messages.add(UltronMessage(id: ++_seq, kind: UltronMessageKind.error, text: errorText(e)));
    } finally {
      thinking = false;
      notifyListeners();
    }
  }

  void dismissPlan(int messageId) {
    final i = _indexOf(messageId);
    if (i < 0) return;
    messages[i] = messages[i].copyWith(settled: true);
    messages.add(UltronMessage(id: ++_seq, kind: UltronMessageKind.text, text: 'Plan cancelled. Nothing was changed.'));
    notifyListeners();
  }
}