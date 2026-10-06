import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/j6_entities.dart';

class ComposerWidget extends StatefulWidget {
  final List<J6Provider> providers;
  final J6Provider? selectedProvider;
  final J6Model? selectedModel;
  final Function(J6Provider, J6Model) onSelectModel;
  final Function(String) onSendPrompt;
  final bool isSending;
  final String activeWorkspaceName;

  const ComposerWidget({
    super.key,
    required this.providers,
    required this.selectedProvider,
    required this.selectedModel,
    required this.onSelectModel,
    required this.onSendPrompt,
    required this.isSending,
    required this.activeWorkspaceName,
  });

  @override
  State<ComposerWidget> createState() => _ComposerWidgetState();
}

class _ComposerWidgetState extends State<ComposerWidget> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _handleSend();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isSending) return;
    _controller.clear();
    widget.onSendPrompt(text);
  }

  void _showModelPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select AI Engine & Model',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: widget.providers.map((p) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceSubtle,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.psychology, size: 16, color: AppTheme.accent),
                                const SizedBox(width: 8),
                                Text(
                                  p.displayName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          ...p.models.map((m) {
                            final isSelected = widget.selectedProvider?.id == p.id &&
                                widget.selectedModel?.slug == m.slug;
                            return ListTile(
                              dense: true,
                              title: Text(
                                m.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
                                ),
                              ),
                              subtitle: Text(
                                m.slug,
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle, size: 16, color: AppTheme.accent)
                                  : null,
                              onTap: () {
                                widget.onSelectModel(p, m);
                                Navigator.pop(ctx);
                              },
                            );
                          }),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeProviderName = widget.selectedProvider?.displayName ?? 'AI Engine';
    final activeModelName = widget.selectedModel?.name ?? 'Select Model';

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Prompt text field container
          Container(
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              children: [
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 6,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Ask j6code to code, test, or refactor in this repo... (Shift+Enter for newline)',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                    ),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Clickable Model / Provider Selector
                    InkWell(
                      onTap: () => _showModelPicker(context),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceHover,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.accent.withAlpha(80)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome, size: 12, color: AppTheme.accent),
                            const SizedBox(width: 5),
                            Text(
                              '$activeProviderName: $activeModelName',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, size: 14, color: AppTheme.textMuted),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Active Workspace Folder Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceSubtle,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder_open, size: 12, color: AppTheme.textMuted),
                          const SizedBox(width: 5),
                          Text(
                            widget.activeWorkspaceName.isNotEmpty
                                ? widget.activeWorkspaceName
                                : 'No workspace',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Send Button
                    InkWell(
                      onTap: widget.isSending ? null : _handleSend,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: widget.isSending
                              ? AppTheme.accent.withAlpha(100)
                              : AppTheme.accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.isSending) ...[
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            const Text(
                              'Send',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
