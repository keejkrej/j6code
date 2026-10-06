import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/app_theme.dart';
import '../models/j6_entities.dart';

class MessageItemWidget extends StatelessWidget {
  final J6Message message;

  const MessageItemWidget({
    super.key,
    required this.message,
  });

  MarkdownStyleSheet _getMarkdownStyleSheet(BuildContext context, {required bool isUser}) {
    return MarkdownStyleSheet(
      p: TextStyle(
        fontSize: 13.5,
        height: 1.55,
        color: AppTheme.textPrimary,
      ),
      h1: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
        height: 1.4,
      ),
      h2: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
        height: 1.4,
      ),
      h3: const TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
        height: 1.4,
      ),
      code: const TextStyle(
        fontFamily: 'Consolas, monospace',
        fontSize: 12,
        color: Color(0xFFE2E8F0),
        backgroundColor: Color(0xFF1E1E24),
      ),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquote: const TextStyle(
        color: AppTheme.textSecondary,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: AppTheme.accent, width: 3),
        ),
      ),
      listBullet: const TextStyle(
        fontSize: 13.5,
        color: AppTheme.textSecondary,
      ),
      strong: const TextStyle(
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
      em: const TextStyle(
        fontStyle: FontStyle.italic,
        color: AppTheme.textSecondary,
      ),
      a: const TextStyle(
        color: AppTheme.accent,
        decoration: TextDecoration.underline,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppTheme.borderSubtle,
            width: 1,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isReasoning = message.role == 'reasoning';

    if (isReasoning) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
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
                    'Agent Reasoning',
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

    if (isUser) {
      // User message: starts from ~20% on the left, aligns to the right edge with margins
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(flex: 2), // 20% left offset
            Flexible(
              flex: 8, // up to 80% width
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF222228),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MarkdownBody(
                      data: message.text,
                      selectable: true,
                      styleSheet: _getMarkdownStyleSheet(context, isUser: true),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Assistant / Agent message: full width with horizontal margins
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHover,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: const Center(
                  child: Icon(Icons.auto_awesome_rounded, size: 13, color: AppTheme.accent),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Assistant',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accent,
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
          const SizedBox(height: 8),
          MarkdownBody(
            data: message.text,
            selectable: true,
            styleSheet: _getMarkdownStyleSheet(context, isUser: false),
          ),
        ],
      ),
    );
  }
}
