import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';
import '../models/j6_entities.dart';
import '../services/ui_settings.dart';
import 'ui_kit.dart';

/// t3code-style sidebar: brand header, search + actions, active thread cards,
/// the collapsible "Settled" shelf and an icon footer.
class SidebarWidget extends StatefulWidget {
  final List<J6Project> projects;
  final List<J6Thread> threads;
  final List<J6Provider> providers;
  final String? selectedProjectId;
  final String? selectedThreadId;
  final Function(String threadId) onSelectThread;
  final Function(String projectId) onNewThread;
  final Function(String threadId) onSettleThread;
  final Function(String threadId) onUnsettleThread;
  final VoidCallback onOpenFolder;
  final VoidCallback onCollapse;
  final VoidCallback onRefresh;
  final bool isServerConnected;

  const SidebarWidget({
    super.key,
    required this.projects,
    required this.threads,
    required this.providers,
    required this.selectedProjectId,
    required this.selectedThreadId,
    required this.onSelectThread,
    required this.onNewThread,
    required this.onSettleThread,
    required this.onUnsettleThread,
    required this.onOpenFolder,
    required this.onCollapse,
    required this.onRefresh,
    required this.isServerConnected,
  });

  static const double width = 300;

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  // Settled-tail paging, as in t3code: recent history is the common lookup;
  // the deep tail loads in pages.
  static const int _settledTailInitialCount = 10;
  static const int _settledTailPageCount = 25;
  static const String _settledShelfExpandedKey = 'sidebar.settledExpanded';

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';
  // The shelf is collapsed by default: out of the way, never gone.
  bool _settledExpanded = UiSettings.get<bool>(_settledShelfExpandedKey) ?? false;
  int _settledVisibleCount = _settledTailInitialCount;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toggleSettledShelf() {
    setState(() => _settledExpanded = !_settledExpanded);
    UiSettings.set(_settledShelfExpandedKey, _settledExpanded);
  }

  J6Project? _projectFor(String projectId) =>
      widget.projects.where((p) => p.projectId == projectId).firstOrNull;

