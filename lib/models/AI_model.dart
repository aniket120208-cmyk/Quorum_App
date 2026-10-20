import 'package:flutter/material.dart';

enum AiMode { chat, search, project, replies, update }

extension AiModeInfo on AiMode {
  String get label {
    switch (this) {
      case AiMode.chat:
        return 'Ask AI';
      case AiMode.search:
        return 'Search';
      case AiMode.project:
        return 'Project';
      case AiMode.replies:
        return 'Replies';
      case AiMode.update:
        return 'Status update';
    }
  }

  IconData get icon {
    switch (this) {
      case AiMode.chat:
        return Icons.auto_awesome;
      case AiMode.search:
        return Icons.manage_search;
      case AiMode.project:
        return Icons.account_tree_outlined;
      case AiMode.replies:
        return Icons.reply_all_outlined;
      case AiMode.update:
        return Icons.assignment_outlined;
    }
  }

  String get inputHint {
    switch (this) {
      case AiMode.chat:
        return 'Ask anything about Quorum or your work...';
      case AiMode.search:
        return 'Search messages, posts, meetings...';
      case AiMode.project:
        return 'Ask about your organization, team or community...';
      case AiMode.replies:
        return 'Paste or type the message...';
      case AiMode.update:
        return 'Optional note (not sent)';
    }
  }

  String get emptyTitle {
    switch (this) {
      case AiMode.chat:
        return 'Ask me anything';
      case AiMode.search:
        return 'Search your workspace';
      case AiMode.project:
        return 'Project assistant';
      case AiMode.replies:
        return 'Quick replies and rewrites';
      case AiMode.update:
        return 'Status update generator';
    }
  }

  String get emptyBody {
    switch (this) {
      case AiMode.chat:
        return 'Get answers about how Quorum works, or paste a discussion for context.';
      case AiMode.search:
        return 'Find answers across messages, community posts, organizations and meetings.';
      case AiMode.project:
        return 'Choose a workspace type, paste its ID, then ask a question about it.';
      case AiMode.replies:
        return 'Get reply, follow-up or rewrite suggestions. Review them before sending.';
      case AiMode.update:
        return 'Choose a workspace and timeframe, then tap send to generate a report.';
    }
  }

  bool get needsScope => this == AiMode.project || this == AiMode.update;
  bool get promptOptional => this == AiMode.update;
}

enum AiScope { organization, team, community }

extension AiScopeInfo on AiScope {
  String get label {
    switch (this) {
      case AiScope.organization:
        return 'Organization';
      case AiScope.team:
        return 'Team';
      case AiScope.community:
        return 'Community';
    }
  }

  String get key {
    switch (this) {
      case AiScope.organization:
        return 'organizationId';
      case AiScope.team:
        return 'teamId';
      case AiScope.community:
        return 'communityId';
    }
  }
}

const aiTones = [
  'professional',
  'casual',
  'friendly',
  'concise',
  'enthusiastic',
];

const aiReplyModes = {
  'replies': 'Replies',
  'follow_up': 'Follow-ups',
  'rewrite': 'Rewrite',
};

const aiTimeframes = {
  'today': 'Today',
  'yesterday': 'Yesterday',
  'last_7_days': 'Last 7 days',
  'last_30_days': 'Last 30 days',
  'last_90_days': 'Last 90 days',
};

final RegExp aiUuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class AiMeta {
  final String model;
  final int? totalTokens;

  const AiMeta({required this.model, this.totalTokens});

  factory AiMeta.fromJson(Map<String, dynamic> j) {
    final usage = j['tokenUsage'];
    return AiMeta(
      model: (j['model'] ?? '').toString(),
      totalTokens: usage is Map ? int.tryParse((usage['totalTokens'] ?? '').toString()) : null,
    );
  }
}

class AiSource {
  final String id;
  final String type;
  final String title;
  final String snippet;
  final String author;
  final String? url;
  final DateTime? createdAt;

  const AiSource({
    required this.id,
    required this.type,
    required this.title,
    required this.snippet,
    required this.author,
    this.url,
    this.createdAt,
  });

  factory AiSource.fromJson(Map<String, dynamic> j) => AiSource(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        snippet: (j['snippet'] ?? '').toString(),
        author: (j['author'] ?? '').toString(),
        url: j['url']?.toString(),
        createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString())?.toLocal(),
      );
}

class AiProject {
  final String id;
  final String name;
  final String type;
  final String? description;
  final int memberCount;
  final int? teamCount;
  final int? discussionCount;

  const AiProject({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    required this.memberCount,
    this.teamCount,
    this.discussionCount,
  });

  factory AiProject.fromJson(Map<String, dynamic> j) => AiProject(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        description: j['description']?.toString(),
        memberCount: int.tryParse((j['memberCount'] ?? 0).toString()) ?? 0,
        teamCount: int.tryParse((j['teamCount'] ?? '').toString()),
        discussionCount: int.tryParse((j['discussionCount'] ?? '').toString()),
      );
}

class AiResult {
  final String answer;
  final List<AiSource> sources;
  final AiProject? project;
  final List<String> suggestions;
  final String? disclaimer;
  final Map<String, int> facts;
  final String? target;
  final String? note;
  final AiMeta? meta;

  const AiResult({
    this.answer = '',
    this.sources = const [],
    this.project,
    this.suggestions = const [],
    this.disclaimer,
    this.facts = const {},
    this.target,
    this.note,
    this.meta,
  });
}

enum TurnState { loading, done, error }

class AiTurn {
  final int id;
  final AiMode mode;
  final String prompt;
  final String? caption;
  final Future<AiResult> Function() run;
  final TurnState state;
  final AiResult? result;
  final String? error;

  const AiTurn({
    required this.id,
    required this.mode,
    required this.prompt,
    this.caption,
    required this.run,
    this.state = TurnState.loading,
    this.result,
    this.error,
  });

  AiTurn copyWith({TurnState? state, AiResult? result, String? error}) => AiTurn(
        id: id,
        mode: mode,
        prompt: prompt,
        caption: caption,
        run: run,
        state: state ?? this.state,
        result: result ?? this.result,
        error: error,
      );
}

class AiInteraction {
  final String id;
  final String actionType;
  final String prompt;
  final String response;
  final String? model;
  final DateTime createdAt;

  const AiInteraction({
    required this.id,
    required this.actionType,
    required this.prompt,
    required this.response,
    this.model,
    required this.createdAt,
  });

  factory AiInteraction.fromJson(Map<String, dynamic> j) => AiInteraction(
        id: j['id'].toString(),
        actionType: (j['actionType'] ?? '').toString(),
        prompt: (j['prompt'] ?? '').toString(),
        response: (j['response'] ?? '').toString(),
        model: j['model']?.toString(),
        createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString())?.toLocal() ?? DateTime.now(),
      );
}

class AiHistoryPage {
  final List<AiInteraction> items;
  final String? nextCursor;
  final bool hasMore;

  const AiHistoryPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });
}

const aiActionLabels = {
  'chat': 'Ask AI',
  'search': 'Search',
  'project_assistance': 'Project',
  'quick_replies': 'Replies',
  'project_update': 'Status update',
};