import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

enum _Surface { none, files }

class _SurfaceDef {
  final String label;
  final IconData icon;
  final String key;
  final bool enabled;
  const _SurfaceDef(this.label, this.icon, this.key, {this.enabled = true});
}

/// Right-hand panel modelled on t3code's "Open a surface" launcher.
class RightPanel extends StatefulWidget {
  final String workspaceRoot;
  final VoidCallback onOpenTerminal;
  final VoidCallback onClose;

  const RightPanel({
    super.key,
    required this.workspaceRoot,
    required this.onOpenTerminal,
    required this.onClose,
  });

  static const double width = 420;

  @override
  State<RightPanel> createState() => _RightPanelState();
}

class _RightPanelState extends State<RightPanel> {
  _Surface _surface = _Surface.none;
  final FocusNode _focus = FocusNode();

  static const _surfaces = <_SurfaceDef>[
    _SurfaceDef('Browser', LucideIcons.globe, 'B', enabled: false),
    _SurfaceDef('Terminal', LucideIcons.terminal, 'T'),
    _SurfaceDef('Files', LucideIcons.files, 'F'),
    _SurfaceDef('Diff', LucideIcons.gitCompare, 'D', enabled: false),
    _SurfaceDef('Pull request', LucideIcons.gitPullRequest, 'P', enabled: false),
    _SurfaceDef('Linked pull requests', LucideIcons.link, 'L', enabled: false),
    _SurfaceDef('Agents', LucideIcons.bot, 'A', enabled: false),
    _SurfaceDef('Device', LucideIcons.smartphone, 'M', enabled: false),
  ];

  @override
  void didUpdateWidget(covariant RightPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceRoot != widget.workspaceRoot && _surface == _Surface.files) {
      setState(() {}); // tree re-keys on root
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _open(_SurfaceDef s) {
    if (!s.enabled) return;
    switch (s.key) {
      case 'T':
        widget.onOpenTerminal();
        break;
      case 'F':
        setState(() => _surface = _Surface.files);
        break;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || _surface != _Surface.none) return KeyEventResult.ignored;
    final label = e.logicalKey.keyLabel.toUpperCase();
    final match = _surfaces.where((s) => s.key == label).firstOrNull;
    if (match != null && match.enabled) {
      _open(match);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: () => _focus.requestFocus(),
        behavior: HitTestBehavior.translucent,
        child: Container(
          width: RightPanel.width,
          decoration: BoxDecoration(
            color: context.t3.background,
            border: Border(left: BorderSide(color: context.t3.border)),
          ),
          child: _surface == _Surface.files ? _buildFiles() : _buildLauncher(),
        ),
      ),
    );
  }

  Widget _buildLauncher() {
    return Center(
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                'Open a surface',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: context.t3.foreground),
              ),
            ),
            const SizedBox(height: 14),
            for (final s in _surfaces)
              Tooltip(
                message: s.enabled ? 'Open ${s.label}' : 'Coming soon',
                child: InkWell(
                  onTap: s.enabled ? () => _open(s) : null,
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: context.t3.accent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: Row(
                      children: [
                        Icon(s.icon, size: 17, color: s.enabled ? context.t3.foreground : context.t3.faint),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            s.label,
                            style: TextStyle(
                              fontSize: 14,
                              color: s.enabled ? context.t3.foreground : context.t3.faint,
                            ),
                          ),
                        ),
                        KbdBadge(s.key),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiles() {
    final root = widget.workspaceRoot;
    final name = root.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'Files';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                GhostIconButton(
                  icon: LucideIcons.arrowLeft,
                  iconSize: 16,
                  tooltip: 'Back',
                  onPressed: () => setState(() => _surface = _Surface.none),
                ),
                const SizedBox(width: 8),
                Icon(LucideIcons.files, size: 15, color: context.t3.mutedForeground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.t3.foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(),
        Expanded(
          child: root.isEmpty || !Directory(root).existsSync()
              ? Center(
                  child: Text('No workspace folder', style: TextStyle(fontSize: 13, color: context.t3.mutedForeground)),
                )
              : ListView(
                  key: ValueKey(root),
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                  children: [_DirChildren(path: root, depth: 0)],
                ),
        ),
      ],
    );
  }
}

const _ignoredDirs = {'.git', 'node_modules', '.dart_tool', 'build', '.idea', '.gradle', '__pycache__', '.venv'};

class _DirChildren extends StatelessWidget {
  final String path;
  final int depth;
  const _DirChildren({required this.path, required this.depth});

  @override
  Widget build(BuildContext context) {
    List<FileSystemEntity> entries;
    try {
      entries = Directory(path).listSync(followLinks: false)
        ..removeWhere((e) => e is Directory && _ignoredDirs.contains(_basename(e.path)))
        ..sort((a, b) {
          final ad = a is Directory ? 0 : 1;
          final bd = b is Directory ? 0 : 1;
          if (ad != bd) return ad - bd;
          return _basename(a.path).toLowerCase().compareTo(_basename(b.path).toLowerCase());
        });
    } catch (_) {
      entries = [];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final e in entries) _FileNode(entity: e, depth: depth)],
    );
  }
}

String _basename(String p) => p.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).last;

class _FileNode extends StatefulWidget {
  final FileSystemEntity entity;
  final int depth;
  const _FileNode({required this.entity, required this.depth});

  @override
  State<_FileNode> createState() => _FileNodeState();
}

class _FileNodeState extends State<_FileNode> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final isDir = widget.entity is Directory;
    final name = _basename(widget.entity.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: isDir
              ? () => setState(() => _open = !_open)
              : () => Clipboard.setData(ClipboardData(text: widget.entity.path)),
          borderRadius: BorderRadius.circular(6),
          hoverColor: context.t3.accent,
          child: Padding(
            padding: EdgeInsets.only(left: 6.0 + widget.depth * 14, top: 4, bottom: 4, right: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  child: isDir
                      ? Icon(
                          _open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                          size: 15,
                          color: context.t3.mutedForeground,
                        )
                      : null,
                ),
                const SizedBox(width: 4),
                Icon(
                  isDir ? (_open ? LucideIcons.folderOpen : LucideIcons.folder) : LucideIcons.file,
                  size: 15,
                  color: context.t3.mutedForeground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.monoFont,
                      fontFamilyFallback: AppTheme.monoFallback,
                      fontSize: 12.5,
                      color: isDir ? context.t3.foregroundSubtle : context.t3.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isDir && _open) _DirChildren(path: widget.entity.path, depth: widget.depth + 1),
      ],
    );
  }
}
