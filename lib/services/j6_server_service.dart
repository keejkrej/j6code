import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import '../models/j6_entities.dart';
import 'j6_logger.dart';

/// Embedded Standalone J6 Orchestration and Storage Engine
/// 
/// Runs completely independently inside the client application with zero
/// dependencies on external server processes or shared third-party databases.
class J6ServerService {
  static final String userProfile =
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      'C:\\Users\\ctyja';
  static final String j6Dir = '$userProfile\\.j6code';
  static final String userdataDir = '$j6Dir\\userdata';
  static final String sqlitePath = '$userdataDir\\state.sqlite';
  static final String cachesDir = '$j6Dir\\caches';

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectionStateChanged => _connectionStateController.stream;

  final _messagesController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onMessageReceived => _messagesController.stream;

  Database? _db;

  void _ensureDirectories() {
    try {
      final userDir = Directory(userdataDir);
      if (!userDir.existsSync()) {
        userDir.createSync(recursive: true);
      }
      final cacheDir = Directory(cachesDir);
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
    } catch (e, stack) {
      J6Logger.error('Failed to create j6code directories', e, stack);
    }
  }

  Database _getDb() {
    if (_db != null) {
      try {
        _db!.select('SELECT 1');
        return _db!;
      } catch (_) {
        _db = null;
      }
    }
    _ensureDirectories();
    _db = sqlite3.open(sqlitePath);
    _initSchema(_db!);
    return _db!;
  }

  void _initSchema(Database db) {
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA busy_timeout = 5000;');

    db.execute('''
      CREATE TABLE IF NOT EXISTS projection_projects (
        project_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        workspace_root TEXT NOT NULL,
        scripts_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS projection_threads (
        thread_id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        title TEXT NOT NULL,
        model_selection_json TEXT,
        runtime_mode TEXT DEFAULT 'full-access',
        interaction_mode TEXT DEFAULT 'default',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS projection_thread_messages (
        message_id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        role TEXT NOT NULL,
        text TEXT NOT NULL,
        is_streaming INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS projection_thread_activities (
        activity_id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        turn_id TEXT,
        kind TEXT NOT NULL,
        summary TEXT NOT NULL,
        payload_json TEXT,
        created_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_thread ON projection_thread_messages(thread_id, created_at);
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_activities_thread ON projection_thread_activities(thread_id, created_at);
    ''');
  }

  Future<void> connect() async {
    J6Logger.info('Initializing independent embedded J6 engine and local storage...');
    try {
      _getDb();
      _isConnected = true;
      _connectionStateController.add(true);
      J6Logger.info('J6 embedded engine ready. Database: $sqlitePath');
    } catch (e, stack) {
      J6Logger.error('Failed to initialize local J6 database', e, stack);
      _isConnected = false;
      _connectionStateController.add(false);
    }
  }