  String? _providerNameFor(J6Thread t) {
    final raw = t.modelSelectionJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map && parsed['instanceId'] != null) {
        final id = parsed['instanceId'].toString();
        return widget.providers.where((p) => p.id == id).firstOrNull?.displayName ?? id;
      }
    } catch (_) {}
    return null;
  }

  void _handleNewThreadTap(BuildContext buttonContext) {
    if (widget.projects.isEmpty) {
      widget.onOpenFolder();
      return;
    }
    if (widget.projects.length == 1) {
      widget.onNewThread(widget.projects.first.projectId);
      return;
    }
    final box = buttonContext.findRenderObject() as RenderBox;
    final overlay = Overlay.of(buttonContext).context.findRenderObject() as RenderBox;
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset(0, box.size.height + 4), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: buttonContext,
      position: pos,
      color: context.t3.popover,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: context.t3.input),
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text('New thread in…', style: TextStyle(fontSize: 11.5, color: context.t3.sidebarMutedForeground)),
        ),
        ...widget.projects.map((p) => PopupMenuItem<String>(
              value: p.projectId,
              height: 34,
              child: Row(children: [
                ProjectAvatar(name: p.title, size: 18),
                const SizedBox(width: 10),
                Text(p.title, style: TextStyle(fontSize: 13, color: context.t3.sidebarForeground)),
              ]),
            )),
      ],
    ).then((id) {
      if (id != null) widget.onNewThread(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.threads
        : widget.threads.where((t) {
            final proj = _projectFor(t.projectId)?.title.toLowerCase() ?? '';
            return t.title.toLowerCase().contains(q) || proj.contains(q);
          }).toList();

    // Active: newest activity first (already ordered by updated_at).
    final active = filtered.where((t) => !t.isSettled).toList();
    // Settled: most recently wrapped up first (t3code sortSettledThreads).
    final settled = filtered.where((t) => t.isSettled).toList()
      ..sort((a, b) {
        final byTime = b.settledTimestamp.compareTo(a.settledTimestamp);
        return byTime != 0 ? byTime : a.threadId.compareTo(b.threadId);
      });

    // The open thread must never hide under "Show more": a deep settled
    // thread is pulled into the visible tail so its highlight and the
    // un-settle affordance stay reachable.
    final visibleSettled = settled.take(_settledVisibleCount).toList();
    final deepSelected =
        settled.skip(_settledVisibleCount).where((t) => t.threadId == widget.selectedThreadId).firstOrNull;
    if (deepSelected != null) visibleSettled.add(deepSelected);
    final hiddenSettledCount = settled.length - visibleSettled.length;
    // Collapsed shelf: only the open thread (if settled) stays visible.
    final renderedSettled = _settledExpanded
        ? visibleSettled
        : visibleSettled.where((t) => t.threadId == widget.selectedThreadId).toList();

    return Container(
      width: SidebarWidget.width,
      decoration: BoxDecoration(
        color: context.t3.sidebar,
        border: Border(right: BorderSide(color: context.t3.sidebarBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand header
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  GhostIconButton(
                    icon: LucideIcons.panelLeft,
                    tooltip: 'Collapse sidebar',
                    onPressed: widget.onCollapse,
                  ),
                  const SizedBox(width: 12),
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(
                        text: 'J6',
                        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3),
                      ),
                      TextSpan(
                        text: ' Code',
                        style: TextStyle(fontWeight: FontWeight.w500, color: context.t3.sidebarForeground),
                      ),
                    ]),
                    style: TextStyle(fontSize: 15, color: context.t3.sidebarForeground),
                  ),
                ],
              ),
            ),
          ),

          // Search + actions
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _searchFocus.requestFocus(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            Icon(LucideIcons.search, size: 18, color: context.t3.sidebarMutedForeground),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocus,
                                onChanged: (v) => setState(() {
                                  _query = v;
                                  _settledVisibleCount = _settledTailInitialCount;
                                }),
                                style: TextStyle(fontSize: 14, color: context.t3.sidebarForeground),
                                decoration: InputDecoration(
                                  hintText: 'Search',
                                  hintStyle: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: context.t3.sidebarMutedForeground,
                                  ),
                                  isDense: true,
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            if (_query.isNotEmpty)
                              GhostIconButton(
                                icon: LucideIcons.x,
                                size: 20,
                                iconSize: 14,
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                GhostIconButton(
                  icon: LucideIcons.folderPlus,
                  tooltip: 'Add project folder',
                  onPressed: widget.onOpenFolder,
                ),
                const SizedBox(width: 2),
                Builder(
                  builder: (btnCtx) => GhostIconButton(
                    icon: LucideIcons.squarePen,
                    iconSize: 17,
                    tooltip: 'New thread',
                    onPressed: () => _handleNewThreadTap(btnCtx),
                  ),
                ),
              ],
            ),
          ),

          // Thread list
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(hasQuery: q.isNotEmpty, onOpenFolder: widget.onOpenFolder)
                : CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                        sliver: SliverList.list(children: [
                          if (active.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              child: Text(
                                'No active threads',
                                style: TextStyle(fontSize: 12.5, color: context.t3.sidebarMutedForeground),
                              ),
                            ),
                          ...active.map((t) => _RecentThreadCard(
                                key: ValueKey('active-${t.threadId}'),
                                thread: t,
                                project: _projectFor(t.projectId),
                                providerName: _providerNameFor(t),
                                selected: t.threadId == widget.selectedThreadId,
                                onTap: () => widget.onSelectThread(t.threadId),
                                onSettle: () => widget.onSettleThread(t.threadId),
                              )),
                        ]),
                      ),
                      // The shelf sits at the bottom of the list (t3code `mt-auto`).
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (settled.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                _SectionHeader(
                                  label: _settledExpanded ? 'Settled' : 'Settled (${settled.length})',
                                  expanded: _settledExpanded,
                                  onToggle: _toggleSettledShelf,
                                ),
                                const SizedBox(height: 4),
                                ...renderedSettled.map((t) => _SettledThreadRow(
                                      key: ValueKey('settled-${t.threadId}'),
                                      thread: t,
                                      project: _projectFor(t.projectId),
                                      selected: t.threadId == widget.selectedThreadId,
                                      onTap: () => widget.onSelectThread(t.threadId),
                                      onUnsettle: () => widget.onUnsettleThread(t.threadId),
                                    )),
                                if (_settledExpanded && hiddenSettledCount > 0)
                                  _SidebarRowButton(
                                    icon: LucideIcons.plus,
                                    label: 'Show ${math.min(hiddenSettledCount, _settledTailPageCount)} more',
                                    onTap: () => setState(() => _settledVisibleCount += _settledTailPageCount),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),

          // Footer
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Row(
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: AppTheme.mode,
                  builder: (context, mode, _) => MenuAnchor(
                    alignmentOffset: const Offset(0, -4),
                    menuChildren: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                        child: Text('Appearance',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.t3.mutedForeground)),
                      ),
                      for (final (m, label, icon) in const [
                        (ThemeMode.system, 'System', LucideIcons.monitor),
                        (ThemeMode.light, 'Light', LucideIcons.sun),
                        (ThemeMode.dark, 'Dark', LucideIcons.moon),
                      ])
                        MenuItemButton(
                          style: ButtonStyle(
                            minimumSize: const WidgetStatePropertyAll(Size(180, 32)),
                            overlayColor: WidgetStatePropertyAll(context.t3.accent),
                          ),
                          leadingIcon: Icon(icon, size: 15, color: context.t3.mutedForeground),
                          trailingIcon:
                              mode == m ? Icon(LucideIcons.check, size: 15, color: context.t3.foreground) : null,
                          onPressed: () => AppTheme.setMode(m),
                          child: Text(label, style: TextStyle(fontSize: 13, color: context.t3.foreground)),
                        ),
                    ],
                    builder: (context, controller, _) => GhostIconButton(
                      icon: LucideIcons.settings,
                      tooltip: 'Settings',
                      onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: widget.isServerConnected ? 'Local engine running' : 'Standalone mode',
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.isServerConnected ? context.t3.success : context.t3.sidebarIcon,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                GhostIconButton(
                  icon: LucideIcons.refreshCw,
                  tooltip: 'Refresh',
                  onPressed: widget.onRefresh,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentThreadCard extends StatefulWidget {
  final J6Thread thread;
  final J6Project? project;
  final String? providerName;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSettle;

  const _RecentThreadCard({
    super.key,
    required this.thread,
    required this.project,
    required this.providerName,
    required this.selected,
    required this.onTap,
    required this.onSettle,
  });

  @override
  State<_RecentThreadCard> createState() => _RecentThreadCardState();
}

class _RecentThreadCardState extends State<_RecentThreadCard> {
  bool _hover = false;

  Widget _buildTrailing(BuildContext context) {
    final thread = widget.thread;
    if (thread.isRunning) {
      // A turn in flight can't be settled (t3code refuses as well).
      return Tooltip(
        message: "Running threads can't be settled",
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: context.t3.sidebarMutedForeground),
          ),
          const SizedBox(width: 6),
          Text('Working', style: TextStyle(fontSize: 12.5, color: context.t3.sidebarMutedForeground)),
        ]),
      );
    }
    if (_hover) {
      return Tooltip(
        message: 'Settle thread',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: widget.onSettle,
            borderRadius: BorderRadius.circular(6),
            hoverColor: context.t3.sidebarAccent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.check, size: 13, color: context.t3.sidebarForeground),
                const SizedBox(width: 4),
                Text('Settle', style: TextStyle(fontSize: 12.5, color: context.t3.sidebarForeground)),
              ]),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        relativeTime(thread.updatedAt),
        style: TextStyle(fontSize: 12.5, color: context.t3.sidebarMutedForeground),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final project = widget.project;
    final providerName = widget.providerName;
    final projectName = project?.title ?? 'Project';
    final root = project?.workspaceRoot ?? '';
    final folder = root.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).lastOrNull;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: widget.selected ? context.t3.sidebarRowSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: context.t3.sidebarRowHover,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ProjectAvatar(name: projectName, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        projectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: context.t3.sidebarForeground),
                      ),
                    ),
                    SizedBox(height: 22, child: Center(child: _buildTrailing(context))),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  thread.title.isNotEmpty ? thread.title : 'Untitled thread',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: context.t3.sidebarForeground,
                  ),
                ),
                if (folder != null || providerName != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (folder != null) ...[
                        Icon(
                          project?.isGitRepo == true ? LucideIcons.gitBranch : LucideIcons.folder,
                          size: 13,
                          color: context.t3.sidebarIcon,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            folder,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: context.t3.sidebarIcon),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      if (providerName != null)
                        Tooltip(
                          message: providerName,
                          child: Text(
                            providerName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.t3.sidebarMutedForeground,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _SettledThreadRow extends StatefulWidget {
  final J6Thread thread;
  final J6Project? project;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onUnsettle;

  const _SettledThreadRow({
    super.key,
    required this.thread,
    required this.project,
    required this.selected,
    required this.onTap,
    required this.onUnsettle,
  });

  @override
  State<_SettledThreadRow> createState() => _SettledThreadRowState();
}

class _SettledThreadRowState extends State<_SettledThreadRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: selected ? context.t3.sidebarRowSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: context.t3.sidebarRowHover,
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 6),
              child: Row(
                children: [
                  // Favicon is dimmed at rest and restored on hover/selection.
                  ProjectAvatar(name: widget.project?.title ?? '?', size: 18, muted: !(selected || _hover)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      thread.title.isNotEmpty ? thread.title : 'Untitled thread',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: selected || _hover ? context.t3.sidebarForeground : context.t3.sidebarMutedForeground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 24,
                    child: Center(
                      child: _hover
                          ? GhostIconButton(
                              icon: LucideIcons.undo2,
                              size: 24,
                              iconSize: 15,
                              tooltip: 'Un-settle thread',
                              color: context.t3.sidebarMutedForeground,
                              onPressed: widget.onUnsettle,
                            )
                          : Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Tooltip(
                                message: relativeTime(thread.settledTimestamp) == 'now'
                                    ? 'Settled just now'
                                    : 'Settled ${relativeTime(thread.settledTimestamp)} ago',
                                child: Text(
                                  relativeTime(thread.settledTimestamp),
                                  style: TextStyle(fontSize: 12.5, color: context.t3.sidebarIcon),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final bool expanded;
  final VoidCallback onToggle;

  const _SectionHeader({required this.label, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      hoverColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.t3.sidebarMutedForeground,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: context.t3.sidebarBorder)),
            const SizedBox(width: 8),
            Icon(
              expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 16,
              color: context.t3.sidebarMutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarRowButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SidebarRowButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: context.t3.sidebarRowHover,
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              SizedBox(width: 18, child: Icon(icon, size: 18, color: context.t3.sidebarMutedForeground)),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(fontSize: 14, color: context.t3.sidebarMutedForeground)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasQuery;
  final VoidCallback onOpenFolder;

  const _EmptyState({required this.hasQuery, required this.onOpenFolder});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            hasQuery ? 'No matching threads' : 'No threads yet',
            style: TextStyle(fontSize: 13, color: context.t3.sidebarMutedForeground),
          ),
          if (!hasQuery) ...[
            const SizedBox(height: 10),
            OutlineButtonSmall(
              icon: LucideIcons.folderPlus,
              label: 'Add a project',
              onTap: onOpenFolder,
            ),
          ],
        ],
      ),
    );
  }
}
