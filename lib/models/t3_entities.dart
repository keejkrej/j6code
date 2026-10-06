import 'dart:convert';

class T3Project {
  final String projectId;
  final String title;
  final String workspaceRoot;
  final DateTime createdAt;
  final DateTime updatedAt;

  T3Project({
    required this.projectId,
    required this.title,
    required this.workspaceRoot,
    required this.createdAt,
    required this.updatedAt,
  });

  factory T3Project.fromJson(Map<String, dynamic> json) {
    return T3Project(
      projectId: json['project_id'] ?? '',
      title: json['title'] ?? 'Untitled Project',
      workspaceRoot: json['workspace_root'] ?? '',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class T3Thread {
  final String threadId;
  final String projectId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  T3Thread({
    required this.threadId,
    required this.projectId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory T3Thread.fromJson(Map<String, dynamic> json) {
    return T3Thread(
      threadId: json['thread_id'] ?? '',
      projectId: json['project_id'] ?? '',
      title: json['title'] ?? 'Untitled Conversation',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class T3Message {
  final String messageId;
  final String threadId;
  final String role; // 'user', 'assistant', 'reasoning'
  final String text;
  final bool isStreaming;
  final DateTime createdAt;

  T3Message({
    required this.messageId,
    required this.threadId,
    required this.role,
    required this.text,
    required this.isStreaming,
    required this.createdAt,
  });

  factory T3Message.fromJson(Map<String, dynamic> json) {
    return T3Message(
      messageId: json['message_id'] ?? '',
      threadId: json['thread_id'] ?? '',
      role: json['role'] ?? 'user',
      text: json['text'] ?? '',
      isStreaming: json['is_streaming'] == 1 || json['is_streaming'] == true,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class T3Activity {
  final String activityId;
  final String threadId;
  final String kind;
  final String summary;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  T3Activity({
    required this.activityId,
    required this.threadId,
    required this.kind,
    required this.summary,
    required this.payload,
    required this.createdAt,
  });

  factory T3Activity.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> p = {};
    if (json['payload_json'] != null) {
      try {
        p = jsonDecode(json['payload_json']);
      } catch (_) {}
    }
    return T3Activity(
      activityId: json['activity_id'] ?? '',
      threadId: json['thread_id'] ?? '',
      kind: json['kind'] ?? '',
      summary: json['summary'] ?? '',
      payload: p,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}
