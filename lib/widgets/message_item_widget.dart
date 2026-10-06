import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/app_theme.dart';
import '../models/t3_entities.dart';

class MessageItemWidget extends StatelessWidget {
  final T3Message message;

  const MessageItemWidget({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isReasoning = message.role == 'reasoning';

    if (isReasoning) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.psychology_outlined, size: 16, color: AppTheme.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Thought Process',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.text,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Role Avatar
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: isUser ? AppTheme.accent : AppTheme.surfaceHover,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isUser ? AppTheme.accent : AppTheme.border,
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(
                isUser ? Icons.person_rounded : Icons.auto_awesome_rounded,
                size: 16,
                color: isUser ? Colors.white : AppTheme.accent,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Message Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isUser ? 'You' : 'Antigravity (Assistant)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isUser ? AppTheme.textPrimary : AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                    ),
                    if (message.isStreaming) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 8,
                        height: 8,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                MarkdownBody(
                  data: message.text,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: AppTheme.textPrimary,
                    ),
                    code: const TextStyle(
                      fontFamily: 'Consolas, monospace',
                      fontSize: 12.5,
                      backgroundColor: AppTheme.surfaceHover,
                      color: AppTheme.accent,
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: AppTheme.surfaceSubtle,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.border),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