  String? _findExecutable(List<String> candidates) {
    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  String? _resolveAgyPath() {
    final localApp = Platform.environment['LOCALAPPDATA'] ?? 'C:\\Users\\ctyja\\AppData\\Local';
    return _findExecutable([
      '$localApp\\agy\\bin\\agy.exe',
      '$userProfile\\AppData\\Local\\agy\\bin\\agy.exe',
      'agy.exe',
    ]);
  }

  String? _resolveGrokPath() {
    return _findExecutable([
      '$userProfile\\.grok\\bin\\grok.exe',
      'grok.exe',
    ]);
  }

  String? _resolveOpenCodePath() {
    final localApp = Platform.environment['LOCALAPPDATA'] ?? 'C:\\Users\\ctyja\\AppData\\Local';
    return _findExecutable([
      '$localApp\\mise\\shims\\opencode.exe',
      'opencode.exe',
    ]);
  }

  /// Automatically discovers available AI agent engines on this computer
  Future<List<J6Provider>> loadAvailableProviders() async {
    final List<J6Provider> providers = [];

    // 1. Antigravity Provider
    final agyPath = _resolveAgyPath();
    if (agyPath != null) {
      providers.add(J6Provider(
        id: 'antigravity',
        name: 'Antigravity (Gemini)',
        models: [
          J6Model(slug: 'gemini-3.8-flash-high', name: 'Gemini 3.8 Flash (High)'),
          J6Model(slug: 'gemini-3.7-flash-high', name: 'Gemini 3.7 Flash (High)'),
          J6Model(slug: 'claude-sonnet-5-5-high', name: 'Claude Sonnet 5.5 (High)'),
          J6Model(slug: 'claude-opus-5-5-high', name: 'Claude Opus 5.5 (High)'),
          J6Model(slug: 'gemini-3.1-pro-high', name: 'Gemini 3.1 Pro (High)'),
        ],
      ));
    }

    // 2. Grok Build Provider
    final grokPath = _resolveGrokPath();
    if (grokPath != null) {
      providers.add(J6Provider(
        id: 'grok',
        name: 'Grok Build',
        models: [
          J6Model(slug: 'grok-4.7-build', name: 'Grok 4.7 Build'),
          J6Model(slug: 'grok-4.5-mini', name: 'Grok 4.5 Mini'),
        ],
      ));
    }

    // 3. OpenCode Provider
    final openCodePath = _resolveOpenCodePath();
    if (openCodePath != null) {
      providers.add(J6Provider(
        id: 'opencode',
        name: 'OpenCode',
        models: [
          J6Model(slug: 'opencode-agent', name: 'OpenCode Agent'),
          J6Model(slug: 'claude-3-7-sonnet', name: 'Claude 3.7 Sonnet'),
          J6Model(slug: 'gpt-4o', name: 'GPT-4o'),
        ],
      ));
    }

    // Fallback if none detected
    if (providers.isEmpty) {
      providers.add(J6Provider(
        id: 'antigravity',
        name: 'Antigravity (Gemini)',
        models: [
          J6Model(slug: 'gemini-3.8-flash-high', name: 'Gemini 3.8 Flash (High)'),
          J6Model(slug: 'gemini-3.7-flash-high', name: 'Gemini 3.7 Flash (High)'),
        ],
      ));
    }

    J6Logger.info('Discovered ${providers.length} available local AI providers');
    return providers;
  }

  /// Opens or registers an arbitrary workspace folder as a Project
  Future<J6Project?> openFolderAsProject(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (!dir.existsSync()) {
        J6Logger.warn('Folder does not exist: $folderPath');
        return null;
      }

      final normalizedPath = dir.path.replaceAll('/', '\\');
      final folderName = dir.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'Project';
      final isGit = Directory('$normalizedPath\\.git').existsSync() || Directory('$normalizedPath/.git').existsSync();

      final db = _getDb();
      final existing = db.select(
        'SELECT * FROM projection_projects WHERE workspace_root = ? LIMIT 1',
        [normalizedPath],
      );

      if (existing.isNotEmpty) {
        final row = existing.first;
        J6Logger.info('Found existing project: ${row['title']} (${row['project_id']})');
        return J6Project(
          projectId: row['project_id'].toString(),
          title: row['title']?.toString() ?? folderName,
          workspaceRoot: normalizedPath,
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
          updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? DateTime.now(),
          isGitRepo: isGit,
        );
      }

      final id = "proj_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond % 1000}";
      final now = DateTime.now().toUtc().toIso8601String();
      db.execute(
        'INSERT INTO projection_projects (project_id, title, workspace_root, scripts_json, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [id, folderName, normalizedPath, '[]', now, now],
      );

      J6Logger.info('Registered independent project: $folderName ($id) at $normalizedPath');

      return J6Project(
        projectId: id,
        title: folderName,
        workspaceRoot: normalizedPath,
        createdAt: DateTime.parse(now),
        updatedAt: DateTime.parse(now),
        isGitRepo: isGit,
      );
    } catch (e, stack) {
      J6Logger.error('Error opening folder as project', e, stack);
    }
    return null;
  }

