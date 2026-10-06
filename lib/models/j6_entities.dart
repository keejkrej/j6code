
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

  J6Thread({
    required this.threadId,
    required this.projectId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.modelSelectionJson,
  });

  factory J6Thread.fromJson(Map<String, dynamic> json) {
    return J6Thread(
      threadId: json['thread_id'] ?? '',
      projectId: json['project_id'] ?? '',
      title: json['title'] ?? 'Untitled Conversation',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      modelSelectionJson: json['model_selection_json']?.toString(),
    );
  }
}

class J6Message {
  final String messageId;
  final String threadId;
  final String role; // 'user', 'assistant', 'reasoning'
  final String text;
  final bool isStreaming;
  final DateTime createdAt;

  J6Message({
    required this.messageId,
    required this.threadId,
    required this.role,
    required this.text,
    required this.isStreaming,
    required this.createdAt,
  });

  factory J6Message.fromJson(Map<String, dynamic> json) {
    return J6Message(
      messageId: json['message_id'] ?? '',
      threadId: json['thread_id'] ?? '',
      role: json['role'] ?? 'user',
      text: json['text'] ?? '',
      isStreaming: json['is_streaming'] == 1 || json['is_streaming'] == true,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
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
