import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'theme/app_theme.dart';
import 'models/j6_entities.dart';
import 'services/j6_server_service.dart';
import 'services/j6_logger.dart';
import 'services/ui_settings.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'widgets/sidebar_widget.dart';
import 'widgets/message_item_widget.dart';
import 'widgets/activity_item_widget.dart';
import 'widgets/composer_widget.dart';
import 'widgets/terminal_drawer.dart';
import 'widgets/right_panel.dart';
import 'widgets/ui_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  J6Logger.init();
  J6Logger.info('Starting j6code application...');
  runApp(const ProviderScope(child: J6CodeApp()));
}

class J6CodeApp extends StatelessWidget {
  const J6CodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.mode,
      builder: (context, mode, _) => MaterialApp(
        title: 'j6code',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: mode,
        home: const MainScreen(),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _ToggleSidebarIntent extends Intent {
  const _ToggleSidebarIntent();
}

class _ToggleTerminalIntent extends Intent {
  const _ToggleTerminalIntent();
}

class _ToggleRightPanelIntent extends Intent {
  const _ToggleRightPanelIntent();
}

class _MainScreenState extends State<MainScreen> {
  /// Matches t3code's --chat-content-max-width (46rem).
  static const double _chatMaxWidth = 736;

  final J6ServerService _serverService = J6ServerService();

  List<J6Project> _projects = [];
  List<J6Thread> _threads = [];
  List<J6Message> _messages = [];
  List<J6Activity> _activities = [];
  List<J6Provider> _providers = [];

  String? _selectedProjectId;
  String? _selectedThreadId;
  J6Provider? _selectedProvider;
  J6Model? _selectedModel;

  static const String _runtimeModeKey = 'composer.runtimeMode';
  RuntimeMode _runtimeMode = RuntimeMode.fromId(UiSettings.get<String>(_runtimeModeKey));
  final GlobalKey<ComposerWidgetState> _composerKey = GlobalKey<ComposerWidgetState>();

  bool _isServerConnected = false;
  bool _isSending = false;
  Timer? _refreshTimer;
  final ScrollController _scrollController = ScrollController();

  // Layout state
  bool _sidebarOpen = true;
  bool _rightPanelOpen = false;
  bool _terminalOpen = false;
  bool _showScrollToEnd = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initServices();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final away = pos.maxScrollExtent - pos.pixels > 240;
    if (away != _showScrollToEnd) setState(() => _showScrollToEnd = away);
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels < 120;
  }

  Future<void> _initServices() async {
    J6Logger.info('Initializing services and connecting to backend...');
    await _serverService.connect();
    setState(() => _isServerConnected = _serverService.isConnected);

    _serverService.onConnectionStateChanged.listen((connected) {
      J6Logger.info('WebSocket connection state changed: $connected');
      if (mounted) setState(() => _isServerConnected = connected);
    });

    // Load available engines & models (Antigravity, Grok, OpenCode, Claude, etc.)
    final providers = await _serverService.loadAvailableProviders();
    J6Provider? defaultProvider;
    J6Model? defaultModel;

    if (providers.isNotEmpty) {
      defaultProvider = providers.firstWhere(
        (p) => p.id == 'antigravity' || p.id == 'grok',
        orElse: () => providers.first,
      );
      if (defaultProvider.models.isNotEmpty) {
        defaultModel = defaultProvider.models.firstWhere(
          (m) => m.name.contains('Flash') || m.name.contains('High') || m.name.contains('Build'),
          orElse: () => defaultProvider!.models.first,
        );
      }
    }

    if (mounted) {
      setState(() {
        _providers = providers;
        _selectedProvider = defaultProvider;
        _selectedModel = defaultModel;
      });
    }

    await _loadInitialData();

    // Polling timer to keep live transcript updated with real-time activities
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _pollUpdates();
    });
  }

  Future<void> _loadInitialData() async {
    final projects = await _serverService.fetchProjects();
    // The sidebar lists threads across all projects, like t3code.
    final threads = await _serverService.fetchThreads(null);

    String? currentThreadId = _selectedThreadId;
    if ((currentThreadId == null || !threads.any((t) => t.threadId == currentThreadId)) && threads.isNotEmpty) {
      currentThreadId = threads.first.threadId;
    }
    final currentThread = threads.where((t) => t.threadId == currentThreadId).firstOrNull;
    final String? currentProjectId =
        currentThread?.projectId ?? _selectedProjectId ?? (projects.isNotEmpty ? projects.first.projectId : null);

    List<J6Message> messages = [];
    List<J6Activity> activities = [];
    if (currentThreadId != null) {
      messages = await _serverService.fetchThreadMessages(currentThreadId);
      activities = await _serverService.fetchThreadActivities(currentThreadId);
    }

    J6Logger.info(
        'Loaded initial data: ${projects.length} projects, ${threads.length} threads, ${messages.length} messages');

    if (mounted) {
      setState(() {
        _projects = projects;
        _threads = threads;
        _selectedProjectId = currentProjectId;
        _selectedThreadId = currentThreadId;
        if (currentThread != null) _runtimeMode = currentThread.runtimeMode;
        _messages = messages;
        _activities = activities;
      });
      _alignModelWithThread(currentThread);
      _scrollToBottom(animate: false);
    }
  }

  Future<void> _refreshAll() async {
    final projects = await _serverService.fetchProjects();
    if (mounted) setState(() => _projects = projects);
    await _pollUpdates();
  }

  Future<void> _pollUpdates() async {
    final threads = await _serverService.fetchThreads(null);
    List<J6Message>? messages;
    List<J6Activity>? activities;
    final threadId = _selectedThreadId;
    if (threadId != null) {
      messages = await _serverService.fetchThreadMessages(threadId);
      activities = await _serverService.fetchThreadActivities(threadId);
    }
    if (!mounted) return;
    final stick = _isNearBottom;
    final grew = messages != null &&
        (messages.length != _messages.length ||
            activities!.length != _activities.length ||
            (messages.isNotEmpty && _messages.isNotEmpty && messages.last.text.length != _messages.last.text.length));
    setState(() {
      _threads = threads;
      // Ignore stale results if the user switched threads mid-request.
      if (threadId != null && threadId == _selectedThreadId) {
        _messages = messages!;
        _activities = activities!;
      }
    });
    if (grew && stick) _scrollToBottom();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _alignModelWithThread(J6Thread? th) {
    if (th?.modelSelectionJson == null) return;
    try {
      final parsed = jsonDecode(th!.modelSelectionJson!);
      if (parsed is Map && parsed['instanceId'] != null) {
        final inst = parsed['instanceId'].toString();
        final mod = parsed['model']?.toString();
        final matchingProvider = _providers.where((p) => p.id == inst).firstOrNull;
        if (matchingProvider != null) {
          setState(() {
            _selectedProvider = matchingProvider;
            final matchingModel = matchingProvider.models.where((m) => m.slug == mod).firstOrNull;
            if (matchingModel != null) _selectedModel = matchingModel;
          });
        }
      }
    } catch (_) {}
  }

  void _selectThread(String threadId) async {
    J6Logger.info('Selected thread: $threadId');

    // Auto-align model selection with thread's existing driver if bound
    final th = _threads.where((t) => t.threadId == threadId).firstOrNull;
    _alignModelWithThread(th);

    setState(() {
      _selectedThreadId = threadId;
      if (th != null) {
        _selectedProjectId = th.projectId;
        _runtimeMode = th.runtimeMode;
      }
      _messages = [];
      _activities = [];
    });
    final messages = await _serverService.fetchThreadMessages(threadId);
    final activities = await _serverService.fetchThreadActivities(threadId);
    if (mounted && _selectedThreadId == threadId) {
      setState(() {
        _messages = messages;
        _activities = activities;
      });
      _scrollToBottom(animate: false);
    }
  }

  /// Starts a draft thread in [projectId]; the thread row is created on the
  /// first prompt (see [_handleSendPrompt]).
  void _handleNewThread(String projectId) {
    J6Logger.info('Starting draft thread for project $projectId');
    setState(() {
      _selectedProjectId = projectId;
      _selectedThreadId = null;
      _runtimeMode = RuntimeMode.fromId(UiSettings.get<String>(_runtimeModeKey));
      _messages = [];
      _activities = [];
    });
  }

  Future<void> _handleOpenFolder() async {
    J6Logger.info('Opening folder picker dialog...');
    final selectedDirectory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Git Repository / Workspace Folder',
    );

    if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
      J6Logger.info('User selected directory: $selectedDirectory');
      final project = await _serverService.openFolderAsProject(selectedDirectory);
      if (project != null) {
        final projects = await _serverService.fetchProjects();
        setState(() => _projects = projects);
        _handleNewThread(project.projectId);
      }
    }
  }

  Future<void> _openInExplorer(String path) async {
    if (path.isEmpty) return;
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [path]);
      } else {
        await Process.start('xdg-open', [path]);
      }
    } catch (e, st) {
      J6Logger.error('Failed to open folder', e, st);
    }
  }

  Future<void> _handleSendPrompt(
    String prompt,
    List<J6Attachment> attachments, {
    RuntimeMode? runtimeModeOverride,
  }) async {
    if (prompt.isEmpty && attachments.isEmpty) return;

    String? projectId = _selectedProjectId;
    if (projectId == null) {
      if (_projects.isNotEmpty) {
        projectId = _projects.first.projectId;
      } else {
        final newProj = await _serverService.openFolderAsProject(Platform.environment['USERPROFILE'] ?? 'C:\\\\');
        projectId = newProj?.projectId ?? 'proj_default';
      }
      setState(() => _selectedProjectId = projectId);
    }

    setState(() => _isSending = true);

    String threadId = _selectedThreadId ?? '';
    final providerId = _selectedProvider?.id ?? 'antigravity';
    final modelSlug = _selectedModel?.slug ?? 'gemini-3.8-flash-high';

    if (threadId.isEmpty) {
      final titleSource = prompt.isNotEmpty ? prompt : attachments.map((a) => a.name).join(', ');
      final title = titleSource.length > 35 ? '${titleSource.substring(0, 35)}...' : titleSource;
      final created = await _serverService.createThread(
        projectId: projectId,
        title: title,
        providerId: providerId,
        modelSlug: modelSlug,
        runtimeMode: _runtimeMode,
      );
      threadId = created ?? 'th_${DateTime.now().millisecondsSinceEpoch}';
      setState(() => _selectedThreadId = threadId);
    }

    // Immediately show the user's message locally so it never vanishes
    final optimisticMsg = J6Message(
      messageId: 'opt_${DateTime.now().millisecondsSinceEpoch}',
      threadId: threadId,
      role: 'user',
      text: prompt,
      isStreaming: false,
      createdAt: DateTime.now(),
      attachments: attachments,
    );

    setState(() {
      _messages = [..._messages, optimisticMsg];
    });
    _scrollToBottom();

    final mode = runtimeModeOverride ?? _runtimeMode;
    J6Logger.info('Sending prompt to $providerId ($modelSlug, ${mode.id}, ${attachments.length} attachments) '
        'in thread $threadId: ${prompt.replaceAll('\n', ' ')}');

    await _serverService.sendPrompt(
      threadId: threadId,
      projectId: projectId,
      prompt: prompt,
      providerId: providerId,
      modelSlug: modelSlug,
      runtimeMode: mode,
      attachments: attachments,
    );

    setState(() => _isSending = false);

    await _pollUpdates();
    _scrollToBottom();
  }

  /// Composer access selector: remembered as the default for new threads and
  /// stored on the open thread (t3code keeps runtimeMode per thread).
  void _handleRuntimeModeChanged(RuntimeMode mode) {
    setState(() => _runtimeMode = mode);
    UiSettings.set(_runtimeModeKey, mode.id);
    final threadId = _selectedThreadId;
    if (threadId != null) _serverService.setThreadRuntimeMode(threadId, mode);
  }

  /// Headless agents can't pause for approval, so a denied action is
  /// approved by re-running the turn once with full access.
  void _approveDeniedActions(List<String> actions) {
    _handleSendPrompt(
      'Approved: you may now perform the action(s) that were denied (${actions.join(', ')}). Continue where you left off.',
      const [],
      runtimeModeOverride: RuntimeMode.fullAccess,
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _serverService.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? _unsettlingThreadId;

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, width: 360));
  }

  /// Moves a thread to the Settled shelf (t3code "Settle thread").
  Future<void> _handleSettleThread(String threadId) async {
    final ok = await _serverService.settleThread(threadId);
    if (!ok) _showToast("Can't settle while the agent is working");
    await _pollUpdates();
  }

  /// Pins a settled thread back to active (t3code "Un-settle thread").
  Future<void> _handleUnsettleThread(String threadId) async {
    setState(() => _unsettlingThreadId = threadId);
    try {
      final ok = await _serverService.unsettleThread(threadId);
      if (!ok) _showToast("Couldn't un-settle thread");
      await _pollUpdates();
    } finally {
      if (mounted) setState(() => _unsettlingThreadId = null);
    }
  }

  /// Groups consecutive activities into single collapsible cards
  List<dynamic> _buildGroupedTimeline(List<J6Message> messages, List<J6Activity> activities) {
    final List<dynamic> rawItems = [...messages, ...activities];
    rawItems.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final List<dynamic> grouped = [];
    List<J6Activity> currentActivityGroup = [];
    String? currentGroupType;

    for (final item in rawItems) {
      if (item is J6Message) {
        if (currentActivityGroup.isNotEmpty) {
          grouped.add(ActivityGroupWidget(
            groupType: currentGroupType ?? 'other',
            activities: List.from(currentActivityGroup),
          ));
          currentActivityGroup.clear();
          currentGroupType = null;
        }
        grouped.add(item);
      } else if (item is J6Activity && item.kind == 'approval.denied') {
        if (currentActivityGroup.isNotEmpty) {
          grouped.add(ActivityGroupWidget(
            groupType: currentGroupType ?? 'other',
            activities: List.from(currentActivityGroup),
          ));
          currentActivityGroup = [];
          currentGroupType = null;
        }
        final actions = (item.payload['deniedActions'] as List?)?.map((e) => e.toString()).toList() ?? const [];
        grouped.add(_ApprovalCard(
          key: ValueKey(item.activityId),
          actions: actions,
          // Only the newest request is actionable; older ones are history.
          actionable: identical(item, rawItems.last) && !_isSending,
          onApprove: () => _approveDeniedActions(actions),
          onAlwaysAllow: () {
            _handleRuntimeModeChanged(RuntimeMode.fullAccess);
            _approveDeniedActions(actions);
          },
        ));
      } else if (item is J6Activity) {
        final kind = ToolActivityHelper.classifyKind(item);
        if (currentActivityGroup.isEmpty) {
          currentActivityGroup.add(item);
          currentGroupType = kind;
        } else if (currentGroupType == kind) {
          currentActivityGroup.add(item);
        } else {
          grouped.add(ActivityGroupWidget(
            groupType: currentGroupType ?? 'other',
            activities: List.from(currentActivityGroup),
          ));
          currentActivityGroup = [item];
          currentGroupType = kind;
        }
      }
    }

    if (currentActivityGroup.isNotEmpty) {
      grouped.add(ActivityGroupWidget(
        groupType: currentGroupType ?? 'other',
        activities: List.from(currentActivityGroup),
      ));
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final timelineItems = _buildGroupedTimeline(_messages, _activities);

    final currentThread = _threads.where((t) => t.threadId == _selectedThreadId).firstOrNull;
    final currentProject = _projects.firstWhere(
      (p) => p.projectId == _selectedProjectId,
      orElse: () => J6Project(
        projectId: '',
        title: 'j6code',
        workspaceRoot: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyB, control: true): _ToggleSidebarIntent(),
        SingleActivator(LogicalKeyboardKey.keyJ, control: true): _ToggleTerminalIntent(),
        SingleActivator(LogicalKeyboardKey.keyB, control: true, alt: true): _ToggleRightPanelIntent(),
      },
      child: Actions(
        actions: {
          _ToggleSidebarIntent: CallbackAction<_ToggleSidebarIntent>(
            onInvoke: (_) => setState(() => _sidebarOpen = !_sidebarOpen),
          ),
          _ToggleTerminalIntent: CallbackAction<_ToggleTerminalIntent>(
            onInvoke: (_) => setState(() => _terminalOpen = !_terminalOpen),
          ),
          _ToggleRightPanelIntent: CallbackAction<_ToggleRightPanelIntent>(
            onInvoke: (_) => setState(() => _rightPanelOpen = !_rightPanelOpen),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Row(
              children: [
                if (_sidebarOpen)
                  SidebarWidget(
                    projects: _projects,
                    threads: _threads,
                    providers: _providers,
                    selectedProjectId: _selectedProjectId,
                    selectedThreadId: _selectedThreadId,
                    isServerConnected: _isServerConnected,
                    onSelectThread: _selectThread,
                    onNewThread: _handleNewThread,
                    onSettleThread: _handleSettleThread,
                    onUnsettleThread: _handleUnsettleThread,
                    onOpenFolder: _handleOpenFolder,
                    onCollapse: () => setState(() => _sidebarOpen = false),
                    onRefresh: _refreshAll,
                  ),
                Expanded(
                  child: Column(
                    children: [
                      _buildHeader(currentProject, currentThread),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(child: _buildTimeline(timelineItems, currentProject)),
                                  if (currentThread != null && currentThread.isSettled)
                                    _SettledThreadBanner(
                                      maxWidth: _chatMaxWidth + 32,
                                      pending: _unsettlingThreadId == currentThread.threadId,
                                      onUnsettle: () => _handleUnsettleThread(currentThread.threadId),
                                    ),
                                  ComposerWidget(
                                    key: _composerKey,
                                    runtimeMode: _runtimeMode,
                                    onRuntimeModeChanged: _handleRuntimeModeChanged,
                                    providers: _providers,
                                    selectedProvider: _selectedProvider,
                                    selectedModel: _selectedModel,
                                    onSelectModel: (p, m) {
                                      setState(() {
                                        _selectedProvider = p;
                                        _selectedModel = m;
                                      });
                                    },
                                    onSendPrompt: _handleSendPrompt,
                                    isSending: _isSending,
                                    activeWorkspaceName: currentProject.title,
                                    isGitRepo: currentProject.isGitRepo,
                                    maxWidth: _chatMaxWidth + 32,
                                  ),
                                  if (_terminalOpen)
                                    TerminalDrawer(
                                      key: ValueKey('term_${currentProject.projectId}'),
                                      workingDirectory: currentProject.workspaceRoot,
                                      onClose: () => setState(() => _terminalOpen = false),
                                      onAddToChat: (text) =>
                                          _composerKey.currentState?.insertText('```\n${text.trimRight()}\n```\n'),
                                    ),
                                ],
                              ),
                            ),
                            if (_rightPanelOpen)
                              RightPanel(
                                workspaceRoot: currentProject.workspaceRoot,
                                onOpenTerminal: () => setState(() => _terminalOpen = true),
                                onClose: () => setState(() => _rightPanelOpen = false),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(J6Project project, J6Thread? thread) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.t3.background,
        border: Border(bottom: BorderSide(color: context.t3.border)),
      ),
      child: Row(
        children: [
          if (!_sidebarOpen) ...[
            GhostIconButton(
              icon: LucideIcons.panelLeft,
              tooltip: 'Expand sidebar (Ctrl+B)',
              onPressed: () => setState(() => _sidebarOpen = true),
            ),
            const SizedBox(width: 10),
          ],
          ProjectAvatar(name: project.title, size: 18),
          const SizedBox(width: 8),
          Text(project.title, style: TextStyle(fontSize: 13.5, color: context.t3.foregroundSubtle)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('/', style: TextStyle(fontSize: 13.5, color: context.t3.faint)),
          ),
          Expanded(
            child: Text(
              thread?.title ?? 'New thread',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: thread == null ? context.t3.mutedForeground : context.t3.foreground,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (project.workspaceRoot.isNotEmpty) ...[
            Tooltip(
              message: project.workspaceRoot,
              child: OutlineButtonSmall(
                icon: LucideIcons.folderOpen,
                label: 'Open',
                onTap: () => _openInExplorer(project.workspaceRoot),
              ),
            ),
            const SizedBox(width: 12),
          ],
          GhostIconButton(
            icon: LucideIcons.squareTerminal,
            tooltip: 'Toggle terminal (Ctrl+J)',
            active: _terminalOpen,
            onPressed: () => setState(() => _terminalOpen = !_terminalOpen),
          ),
          const SizedBox(width: 4),
          GhostIconButton(
            icon: LucideIcons.columns2,
            tooltip: 'Toggle panel (Ctrl+Alt+B)',
            active: _rightPanelOpen,
            onPressed: () => setState(() => _rightPanelOpen = !_rightPanelOpen),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(List<dynamic> items, J6Project project) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProjectAvatar(name: project.title, size: 40),
              const SizedBox(height: 18),
              Text(
                'What should we build in ${project.title}?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: context.t3.foreground),
              ),
              const SizedBox(height: 8),
              Text(
                _selectedModel != null
                    ? '${_selectedProvider?.displayName ?? ''} · ${_selectedModel!.name}'
                    : 'Pick a model below and start a thread.',
                style: TextStyle(fontSize: 13, color: context.t3.mutedForeground),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              Widget child;
              if (item is J6Message) {
                child = MessageItemWidget(message: item);
              } else if (item is Widget) {
                child = item;
              } else if (item is J6Activity) {
                child = ActivityItemWidget(activity: item);
              } else {
                child = const SizedBox.shrink();
              }
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _chatMaxWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: child,
                  ),
                ),
              );
            },
          ),
        ),
        if (_showScrollToEnd)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                color: context.t3.popover,
                shape: StadiumBorder(side: BorderSide(color: context.t3.input)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => _scrollToBottom(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.chevronDown, size: 16, color: context.t3.foreground),
                        const SizedBox(width: 4),
                        Text(
                          'Scroll to end',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.t3.foreground),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Info banner shown above the composer while viewing a settled thread
/// (t3code ChatComposer "This thread is settled").
class _SettledThreadBanner extends StatelessWidget {
  final double maxWidth;
  final bool pending;
  final VoidCallback onUnsettle;

  const _SettledThreadBanner({required this.maxWidth, required this.pending, required this.onUnsettle});

  @override
  Widget build(BuildContext context) {
    final t3 = context.t3;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: t3.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t3.border),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.circleCheck, size: 16, color: t3.mutedForeground),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'This thread is settled',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t3.foreground),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Send a message to unsettle',
                        style: TextStyle(fontSize: 12, color: t3.mutedForeground),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GhostChip(
                  icon: LucideIcons.undo2,
                  label: pending ? 'Un-settling...' : 'Un-settle',
                  color: t3.foreground,
                  onTap: pending ? null : onUnsettle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when a Supervised / Auto-accept-edits run had an action declined.
/// Headless CLIs can't pause mid-turn for approval, so approving re-runs the
/// turn once with full access (or switches the thread to Full access).
class _ApprovalCard extends StatelessWidget {
  final List<String> actions;
  final bool actionable;
  final VoidCallback onApprove;
  final VoidCallback onAlwaysAllow;

  const _ApprovalCard({
    super.key,
    required this.actions,
    required this.actionable,
    required this.onApprove,
    required this.onAlwaysAllow,
  });

  @override
  Widget build(BuildContext context) {
    final t3 = context.t3;
    final what = actions.isEmpty ? 'an action' : actions.join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(t3.warning.withAlpha(actionable ? 18 : 8), t3.card),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t3.warning.withAlpha(actionable ? 90 : 40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(LucideIcons.shieldAlert, size: 15, color: t3.warning),
              const SizedBox(width: 8),
              Text(
                actionable ? 'Approval needed' : 'Approval requested',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t3.foreground),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'The agent asked to run $what. The current access mode requires approval, so it was declined.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: t3.mutedForeground),
            ),
            if (actionable) ...[
              const SizedBox(height: 10),
              Row(children: [
                Material(
                  color: t3.primary,
                  borderRadius: BorderRadius.circular(7),
                  child: InkWell(
                    onTap: onApprove,
                    borderRadius: BorderRadius.circular(7),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(LucideIcons.check, size: 14, color: t3.primaryForeground),
                        const SizedBox(width: 6),
                        Text('Approve & continue',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t3.primaryForeground)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GhostChip(
                  icon: LucideIcons.lockOpen,
                  label: 'Always allow (Full access)',
                  color: t3.foregroundSubtle,
                  onTap: onAlwaysAllow,
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