  Future<List<J6Project>> fetchProjects() async {
    try {
      final db = _getDb();
      final results = db.select('SELECT * FROM projection_projects ORDER BY updated_at DESC');
      final List<J6Project> list = [];
      for (final row in results) {
        final root = row['workspace_root']?.toString() ?? '';
        bool isGit = false;
        try {
          if (root.isNotEmpty) {
            isGit = Directory('$root\\.git').existsSync() || Directory('$root/.git').existsSync();
          }
        } catch (_) {}

        list.add(J6Project(
          projectId: row['project_id'].toString(),
          title: row['title'].toString(),
          workspaceRoot: root,
          createdAt: DateTime.tryParse(row['created_at'].toString()) ?? DateTime.now(),
          updatedAt: DateTime.tryParse(row['updated_at'].toString()) ?? DateTime.now(),
          isGitRepo: isGit,
        ));
      }
      return list;
    } catch (e, stack) {
      J6Logger.error('Error fetching projects from j6 database', e, stack);
    }
    return [];
  }

  Future<List<J6Thread>> fetchThreads(String? projectId) async {
    try {
      final db = _getDb();
      final results = projectId != null
          ? db.select(
              'SELECT * FROM projection_threads WHERE project_id = ? ORDER BY updated_at DESC',
              [projectId],
            )
          : db.select('SELECT * FROM projection_threads ORDER BY updated_at DESC');

      final List<J6Thread> list = [];
      for (final row in results) {
        list.add(J6Thread(
          threadId: row['thread_id'].toString(),
          projectId: row['project_id'].toString(),
          title: row['title']?.toString() ?? 'Untitled Task',
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
          updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? DateTime.now(),
          modelSelectionJson: row['model_selection_json']?.toString(),
        ));
      }
      return list;
    } catch (e, stack) {
      J6Logger.error('Error fetching threads from j6 database', e, stack);
    }
    return [];
  }

  Future<List<J6Message>> fetchThreadMessages(String threadId) async {
    try {
      final db = _getDb();
      final results = db.select(
        'SELECT * FROM projection_thread_messages WHERE thread_id = ? ORDER BY created_at ASC',
        [threadId],
      );

      final List<J6Message> list = [];
      for (final row in results) {
        list.add(J6Message(
          messageId: row['message_id'].toString(),
          threadId: row['thread_id'].toString(),
          role: row['role']?.toString() ?? 'user',
          text: row['text']?.toString() ?? '',
          isStreaming: row['is_streaming'] == 1,
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
        ));
      }
      return list;
    } catch (e, stack) {
      J6Logger.error('Error fetching messages from j6 database', e, stack);
    }
    return [];
  }

  Future<List<J6Activity>> fetchThreadActivities(String threadId) async {
    try {
      final db = _getDb();
      final results = db.select(
        'SELECT * FROM projection_thread_activities WHERE thread_id = ? ORDER BY created_at ASC',
        [threadId],
      );

      final List<J6Activity> list = [];
      final Map<String, int> toolKeyToIndex = {};

      for (final row in results) {
        Map<String, dynamic> payload = {};
        final rawPayload = row['payload_json']?.toString();
        if (rawPayload != null && rawPayload.isNotEmpty) {
          try {
            payload = jsonDecode(rawPayload);
          } catch (_) {}
        }

        final data = payload['data'] is Map ? payload['data'] as Map : {};
        final toolCallId = (payload['toolCallId'] ?? data['toolCallId'])?.toString().trim();
        final turnId = row['turn_id']?.toString().trim() ?? '';
        final kind = row['kind']?.toString() ?? '';

        final activity = J6Activity(
          activityId: row['activity_id']?.toString() ?? '',
          threadId: row['thread_id']?.toString() ?? '',
          kind: kind,
          summary: row['summary']?.toString() ?? '',
          payload: payload,
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
        );

        if (toolCallId != null && toolCallId.isNotEmpty) {
          final toolKey = 'tool:$turnId:$toolCallId';
          if (toolKeyToIndex.containsKey(toolKey)) {
            final existingIndex = toolKeyToIndex[toolKey]!;
            list[existingIndex] = activity;
          } else {
            toolKeyToIndex[toolKey] = list.length;
            list.add(activity);
          }
        } else {
          list.add(activity);
        }
      }
      return list;
    } catch (e, stack) {
      J6Logger.error('Error fetching activities from j6 database', e, stack);
    }
    return [];
  }

