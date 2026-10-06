import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/t3_entities.dart';
import '../services/t3_server_service.dart';

class SidebarWidget extends StatelessWidget {
  final List<T3Project> projects;
  final List<T3Thread> threads;
  final String? selectedProjectId;
  final String? selectedThreadId;
  final Function(String projectId) onSelectProject;
  final Function(String threadId) onSelectThread;
  final VoidCallback onNewThread;
  final bool isServerConnected;

  const SidebarWidget({
    super.key,
    required this.projects,
    required this.threads,
    required this.selectedProjectId,
    required this.selectedThreadId,
    required this.onSelectProject,
    required this.onSelectThread,
    required this.onNewThread,
    required this.isServerConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App Header & Branding
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Text(
                      'T3',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'T3 Code',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'Flutter Desktop',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Connection indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isServerConnected ? AppTheme.success.withAlpha(30) : AppTheme.error.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isServerConnected ? AppTheme.success : AppTheme.error,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isServerConnected ? AppTheme.success : AppTheme.error,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isServerConnected ? 'LIVE' : 'OFFLINE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isServerConnected ? AppTheme.success : AppTheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // New Thread Button
          Padding(
            padding: const EdgeInsets.all(12),
            child: InkWell(
              onTap: onNewThread,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: AppTheme.accentSubtle,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.accent.withAlpha(70)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 16, color: AppTheme.accent),
                    SizedBox(width: 8),
                    Text(
                      'New Thread',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Workspace / Project Selector
          if (projects.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Text(
                    'PROJECT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    projects.first.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
          ],

          // Threads List Header
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'THREADS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: AppTheme.textMuted,
              ),
            ),
          ),

          // Thread list view
          Expanded(
            child: threads.isEmpty
                ? const Center(
                    child: Text(
                      'No threads yet',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: threads.length,
                    itemBuilder: (context, index) {
                      final thread = threads[index];
                      final isSelected = thread.threadId == selectedThreadId;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.surfaceHover : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: isSelected
                              ? Border.all(color: AppTheme.accent.withAlpha(60), width: 1)
                              : null,
                        ),
                        child: ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          leading: Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 16,
                            color: isSelected ? AppTheme.accent : AppTheme.textMuted,
                          ),
                          title: Text(
                            thread.title.isNotEmpty ? thread.title : 'Untitled Thread',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                            ),
                          ),
                          subtitle: Text(
                            '${thread.updatedAt.hour.toString().padLeft(2, '0')}:${thread.updatedAt.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          onTap: () => onSelectThread(thread.threadId),
                        ),
                      );
                    },
                  ),
          ),

          // Footer info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Row(
              children: [
                const Icon(Icons.dns_outlined, size: 14, color: AppTheme.textMuted),
                const SizedBox(width: 8),
                Text(
                  'Port ${T3ServerService.serverPort}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                const Spacer(),
                const Text(
                  'v0.0.45',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
