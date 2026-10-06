import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:j6code/services/j6_server_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('J6ServerService uses isolated ~/.j6code and initializes schema', () async {
    final service = J6ServerService();
    expect(J6ServerService.j6Dir.endsWith('.j6code'), isTrue);
    expect(J6ServerService.sqlitePath.contains('.j6code'), isTrue);
    expect(J6ServerService.sqlitePath.contains('.t3'), isFalse);

    await service.connect();
    expect(service.isConnected, isTrue);

    // Verify database file exists in .j6code
    final dbFile = File(J6ServerService.sqlitePath);
    expect(dbFile.existsSync(), isTrue);

    // Test project creation
    final testPath = Directory.current.path;
    final project = await service.openFolderAsProject(testPath);
    expect(project, isNotNull);

    final projects = await service.fetchProjects();
    expect(projects.any((p) => p.projectId == project!.projectId), isTrue);

    // Test thread creation
    final threadId = await service.createThread(
      projectId: project!.projectId,
      title: 'Independent Test Thread',
    );
    expect(threadId, isNotNull);

    final threads = await service.fetchThreads(project.projectId);
    expect(threads.any((t) => t.threadId == threadId), isTrue);

    // Test provider detection
    final providers = await service.loadAvailableProviders();
    expect(providers.isNotEmpty, isTrue);

    service.dispose();
  });
}
