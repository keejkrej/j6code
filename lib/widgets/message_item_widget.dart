import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';
import '../models/j6_entities.dart';

/// Chat timeline message in the t3code style: right-aligned soft bubble for the
/// user, borderless full-width markdown for the assistant, and inline red
/// error rows.
class MessageItemWidget extends StatelessWidget {
  final J6Message message;

  const MessageItemWidget({super.key, required this.message});

  static final RegExp _errorPattern = RegExp(r'^\s*\[Error[^\]]*\]\s*$', multiLine: true);

  static MarkdownStyleSheet markdownStyle(BuildContext context) {
    final body = TextStyle(fontSize: 14.5, height: 1.6, color: context.t3.foreground);
    return MarkdownStyleSheet(
      p: body,
      pPadding: const EdgeInsets.only(bottom: 2),
      h1: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: context.t3.foreground, height: 1.4),
      h2: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.t3.foreground, height: 1.4),
      h3: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.t3.foreground, height: 1.4),
      h1Padding: const EdgeInsets.only(top: 8),
      h2Padding: const EdgeInsets.only(top: 8),
      h3Padding: const EdgeInsets.only(top: 6),
      blockSpacing: 12,
      code: TextStyle(
        fontFamily: AppTheme.monoFont,
        fontFamilyFallback: AppTheme.monoFallback,
        fontSize: 12.5,
        color: context.t3.foreground,
        backgroundColor: context.t3.accent,
      ),
      codeblockDecoration: BoxDecoration(
        color: context.t3.codeBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.t3.border),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      blockquote: TextStyle(color: context.t3.foregroundSubtle),
      blockquotePadding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: context.t3.input, width: 3)),
      ),
      listBullet: body.copyWith(color: context.t3.mutedForeground),
      listIndent: 22,
      strong: TextStyle(fontWeight: FontWeight.w700, color: context.t3.foreground),
      em: const TextStyle(fontStyle: FontStyle.italic),
      a: TextStyle(color: context.t3.link, decoration: TextDecoration.none),
      tableHead: TextStyle(fontWeight: FontWeight.w600, color: context.t3.foreground),
      tableBody: body,
      tableBorder: TableBorder.all(color: context.t3.border),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.t3.border, width: 1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (message.role) {
      case 'user':
        return _UserBubble(message: message);
      case 'reasoning':
        return _ReasoningBlock(text: message.text);
      default:
        return _buildAssistant(context);
    }
  }

  Widget _buildAssistant(BuildContext context) {
    final text = message.text;
    final errors = _errorPattern.allMatches(text).map((m) => m.group(0)!.trim()).toList();
    final body = text.replaceAll(_errorPattern, '').trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (body.isNotEmpty)
            MarkdownBody(data: body, selectable: true, styleSheet: markdownStyle(context)),
          if (body.isEmpty && message.isStreaming) const _WorkingIndicator(),
          for (final e in errors) ErrorRow(text: e.substring(1, e.length - 1)),
          if (body.isNotEmpty && message.isStreaming) ...[
            const SizedBox(height: 6),
            const _WorkingIndicator(),
          ],
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  final J6Message message;
  const _UserBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final t = message.createdAt.toLocal();
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: FractionallySizedBox(
          widthFactor: 0.8,
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (message.attachments.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: message.text.isEmpty ? 0 : 6),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final a in message.attachments) _MessageAttachment(attachment: a)],
                  ),
                ),
              if (message.text.isNotEmpty)
                Tooltip(
                  message: time,
                  waitDuration: const Duration(milliseconds: 700),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      color: context.t3.messageSurface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: SelectableText(
                      message.text,
                      style: TextStyle(fontSize: 14.5, height: 1.5, color: context.t3.foreground),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageAttachment extends StatelessWidget {
  final J6Attachment attachment;
  const _MessageAttachment({required this.attachment});

  void _open(BuildContext context) {
    if (attachment.isImage) {
      showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (ctx) => GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Center(
            child: InteractiveViewer(child: Image.file(File(attachment.path))),
          ),
        ),
      );
    } else if (Platform.isWindows) {
      Process.start('explorer.exe', ['/select,', attachment.path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t3 = context.t3;
    final showImage = attachment.isImage && !attachment.path.toLowerCase().endsWith('.svg');
    return Tooltip(
      message: attachment.name,
      child: Material(
        color: t3.messageSurface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(context),
          child: showImage
              ? Image.file(
                  File(attachment.path),
                  height: 120,
                  fit: BoxFit.cover,
                  cacheHeight: 240,
                  errorBuilder: (_, _, _) => _chip(t3, missing: true),
                )
              : _chip(t3),
        ),
      ),
    );
  }

  Widget _chip(T3Colors t3, {bool missing = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(missing ? LucideIcons.fileX : (attachment.isImage ? LucideIcons.image : LucideIcons.fileText),
              size: 15, color: t3.mutedForeground),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(attachment.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: t3.foreground)),
          ),
        ]),
      );
}

class _ReasoningBlock extends StatefulWidget {
  final String text;
  const _ReasoningBlock({required this.text});

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Thought', style: TextStyle(fontSize: 13, color: context.t3.mutedForeground)),
                  const SizedBox(width: 4),
                  Icon(
                    _open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                    size: 16,
                    color: context.t3.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Container(
              margin: const EdgeInsets.only(top: 4, left: 2),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: context.t3.input, width: 2)),
              ),
              child: SelectableText(
                widget.text,
                style: TextStyle(fontSize: 13, height: 1.55, color: context.t3.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }
}

/// Red inline error line with a chevron, as in the t3code timeline.
class ErrorRow extends StatefulWidget {
  final String text;
  const ErrorRow({super.key, required this.text});

  @override
  State<ErrorRow> createState() => _ErrorRowState();
}

class _ErrorRowState extends State<ErrorRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(LucideIcons.circleAlert, size: 16, color: context.t3.error),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.text,
                maxLines: _open ? null : 1,
                overflow: _open ? null : TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, height: 1.4, color: context.t3.error),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
              size: 16,
              color: context.t3.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkingIndicator extends StatefulWidget {
  const _WorkingIndicator();

  @override
  State<_WorkingIndicator> createState() => _WorkingIndicatorState();
}

class _WorkingIndicatorState extends State<_WorkingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Text('Working…', style: TextStyle(fontSize: 13.5, color: context.t3.mutedForeground)),
    );
  }
}
