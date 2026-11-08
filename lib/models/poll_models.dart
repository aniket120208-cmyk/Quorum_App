import 'package:quorum_app/models/chat_models.dart';

const int pollMaxOptions = 12;
const int pollMinOptions = 2;
const int pollMaxQuestionLength = 200;
const int pollMaxOptionLength = 100;

class PollVoter {
  final String userId;
  final ChatUser user;

  const PollVoter({required this.userId, required this.user});

  factory PollVoter.fromJson(Map<String, dynamic> j) {
    final userMap = j['user'] is Map ? Map<String, dynamic>.from(j['user']) : <String, dynamic>{};
    final id = (j['userId'] ?? userMap['id'] ?? j['id'] ?? '').toString();
    if (userMap['id'] == null) userMap['id'] = id;
    if (userMap['name'] == null && j['name'] != null) userMap['name'] = j['name'];
    return PollVoter(userId: id, user: ChatUser.fromJson(userMap));
  }
}

class PollOption {
  final String id;
  final String text;
  final int order;
  final int voteCount;
  final double percentage;
  final bool hasVoted;
  final List<PollVoter> voters;

  const PollOption({
    required this.id,
    required this.text,
    this.order = 0,
    this.voteCount = 0,
    this.percentage = 0,
    this.hasVoted = false,
    this.voters = const [],
  });

  PollOption copyWith({
    int? voteCount,
    double? percentage,
    bool? hasVoted,
    List<PollVoter>? voters,
  }) =>
      PollOption(
        id: id,
        text: text,
        order: order,
        voteCount: voteCount ?? this.voteCount,
        percentage: percentage ?? this.percentage,
        hasVoted: hasVoted ?? this.hasVoted,
        voters: voters ?? this.voters,
      );

  factory PollOption.fromJson(Map<String, dynamic> j, int index) {
    final voters = j['voters'] is List
        ? (j['voters'] as List)
            .whereType<Map>()
            .map((e) => PollVoter.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <PollVoter>[];
    return PollOption(
      id: (j['id'] ?? '').toString(),
      text: (j['text'] ?? j['label'] ?? '').toString(),
      order: int.tryParse((j['order'] ?? index).toString()) ?? index,
      voteCount: int.tryParse((j['voteCount'] ?? j['votes'] ?? voters.length).toString()) ?? voters.length,
      percentage: double.tryParse((j['percentage'] ?? 0).toString()) ?? 0,
      hasVoted: j['hasVoted'] == true,
      voters: voters,
    );
  }
}

class PollDraft {
  final String question;
  final List<String> options;
  final bool allowMultipleAnswers;

  const PollDraft({
    required this.question,
    required this.options,
    this.allowMultipleAnswers = false,
  });

  Map<String, dynamic> toJson() => {
        'question': question,
        'options': options,
        'allowMultipleAnswers': allowMultipleAnswers,
      };
}

class Poll {
  final String id;
  final String question;
  final bool allowMultipleAnswers;
  final bool isClosed;
  final int totalVotes;
  final int uniqueVotersCount;
  final bool hasVoted;
  final List<String> userVotedOptionIds;
  final List<PollOption> options;
  final DateTime? createdAt;

  const Poll({
    required this.id,
    required this.question,
    this.allowMultipleAnswers = false,
    this.isClosed = false,
    this.totalVotes = 0,
    this.uniqueVotersCount = 0,
    this.hasVoted = false,
    this.userVotedOptionIds = const [],
    this.options = const [],
    this.createdAt,
  });

  bool votedFor(String optionId) => userVotedOptionIds.contains(optionId);

  bool get hasVoterDetails => options.any((o) => o.voters.isNotEmpty);

  factory Poll.fromDraft(String id, PollDraft draft) => Poll(
        id: id,
        question: draft.question,
        allowMultipleAnswers: draft.allowMultipleAnswers,
        options: [
          for (var i = 0; i < draft.options.length; i++)
            PollOption(id: '${id}_$i', text: draft.options[i], order: i),
        ],
      );

