import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';
import '../models/j6_entities.dart';
import 'ui_kit.dart';

/// Floating, rounded composer in the style of t3code, with a row of
/// low-emphasis context chips underneath (host, workspace, model, access).
class ComposerWidget extends StatefulWidget {
  final List<J6Provider> providers;
  final J6Provider? selectedProvider;
  final J6Model? selectedModel;
  final Function(J6Provider, J6Model) onSelectModel;
  final void Function(String prompt, List<J6Attachment> attachments) onSendPrompt;
  final bool isSending;
  final String activeWorkspaceName;
  final bool isGitRepo;
  final double maxWidth;
  final RuntimeMode runtimeMode;
  final ValueChanged<RuntimeMode> onRuntimeModeChanged;

  const ComposerWidget({
    super.key,
    required this.providers,
    required this.selectedProvider,
    required this.selectedModel,
    required this.onSelectModel,
    required this.onSendPrompt,
    required this.isSending,
    required this.activeWorkspaceName,
    required this.runtimeMode,
    required this.onRuntimeModeChanged,
    this.isGitRepo = false,
    this.maxWidth = 768,
  });

  @override
  State<ComposerWidget> createState() => ComposerWidgetState();
}

class ComposerWidgetState extends State<ComposerWidget> {
  /// t3code caps a message at 8 attachments.
  static const int _maxAttachments = 8;

  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode;
  bool _focused = false;
  bool _dragging = false;
  final List<J6Attachment> _attachments = [];

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    _focusNode.addListener(() => setState(() => _focused = _focusNode.hasFocus));
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Inserts [text] at the caret (used by the terminal's "Add to chat").
  void insertText(String text) {
    final value = _controller.value;
    final sel = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
    final before = value.text.substring(0, sel.start);
    final needsBreak = before.isNotEmpty && !before.endsWith('\n');
    final insert = '${needsBreak ? '\n' : ''}$text';
    final next = value.text.replaceRange(sel.start, sel.end, insert);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: sel.start + insert.length),
    );
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.enter && !hw.isShiftPressed) {
      _handleSend();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyV && hw.isControlPressed) {
      // Text pastes normally; when the clipboard holds an image or copied
      // files instead, turn them into attachments.
      _pasteNonText();
    }
    return KeyEventResult.ignored;
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if ((text.isEmpty && _attachments.isEmpty) || widget.isSending) return;
    final attachments = List<J6Attachment>.from(_attachments);
    _controller.clear();
    setState(_attachments.clear);
    widget.onSendPrompt(text, attachments);
  }

  void _addPaths(Iterable<String> paths) {
    final added = <J6Attachment>[];
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue; // folders and vanished files are skipped
      if (_attachments.any((a) => a.path == path) || added.any((a) => a.path == path)) continue;
      added.add(J6Attachment(
        name: path.split(RegExp(r'[\\/]')).last,
        path: path,
        mimeType: J6Attachment.mimeTypeFor(path),
        sizeBytes: file.lengthSync(),
      ));
    }
    if (added.isEmpty) return;
    final room = _maxAttachments - _attachments.length;
    setState(() => _attachments.addAll(added.take(room)));
    if (added.length > room && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can attach up to 8 files per message.'), width: 360, behavior: SnackBarBehavior.floating),
      );
    }
    _focusNode.requestFocus();
  }

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Attach files');
    _addPaths(files.map((f) => f.path).whereType<String>());
  }

  Future<void> _pasteNonText() async {
    if (!Platform.isWindows) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if ((data?.text ?? '').isNotEmpty) return;
    final paths = await _readClipboardFilesWindows();
    if (paths.isNotEmpty) _addPaths(paths);
  }

  /// Flutter's clipboard is text-only, so ask PowerShell (STA) for copied
  /// files or a bitmap; bitmaps are saved as PNG in the temp folder.
  static Future<List<String>> _readClipboardFilesWindows() async {
    final out = '${Directory.systemTemp.path}\\j6code_paste_${DateTime.now().millisecondsSinceEpoch}.png';
    final script = r'''
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$files = [System.Windows.Forms.Clipboard]::GetFileDropList()
if ($files.Count -gt 0) { $files | ForEach-Object { $_ }; exit }
$img = [System.Windows.Forms.Clipboard]::GetImage()
if ($img) { $img.Save($env:J6_PASTE_OUT, [System.Drawing.Imaging.ImageFormat]::Png); $env:J6_PASTE_OUT }
''';
    try {
      final result = await Process.run(
        'powershell.exe',
        ['-NoLogo', '-NoProfile', '-NonInteractive', '-STA', '-Command', script],
        environment: {'J6_PASTE_OUT': out},
      ).timeout(const Duration(seconds: 5));
      return (result.stdout as String).split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  Widget _buildModelMenu() {
    final modelLabel = widget.selectedModel?.slug ?? widget.selectedModel?.name ?? 'Select model';
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final p in widget.providers) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              p.displayName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.t3.mutedForeground,
              ),
            ),
          ),
          for (final m in p.models)
            MenuItemButton(
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(Size(260, 32)),
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                overlayColor: WidgetStatePropertyAll(context.t3.accent),
              ),
              onPressed: () => widget.onSelectModel(p, m),
              trailingIcon: (widget.selectedProvider?.id == p.id && widget.selectedModel?.slug == m.slug)
                  ? Icon(LucideIcons.check, size: 15, color: context.t3.foreground)
                  : null,
              child: Text(
                m.name,
                style: TextStyle(fontSize: 13, color: context.t3.foreground),
              ),
            ),
        ],
      ],
      builder: (context, controller, _) => _ComposerPill(
        icon: LucideIcons.sparkles,
        label: modelLabel,
        tooltip: widget.selectedProvider?.displayName,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend = (_controller.text.trim().isNotEmpty || _attachments.isNotEmpty) && !widget.isSending;
    final workspace = widget.activeWorkspaceName.isNotEmpty ? widget.activeWorkspaceName : 'No workspace';

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main prompt card (also a drop target for files)
              DropTarget(
                onDragEntered: (_) => setState(() => _dragging = true),
                onDragExited: (_) => setState(() => _dragging = false),
                onDragDone: (detail) {
                  setState(() => _dragging = false);
                  _addPaths(detail.files.map((f) => f.path));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: _dragging ? Color.alphaBlend(context.t3.info.withAlpha(14), context.t3.card) : context.t3.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _dragging
                          ? context.t3.info.withAlpha(160)
                          : _focused
                              ? context.t3.mutedForeground.withAlpha(90)
                              : context.t3.input,
                    ),
                    boxShadow: [
                      BoxShadow(color: context.t3.composerShadow, blurRadius: 28, spreadRadius: -18, offset: const Offset(0, 12)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_attachments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final a in _attachments)
                                _AttachmentPreview(
                                  attachment: a,
                                  onRemove: () => setState(() => _attachments.remove(a)),
                                ),
                            ],
                          ),
                        ),
                      GestureDetector(
                        onTap: () => _focusNode.requestFocus(),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 56),
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              minLines: 1,
                              maxLines: 12,
                              style: TextStyle(fontSize: 15, height: 1.45, color: context.t3.foreground),
                              decoration: InputDecoration(
                                hintText: _dragging
                                    ? 'Drop files to attach'
                                    : 'Ask for changes, send follow-ups, or attach images',
                                hintStyle: TextStyle(fontSize: 15, color: context.t3.mutedForeground),
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        child: Row(
                          children: [
                            Flexible(child: _buildModelMenu()),
                            Container(
                              width: 1,
                              height: 18,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              color: context.t3.input,
                            ),
                            _AccessMenu(mode: widget.runtimeMode, onChanged: widget.onRuntimeModeChanged),
                            const Spacer(),
                            GhostIconButton(
                              icon: LucideIcons.paperclip,
                              size: 34,
                              iconSize: 18,
                              tooltip: 'Attach files (or drop / paste them)',
                              onPressed: _attachments.length >= _maxAttachments ? null : _pickFiles,
                            ),
                            const SizedBox(width: 6),
                            _SendButton(
                              enabled: canSend,
                              busy: widget.isSending,
                              onTap: _handleSend,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Context tray tucked beneath the card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: context.t3.background,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                    border: Border(
                      left: BorderSide(color: context.t3.border),
                      right: BorderSide(color: context.t3.border),
                      bottom: BorderSide(color: context.t3.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      const GhostChip(icon: LucideIcons.server, label: 'Local', tooltip: 'Execution host'),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: GhostChip(
                            icon: widget.isGitRepo ? LucideIcons.gitBranch : LucideIcons.folder,
                            label: workspace,
                            color: context.t3.faint,
                            tooltip: widget.isGitRepo ? 'Git repository' : 'Workspace folder',
                          ),
                        ),
                      ),
                    ],
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

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Pending attachment in the composer: image thumbnail or file chip, with a
/// remove button.
class _AttachmentPreview extends StatelessWidget {
  final J6Attachment attachment;
  final VoidCallback onRemove;

  const _AttachmentPreview({required this.attachment, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final t3 = context.t3;
    final Widget body;
    if (attachment.isImage && !attachment.path.toLowerCase().endsWith('.svg')) {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(attachment.path),
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          cacheWidth: 128,
          errorBuilder: (_, _, _) => _fileChip(context),
        ),
      );
    } else {
      body = _fileChip(context);
    }
    return Tooltip(
      message: '${attachment.name} · ${formatBytes(attachment.sizeBytes)}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t3.border),
            ),
            child: body,
          ),
          Positioned(
            top: -6,
            right: -6,
            child: Material(
              color: t3.popover,
              shape: CircleBorder(side: BorderSide(color: t3.input)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(LucideIcons.x, size: 11, color: t3.foreground),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileChip(BuildContext context) {
    final t3 = context.t3;
    return Container(
      height: 64,
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: t3.muted, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(attachment.isImage ? LucideIcons.image : LucideIcons.fileText, size: 18, color: t3.mutedForeground),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t3.foreground)),
                Text(formatBytes(attachment.sizeBytes), style: TextStyle(fontSize: 11, color: t3.mutedForeground)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Runtime-mode selector (t3code runtimeModeConfig): Supervised,
/// Auto-accept edits, Auto, Full access.
class _AccessMenu extends StatelessWidget {
  final RuntimeMode mode;
  final ValueChanged<RuntimeMode> onChanged;

  const _AccessMenu({required this.mode, required this.onChanged});

  static IconData iconFor(RuntimeMode m) => switch (m) {
        RuntimeMode.approvalRequired => LucideIcons.lock,
        RuntimeMode.autoAcceptEdits => LucideIcons.penLine,
        RuntimeMode.auto => LucideIcons.sparkles,
        RuntimeMode.fullAccess => LucideIcons.lockOpen,
      };

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final m in RuntimeMode.values)
          MenuItemButton(
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(300, 48)),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
              overlayColor: WidgetStatePropertyAll(context.t3.accent),
            ),
            leadingIcon: Icon(iconFor(m), size: 15, color: context.t3.foregroundSubtle),
            trailingIcon: mode == m ? Icon(LucideIcons.check, size: 15, color: context.t3.foreground) : null,
            onPressed: () => onChanged(m),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.label, style: TextStyle(fontSize: 13, color: context.t3.foreground)),
                const SizedBox(height: 1),
                Text(m.description, style: TextStyle(fontSize: 11.5, color: context.t3.mutedForeground)),
              ],
            ),
          ),
      ],
      builder: (context, controller, _) => _ComposerPill(
        icon: iconFor(mode),
        label: mode.label,
        tooltip: mode.description,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Larger pill used inside the composer card (model / access selectors).
class _ComposerPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? tooltip;

  const _ComposerPill({required this.icon, required this.label, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final pill = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: context.t3.accent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: context.t3.mutedForeground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.t3.foregroundSubtle),
                ),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronDown, size: 15, color: context.t3.mutedForeground),
            ],
          ),
        ),
      ),
    );
    if (tooltip == null) return pill;
    return Tooltip(message: tooltip!, child: pill);
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _SendButton({required this.enabled, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Send (Enter)',
      child: Material(
        color: enabled || busy ? context.t3.primary : context.t3.input,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          hoverColor: const Color(0x22FFFFFF),
          child: SizedBox(
            width: 34,
            height: 34,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(context.t3.primaryForeground),
                    ),
                  )
                : Icon(
                    LucideIcons.arrowUp,
                    size: 18,
                    color: enabled ? context.t3.primaryForeground : context.t3.mutedForeground,
                  ),
          ),
        ),
      ),
    );
  }
}
