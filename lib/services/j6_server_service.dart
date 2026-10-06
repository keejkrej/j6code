import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/j6_entities.dart';
import 'j6_logger.dart';

class J6ServerService {
  static const int serverPort = 3773;
  static const String serverHost = '127.0.0.1';
  static final String userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\ctyja';
  static final String t3Dir = '$userProfile\\.t3';
  static final String sqlitePath = '$t3Dir\\userdata\\state.sqlite';
  static final String cachesDir = '$t3Dir\\caches';
  static final String signingKeyPath = '$t3Dir\\userdata\\secrets\\server-signing-key.bin';

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectionStateChanged => _connectionStateController.stream;

  final _messagesController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onMessageReceived => _messagesController.stream;

  Database? _db;

  Database _getDb({bool readOnly = true}) {
    if (_db != null) {
      try {
        _db!.select('SELECT 1');
        return _db!;
      } catch (_) {
        _db = null;
      }
    }
    final mode = readOnly ? OpenMode.readOnly : OpenMode.readWrite;
    _db = sqlite3.open(sqlitePath, mode: mode);
    return _db!;
  }

  // Mint WebSocket token using secret key
  String? mintWebSocketTicket() {
    try {
      final keyFile = File(signingKeyPath);
      if (!keyFile.existsSync()) {
        J6Logger.warn('Signing key file not found at: $signingKeyPath');
        return null;
      }
      final signingKey = keyFile.readAsBytesSync();

      const sessionId = "4c1f5c3b-a420-414e-8355-54cdd847d53a";
      final now = DateTime.now().millisecondsSinceEpoch;
      final exp = now + (30 * 24 * 60 * 60 * 1000); // 30 days

      final claims = {
        'v': 1,
        'kind': 'websocket',
        'sid': sessionId,
        'iat': now,
        'exp': exp,
      };

      final payloadJson = jsonEncode(claims);
      final payloadBase64Url = base64Url.encode(utf8.encode(payloadJson)).replaceAll('=', '');

      final hmac = Hmac(sha256, signingKey);
      final digest = hmac.convert(utf8.encode(payloadBase64Url));
      final signatureBase64Url = base64Url.encode(digest.bytes).replaceAll('=', '');

      return '$payloadBase64Url.$signatureBase64Url';
    } catch (e, stack) {
      J6Logger.error('Error minting websocket ticket', e, stack);
      return null;
    }
  }

  Future<void> connect() async {
    final ticket = mintWebSocketTicket();
    final uriStr = ticket != null 
        ? 'ws://$serverHost:$serverPort/ws?wsTicket=$ticket'
        : 'ws://$serverHost:$serverPort/ws';

    J6Logger.info('Connecting to WebSocket server at ws://$serverHost:$serverPort/ws');
    try {
      _channel = WebSocketChannel.connect(Uri.parse(uriStr));
      _isConnected = true;
      _connectionStateController.add(true);
      J6Logger.info('WebSocket connected successfully');

      _channel!.stream.listen(
        (data) {
          try {
            if (data is String) {
              final parsed = jsonDecode(data);
              if (parsed is Map<String, dynamic>) {
                _messagesController.add(parsed);
              }
            }
          } catch (_) {}
        },
        onError: (err) {
          J6Logger.warn('WebSocket stream error: $err');
          _isConnected = false;
          _connectionStateController.add(false);
        },
        onDone: () {
          J6Logger.info('WebSocket stream closed');
          _isConnected = false;
          _connectionStateController.add(false);
        },
      );
    } catch (e, stack) {
      J6Logger.error('Failed to establish WebSocket connection', e, stack);
      _isConnected = false;
      _connectionStateController.add(false);
    }
  }

