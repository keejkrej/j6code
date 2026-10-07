import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:xterm/xterm.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

/// One interactive shell running inside a pseudo-terminal (ConPTY on
/// Windows). Rendering and input are handled by xterm.dart, so full-screen
/// programs (vim, less, REPLs, prompts, progress bars) work like they do in
/// t3code's drawer.
class _PtySession {
  _PtySession({required this.cwd, required this.index});

  final String cwd;
  final int index;
  final Terminal terminal = Terminal(maxLines: 10000);
  final TerminalController controller = TerminalController();
  final FocusNode focusNode = FocusNode();
  Pty? pty;
  StreamSubscription<String>? _output;
  int? exitCode;

  String get title => 'Terminal $index';

  void start() {
    final shell = _resolveShell();
    try {
      pty = Pty.start(
        shell.executable,
        arguments: shell.arguments,
        workingDirectory: cwd,
        // flutter_pty only forwards a few variables by default; Windows tools
        // need the full environment (SystemRoot, APPDATA, PATHEXT, …).
        environment: {...Platform.environment, 'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
        columns: terminal.viewWidth,
        rows: terminal.viewHeight,
      );
    } catch (e) {
      terminal.write('\x1b[31mFailed to start ${shell.executable}: $e\x1b[0m\r\n');
      return;
    }
    final p = pty!;
    _output = p.output.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen(terminal.write);
    p.exitCode.then((code) {
      exitCode = code;
      terminal.write('\r\n\x1b[2m[Process exited with code $code]\x1b[0m\r\n');
    });
    terminal.onOutput = (data) => p.write(const Utf8Encoder().convert(data));
    terminal.onResize = (w, h, pw, ph) => p.resize(h, w);
  }

  void dispose() {
    _output?.cancel();
    pty?.kill();
    focusNode.dispose();
  }

  static ({String executable, List<String> arguments}) _resolveShell() {
    if (Platform.isWindows) {
      // Prefer PowerShell 7, fall back to Windows PowerShell.
      final pathDirs = (Platform.environment['PATH'] ?? '').split(';');
      final hasPwsh = pathDirs.any((d) => d.isNotEmpty && File('$d\\pwsh.exe').existsSync());
      return (executable: hasPwsh ? 'pwsh.exe' : 'powershell.exe', arguments: const ['-NoLogo']);
    }
    return (executable: Platform.environment['SHELL'] ?? 'bash', arguments: const ['-l']);
  }
}

/// Bottom terminal drawer in the style of t3code.
class TerminalDrawer extends StatefulWidget {
  final String workingDirectory;
  final VoidCallback onClose;

  /// Receives selected terminal text for t3code's "Add to chat".
  final ValueChanged<String>? onAddToChat;

  const TerminalDrawer({super.key, required this.workingDirectory, required this.onClose, this.onAddToChat});

  @override
  State<TerminalDrawer> createState() => _TerminalDrawerState();
}

class _TerminalDrawerState extends State<TerminalDrawer> {
  static const double _minHeight = 140;
  double _height = 320;

  final List<_PtySession> _sessions = [];
  int _active = 0;
  int _nextIndex = 1;

  _PtySession get _session => _sessions[_active];

  @override
  void initState() {
    super.initState();
    _addSession();
  }

  @override
  void dispose() {
    for (final s in _sessions) {
      s.dispose();
    }
    super.dispose();
  }

  String _initialCwd() {
    final dir = widget.workingDirectory;
    if (dir.isNotEmpty && Directory(dir).existsSync()) return dir;
    return Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.current.path;
  }

