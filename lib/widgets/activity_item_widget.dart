import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/j6_entities.dart';

class ActivityItemWidget extends StatelessWidget {
  final J6Activity activity;

  const ActivityItemWidget({
    super.key,
    required this.activity,
  });

  @override
  Widget build(BuildContext context) {
    final payload = activity.payload;
    final itemType = payload['itemType'] ?? '';
    final status = payload['status'] ?? '';
    final title = payload['title'] ?? activity.summary;
    final detail = payload['detail'] ?? '';
    final command = payload['command'] ?? '';
    final provider = payload['provider'] ?? '';
    final model = payload['model'] ?? '';

    final isCommand = itemType == 'command_execution' || command.isNotEmpty;
    final isDispatch = itemType == 'prompt_dispatch';
    final isDone = status == 'completed';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      title.isNotEmpty ? title : (isCommand ? 'Terminal Run' : 'Tool Activity'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isDone ? AppTheme.success.withAlpha(25) : AppTheme.accent.withAlpha(25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status.isNotEmpty ? status.toUpperCase() : 'ACTIVE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isDone ? AppTheme.success : AppTheme.accent,
                        ),
                      ),
                    ),
                    if (provider.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
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
                if (detail.isNotEmpty || command.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    command.isNotEmpty ? command : detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Consolas, monospace',
                      fontSize: 11,
                      color: AppTheme.textMuted,
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
