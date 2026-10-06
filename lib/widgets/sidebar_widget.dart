import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/j6_entities.dart';

class SidebarWidget extends StatelessWidget {
  final List<J6Project> projects;
  final List<J6Thread> threads;
  final String? selectedProjectId;
  final String? selectedThreadId;
  final Function(String projectId) onSelectProject;
  final Function(String threadId) onSelectThread;
  final VoidCallback onNewThread;
  final VoidCallback onOpenFolder;
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
    required this.onOpenFolder,
    required this.isServerConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 290,
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
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withAlpha(50),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'J6',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
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
                      'j6code',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'AI Workspace Client',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Connection indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: isServerConnected ? AppTheme.success.withAlpha(25) : AppTheme.error.withAlpha(25),
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
                        isServerConnected ? 'CONNECTED' : 'STANDALONE',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: isServerConnected ? AppTheme.success : AppTheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Action Buttons: Open Folder / Repo + New Thread
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onOpenFolder,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceSubtle,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open_rounded, size: 15, color: AppTheme.textSecondary),
                          SizedBox(width: 6),
                          Text(
                            'Open Repo',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: onNewThread,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.accentSubtle,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.accent.withAlpha(70)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, size: 15, color: AppTheme.accent),
                          SizedBox(width: 6),
                          Text(
                            'New Thread',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Workspace / Projects Dropdown / List
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'ACTIVE REPOSITORY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: AppTheme.textMuted,
                  ),
                ),
                const Spacer(),
                Text(
                  '${projects.length} loaded',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),

          if (projects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHover,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedProjectId ?? (projects.isNotEmpty ? projects.first.projectId : null),
                    dropdownColor: AppTheme.surfaceHover,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppTheme.textMuted),
                    items: projects.map((p) {
                      return DropdownMenuItem<String>(
                        value: p.projectId,
                        child: Row(
                          children: [
                            Icon(
                              p.isGitRepo ? Icons.alt_route_rounded : Icons.folder_rounded,
                              size: 15,
                              color: p.isGitRepo ? AppTheme.accent : AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                p.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) onSelectProject(val);
                    },
                  ),
                ),
              ),
            ),

          const Divider(height: 20),

          // Threads List Header
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'CONVERSATIONS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: AppTheme.textMuted,
              ),
            ),
          ),

          // Thread list view
          Expanded(
            child: threads.isEmpty
                ? const Center(
                    child: Text(
                      'No conversations yet\nClick New Thread to begin',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.5),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: threads.length,
                    itemBuilder: (context, index) {
                      final thread = threads[index];
                      final isSelected = thread.threadId == selectedThreadId;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 3),
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
                            size: 15,
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
            child: const Row(
              children: [
                Icon(Icons.terminal_rounded, size: 14, color: AppTheme.textMuted),
                SizedBox(width: 8),
                Text(
                  'j6code v1.0.0',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                Spacer(),
                Text(
                  'Desktop x64',
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