  void _addSession() {
    final session = _PtySession(cwd: _initialCwd(), index: _nextIndex++);
    setState(() {
      _sessions.add(session);
      _active = _sessions.length - 1;
    });
    // Start once the view has laid out so the PTY gets the real grid size.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      session.start();
      session.focusNode.requestFocus();
    });
  }

  void _selectSession(int i) {
    setState(() => _active = i);
    WidgetsBinding.instance.addPostFrameCallback((_) => _session.focusNode.requestFocus());
  }

  void _closeSession() {
    if (_sessions.length == 1) {
      widget.onClose();
      return;
    }
    final s = _session;
    setState(() {
      _sessions.removeAt(_active);
      _active = _active.clamp(0, _sessions.length - 1);
    });
    s.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) => _session.focusNode.requestFocus());
  }

  String? _selectedText(_PtySession s) {
    final sel = s.controller.selection;
    if (sel == null) return null;
    final text = s.terminal.buffer.getText(sel);
    return text.trim().isEmpty ? null : text;
  }

  Future<void> _copy(_PtySession s) async {
    final text = _selectedText(s);
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    s.controller.clearSelection();
  }

  Future<void> _paste(_PtySession s) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) s.terminal.paste(text);
  }

  /// Right-click menu, as in t3code: Add to chat / Copy (need a selection) and Paste.
  Future<void> _showContextMenu(_PtySession s, Offset globalPosition) async {
    final selection = _selectedText(s);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final t3 = context.t3;
    PopupMenuItem<String> item(String value, IconData icon, String label, {bool enabled = true}) => PopupMenuItem(
          value: value,
          enabled: enabled,
          height: 32,
          child: Row(children: [
            Icon(icon, size: 14, color: enabled ? t3.foregroundSubtle : t3.faint),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 13, color: enabled ? t3.foreground : t3.faint)),
          ]),
        );
    final choice = await showMenu<String>(
      context: context,
      color: t3.popover,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: t3.input)),
      position: RelativeRect.fromRect(globalPosition & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        if (widget.onAddToChat != null)
          item('add', LucideIcons.messageSquarePlus, 'Add to chat', enabled: selection != null),
        item('copy', LucideIcons.copy, 'Copy', enabled: selection != null),
        item('paste', LucideIcons.clipboardPaste, 'Paste'),
        item('clear', LucideIcons.eraser, 'Clear'),
      ],
    );
    switch (choice) {
      case 'add':
        if (selection != null) widget.onAddToChat?.call(selection);
        s.controller.clearSelection();
      case 'copy':
        await _copy(s);
      case 'paste':
        await _paste(s);
      case 'clear':
        s.terminal.buffer.clear();
        s.terminal.buffer.setCursor(0, 0);
        s.pty?.write(const Utf8Encoder().convert('\r'));
    }
    s.focusNode.requestFocus();
  }

  KeyEventResult _onKey(_PtySession s, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    final key = event.logicalKey;
    // Ctrl+J toggles the drawer even while the terminal has focus (t3code).
    if (hw.isControlPressed && !hw.isShiftPressed && key == LogicalKeyboardKey.keyJ) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    // Ctrl+C copies when there is a selection; otherwise it is SIGINT.
    if (hw.isControlPressed && !hw.isShiftPressed && key == LogicalKeyboardKey.keyC && _selectedText(s) != null) {
      _copy(s);
      return KeyEventResult.handled;
    }
    if (hw.isControlPressed && hw.isShiftPressed && key == LogicalKeyboardKey.keyV) {
      _paste(s);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  TerminalTheme _theme(T3Colors t3, Brightness b) {
    final dark = b == Brightness.dark;
    return TerminalTheme(
      cursor: t3.terminalCursor,
      selection: t3.terminalSelection,
      foreground: t3.terminalForeground,
      background: t3.terminalBackground,
      black: dark ? const Color(0xFF1C2129) : const Color(0xFF1C2129),
      red: dark ? const Color(0xFFF7768E) : const Color(0xFFC0392B),
      green: dark ? const Color(0xFF7DCFA0) : const Color(0xFF1E8449),
      yellow: dark ? const Color(0xFFE0AF68) : const Color(0xFFB9770E),
      blue: dark ? const Color(0xFF7AA2F7) : const Color(0xFF2563EB),
      magenta: dark ? const Color(0xFFBB9AF7) : const Color(0xFF8E44AD),
      cyan: dark ? const Color(0xFF7DCFFF) : const Color(0xFF0E7490),
      white: dark ? const Color(0xFFC0CAF5) : const Color(0xFF6B7280),
      brightBlack: dark ? const Color(0xFF565F89) : const Color(0xFF9CA3AF),
      brightRed: dark ? const Color(0xFFFF8FA3) : const Color(0xFFE74C3C),
      brightGreen: dark ? const Color(0xFF9EE6B8) : const Color(0xFF27AE60),
      brightYellow: dark ? const Color(0xFFFFC777) : const Color(0xFFD4AC0D),
      brightBlue: dark ? const Color(0xFF9DB8FF) : const Color(0xFF3B82F6),
      brightMagenta: dark ? const Color(0xFFD0B4FF) : const Color(0xFFA569BD),
      brightCyan: dark ? const Color(0xFFA4DCFF) : const Color(0xFF0891B2),
      brightWhite: dark ? const Color(0xFFEDF1F7) : const Color(0xFF1C2129),
      searchHitBackground: const Color(0xFFFFDF5D),
      searchHitBackgroundCurrent: const Color(0xFFFF9632),
      searchHitForeground: const Color(0xFF000000),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t3 = context.t3;
    final theme = _theme(t3, Theme.of(context).brightness);
    final textStyle = TerminalStyle(
      fontSize: 13,
      height: 1.3,
      fontFamily: AppTheme.monoFont,
      fontFamilyFallback: AppTheme.monoFallback,
    );

    return SizedBox(
      height: _height,
      child: Container(
        decoration: BoxDecoration(
          color: t3.terminalBackground,
          border: Border(top: BorderSide(color: t3.border)),
        ),
        child: Stack(
          children: [
            // Terminal body: every session stays mounted so its scrollback and
            // running program survive tab switches.
            Positioned.fill(
              child: IndexedStack(
                index: _active,
                children: [
                  for (final s in _sessions)
                    TerminalView(
                      s.terminal,
                      key: ObjectKey(s),
                      controller: s.controller,
                      focusNode: s.focusNode,
                      theme: theme,
                      textStyle: textStyle,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                      cursorType: TerminalCursorType.block,
                      hardwareKeyboardOnly: true,
                      keyboardAppearance: Theme.of(context).brightness,
                      onKeyEvent: (_, e) => _onKey(s, e),
                      onSecondaryTapDown: (d, _) => _showContextMenu(s, d.globalPosition),
                    ),
                ],
              ),
            ),

            // Resize handle
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 6,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) {
                    final maxH = MediaQuery.of(context).size.height * 0.75;
                    setState(() => _height = (_height - d.delta.dy).clamp(_minHeight, maxH));
                  },
                ),
              ),
            ),

            // Toolbar (top-right)
            Positioned(
              top: 8,
              right: 10,
              child: Row(
                children: [
                  if (_sessions.length > 1)
                    for (var i = 0; i < _sessions.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: GhostIconButton(
                          icon: LucideIcons.squareTerminal,
                          size: 24,
                          iconSize: 14,
                          active: i == _active,
                          tooltip: _sessions[i].title,
                          onPressed: () => _selectSession(i),
                        ),
                      ),
                  _ToolbarGroup(children: [
                    GhostIconButton(
                      icon: LucideIcons.plus,
                      size: 24,
                      iconSize: 15,
                      tooltip: 'New terminal',
                      onPressed: _addSession,
                    ),
                    GhostIconButton(
                      icon: LucideIcons.trash2,
                      size: 24,
                      iconSize: 14,
                      tooltip: 'Kill terminal',
                      onPressed: _closeSession,
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarGroup extends StatelessWidget {
  final List<Widget> children;
  const _ToolbarGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: context.t3.terminalBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.t3.input),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
