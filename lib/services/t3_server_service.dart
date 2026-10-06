import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/t3_entities.dart';

class T3ServerService {
  static const int serverPort = 3773;
  static const String serverHost = '127.0.0.1';
  static final String userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\ctyja';
  static final String t3Dir = '$userProfile\\.t3';
  static final String sqlitePath = '$t3Dir\\userdata\\state.sqlite';
  static final String signingKeyPath = '$t3Dir\\userdata\\secrets\\server-signing-key.bin';

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectionStateChanged => _connectionStateController.stream;

  final _messagesController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onMessageReceived => _messagesController.stream;

  Timer? _pollingTimer;

  // Mint WebSocket token using secret key
  String? mintWebSocketTicket() {
    try {
      final keyFile = File(signingKeyPath);
      if (!keyFile.existsSync()) return null;
      final signingKey = keyFile.readAsBytesSync();

      // Look up active session or generate standard payload
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
      if (kDebugMode) {
        print("Error minting websocket ticket: $e");
      }
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

  // Fast reader for SQLite via node helper script or direct process query
  Future<List<T3Project>> fetchProjects() async {
    try {
      final script = '''
const { DatabaseSync } = require("node:sqlite");
const db = new DatabaseSync("$sqlitePath".replace(/\\\\/g, "/"), { readOnly: true });
console.log(JSON.stringify(db.prepare("SELECT * FROM projection_projects ORDER BY updated_at DESC").all()));
''';
      final res = await Process.run('node', ['-e', script]);
      if (res.exitCode == 0) {
        final list = jsonDecode(res.stdout.toString().trim()) as List<dynamic>;
        return list.map((item) => T3Project.fromJson(Map<String, dynamic>.from(item))).toList();
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching projects: $e");
    }
    return [];
  }

  Future<List<T3Thread>> fetchThreads(String? projectId) async {
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
        return list.map((item) => T3Thread.fromJson(Map<String, dynamic>.from(item))).toList();
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching threads: $e");
    }
    return [];
  }

  Future<List<T3Message>> fetchThreadMessages(String threadId) async {
    try {
      final script = '''
const { DatabaseSync } = require("node:sqlite");
const db = new DatabaseSync("$sqlitePath".replace(/\\\\/g, "/"), { readOnly: true });
console.log(JSON.stringify(db.prepare("SELECT * FROM projection_thread_messages WHERE thread_id = '$threadId' ORDER BY created_at ASC").all()));
''';
      final res = await Process.run('node', ['-e', script]);
      if (res.exitCode == 0) {
        final list = jsonDecode(res.stdout.toString().trim()) as List<dynamic>;
        return list.map((item) => T3Message.fromJson(Map<String, dynamic>.from(item))).toList();
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching messages: $e");
    }
    return [];
  }

  Future<List<T3Activity>> fetchThreadActivities(String threadId) async {
    try {
      final script = '''
const { DatabaseSync } = require("node:sqlite");
const db = new DatabaseSync("$sqlitePath".replace(/\\\\/g, "/"), { readOnly: true });
console.log(JSON.stringify(db.prepare("SELECT * FROM projection_thread_activities WHERE thread_id = '$threadId' ORDER BY sequence ASC").all()));
''';
      final res = await Process.run('node', ['-e', script]);
      if (res.exitCode == 0) {
        final list = jsonDecode(res.stdout.toString().trim()) as List<dynamic>;
        return list.map((item) => T3Activity.fromJson(Map<String, dynamic>.from(item))).toList();
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching activities: $e");
    }
    return [];
  }

  Future<bool> sendPrompt({
    required String threadId,
    required String projectId,
    required String prompt,
  }) async {
    try {
      // Direct command dispatch to the orchestration engine
      final script = '''
const { DatabaseSync } = require("node:sqlite");
const db = new DatabaseSync("$sqlitePath".replace(/\\\\/g, "/"));
const now = new Date().toISOString();
const id = "msg_" + Math.random().toString(36).slice(2);
db.prepare("INSERT INTO projection_thread_messages (message_id, thread_id, role, text, is_streaming, created_at, updated_at) VALUES (?, ?, 'user', ?, 0, ?, ?)").run(id, "$threadId", ${jsonEncode(prompt)}, now, now);
db.prepare("UPDATE projection_threads SET updated_at = ? WHERE thread_id = ?").run(now, "$threadId");
console.log("SUCCESS");
''';
      final res = await Process.run('node', ['-e', script]);
      return res.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _pollingTimer?.cancel();
    _channel?.sink.close();
    _connectionStateController.close();
    _messagesController.close();
  }
}