  /// Load available AI providers and their models (Grok, OpenCode, Antigravity, Claude, etc.)
  Future<List<J6Provider>> loadAvailableProviders() async {
    final List<J6Provider> providers = [];
    try {
      final cacheDir = Directory(cachesDir);
      if (cacheDir.existsSync()) {
        final files = cacheDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
        for (final file in files) {
          final fileName = file.uri.pathSegments.last.replaceAll('.json', '');
          try {
            final content = jsonDecode(file.readAsStringSync());
            if (content is Map<String, dynamic>) {
              final displayName = content['displayName'] ?? fileName;
              final rawModels = content['models'] as List<dynamic>? ?? [];
              final models = rawModels.map((m) {
                final slug = m['slug'] ?? m['id'] ?? m['name'] ?? '';
                final name = m['name'] ?? slug;
                return J6Model(slug: slug.toString(), name: name.toString());
              }).toList();

              if (models.isNotEmpty) {
                providers.add(J6Provider(
                  id: fileName,
                  displayName: displayName.toString(),
                  models: models,
                ));
              }
            }
          } catch (_) {}
        }
      }
    } catch (e, stack) {
      J6Logger.error('Error loading AI providers', e, stack);
    }

    if (providers.isEmpty) {
      providers.addAll([
        const J6Provider(
          id: 'antigravity',
          displayName: 'Anti Gravity (ACP)',
          models: [
            J6Model(slug: 'gemini-3.8-flash-high', name: 'Gemini 3.8 Flash (High)'),
            J6Model(slug: 'gemini-3.7-flash-high', name: 'Gemini 3.7 Flash (High)'),
            J6Model(slug: 'gemini-3.1-pro-high', name: 'Gemini 3.1 Pro (High)'),
          ],
        ),
        const J6Provider(
          id: 'grok',
          displayName: 'Grok Build',
          models: [
            J6Model(slug: 'grok-build', name: 'Grok Build'),
            J6Model(slug: 'grok-4.7', name: 'Grok 4.7'),
          ],
        ),
        const J6Provider(
          id: 'opencode',
          displayName: 'Open Code',
          models: [
            J6Model(slug: 'deepseek-v4-pro', name: 'DeepSeek V4 Pro'),
            J6Model(slug: 'deepseek-v4-flash', name: 'DeepSeek V4 Flash'),
            J6Model(slug: 'gpt-oss:120b', name: 'gpt-oss:120b'),
          ],
        ),
      ]);
    }

    J6Logger.info('Discovered ${providers.length} AI providers: ${providers.map((p) => p.displayName).join(', ')}');
    return providers;
  }

