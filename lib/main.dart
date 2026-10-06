import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'models/t3_entities.dart';
import 'services/t3_server_service.dart';
import 'widgets/sidebar_widget.dart';
import 'widgets/message_item_widget.dart';
import 'widgets/activity_item_widget.dart';
import 'widgets/composer_widget.dart';

void main() {
  runApp(const ProviderScope(child: T3CodeApp()));
}

class T3CodeApp extends StatelessWidget {
  const T3CodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'T3 Code',
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
  final T3ServerService _serverService = T3ServerService();
  
  List<T3Project> _projects = [];
  List<T3Thread> _threads = [];
  List<T3Message> _messages = [];
  List<T3Activity> _activities = [];
  
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
    await _serverService.connect();
    _serverService.onConnectionStateChanged.listen((connected) {
      if (mounted) {
        setState(() => _isServerConnected = connected);
      }
    });

    await _loadInitialData();

    // Auto-refresh state every 3 seconds to keep live with ongoing tasks
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _pollUpdates();
    });
  }

  Future<void> _loadInitialData() async {
    final projects = await _serverService.fetchProjects();
    final threads = await _serverService.fetchThreads(projects.isNotEmpty ? projects.first.projectId : null);
    
    String? currentThreadId = _selectedThreadId;
    if (currentThreadId == null && threads.isNotEmpty) {
      currentThreadId = threads.first.threadId;
    }

    List<T3Message> messages = [];
    List<T3Activity> activities = [];
    if (currentThreadId != null) {
      messages = await _serverService.fetchThreadMessages(currentThreadId);
      activities = await _serverService.fetchThreadActivities(currentThreadId);
    }

    if (mounted) {
      setState(() {
        _projects = projects;
        _threads = threads;
        if (projects.isNotEmpty && _selectedProjectId == null) {
          _selectedProjectId = projects.first.projectId;
        }
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
    // Switch to clean view
    setState(() {
      _selectedThreadId = null;
      _messages = [];
      _activities = [];
    });
  }

  void _handleSendPrompt(String prompt) async {
    if (_selectedProjectId == null) return;
    setState(() => _isSending = true);

    String threadId = _selectedThreadId ?? 'thread_${DateTime.now().millisecondsSinceEpoch}';
    await _serverService.sendPrompt(
      threadId: threadId,
      projectId: _selectedProjectId!,
      prompt: prompt,
    );

    setState(() {
      _isSending = false;
      _selectedThreadId = threadId;
    });

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
    // Merge messages and activities chronologically for the transcript
    final List<dynamic> timelineItems = [..._messages, ..._activities];
    timelineItems.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final currentThread = _threads.firstWhere(
      (t) => t.threadId == _selectedThreadId,
      orElse: () => T3Thread(
        threadId: '',
        projectId: '',
        title: 'New Conversation',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    return Scaffold(
      body: Row(
        children: [
          // Left Sidebar
          SidebarWidget(
            projects: _projects,
            threads: _threads,
            selectedProjectId: _selectedProjectId,
            selectedThreadId: _selectedThreadId,
            isServerConnected: _isServerConnected,
            onSelectProject: (id) => setState(() => _selectedProjectId = id),
            onSelectThread: _selectThread,
            onNewThread: _handleNewThread,
          ),

          // Main Conversation Area
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
                        Icons.tag_rounded,
                        size: 16,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currentThread.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        color: AppTheme.textMuted,
                        onPressed: _pollUpdates,
                        tooltip: 'Refresh transcript',
                      ),
                    ],
                  ),
                ),

                // Conversation Transcript / Stream
                Expanded(
                  child: timelineItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceSubtle,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 24,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'What would you like to build?',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Type a prompt below to interact with your codebase.',
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
                            if (item is T3Message) {
                              return MessageItemWidget(message: item);
                            } else if (item is T3Activity) {
                              return ActivityItemWidget(activity: item);
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                ),

                // Bottom Composer
                ComposerWidget(
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
