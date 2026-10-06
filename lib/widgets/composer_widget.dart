import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/j6_entities.dart';

class ComposerWidget extends StatefulWidget {
  final List<J6Provider> providers;
  final J6Provider? selectedProvider;
  final J6Model? selectedModel;
  final Function(J6Provider provider, J6Model model) onSelectModel;
  final Function(String prompt) onSendPrompt;
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
  final FocusNode _focusNode = FocusNode();

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isSending) return;
    widget.onSendPrompt(text);
    _controller.clear();
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
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.hub_rounded, size: 20, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  const Text(
                    'Select AI Engine & Model',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Connect to Grok Build, OpenCode, Anti Gravity ACP, or Claude models for coding tasks.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const Divider(height: 24),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.providers.length,
                  itemBuilder: (context, pIndex) {
                    final p = widget.providers[pIndex];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: Text(
                            p.displayName.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                        ...p.models.map((m) {
                          final isSelected = widget.selectedProvider?.id == p.id &&
                              widget.selectedModel?.slug == m.slug;
                          return ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            selected: isSelected,
                            selectedTileColor: AppTheme.surfaceHover,
                            leading: Icon(
                              Icons.auto_awesome_rounded,
                              size: 16,
                              color: isSelected ? AppTheme.accent : AppTheme.textMuted,
                            ),
                            title: Text(
                              m.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                              ),
                            ),
                            subtitle: Text(
                              m.slug,
                              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.accent)
                                : null,
                            onTap: () {
                              widget.onSelectModel(p, m);
                              Navigator.pop(ctx);
                            },
                          );
                        }),
                        const SizedBox(height: 10),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeModelName = widget.selectedModel?.name ?? 'Grok Build';
    final activeProviderName = widget.selectedProvider?.displayName ?? 'Grok';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
      ),
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
                KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _handleSend();
                    }
                  },
                  child: TextField(
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
                    const SizedBox(width: 8),
                    // Active Workspace Tag
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceHover,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder_outlined, size: 12, color: AppTheme.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            widget.activeWorkspaceName,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Send button
                    IconButton(
                      icon: widget.isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
                              ),
                            )
                          : const Icon(Icons.arrow_upward_rounded, size: 18),
                      color: AppTheme.accent,
                      onPressed: widget.isSending ? null : _handleSend,
                      tooltip: 'Send prompt to agent (Enter)',
                      splashRadius: 18,
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