  Future<String?> createThread({
    required String projectId,
    required String title,
    String? providerId,
    String? modelSlug,
  }) async {
    try {
      final id = "th_${DateTime.now().millisecondsSinceEpoch}_${(1000 + DateTime.now().microsecond % 9000)}";
      final now = DateTime.now().toUtc().toIso8601String();

      final modelSelection = {
        'instanceId': providerId ?? 'antigravity',
        'model': modelSlug ?? 'gemini-3.8-flash-high',
      };

      final db = _getDb();
      db.execute(
        'INSERT INTO projection_threads (thread_id, project_id, title, model_selection_json, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [id, projectId, title, jsonEncode(modelSelection), now, now],
      );

      J6Logger.info('Created new thread: $id ("$title") in j6 database');
      return id;
    } catch (e, stack) {
      J6Logger.error('Error creating thread', e, stack);
    }
    return null;
  }

  /// Sends a prompt and executes agent turn through native embedded orchestration
  Future<bool> sendPrompt({
    required String threadId,
    required String projectId,
    required String prompt,
    required String providerId,
    required String modelSlug,
  }) async {
    try {
      final db = _getDb();
      final now = DateTime.now().toUtc().toIso8601String();
      final userMsgId = "msg_user_${DateTime.now().millisecondsSinceEpoch}";
      final asstMsgId = "msg_asst_${DateTime.now().millisecondsSinceEpoch}";
      final turnId = "turn_${DateTime.now().millisecondsSinceEpoch}";

      // 1. Persist user message in SQLite
      db.execute(
        'INSERT INTO projection_thread_messages (message_id, thread_id, role, text, is_streaming, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        [userMsgId, threadId, 'user', prompt, 0, now],
      );

      // 2. Insert placeholder assistant message with is_streaming = 1
      db.execute(
        'INSERT INTO projection_thread_messages (message_id, thread_id, role, text, is_streaming, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        [asstMsgId, threadId, 'assistant', '', 1, now],
      );

      // 3. Resolve workspace root for this project
      String workspaceRoot = Directory.current.path;
      final projResults = db.select(
        'SELECT workspace_root FROM projection_projects WHERE project_id = ? LIMIT 1',
        [projectId],
      );
      if (projResults.isNotEmpty && projResults.first['workspace_root'] != null) {
        workspaceRoot = projResults.first['workspace_root'].toString();
      }

      // 4. Retrieve or update thread conversation ID for multi-turn persistence
      String? conversationId;
      final threadResults = db.select(
        'SELECT model_selection_json FROM projection_threads WHERE thread_id = ? LIMIT 1',
        [threadId],
      );
      if (threadResults.isNotEmpty && threadResults.first['model_selection_json'] != null) {
        try {
          final parsed = jsonDecode(threadResults.first['model_selection_json'].toString());
          if (parsed is Map && parsed['conversationId'] != null) {
            conversationId = parsed['conversationId'].toString();
          }
        } catch (_) {}
      }

      // 5. Dispatch native agent execution asynchronously
      _runAgentProcess(
        threadId: threadId,
        turnId: turnId,
        asstMsgId: asstMsgId,
        workspaceRoot: workspaceRoot,
        prompt: prompt,
        providerId: providerId,
        modelSlug: modelSlug,
        existingConversationId: conversationId,
      );

      return true;
    } catch (e, stack) {
      J6Logger.error('Error in sendPrompt', e, stack);
      return false;
    }
  }

