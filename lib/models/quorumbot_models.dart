class UltronStep {
  final int step;
  final String action;
  final String description;
  final Map<String, dynamic> params;

  const UltronStep({
    required this.step,
    required this.action,
    required this.description,
    required this.params,
  });

  factory UltronStep.fromJson(Map<String, dynamic> j) => UltronStep(
        step: (j['step'] as num?)?.toInt() ?? 0,
        action: (j['action'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        params: j['params'] is Map ? Map<String, dynamic>.from(j['params']) : <String, dynamic>{},
      );

  String get label {
    switch (action) {
      case 'CREATE_TEAM':
        return 'Create team';
      case 'SCHEDULE_MEETING':
        return 'Schedule meeting';
      case 'CREATE_MEETING':
        return 'Create meeting';
      case 'START_VIDEO_CALL':
        return 'Start video call';
      case 'SHARE_DOCUMENT':
        return 'Share document';
      case 'NOTIFY_MEMBERS':
        return 'Notify members';
      default:
        return action.replaceAll('_', ' ').toLowerCase();
    }
  }
}

class UltronPlan {
  final String planId;
  final String summary;
  final List<UltronStep> steps;
  final DateTime? expiresAt;

  const UltronPlan({
    required this.planId,
    required this.summary,
    required this.steps,
    this.expiresAt,
  });

  factory UltronPlan.fromJson(Map<String, dynamic> j) => UltronPlan(
        planId: (j['planId'] ?? '').toString(),
        summary: (j['summary'] ?? '').toString(),
        steps: (j['steps'] is List ? j['steps'] as List : const [])
            .whereType<Map>()
            .map((e) => UltronStep.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        expiresAt: DateTime.tryParse((j['expiresAt'] ?? '').toString()),
      );

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!.toLocal());
}

class UltronStepResult {
  final int step;
  final String action;
  final String description;
  final bool success;
  final String? error;
  final Map<String, dynamic> resource;

  const UltronStepResult({
    required this.step,
    required this.action,
    required this.description,
    required this.success,
    this.error,
    this.resource = const {},
  });

  factory UltronStepResult.fromJson(Map<String, dynamic> j) => UltronStepResult(
        step: (j['step'] as num?)?.toInt() ?? 0,
        action: (j['action'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        success: j['success'] == true,
        error: (j['error'] ?? j['message'])?.toString(),
        resource: j['resource'] is Map ? Map<String, dynamic>.from(j['resource']) : <String, dynamic>{},
      );

  String? get joinUrl {
    final v = resource['joinUrl'] ?? resource['meetingLink'];
    return v == null || v.toString().isEmpty ? null : v.toString();
  }

  String? get meetingLink => joinUrl;

  String? get meetingCode {
    final v = resource['meetingCode'];
    return v == null || v.toString().isEmpty ? null : v.toString();
  }

  bool get isMeetingStart => action == 'CREATE_MEETING' || action == 'START_VIDEO_CALL';

  String get title {
    final v = resource['title'] ?? resource['name'];
    return v == null ? description : v.toString();
  }
}

class UltronExecution {
  final String planId;
  final String summary;
  final String status;
  final List<UltronStepResult> results;

  const UltronExecution({
    required this.planId,
    required this.summary,
    required this.status,
    required this.results,
  });

  factory UltronExecution.fromJson(Map<String, dynamic> j) => UltronExecution(
        planId: (j['planId'] ?? '').toString(),
        summary: (j['summary'] ?? '').toString(),
        status: (j['status'] ?? 'COMPLETED').toString(),
        results: (j['results'] is List ? j['results'] as List : const [])
            .whereType<Map>()
            .map((e) => UltronStepResult.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  UltronStepResult? get meetingStep {
    for (final r in results) {
      if (r.success && r.isMeetingStart && r.meetingCode != null) return r;
    }
    return null;
  }

  bool get allOk => results.isNotEmpty && results.every((r) => r.success);
  int get okCount => results.where((r) => r.success).length;
}

class UltronOutcome {
  final UltronPlan plan;
  final UltronExecution? execution;

  const UltronOutcome(this.plan, this.execution);
}

enum UltronMessageKind { user, text, plan, execution, error }

class UltronMessage {
  final int id;
  final UltronMessageKind kind;
  final String text;
  final UltronPlan? plan;
  final UltronExecution? execution;
  final Set<int> skipped;
  final bool busy;
  final bool settled;
  final bool ask;

  const UltronMessage({
    required this.id,
    required this.kind,
    this.ask = false,
    this.text = '',
    this.plan,
    this.execution,
    this.skipped = const {},
    this.busy = false,
    this.settled = false,
  });

  UltronMessage copyWith({
    Set<int>? skipped,
    bool? busy,
    bool? settled,
    UltronExecution? execution,
  }) =>
      UltronMessage(
        id: id,
        kind: kind,
        ask: ask,
        text: text,
        plan: plan,
        execution: execution ?? this.execution,
        skipped: skipped ?? this.skipped,
        busy: busy ?? this.busy,
        settled: settled ?? this.settled,
      );
}