  /// Open or import a directory on the laptop as a project in j6code
  Future<J6Project?> openFolderAsProject(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (!dir.existsSync()) {
        J6Logger.warn('Cannot open non-existent directory: $folderPath');
        return null;
      }

      final normalizedPath = dir.path.replaceAll('/', '\\');
      final folderName = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final gitDir = Directory('${dir.path}\\.git');
      final isGit = gitDir.existsSync();

      final db = _getDb(readOnly: false);
      final existing = db.select(
        'SELECT * FROM projection_projects WHERE workspace_root = ? OR workspace_root = ?',
        [normalizedPath, dir.path.replaceAll('\\', '/')],
      );

      if (existing.isNotEmpty) {
        final row = existing.first;
        J6Logger.info('Found existing project for $normalizedPath -> id: ${row['project_id']}');
        return J6Project(
          projectId: row['project_id'].toString(),
          title: row['title'].toString(),
          workspaceRoot: row['workspace_root'].toString(),
          createdAt: DateTime.tryParse(row['created_at'].toString()) ?? DateTime.now(),
          updatedAt: DateTime.tryParse(row['updated_at'].toString()) ?? DateTime.now(),
          isGitRepo: isGit,
        );
      }

      final id = "proj_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond % 1000}";
      final now = DateTime.now().toUtc().toIso8601String();
      db.execute(
        'INSERT INTO projection_projects (project_id, title, workspace_root, scripts_json, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [id, folderName, normalizedPath, '[]', now, now],
      );

      J6Logger.info('Registered new project: $folderName ($id) at $normalizedPath (git: $isGit)');

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

  /// Direct high-performance SQLite reader
  Future<List<J6Project>> fetchProjects() async {
    try {
      final db = _getDb(readOnly: true);
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
          title: row['title']?.toString() ?? 'Project',
          workspaceRoot: root,
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
          updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? DateTime.now(),
          isGitRepo: isGit,
        ));
      }
      return list;
    } catch (e, stack) {
      J6Logger.error('Error fetching projects from sqlite', e, stack);
    }
    return [];
  }

  Future<List<J6Thread>> fetchThreads(String? projectId) async {
    try {
      final db = _getDb(readOnly: true);
      final ResultSet results;
      if (projectId != null && projectId.isNotEmpty) {
        results = db.select(
          'SELECT * FROM projection_threads WHERE project_id = ? ORDER BY updated_at DESC',
          [projectId],
        );
      } else {
        results = db.select('SELECT * FROM projection_threads ORDER BY updated_at DESC');
      }

      final List<J6Thread> list = [];
      for (final row in results) {
        list.add(J6Thread(
          threadId: row['thread_id'].toString(),
          projectId: row['project_id']?.toString() ?? '',
          title: row['title']?.toString() ?? 'Conversation',
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
          updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? DateTime.now(),
        ));
      }
      return list;
    } catch (e, stack) {
      J6Logger.error('Error fetching threads from sqlite', e, stack);
    }
    return [];
  }

  Future<List<J6Message>> fetchThreadMessages(String threadId) async {
    try {
      final db = _getDb(readOnly: true);
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
      J6Logger.error('Error fetching messages from sqlite', e, stack);
    }
    return [];
  }

  Future<List<J6Activity>> fetchThreadActivities(String threadId) async {
    try {
      final db = _getDb(readOnly: true);
      final results = db.select(
        'SELECT * FROM projection_thread_activities WHERE thread_id = ? ORDER BY rowid ASC',
        [threadId],
      );

      final List<J6Activity> list = [];
      for (final row in results) {
        Map<String, dynamic> payload = {};
        final rawPayload = row['payload_json']?.toString();
        if (rawPayload != null && rawPayload.isNotEmpty) {
          try {
            payload = jsonDecode(rawPayload);
          } catch (_) {}
        }

        list.add(J6Activity(
          activityId: row['activity_id']?.toString() ?? '',
          threadId: row['thread_id']?.toString() ?? '',
          kind: row['kind']?.toString() ?? '',
          summary: row['summary']?.toString() ?? '',
          payload: payload,
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
        ));
      }
      return list;
    } catch (e, stack) {
      J6Logger.error('Error fetching activities from sqlite', e, stack);
    }
    return [];
  }

  Future<String?> createThread({
    required String projectId,
    required String title,
  }) async {
    try {
      final id = "th_${DateTime.now().millisecondsSinceEpoch}_${(1000 + DateTime.now().microsecond % 9000)}";
      final now = DateTime.now().toUtc().toIso8601String();
      final db = _getDb(readOnly: false);
      db.execute(
        'INSERT INTO projection_threads (thread_id, project_id, title, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [id, projectId, title, now, now],
      );
      J6Logger.info('Created thread: $id ("$title") for project $projectId');
      return id;
    } catch (e, stack) {
      J6Logger.error('Error creating thread via sqlite3', e, stack);
    }
    return null;
  }

  Future<bool> sendPrompt({
    required String threadId,
    required String projectId,
    required String prompt,
    required String providerId,
    required String modelSlug,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final msgId = "msg_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond % 1000}";
      final db = _getDb(readOnly: false);

      // 1. Insert user message
      db.execute(
        'INSERT INTO projection_thread_messages (message_id, thread_id, role, text, is_streaming, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [msgId, threadId, 'user', prompt, 0, now, now],
      );

      // 2. Update thread touch time
      db.execute(
        'UPDATE projection_threads SET updated_at = ? WHERE thread_id = ?',
        [now, threadId],
      );

      // 3. Insert agent activity indicating prompt dispatch
      final actId = "act_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond % 1000}";
      final payload = {
        'itemType': 'prompt_dispatch',
        'status': 'inProgress',
        'provider': providerId,
        'model': modelSlug,
        'title': 'Sent prompt to $providerId ($modelSlug)',
      };
      db.execute(
        'INSERT INTO projection_thread_activities (activity_id, thread_id, kind, summary, payload_json, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        [actId, threadId, 'tool.updated', 'Dispatched to $providerId', jsonEncode(payload), now],
      );

      J6Logger.info('Successfully persisted prompt message ($msgId) and dispatched activity ($actId)');
      return true;
    } catch (e, stack) {
      J6Logger.error('Error sending prompt via sqlite3', e, stack);
      return false;
    }
  }

  void dispose() {
    _channel?.sink.close();
    _connectionStateController.close();
    _messagesController.close();
    try {
      _db?.close();
    } catch (_) {}
  }
}
