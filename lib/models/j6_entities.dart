import 'dart:convert';

/// Agent permission policy (port of t3code's RuntimeMode / runtimeModeConfig).
enum RuntimeMode {
  approvalRequired('approval-required', 'Supervised', 'Ask before commands and file changes.'),
  autoAcceptEdits('auto-accept-edits', 'Auto-accept edits', 'Auto-approve edits, ask before other actions.'),
  auto('auto', 'Auto', 'Supported providers approve routine actions; others still ask.'),
  fullAccess('full-access', 'Full access', 'Allow commands and edits without prompts.');

  const RuntimeMode(this.id, this.label, this.description);
  final String id;
  final String label;
  final String description;

  static RuntimeMode fromId(String? id) =>
      RuntimeMode.values.where((m) => m.id == id).firstOrNull ?? RuntimeMode.fullAccess;
}

class J6Project {
  final String projectId;
  final String title;
  final String workspaceRoot;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isGitRepo;

  J6Project({
    required this.projectId,
    required this.title,
    required this.workspaceRoot,
    required this.createdAt,
    required this.updatedAt,
    this.isGitRepo = false,
  });

  factory J6Project.fromJson(Map<String, dynamic> json) {
    return J6Project(
      projectId: json['project_id'] ?? '',
      title: json['title'] ?? 'Untitled Project',
      workspaceRoot: json['workspace_root'] ?? '',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      isGitRepo: json['is_git_repo'] == true || json['is_git_repo'] == 1,
    );
  }
}

class J6Thread {
  final String threadId;
  final String projectId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? modelSelectionJson;

  /// t3code settlement state: null (automatic), 'settled' or 'active'.
  final String? settledOverride;
  final DateTime? settledAt;
  final DateTime? unsettledAt;

  /// A run is in flight (streaming assistant message); such threads can't be settled.
  final bool isRunning;

  /// Permission policy for agent turns in this thread.
  final RuntimeMode runtimeMode;

  J6Thread({
    required this.threadId,
    required this.projectId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.modelSelectionJson,
    this.settledOverride,
    this.settledAt,
    this.unsettledAt,
    this.isRunning = false,
    this.runtimeMode = RuntimeMode.fullAccess,
  });

  /// Explicitly settled, or automatically settled (settled_at set without an override).
  bool get isSettled => settledOverride == 'settled' || (settledOverride == null && settledAt != null);

  /// "How long ago did this wrap up" — sort key and time label for settled
  /// rows (port of t3code's resolveSettledThreadTimestamp).
  DateTime get settledTimestamp => settledAt ?? updatedAt;

  factory J6Thread.fromJson(Map<String, dynamic> json) {
    return J6Thread(
      threadId: json['thread_id'] ?? '',
      projectId: json['project_id'] ?? '',
      title: json['title'] ?? 'Untitled Conversation',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      modelSelectionJson: json['model_selection_json']?.toString(),
      settledOverride: json['settled_override']?.toString(),
      settledAt: DateTime.tryParse(json['settled_at']?.toString() ?? ''),
      unsettledAt: DateTime.tryParse(json['unsettled_at']?.toString() ?? ''),
    );
  }
}

/// A file or image attached to a user message (t3code ChatAttachment).
class J6Attachment {
  final String name;
  final String path;
  final String mimeType;
  final int sizeBytes;

  const J6Attachment({required this.name, required this.path, required this.mimeType, required this.sizeBytes});

  bool get isImage => mimeType.startsWith('image/');

  Map<String, dynamic> toJson() => {'name': name, 'path': path, 'mimeType': mimeType, 'sizeBytes': sizeBytes};

  factory J6Attachment.fromJson(Map<String, dynamic> json) => J6Attachment(
        name: json['name']?.toString() ?? 'file',
        path: json['path']?.toString() ?? '',
        mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      );

  static List<J6Attachment> listFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        return parsed.whereType<Map>().map((m) => J6Attachment.fromJson(m.cast<String, dynamic>())).toList();
      }
    } catch (_) {}
    return const [];
  }

  static String mimeTypeFor(String path) {
    final ext = path.split('.').last.toLowerCase();
    const map = {
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'bmp': 'image/bmp',
      'svg': 'image/svg+xml',
      'pdf': 'application/pdf',
      'json': 'application/json',
      'md': 'text/markdown',
      'txt': 'text/plain',
    };
    return map[ext] ?? 'application/octet-stream';
  }
}

class J6Message {
  final String messageId;
  final String threadId;
  final String role; // 'user', 'assistant', 'reasoning'
  final String text;
  final bool isStreaming;
  final DateTime createdAt;
  final List<J6Attachment> attachments;

  J6Message({
    required this.messageId,
    required this.threadId,
    required this.role,
    required this.text,
    required this.isStreaming,
    required this.createdAt,
    this.attachments = const [],
  });

  factory J6Message.fromJson(Map<String, dynamic> json) {
    return J6Message(
      messageId: json['message_id'] ?? '',
      threadId: json['thread_id'] ?? '',
      role: json['role'] ?? 'user',
      text: json['text'] ?? '',
      isStreaming: json['is_streaming'] == 1 || json['is_streaming'] == true,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      attachments: J6Attachment.listFromJson(json['attachments_json']?.toString()),
    );
  }
}

class J6Activity {
  final String activityId;
  final String threadId;
  final String kind;
  final String summary;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  J6Activity({
    required this.activityId,
    required this.threadId,
    required this.kind,
    required this.summary,
    required this.payload,
    required this.createdAt,
  });

  factory J6Activity.fromJson(Map<String, dynamic> json) {
    return J6Activity(
      activityId: json['activity_id'] ?? '',
      threadId: json['thread_id'] ?? '',
      kind: json['kind'] ?? '',
      summary: json['summary'] ?? '',
      payload: json['payload'] is Map ? json['payload'] : {},
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class J6Model {
  final String slug;
  final String name;

  J6Model({required this.slug, required this.name});
}

class J6Provider {
  final String id;
  final String name;
  final List<J6Model> models;

  J6Provider({
    required this.id,
    required this.name,
    required this.models,
  });

  String get displayName => name;
}
