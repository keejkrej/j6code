import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/j6_entities.dart';

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

  // Mint WebSocket token using secret key
  String? mintWebSocketTicket() {
    try {
      final keyFile = File(signingKeyPath);
      if (!keyFile.existsSync()) return null;
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
    } catch (e) {
      if (kDebugMode) print("Error minting websocket ticket: $e");
      return null;
    }
  }

  Future<void> connect() async {
    final ticket = mintWebSocketTicket();
    final uriStr = ticket != null 
        ? 'ws://$serverHost:$serverPort/ws?wsTicket=$ticket'
        : 'ws://$serverHost:$serverPort/ws';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(uriStr));
      _isConnected = true;
      _connectionStateController.add(true);

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
          _isConnected = false;
          _connectionStateController.add(false);
        },
        onDone: () {
          _isConnected = false;
          _connectionStateController.add(false);
        },
      );
    } catch (e) {
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
    } catch (e) {
      if (kDebugMode) print("Error loading providers: $e");
    }

    // Default fallbacks if caches are empty
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

    return providers;
  }

  /// Open or import a directory on the laptop as a project in j6code
  Future<J6Project?> openFolderAsProject(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (!dir.existsSync()) return null;

      final normalizedPath = dir.path.replaceAll('\\', '/');
      final folderName = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final gitDir = Directory('${dir.path}\\.git');
      final isGit = gitDir.existsSync();

      // Check if project exists or insert into state.sqlite
      final script = '''
const { DatabaseSync } = require("node:sqlite");
const db = new DatabaseSync("$sqlitePath".replace(/\\\\/g, "/"));
const normalized = "$normalizedPath".replace(/\\//g, "\\\\\\\\");
let p = db.prepare("SELECT * FROM projection_projects WHERE workspace_root = ? OR workspace_root = ?").get(normalized, "$normalizedPath");
if (!p) {
  const id = "proj_" + Math.random().toString(36).slice(2);
  const now = new Date().toISOString();
  db.prepare("INSERT INTO projection_projects (project_id, title, workspace_root, scripts_json, created_at, updated_at) VALUES (?, ?, ?, '[]', ?, ?)").run(id, ${jsonEncode(folderName)}, normalized, now, now);
  p = db.prepare("SELECT * FROM projection_projects WHERE project_id = ?").get(id);
}
console.log(JSON.stringify(p));
''';
      final res = await Process.run('node', ['-e', script]);
      if (res.exitCode == 0) {
        final parsed = jsonDecode(res.stdout.toString().trim());
        if (parsed != null) {
          final proj = J6Project.fromJson(Map<String, dynamic>.from(parsed));
          return J6Project(
            projectId: proj.projectId,
            title: proj.title,
            workspaceRoot: proj.workspaceRoot,
            createdAt: proj.createdAt,
            updatedAt: proj.updatedAt,
            isGitRepo: isGit,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error opening folder: $e");
    }
    return null;
  }

  /// Fast reader for SQLite via node helper
  Future<List<J6Project>> fetchProjects() async {
    try {
      final script = '''
const { DatabaseSync } = require("node:sqlite");
const fs = require("node:fs");
const db = new DatabaseSync("$sqlitePath".replace(/\\\\/g, "/"), { readOnly: true });
const projects = db.prepare("SELECT * FROM projection_projects ORDER BY updated_at DESC").all();
for (const p of projects) {
  try {
    p.is_git_repo = fs.existsSync(p.workspace_root + "/.git") || fs.existsSync(p.workspace_root + "\\\\.git");
  } catch (_) {
    p.is_git_repo = false;
  }
}
console.log(JSON.stringify(projects));
''';
      final res = await Process.run('node', ['-e', script]);
      if (res.exitCode == 0) {
        final list = jsonDecode(res.stdout.toString().trim()) as List<dynamic>;
        return list.map((item) => J6Project.fromJson(Map<String, dynamic>.from(item))).toList();
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching projects: $e");
    }
    return [];
  }

  Future<List<J6Thread>> fetchThreads(String? projectId) async {
    try {
      final condition = (projectId != null && projectId.isNotEmpty)
          ? "WHERE project_id = '$projectId'"
          : "";
      final script = '''
const { DatabaseSync } = require("node:sqlite");
const db = new DatabaseSync("$sqlitePath".replace(/\\\\/g, "/"), { readOnly: true });
console.log(JSON.stringify(db.prepare("SELECT * FROM projection_threads $condition ORDER BY updated_at DESC").all()));
''';
      final res = await Process.run('node', ['-e', script]);
      if (res.exitCode == 0) {
        final list = jsonDecode(res.stdout.toString().trim()) as List<dynamic>;
        return list.map((item) => J6Thread.fromJson(Map<String, dynamic>.from(item))).toList();
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching threads: $e");
    }
    return [];
  }

  Future<List<J6Message>> fetchThreadMessages(String threadId) async {
    try {
      final script = '''
const { DatabaseSync } = require("node:sqlite");
const db = new DatabaseSync("$sqlitePath".replace(/\\\\/g, "/"), { readOnly: true });
console.log(JSON.stringify(db.prepare("SELECT * FROM projection_thread_messages WHERE thread_id = '$threadId' ORDER BY created_at ASC").all()));
''';
      final res = await Process.run('node', ['-e', script]);
      if (res.exitCode == 0) {
        final list = jsonDecode(res.stdout.toString().trim()) as List<dynamic>;
        return list.map((item) => J6Message.fromJson(Map<String, dynamic>.from(item))).toList();
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching messages: $e");
    }
    return [];
  }

  Future<List<J6Activity>> fetchThreadActivities(String threadId) async {
    try {
      final script = '''
const { DatabaseSync } = require("node:sqlite");
const db = new DatabaseSync("$sqlitePath".replace(/\\\\/g, "/"), { readOnly: true });
console.log(JSON.stringify(db.prepare("SELECT * FROM projection_thread_activities WHERE thread_id = '$threadId' ORDER BY sequence ASC").all()));
''';
      final res = await Process.run('node', ['-e', script]);
      if (res.exitCode == 0) {
        final list = jsonDecode(res.stdout.toString().trim()) as List<dynamic>;
        return list.map((item) => J6Activity.fromJson(Map<String, dynamic>.from(item))).toList();
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching activities: $e");
    }
    return [];
  }

  Future<String?> createThread({
    required String projectId,
    required String title,
  }) async {
    try {
      final id = "th_${DateTime.now().millisecondsSinceEpoch}_${(1000 + DateTime.now().microsecond % 9000)}";
      final script = '''
const { DatabaseSync } = require("node:sqlite");
const db = new DatabaseSync("$sqlitePath".replace(/\\\\/g, "/"));
const now = new Date().toISOString();
db.prepare("INSERT INTO projection_threads (thread_id, project_id, title, created_at, updated_at) VALUES (?, ?, ?, ?, ?)").run("$id", "$projectId", ${jsonEncode(title)}, now, now);
console.log("$id");
''';
      final res = await Process.run('node', ['-e', script]);
      if (res.exitCode == 0) {
        return res.stdout.toString().trim();
      }
    } catch (e) {
      if (kDebugMode) print("Error creating thread: $e");
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
      final script = '''
const { DatabaseSync } = require("node:sqlite");
const db = new DatabaseSync("$sqlitePath".replace(/\\\\/g, "/"));
const now = new Date().toISOString();
const id = "msg_" + Math.random().toString(36).slice(2);
db.prepare("INSERT INTO projection_thread_messages (message_id, thread_id, role, text, is_streaming, created_at, updated_at) VALUES (?, ?, 'user', ?, 0, ?, ?)").run(id, "$threadId", ${jsonEncode(prompt)}, now, now);
db.prepare("UPDATE projection_threads SET updated_at = ? WHERE thread_id = ?").run(now, "$threadId");

// Insert activity record reflecting provider and model invocation
const actId = "act_" + Math.random().toString(36).slice(2);
const payload = {
  itemType: "prompt_dispatch",
  status: "inProgress",
  provider: "$providerId",
  model: "$modelSlug",
  title: "Dispatched prompt to $providerId ($modelSlug)"
};
db.prepare("INSERT INTO projection_thread_activities (activity_id, thread_id, kind, summary, payload_json, created_at) VALUES (?, ?, 'tool.updated', ?, ?, ?)").run(actId, "$threadId", "Dispatched to $providerId", JSON.stringify(payload), now);

console.log("SUCCESS");
''';
      final res = await Process.run('node', ['-e', script]);
      return res.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _channel?.sink.close();
    _connectionStateController.close();
    _messagesController.close();
  }
}
