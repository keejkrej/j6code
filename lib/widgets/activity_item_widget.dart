import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/j6_entities.dart';

/// Helper to extract clean executable and full command from activity payload
class ToolActivityHelper {
  static String extractCleanFullCommand(J6Activity activity) {
    final payload = activity.payload;
    final data = payload['data'] is Map ? payload['data'] as Map : {};
    final item = (data['item'] is Map) ? data['item'] as Map : (payload['item'] is Map ? payload['item'] as Map : {});
    final rawInput = (data['rawInput'] is Map) ? data['rawInput'] as Map : {};
    final rawOutput = (data['rawOutput'] is Map) ? data['rawOutput'] as Map : {};

    // 1. Direct command strings
    final candidates = [
      data['command'],
      item['command'],
      rawInput['command_line'],
      rawInput['command'],
      rawOutput['commandLine'],
      rawOutput['command'],
      payload['command'],
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }

    // 2. Executable + args
    final executable = rawInput['executable']?.toString().trim();
    final args = rawInput['args'];
    if (executable != null && executable.isNotEmpty) {
      if (args is List && args.isNotEmpty) {
        return '$executable ${args.join(' ')}';
      } else if (args is String && args.isNotEmpty) {
        return '$executable $args';
      }
      return executable;
    }

    // 3. Fallback to detail or summary
    final detail = payload['detail']?.toString().trim() ?? '';
    if (detail.isNotEmpty) return detail;
    return activity.summary;
  }

  static String extractPrimaryPath(J6Activity activity) {
    final payload = activity.payload;
    final data = payload['data'] is Map ? payload['data'] as Map : {};
    final rawInput = (data['rawInput'] is Map) ? data['rawInput'] as Map : {};

    final candidates = [
      rawInput['absolute_path'],
      rawInput['target_file'],
      rawInput['file_path'],
      rawInput['path'],
      data['filePath'],
      data['path'],
      payload['detail'],
    ];

    for (final c in candidates) {
      if (c is String && c.trim().isNotEmpty) {
        final path = c.trim();
        // Return basename or last 2 segments for readability
        final parts = path.replaceAll('\\', '/').split('/');
        if (parts.length > 2) {
          return parts.sublist(parts.length - 2).join('/');
        }
        return path;
      }
    }
    return '';
  }

  static String classifyKind(J6Activity activity) {
    final summary = activity.summary.toLowerCase();
    final itemType = (activity.payload['itemType']?.toString() ?? '').toLowerCase();
    if (summary.contains('command') || itemType.contains('command')) return 'command';
    if (summary.contains('read') || itemType.contains('read')) return 'read';
    if (summary.contains('change') || summary.contains('edit') || summary.contains('write') || itemType.contains('file_change')) return 'edit';
    return 'other';
  }
}

/// A collapsible group widget representing consecutive activities (e.g. "Ran 4 commands", "Read 9 files")
class ActivityGroupWidget extends StatefulWidget {
  final String groupType; // 'command', 'read', 'edit', 'other'
  final List<J6Activity> activities;

  const ActivityGroupWidget({
    super.key,
    required this.groupType,
    required this.activities,
  });

  @override
  State<ActivityGroupWidget> createState() => _ActivityGroupWidgetState();
}

class _ActivityGroupWidgetState extends State<ActivityGroupWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.activities.length;
    final lastActivity = widget.activities.last;
    final timeStr = '${lastActivity.createdAt.hour.toString().padLeft(2, '0')}:${lastActivity.createdAt.minute.toString().padLeft(2, '0')}';

    String title;
    IconData icon;
    Color iconColor;

    switch (widget.groupType) {
      case 'command':
        title = count == 1 ? 'Ran 1 command' : 'Ran $count commands';
        icon = Icons.terminal_rounded;
        iconColor = const Color(0xFF22C55E);
        break;
      case 'read':
        title = count == 1 ? 'Read 1 file' : 'Read $count files';
        icon = Icons.description_outlined;
        iconColor = const Color(0xFF60A5FA);
        break;
      case 'edit':
        title = count == 1 ? 'Changed 1 file' : 'Changed $count files';
        icon = Icons.edit_note_rounded;
        iconColor = const Color(0xFFA78BFA);
        break;
      default:
        title = count == 1 ? widget.activities.first.summary : '$count tool activities';
        icon = Icons.handyman_outlined;
        iconColor = AppTheme.accent;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row (collapsible toggle)
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                    size: 16,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Icon(icon, size: 15, color: iconColor),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded items list
          if (_isExpanded) ...[
            const Divider(height: 1, color: AppTheme.borderSubtle),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: widget.activities.map((act) => _buildDetailItem(act)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailItem(J6Activity activity) {
    final status = activity.payload['status']?.toString() ?? 'completed';
    final isDone = status == 'completed';
    final fullCommand = ToolActivityHelper.extractCleanFullCommand(activity);
    final primaryPath = ToolActivityHelper.extractPrimaryPath(activity);

    final displayContent = widget.groupType == 'command'
        ? fullCommand
        : (primaryPath.isNotEmpty ? primaryPath : fullCommand);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone ? const Color(0xFF22C55E) : const Color(0xFF6366F1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              displayContent,
              style: TextStyle(
                fontFamily: widget.groupType == 'command' ? 'Consolas, monospace' : null,
                fontSize: 11.5,
                height: 1.4,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standalone single activity widget (fallback or dispatch events)
class ActivityItemWidget extends StatelessWidget {
  final J6Activity activity;

  const ActivityItemWidget({
    super.key,
    required this.activity,
  });

  @override
  Widget build(BuildContext context) {
    final payload = activity.payload;
    final itemType = payload['itemType']?.toString() ?? '';
    final status = payload['status']?.toString() ?? '';
    final title = payload['title']?.toString() ?? activity.summary;
    final fullCommand = ToolActivityHelper.extractCleanFullCommand(activity);
    final provider = payload['provider']?.toString() ?? '';
    final model = payload['model']?.toString() ?? '';

    final isCommand = itemType == 'command_execution' || fullCommand.isNotEmpty;
    final isDispatch = itemType == 'prompt_dispatch';
    final isDone = status == 'completed';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCommand
                ? Icons.terminal_rounded
                : (isDispatch ? Icons.bolt_rounded : Icons.handyman_outlined),
            size: 15,
            color: isDone ? AppTheme.success : AppTheme.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDone
                            ? AppTheme.success.withAlpha(30)
                            : AppTheme.accent.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        (status.isNotEmpty ? status : 'COMPLETED').toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isDone ? AppTheme.success : AppTheme.accent,
                        ),
                      ),
                    ),
                    if (provider.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceHover,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$provider ($model)',
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (fullCommand.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    fullCommand,
                    style: const TextStyle(
                      fontFamily: 'Consolas, monospace',
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
