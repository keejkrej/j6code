import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
    final running = widget.activities.any((a) {
      final s = a.payload['status']?.toString() ?? 'completed';
      return s == 'running' || s == 'inProgress' || s == 'in_progress';
    });

    String title;
    IconData icon;

    switch (widget.groupType) {
      case 'command':
        title = running ? 'Running command' : (count == 1 ? 'Ran 1 command' : 'Ran $count commands');
        icon = LucideIcons.terminal;
        break;
      case 'read':
        title = count == 1 ? 'Read 1 file' : 'Read $count files';
        icon = LucideIcons.fileText;
        break;
      case 'edit':
        title = count == 1 ? 'Edited 1 file' : 'Edited $count files';
        icon = LucideIcons.penLine;
        break;
      default:
        title = count == 1 ? widget.activities.first.summary : 'Used $count tools';
        icon = LucideIcons.wrench;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15, color: context.t3.mutedForeground),
                    const SizedBox(width: 8),
                    Text(title, style: TextStyle(fontSize: 13.5, color: context.t3.mutedForeground)),
                    const SizedBox(width: 4),
                    Icon(
                      _isExpanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                      size: 16,
                      color: context.t3.faint,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isExpanded)
            Container(
              margin: const EdgeInsets.only(left: 9, top: 2, bottom: 6),
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: context.t3.input, width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.activities.map(_buildDetailItem).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(J6Activity activity) {
    final status = activity.payload['status']?.toString() ?? 'completed';
    final failed = status == 'failed' || status == 'error';
    final fullCommand = ToolActivityHelper.extractCleanFullCommand(activity);
    final primaryPath = ToolActivityHelper.extractPrimaryPath(activity);
    final isCommand = widget.groupType == 'command';
    final displayContent = isCommand ? fullCommand : (primaryPath.isNotEmpty ? primaryPath : fullCommand);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: isCommand
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: context.t3.codeBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.t3.border),
              ),
              child: SelectableText(
                '\$ $displayContent',
                style: TextStyle(
                  fontFamily: AppTheme.monoFont,
                  fontFamilyFallback: AppTheme.monoFallback,
                  fontSize: 12,
                  height: 1.45,
                  color: failed ? context.t3.error : context.t3.foregroundSubtle,
                ),
              ),
            )
          : SelectableText(
              displayContent,
              style: TextStyle(
                fontFamily: AppTheme.monoFont,
                fontFamilyFallback: AppTheme.monoFallback,
                fontSize: 12,
                height: 1.45,
                color: failed ? context.t3.error : context.t3.mutedForeground,
              ),
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
    final title = payload['title']?.toString() ?? activity.summary;
    final fullCommand = ToolActivityHelper.extractCleanFullCommand(activity);
    final isCommand = itemType == 'command_execution' || itemType == 'command';
    final isDispatch = itemType == 'prompt_dispatch';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCommand ? LucideIcons.terminal : (isDispatch ? LucideIcons.zap : LucideIcons.wrench),
            size: 15,
            color: context.t3.mutedForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fullCommand.isNotEmpty && fullCommand != title ? '$title · $fullCommand' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: context.t3.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}