  void _runAgentProcess({
    required String threadId,
    required String turnId,
    required String asstMsgId,
    required String workspaceRoot,
    required String prompt,
    required String providerId,
    required String modelSlug,
    String? existingConversationId,
  }) async {
    final db = _getDb();
    final StringBuffer assistantBuffer = StringBuffer();

    try {
      if (providerId == 'antigravity') {
        final agyPath = _resolveAgyPath() ?? 'agy.exe';
        final List<String> args = [
          '--print',
          prompt,
          '--model',
          modelSlug,
          '--output-format',
          'stream-json',
          '--dangerously-skip-permissions',
        ];

        if (existingConversationId != null && existingConversationId.isNotEmpty) {
          args.addAll(['--conversation', existingConversationId]);
        }

        J6Logger.info('Launching Antigravity agent process: $agyPath in $workspaceRoot');
        final process = await Process.start(
          agyPath,
          args,
          workingDirectory: workspaceRoot,
          runInShell: true,
        );

        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          _handleAgyStreamLine(
            db: db,
            line: line,
            threadId: threadId,
            turnId: turnId,
            asstMsgId: asstMsgId,
            assistantBuffer: assistantBuffer,
          );
        });

        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          J6Logger.warn('[agy stderr] $line');
        });

        final exitCode = await process.exitCode;
        J6Logger.info('Antigravity process finished with exit code $exitCode');
      } else if (providerId == 'grok') {
        final grokPath = _resolveGrokPath() ?? 'grok.exe';
        final List<String> args = [
          '-p',
          prompt,
          '-m',
          modelSlug,
          '--output-format',
          'streaming-json',
          '--always-approve',
        ];

        if (existingConversationId != null && existingConversationId.isNotEmpty) {
          args.addAll(['--resume', existingConversationId]);
        }

        J6Logger.info('Launching Grok Build agent process: $grokPath in $workspaceRoot');
        final process = await Process.start(
          grokPath,
          args,
          workingDirectory: workspaceRoot,
          runInShell: true,
        );

        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          _handleGrokStreamLine(
            db: db,
            line: line,
            threadId: threadId,
            turnId: turnId,
            asstMsgId: asstMsgId,
            assistantBuffer: assistantBuffer,
          );
        });

        final exitCode = await process.exitCode;
        J6Logger.info('Grok process finished with exit code $exitCode');
      } else if (providerId == 'opencode') {
        final opencodePath = _resolveOpenCodePath() ?? 'opencode.exe';
        final List<String> args = [
          'run',
          prompt,
          '-m',
          modelSlug,
          '--auto',
        ];

        J6Logger.info('Launching OpenCode process: $opencodePath in $workspaceRoot');
        final process = await Process.start(
          opencodePath,
          args,
          workingDirectory: workspaceRoot,
          runInShell: true,
        );

        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          assistantBuffer.writeln(line);
          db.execute(
            'UPDATE projection_thread_messages SET text = ?, is_streaming = 1 WHERE message_id = ?',
            [assistantBuffer.toString(), asstMsgId],
          );
        });

        final exitCode = await process.exitCode;
        J6Logger.info('OpenCode process finished with exit code $exitCode');
      } else {
        // Generic fallback response
        assistantBuffer.write('Executed prompt on model: $modelSlug');
      }
    } catch (e, stack) {
      J6Logger.error('Error during agent execution', e, stack);
      assistantBuffer.writeln('\n[Error executing agent: $e]');
    } finally {
      // Mark assistant message streaming as finished
      try {
        db.execute(
          'UPDATE projection_thread_messages SET text = ?, is_streaming = 0 WHERE message_id = ?',
          [assistantBuffer.toString(), asstMsgId],
        );
        db.execute(
          'UPDATE projection_threads SET updated_at = ? WHERE thread_id = ?',
          [DateTime.now().toUtc().toIso8601String(), threadId],
        );
        _messagesController.add({
          'type': 'thread.turn.completed',
          'threadId': threadId,
          'messageId': asstMsgId,
        });
      } catch (err) {
        J6Logger.error('Failed to finalize message in sqlite', err);
      }
    }
  }

  void _handleAgyStreamLine({
    required Database db,
    required String line,
    required String threadId,
    required String turnId,
    required String asstMsgId,
    required StringBuffer assistantBuffer,
  }) {
    if (line.trim().isEmpty) return;
    try {
      final json = jsonDecode(line);
      if (json is! Map<String, dynamic>) return;

      final event = json['event']?.toString();

      // Capture conversation ID for multi-turn thread persistence
      if (event == 'init' && json['conversation_id'] != null) {
        final convId = json['conversation_id'].toString();
        _saveThreadConversationId(db, threadId, convId);
      }

      if (event == 'step_update') {
        final step = json['step_update'] as Map<String, dynamic>?;
        if (step != null) {
          final stepType = step['step_type']?.toString();
          
          // Streaming text chunks from the model
          if (stepType == 'agent_response' && step.containsKey('text_delta')) {
            final delta = step['text_delta']?.toString() ?? '';
            assistantBuffer.write(delta);
            db.execute(
              'UPDATE projection_thread_messages SET text = ?, is_streaming = 1 WHERE message_id = ?',
              [assistantBuffer.toString(), asstMsgId],
            );
          }

          // Tool calls and activities (file editing, terminal execution, etc.)
          if (stepType == 'tool_call' || step['tool_name'] != null || step['tool_calls'] != null) {
            final toolName = step['tool_name'] ?? 'tool';
            final activityId = 'act_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond % 1000}';
            final now = DateTime.now().toUtc().toIso8601String();
            final payload = {
              'itemType': toolName == 'run_command' ? 'command' : 'tool_call',
              'data': step,
            };

            db.execute(
              'INSERT INTO projection_thread_activities (activity_id, thread_id, turn_id, kind, summary, payload_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
              [
                activityId,
                threadId,
                turnId,
                'toolCall',
                'Running $toolName',
                jsonEncode(payload),
                now,
              ],
            );
          }
        }
      }

      if (event == 'result') {
        final res = json['result'] as Map<String, dynamic>?;
        if (res != null && res['response'] != null && assistantBuffer.isEmpty) {
          assistantBuffer.write(res['response'].toString());
          db.execute(
            'UPDATE projection_thread_messages SET text = ?, is_streaming = 0 WHERE message_id = ?',
            [assistantBuffer.toString(), asstMsgId],
          );
        }
      }
    } catch (_) {
      // Non-JSON stdout lines
      assistantBuffer.writeln(line);
      db.execute(
        'UPDATE projection_thread_messages SET text = ?, is_streaming = 1 WHERE message_id = ?',
        [assistantBuffer.toString(), asstMsgId],
      );
    }
  }

  void _handleGrokStreamLine({
    required Database db,
    required String line,
    required String threadId,
    required String turnId,
    required String asstMsgId,
    required StringBuffer assistantBuffer,
  }) {
    if (line.trim().isEmpty) return;
    try {
      final json = jsonDecode(line);
      if (json is! Map<String, dynamic>) return;

      final type = json['type']?.toString();
      if (type == 'text' && json['data'] != null) {
        final text = json['data'].toString();
        assistantBuffer.write(text);
        db.execute(
          'UPDATE projection_thread_messages SET text = ?, is_streaming = 1 WHERE message_id = ?',
          [assistantBuffer.toString(), asstMsgId],
        );
      } else if (type == 'end' && json['sessionId'] != null) {
        final sessId = json['sessionId'].toString();
        _saveThreadConversationId(db, threadId, sessId);
      }
    } catch (_) {
      assistantBuffer.writeln(line);
    }
  }

  void _saveThreadConversationId(Database db, String threadId, String convId) {
    try {
      final results = db.select(
        'SELECT model_selection_json FROM projection_threads WHERE thread_id = ? LIMIT 1',
        [threadId],
      );
      Map<String, dynamic> data = {};
      if (results.isNotEmpty && results.first['model_selection_json'] != null) {
        try {
          data = jsonDecode(results.first['model_selection_json'].toString());
        } catch (_) {}
      }
      data['conversationId'] = convId;
      db.execute(
        'UPDATE projection_threads SET model_selection_json = ? WHERE thread_id = ?',
        [jsonEncode(data), threadId],
      );
      J6Logger.info('Bound conversation ID $convId to thread $threadId');
    } catch (e) {
      J6Logger.warn('Could not save conversation ID: $e');
    }
  }

  void dispose() {
    _connectionStateController.close();
    _messagesController.close();
    try {
      _db?.close();
    } catch (_) {}
  }
}
