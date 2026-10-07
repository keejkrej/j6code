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

    // Thread settlement (mirrors t3code migrations 033 + 043).
    //   settled_override: NULL (automatic) | 'settled' (user settled) | 'active' (user un-settled)
    //   settled_at:       when the thread was settled
    //   unsettled_at:     when the thread was last brought back from settled
    final threadColumns = db.select('PRAGMA table_info(projection_threads)').map((r) => r['name'] as String).toSet();
    for (final column in const ['settled_override', 'settled_at', 'unsettled_at']) {
      if (!threadColumns.contains(column)) {
        db.execute('ALTER TABLE projection_threads ADD COLUMN $column TEXT');
      }
    }
    // Older databases predate the per-thread runtime mode (t3code RuntimeMode).
    if (!threadColumns.contains('runtime_mode')) {
      db.execute("ALTER TABLE projection_threads ADD COLUMN runtime_mode TEXT DEFAULT 'full-access'");
    }

    // Files/images attached to a user message: JSON list of
    // {name, path, mimeType, sizeBytes} (t3code ChatAttachment).
    final messageColumns =
        db.select('PRAGMA table_info(projection_thread_messages)').map((r) => r['name'] as String).toSet();
    if (!messageColumns.contains('attachments_json')) {
      db.execute('ALTER TABLE projection_thread_messages ADD COLUMN attachments_json TEXT');
    }
  }

  /// Where attachment copies live so transcripts keep rendering them even if
  /// the original file moves.
  static final String attachmentsDir = '$j6Dir\\attachments';

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
      // A streaming assistant message means a run is live. Bounded in time so a
      // crashed run (stuck is_streaming = 1) can't block settling forever —
      // same idea as t3code's QUEUED_TURN_START_GRACE_MS.
      const runningExpr = "EXISTS(SELECT 1 FROM projection_thread_messages m WHERE m.thread_id = t.thread_id "
          "AND m.is_streaming = 1 AND m.created_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-30 minutes')) AS is_running";
      final results = projectId != null
          ? db.select(
              'SELECT t.*, $runningExpr FROM projection_threads t WHERE t.project_id = ? ORDER BY t.updated_at DESC',
              [projectId],
            )
          : db.select('SELECT t.*, $runningExpr FROM projection_threads t ORDER BY t.updated_at DESC');

      final List<J6Thread> list = [];
      for (final row in results) {
        list.add(J6Thread(
          threadId: row['thread_id'].toString(),
          projectId: row['project_id'].toString(),
          title: row['title']?.toString() ?? 'Untitled Task',
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
          updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? DateTime.now(),
          modelSelectionJson: row['model_selection_json']?.toString(),
          settledOverride: row['settled_override']?.toString(),
          settledAt: DateTime.tryParse(row['settled_at']?.toString() ?? ''),
          unsettledAt: DateTime.tryParse(row['unsettled_at']?.toString() ?? ''),
          isRunning: row['is_running'] == 1,
          runtimeMode: RuntimeMode.fromId(row['runtime_mode']?.toString()),
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
          attachments: J6Attachment.listFromJson(row['attachments_json']?.toString()),
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
    RuntimeMode runtimeMode = RuntimeMode.fullAccess,
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
        'INSERT INTO projection_threads (thread_id, project_id, title, model_selection_json, runtime_mode, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, projectId, title, jsonEncode(modelSelection), runtimeMode.id, now, now],
      );

      J6Logger.info('Created new thread: $id ("$title") in j6 database');
      return id;
    } catch (e, stack) {
      J6Logger.error('Error creating thread', e, stack);
    }
    return null;
  }

  /// t3code `thread.settle`: park a finished thread in the Settled shelf.
  /// Refused while a run is live — blocked work must never hide behind a
  /// settled override. Returns false when refused or on error.
  Future<bool> settleThread(String threadId) async {
    try {
      final db = _getDb();
      final threads = await fetchThreads(null);
      final thread = threads.where((t) => t.threadId == threadId).firstOrNull;
      if (thread == null || thread.isRunning) return false;
      if (thread.settledOverride == 'settled') return true; // idempotent, keeps settled_at
      final now = DateTime.now().toUtc().toIso8601String();
      db.execute(
        "UPDATE projection_threads SET settled_override = 'settled', settled_at = ?, unsettled_at = NULL WHERE thread_id = ?",
        [now, threadId],
      );
      J6Logger.info('Settled thread $threadId');
      return true;
    } catch (e, stack) {
      J6Logger.error('Error settling thread', e, stack);
      return false;
    }
  }

  /// t3code `thread.unsettle`: bring a settled thread back to the active list.
  /// The 'active' override pins it there (it won't be auto-settled again).
  Future<bool> unsettleThread(String threadId) async {
    try {
      final db = _getDb();
      final now = DateTime.now().toUtc().toIso8601String();
      db.execute(
        "UPDATE projection_threads SET settled_override = 'active', settled_at = NULL, "
        "unsettled_at = CASE WHEN settled_override = 'active' THEN unsettled_at ELSE ? END, "
        "updated_at = CASE WHEN settled_override = 'active' THEN updated_at ELSE ? END "
        'WHERE thread_id = ?',
        [now, now, threadId],
      );
      J6Logger.info('Un-settled thread $threadId');
      return true;
    } catch (e, stack) {
      J6Logger.error('Error un-settling thread', e, stack);
      return false;
    }
  }

  /// Persists the thread's runtime mode (composer access selector).
  Future<void> setThreadRuntimeMode(String threadId, RuntimeMode mode) async {
    try {
      _getDb().execute('UPDATE projection_threads SET runtime_mode = ? WHERE thread_id = ?', [mode.id, threadId]);
    } catch (e, stack) {
      J6Logger.error('Error saving runtime mode', e, stack);
    }
  }

  /// Copies attachments into the app's attachment store so the transcript
  /// keeps working if the originals move.
  List<J6Attachment> _storeAttachments(String messageId, List<J6Attachment> attachments) {
    if (attachments.isEmpty) return const [];
    final dir = Directory('$attachmentsDir\\$messageId')..createSync(recursive: true);
    final stored = <J6Attachment>[];
    for (final a in attachments) {
      try {
        final src = File(a.path);
        if (!src.existsSync()) continue;
        // Index prefix keeps same-named files from overwriting each other.
        final dest = src.copySync('${dir.path}\\${stored.length}_${a.name}');
        stored.add(J6Attachment(name: a.name, path: dest.path, mimeType: a.mimeType, sizeBytes: src.lengthSync()));
      } catch (e) {
        J6Logger.warn('Could not store attachment ${a.path}: $e');
      }
    }
    return stored;
  }

  /// The CLIs take a plain prompt, so attachments are referenced by absolute
  /// path; every agent can open them with its file/image viewing tool.
  static String _promptWithAttachments(String prompt, List<J6Attachment> attachments) {
    if (attachments.isEmpty) return prompt;
    final lines = attachments.map((a) => '- ${a.path} (${a.isImage ? 'image' : a.mimeType})').join('\n');
    return '$prompt\n\n<attachments>\nThe user attached these files. Open them with your file viewing tool before answering:\n$lines\n</attachments>';
  }

  /// Sends a prompt and executes agent turn through native embedded orchestration
  Future<bool> sendPrompt({
    required String threadId,
    required String projectId,
    required String prompt,
    required String providerId,
    required String modelSlug,
    RuntimeMode runtimeMode = RuntimeMode.fullAccess,
    List<J6Attachment> attachments = const [],
  }) async {
    try {
      final db = _getDb();
      final now = DateTime.now().toUtc().toIso8601String();
      final userMsgId = "msg_user_${DateTime.now().millisecondsSinceEpoch}";
      final asstMsgId = "msg_asst_${DateTime.now().millisecondsSinceEpoch}";
      final turnId = "turn_${DateTime.now().millisecondsSinceEpoch}";

      // 0. A new turn re-engages the thread: clear any settle override so it
      //    returns to the active list (mirrors t3code's turn-start handling).
      db.execute(
        'UPDATE projection_threads SET settled_override = NULL, settled_at = NULL, '
        "unsettled_at = CASE WHEN settled_override = 'settled' THEN ? ELSE unsettled_at END, "
        'updated_at = ? WHERE thread_id = ?',
        [now, now, threadId],
      );

      // 1. Persist user message (and its attachments) in SQLite
      final stored = _storeAttachments(userMsgId, attachments);
      db.execute(
        'INSERT INTO projection_thread_messages (message_id, thread_id, role, text, is_streaming, created_at, attachments_json) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          userMsgId,
          threadId,
          'user',
          prompt,
          0,
          now,
          stored.isEmpty ? null : jsonEncode(stored.map((a) => a.toJson()).toList()),
        ],
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
        prompt: _promptWithAttachments(prompt, stored),
        providerId: providerId,
        modelSlug: modelSlug,
        runtimeMode: runtimeMode,
        attachments: stored,
        existingConversationId: conversationId,
      );

      return true;
    } catch (e, stack) {
      J6Logger.error('Error in sendPrompt', e, stack);
      return false;
    }
  }

  /// Maps a t3code runtime mode onto each CLI's headless permission flags.
  /// Headless runs can't prompt, so "ask" modes auto-deny the risky action;
  /// the denial is recorded as an `approval.denied` activity the UI can
  /// approve-and-retry.
  static List<String> _permissionArgs(String providerId, RuntimeMode mode) {
    switch (providerId) {
      case 'antigravity':
        return switch (mode) {
          RuntimeMode.fullAccess => ['--dangerously-skip-permissions'],
          RuntimeMode.autoAcceptEdits => ['--mode', 'accept-edits'],
          // agy has no classifier mode: "others still ask".
          RuntimeMode.auto || RuntimeMode.approvalRequired => const [],
        };
      case 'grok':
        return switch (mode) {
          RuntimeMode.fullAccess => ['--always-approve'],
          RuntimeMode.autoAcceptEdits => ['--permission-mode', 'acceptEdits'],
          RuntimeMode.auto => ['--permission-mode', 'auto'],
          RuntimeMode.approvalRequired => ['--permission-mode', 'default'],
        };
      case 'opencode':
        return mode == RuntimeMode.fullAccess ? ['--auto'] : const [];
    }
    return const [];
  }

  /// Run executables directly when we resolved a full path; going through
  /// cmd.exe would mangle multi-line prompts.
  static bool _needsShell(String exe) => !exe.contains('\\') && !exe.contains('/');

  void _recordDeniedActions({
    required Database db,
    required String threadId,
    required String turnId,
    required List<String> actions,
  }) {
    if (actions.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      'INSERT INTO projection_thread_activities (activity_id, thread_id, turn_id, kind, summary, payload_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        'act_denied_${DateTime.now().microsecondsSinceEpoch}',
        threadId,
        turnId,
        'approval.denied',
        'Approval needed: ${actions.join(', ')}',
        jsonEncode({'deniedActions': actions}),
        now,
      ],
    );
  }

  void _runAgentProcess({
    required String threadId,
    required String turnId,
    required String asstMsgId,
    required String workspaceRoot,
    required String prompt,
    required String providerId,
    required String modelSlug,
    RuntimeMode runtimeMode = RuntimeMode.fullAccess,
    List<J6Attachment> attachments = const [],
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
          ..._permissionArgs(providerId, runtimeMode),
        ];

        if (existingConversationId != null && existingConversationId.isNotEmpty) {
          args.addAll(['--conversation', existingConversationId]);
        }

        J6Logger.info('Launching Antigravity agent process: $agyPath in $workspaceRoot');
        final process = await Process.start(
          agyPath,
          args,
          workingDirectory: workspaceRoot,
          runInShell: _needsShell(agyPath),
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
          ..._permissionArgs(providerId, runtimeMode),
        ];

        if (existingConversationId != null && existingConversationId.isNotEmpty) {
          args.addAll(['--resume', existingConversationId]);
        }

        J6Logger.info('Launching Grok Build agent process: $grokPath in $workspaceRoot');
        final process = await Process.start(
          grokPath,
          args,
          workingDirectory: workspaceRoot,
          runInShell: _needsShell(grokPath),
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
          ..._permissionArgs(providerId, runtimeMode),
          // opencode can attach files natively as well.
          for (final a in attachments) ...['-f', a.path],
        ];

        J6Logger.info('Launching OpenCode process: $opencodePath in $workspaceRoot');
        final process = await Process.start(
          opencodePath,
          args,
          workingDirectory: workspaceRoot,
          runInShell: _needsShell(opencodePath),
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
        final denied = res?['denied_actions'];
        if (denied is List && denied.isNotEmpty) {
          _recordDeniedActions(
            db: db,
            threadId: threadId,
            turnId: turnId,
            actions: denied
                .whereType<Map>()
                .map((d) => (d['display_name'] ?? d['action'] ?? 'action').toString())
                .toSet()
                .toList(),
          );
        }
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
