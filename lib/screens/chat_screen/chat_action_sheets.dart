import 'package:flutter/material.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'chat_widgets.dart';

enum ChatMenuAction { mute, unmute, clear, block, unblock, delete }

Future<int?> pickMuteDuration(BuildContext context) {
  Widget option(BuildContext ctx, IconData icon, String label, int seconds) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      onTap: () => Navigator.pop(ctx, seconds),
    );
  }

  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Mute notifications',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'You will still receive messages in the app, but no push notifications.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 8),
          option(ctx, Icons.schedule_rounded, 'For 8 hours', 8 * 3600),
          option(ctx, Icons.today_rounded, 'For 1 day', 24 * 3600),
          option(ctx, Icons.date_range_rounded, 'For 1 week', 7 * 24 * 3600),
          option(ctx, Icons.notifications_off_outlined, 'Until I turn it back on', 0),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<bool> confirmChatAction(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
      content: Text(body, style: const TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            action,
            style: TextStyle(color: destructive ? Colors.redAccent : AppColors.primaryLight),
          ),
        ),
      ],
    ),
  );
  return ok == true;
}

List<ChatMenuAction> availableChatActions(Conversation c) {
  return [
    c.muted ? ChatMenuAction.unmute : ChatMenuAction.mute,
    ChatMenuAction.clear,
    if (!c.isGroup && !c.isTeam) c.isBlocked ? ChatMenuAction.unblock : ChatMenuAction.block,
    if (!c.isTeam) ChatMenuAction.delete,
  ];
}

IconData chatActionIcon(ChatMenuAction a) {
  switch (a) {
    case ChatMenuAction.mute:
      return Icons.notifications_off_outlined;
    case ChatMenuAction.unmute:
      return Icons.notifications_active_outlined;
    case ChatMenuAction.clear:
      return Icons.cleaning_services_outlined;
    case ChatMenuAction.block:
      return Icons.block_rounded;
    case ChatMenuAction.unblock:
      return Icons.lock_open_rounded;
    case ChatMenuAction.delete:
      return Icons.delete_outline_rounded;
  }
}

String chatActionLabel(ChatMenuAction a) {
  switch (a) {
    case ChatMenuAction.mute:
      return 'Mute notifications';
    case ChatMenuAction.unmute:
      return 'Unmute notifications';
    case ChatMenuAction.clear:
      return 'Clear chat';
    case ChatMenuAction.block:
      return 'Block';
    case ChatMenuAction.unblock:
      return 'Unblock';
    case ChatMenuAction.delete:
      return 'Delete chat';
  }
}

bool chatActionIsDanger(ChatMenuAction a) =>
    a == ChatMenuAction.clear || a == ChatMenuAction.block || a == ChatMenuAction.delete;

Future<ChatMenuAction?> showChatActionsSheet(BuildContext context, Conversation c, String title) {
  return showModalBottomSheet<ChatMenuAction>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          for (final a in availableChatActions(c))
            ListTile(
              leading: Icon(
                chatActionIcon(a),
                color: chatActionIsDanger(a) ? Colors.redAccent : AppColors.textPrimary,
              ),
              title: Text(
                chatActionLabel(a),
                style: TextStyle(color: chatActionIsDanger(a) ? Colors.redAccent : AppColors.textPrimary),
              ),
              onTap: () => Navigator.pop(ctx, a),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}