import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'theme/app_theme.dart';
import 'models/j6_entities.dart';
import 'services/j6_server_service.dart';
import 'services/j6_logger.dart';
import 'widgets/sidebar_widget.dart';
import 'widgets/message_item_widget.dart';
import 'widgets/activity_item_widget.dart';
import 'widgets/composer_widget.dart';

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
    return MaterialApp(
      title: 'j6code',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final J6ServerService _serverService = J6ServerService();
  
  List<J6Project> _projects = [];
  List<J6Thread> _threads = [];
  List<J6Message> _messages = [];
  List<J6Activity> _activities = [];
  List<J6Provider> _providers = [];
  
  J6Provider? _selectedProvider;
  J6Model? _selectedModel;
  String? _selectedProjectId;
  String? _selectedThreadId;
  bool _isServerConnected = false;
  bool _isSending = false;
  Timer? _refreshTimer;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    J6Logger.info('Initializing MainScreen state...');
    await _serverService.connect();
    _serverService.onConnectionStateChanged.listen((connected) {
      J6Logger.info('WebSocket connection state changed: $connected');
      if (mounted) setState(() => _isServerConnected = connected);
    });

    // Load available engines & models (Grok, OpenCode, Antigravity, etc.)
    final providers = await _serverService.loadAvailableProviders();
    J6Provider? defaultProvider;
    J6Model? defaultModel;

    if (providers.isNotEmpty) {
      defaultProvider = providers.firstWhere(
        (p) => p.id == 'grok' || p.id == 'antigravity',
        orElse: () => providers.first,
      );
      if (defaultProvider.models.isNotEmpty) {
        defaultModel = defaultProvider.models.firstWhere(
          (m) => m.name.contains('Build') || m.name.contains('High'),
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
    final String? currentProjectId = _selectedProjectId ?? (projects.isNotEmpty ? projects.first.projectId : null);
    final threads = await _serverService.fetchThreads(currentProjectId);
    
    String? currentThreadId = _selectedThreadId;
    if ((currentThreadId == null || !threads.any((t) => t.threadId == currentThreadId)) && threads.isNotEmpty) {
      currentThreadId = threads.first.threadId;
    }

    List<J6Message> messages = [];
    List<J6Activity> activities = [];
    if (currentThreadId != null) {
      messages = await _serverService.fetchThreadMessages(currentThreadId);
      activities = await _serverService.fetchThreadActivities(currentThreadId);
    }

    J6Logger.info('Loaded initial data: ${projects.length} projects, ${threads.length} threads for current project ($currentProjectId), ${messages.length} messages');

    if (mounted) {
      setState(() {
        _projects = projects;
        _threads = threads;
        _selectedProjectId = currentProjectId;
        _selectedThreadId = currentThreadId;
        _messages = messages;
        _activities = activities;
      });
      _scrollToBottom();
    }
  }

  Future<void> _pollUpdates() async {
    if (_selectedThreadId != null) {
      final messages = await _serverService.fetchThreadMessages(_selectedThreadId!);
      final activities = await _serverService.fetchThreadActivities(_selectedThreadId!);
      final threads = await _serverService.fetchThreads(_selectedProjectId);

      if (mounted) {
        setState(() {
          _messages = messages;
          _activities = activities;
          _threads = threads;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _selectThread(String threadId) async {
    J6Logger.info('Selected thread: $threadId');
    setState(() {
      _selectedThreadId = threadId;
      _messages = [];
      _activities = [];
    });
    final messages = await _serverService.fetchThreadMessages(threadId);
    final activities = await _serverService.fetchThreadActivities(threadId);
    if (mounted) {
      setState(() {
        _messages = messages;
        _activities = activities;
      });
      _scrollToBottom();
    }
  }

  void _handleNewThread() async {
    if (_selectedProjectId == null) return;
    J6Logger.info('Creating new thread for project $_selectedProjectId');
    final newId = await _serverService.createThread(
      projectId: _selectedProjectId!,
      title: 'New Coding Task',
    );
    if (newId != null) {
      await _loadInitialData();
      _selectThread(newId);
    }
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
        setState(() {
          _projects = projects;
          _selectedProjectId = project.projectId;
        });
        final threads = await _serverService.fetchThreads(project.projectId);
        if (threads.isNotEmpty) {
          _selectThread(threads.first.threadId);
        } else {
          _handleNewThread();
        }
      }
    }
  }

  void _handleSendPrompt(String prompt) async {
    // If no project selected yet, create or fallback to default
    String projectId = _selectedProjectId ?? '';
    if (projectId.isEmpty) {
      if (_projects.isNotEmpty) {
        projectId = _projects.first.projectId;
      } else {
        final newProj = await _serverService.openFolderAsProject(
          'C:\\Users\\ctyja\\workspace\\j6code',
        );
        projectId = newProj?.projectId ?? 'proj_default';
      }
      setState(() => _selectedProjectId = projectId);
    }

    setState(() => _isSending = true);

    String threadId = _selectedThreadId ?? '';
    if (threadId.isEmpty) {
      final title = prompt.length > 35 ? '${prompt.substring(0, 35)}...' : prompt;
      final created = await _serverService.createThread(
        projectId: projectId,
        title: title,
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
    );

    setState(() {
      _messages = [..._messages, optimisticMsg];
    });
    _scrollToBottom();

    final providerId = _selectedProvider?.id ?? 'grok';
    final modelSlug = _selectedModel?.slug ?? 'grok-build';

    J6Logger.info('Sending prompt to $providerId ($modelSlug) in thread $threadId: ${prompt.replaceAll('\n', ' ')}');

    await _serverService.sendPrompt(
      threadId: threadId,
      projectId: projectId,
      prompt: prompt,
      providerId: providerId,
      modelSlug: modelSlug,
    );

    setState(() => _isSending = false);

    await _pollUpdates();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _serverService.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> timelineItems = [..._messages, ..._activities];
    timelineItems.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final currentThread = _threads.firstWhere(
      (t) => t.threadId == _selectedThreadId,
      orElse: () => J6Thread(
        threadId: '',
        projectId: '',
        title: 'New Workspace Session',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

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

    return Scaffold(
      body: Row(
        children: [
          // Sidebar with Repository and Thread management
          SidebarWidget(
            projects: _projects,
            threads: _threads,
            selectedProjectId: _selectedProjectId,
            selectedThreadId: _selectedThreadId,
            isServerConnected: _isServerConnected,
            onSelectProject: (id) {
              setState(() => _selectedProjectId = id);
              _loadInitialData();
            },
            onSelectThread: _selectThread,
            onNewThread: _handleNewThread,
            onOpenFolder: _handleOpenFolder,
          ),

          // Main Conversation & Coding Workspace Area
          Expanded(
            child: Column(
              children: [
                // Top Header Bar
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        currentProject.isGitRepo ? Icons.commit_rounded : Icons.folder_open_rounded,
                        size: 16,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        currentProject.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('/', style: TextStyle(color: AppTheme.textMuted)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currentThread.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      if (currentProject.workspaceRoot.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceHover,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppTheme.borderSubtle),
                          ),
                          child: Text(
                            currentProject.workspaceRoot,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Consolas, monospace',
                              fontSize: 10.5,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        color: AppTheme.textMuted,
                        onPressed: _pollUpdates,
                        tooltip: 'Sync updates',
                      ),
                    ],
                  ),
                ),

                // Conversation & Action Feed
                Expanded(
                  child: timelineItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceSubtle,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: const Icon(
                                  Icons.code_rounded,
                                  size: 28,
                                  color: AppTheme.accent,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Ready to code in ${currentProject.title}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Select your AI engine (Grok Build, OpenCode, Anti Gravity ACP) and ask anything.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: timelineItems.length,
                          itemBuilder: (context, index) {
                            final item = timelineItems[index];
                            if (item is J6Message) {
                              return MessageItemWidget(message: item);
                            } else if (item is J6Activity) {
                              return ActivityItemWidget(activity: item);
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                ),

                // Bottom Composer
                ComposerWidget(
                  providers: _providers,
                  selectedProvider: _selectedProvider,
                  selectedModel: _selectedModel,
                  activeWorkspaceName: currentProject.title,
                  onSelectModel: (provider, model) {
                    setState(() {
                      _selectedProvider = provider;
                      _selectedModel = model;
                    });
                  },
                  onSendPrompt: _handleSendPrompt,
                  isSending: _isSending,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