  factory Poll.fromJson(Map<String, dynamic> j) {
    final rawOptions = j['options'] is List ? (j['options'] as List) : const [];
    final options = <PollOption>[];
    for (var i = 0; i < rawOptions.length; i++) {
      final o = rawOptions[i];
      if (o is Map) options.add(PollOption.fromJson(Map<String, dynamic>.from(o), i));
    }
    options.sort((a, b) => a.order.compareTo(b.order));
    final total = int.tryParse((j['totalVotes'] ?? '').toString()) ?? options.fold<int>(0, (s, o) => s + o.voteCount);
    final votedIds = j['userVotedOptionIds'] is List
        ? (j['userVotedOptionIds'] as List).map((e) => e.toString()).toList()
        : options.where((o) => o.hasVoted).map((o) => o.id).toList();
    final withPercent = options
        .map((o) => o.percentage > 0 || total == 0 ? o : o.copyWith(percentage: o.voteCount * 100 / total))
        .toList();
    return Poll(
      id: (j['id'] ?? '').toString(),
      question: (j['question'] ?? '').toString(),
      allowMultipleAnswers: j['allowMultipleAnswers'] == true,
      isClosed: j['isClosed'] == true,
      totalVotes: total,
      uniqueVotersCount: int.tryParse((j['uniqueVotersCount'] ?? '').toString()) ?? total,
      hasVoted: j['hasVoted'] == true || votedIds.isNotEmpty,
      userVotedOptionIds: votedIds,
      options: withPercent,
      createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString())?.toLocal(),
    );
  }

  static Poll? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final inner = map['poll'] is Map ? Map<String, dynamic>.from(map['poll']) : map;
    if (inner['id'] == null || inner['options'] is! List) return null;
    return Poll.fromJson(inner);
  }

  static List<Poll> listFrom(dynamic raw) {
    final list = raw is Map && raw['polls'] is List ? raw['polls'] : raw;
    if (list is! List) return const [];
    return list.map(Poll.tryParse).whereType<Poll>().toList();
  }

  Poll copyWith({
    bool? isClosed,
    int? totalVotes,
    int? uniqueVotersCount,
    bool? hasVoted,
    List<String>? userVotedOptionIds,
    List<PollOption>? options,
  }) =>
      Poll(
        id: id,
        question: question,
        allowMultipleAnswers: allowMultipleAnswers,
        isClosed: isClosed ?? this.isClosed,
        totalVotes: totalVotes ?? this.totalVotes,
        uniqueVotersCount: uniqueVotersCount ?? this.uniqueVotersCount,
        hasVoted: hasVoted ?? this.hasVoted,
        userVotedOptionIds: userVotedOptionIds ?? this.userVotedOptionIds,
        options: options ?? this.options,
        createdAt: createdAt,
      );

  Poll toggledVote(ChatUser me, String optionId) {
    final current = userVotedOptionIds.toSet();
    final next = <String>{...current};
    if (current.contains(optionId)) {
      next.remove(optionId);
    } else if (allowMultipleAnswers) {
      next.add(optionId);
    } else {
      next
        ..clear()
        ..add(optionId);
    }
    return _withMyVotes(me, next);
  }

  Poll _withMyVotes(ChatUser me, Set<String> mine) {
    final updated = options.map((o) {
      final voters = o.voters.where((v) => v.userId != me.id).toList();
      final has = mine.contains(o.id);
      if (has) voters.add(PollVoter(userId: me.id, user: me));
      final before = o.voters.any((v) => v.userId == me.id) || userVotedOptionIds.contains(o.id);
      final delta = (has ? 1 : 0) - (before ? 1 : 0);
      final count = (o.voteCount + delta).clamp(0, 1 << 30).toInt();
      return o.copyWith(voteCount: count, hasVoted: has, voters: voters);
    }).toList();
    final total = updated.fold<int>(0, (s, o) => s + o.voteCount);
    final wasVoter = userVotedOptionIds.isNotEmpty;
    final isVoter = mine.isNotEmpty;
    final unique = (uniqueVotersCount + (isVoter ? 1 : 0) - (wasVoter ? 1 : 0)).clamp(0, 1 << 30).toInt();
    return copyWith(
      totalVotes: total,
      uniqueVotersCount: unique,
      hasVoted: isVoter,
      userVotedOptionIds: mine.toList(),
      options: updated
          .map((o) => o.copyWith(percentage: total == 0 ? 0 : o.voteCount * 100 / total))
          .toList(),
    );
  }

  Poll resolvedFor(String myId, Poll? previous) {
    if (myId.isEmpty) return this;
    if (!hasVoterDetails) {
      if (previous == null) return this;
      return copyWith(
        hasVoted: previous.hasVoted,
        userVotedOptionIds: previous.userVotedOptionIds,
        options: options
            .map((o) => o.copyWith(hasVoted: previous.votedFor(o.id)))
            .toList(),
      );
    }
    final mine = options
        .where((o) => o.voters.any((v) => v.userId == myId))
        .map((o) => o.id)
        .toList();
    return copyWith(
      hasVoted: mine.isNotEmpty,
      userVotedOptionIds: mine,
      options: options.map((o) => o.copyWith(hasVoted: mine.contains(o.id))).toList(),
    );
  }
}