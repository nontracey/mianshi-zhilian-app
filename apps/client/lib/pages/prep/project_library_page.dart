import 'package:flutter/material.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/pages/practice/project_dig_page.dart';

class ProjectLibraryPage extends StatefulWidget {
  const ProjectLibraryPage({super.key});

  @override
  State<ProjectLibraryPage> createState() => _ProjectLibraryPageState();
}

class _ProjectLibraryPageState extends State<ProjectLibraryPage> {
  final List<Map<String, dynamic>> _projects = [];
  final _storage = StorageService();
  

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final data = await _storage.loadJsonList('project_library');
    setState(() {
      _projects.clear();
      _projects.addAll(data);
    });
  }

  Future<void> _saveProjects() async {
    await _storage.saveJsonList('project_library', _projects);
  }

  Future<void> _addProject(Map<String, dynamic> project) async {
    project['id'] = DateTime.now().millisecondsSinceEpoch.toString();
    project['createdAt'] = DateTime.now().toIso8601String();
    setState(() => _projects.add(project));
    await _saveProjects();
  }

  Future<void> _deleteProject(int index) async {
    setState(() => _projects.removeAt(index));
    await _saveProjects();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('项目深挖库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _navigateToAddProject(context),
          ),
        ],
      ),
      body: _projects.isEmpty
          ? _buildEmptyState(context, isDark)
          : _buildProjectList(context, isDark),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToAddProject(context),
        icon: const Icon(Icons.add),
        label: const Text('添加项目'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              '还没有保存的项目',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '添加你的项目经历，方便面试前快速复习',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _navigateToAddProject(context),
              icon: const Icon(Icons.add),
              label: const Text('添加项目'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectList(BuildContext context, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _projects.length,
      itemBuilder: (context, index) {
        final project = _projects[index];
        return _buildProjectCard(context, index, project, isDark);
      },
    );
  }

  Widget _buildProjectCard(
    BuildContext context,
    int index,
    Map<String, dynamic> project,
    bool isDark,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF263238) : const Color(0xFFE8E8E8),
        ),
      ),
      child: InkWell(
        onTap: () => _viewProjectDetail(context, index, project),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.folder,
                      color: AppColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project['name'] ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${project['role']} · ${project['scale']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : const Color(0xFF666666),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton(
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('编辑'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'practice',
                        child: Row(
                          children: [
                            Icon(Icons.play_arrow, size: 18),
                            SizedBox(width: 8),
                            Text('深挖练习'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('删除', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) => _handleMenuAction(context, index, project, value),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 技术栈
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: (project['techStack']?.split(', ') ?? []).map<Widget>((tech) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tech,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.accent,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // STAR 摘要
              _buildStarSummary('S', project['background'], isDark),
              _buildStarSummary('T', project['task'], isDark),
              _buildStarSummary('A', project['action'], isDark),
              _buildStarSummary('R', project['result'], isDark),
              const SizedBox(height: 8),

              // 更新时间
              Text(
                '更新于 ${project['updatedAt'] ?? ''}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : const Color(0xFF999999),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStarSummary(String label, String? content, bool isDark) {
    if (content == null || content.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.warning,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              content,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : const Color(0xFF666666),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(
    BuildContext context,
    int index,
    Map<String, dynamic> project,
    String action,
  ) {
    switch (action) {
      case 'edit':
        _navigateToEditProject(context, index, project);
        break;
      case 'practice':
        _startProjectDig(context, project);
        break;
      case 'delete':
        _deleteProject(index);
        break;
    }
  }

  void _navigateToAddProject(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProjectDigPage(),
      ),
    ).then((result) {
      if (result != null && result is Map<String, dynamic>) {
        _addProject(result);
      }
    });
  }

  void _navigateToEditProject(
    BuildContext context,
    int index,
    Map<String, dynamic> project,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProjectDigPage(),
      ),
    ).then((result) {
      if (result != null && result is Map<String, dynamic>) {
        setState(() {
          _projects[index] = {..._projects[index], ...result};
        });
        _saveProjects();
      }
    });
  }

  void _viewProjectDetail(
    BuildContext context,
    int index,
    Map<String, dynamic> project,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scrollController) => _buildProjectDetailSheet(
          ctx,
          project,
          scrollController,
        ),
      ),
    );
  }

  Widget _buildProjectDetailSheet(
    BuildContext context,
    Map<String, dynamic> project,
    ScrollController scrollController,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: ListView(
        controller: scrollController,
        children: [
          // 拖动指示器
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 项目名称
          Text(
            project['name'] ?? '',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),

          // 角色和规模
          Text(
            '${project['role']} · ${project['scale']}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),

          // 技术栈
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: (project['techStack']?.split(', ') ?? []).map<Widget>((tech) {
              return Chip(
                label: Text(tech, style: const TextStyle(fontSize: 12)),
                backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                labelStyle: const TextStyle(color: AppColors.accent),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // STAR 详情
          _buildStarDetail('Situation（背景）', project['background']),
          _buildStarDetail('Task（任务）', project['task']),
          _buildStarDetail('Action（行动）', project['action']),
          _buildStarDetail('Result（结果）', project['result']),
          const SizedBox(height: 20),

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('关闭'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _startProjectDig(context, project);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('深挖练习'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStarDetail(String title, String? content) {
    if (content == null || content.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),
        ],
      ),
    );
  }

  void _startProjectDig(BuildContext context, Map<String, dynamic> project) {
    final questions = [
      '这个项目的核心技术难点是什么？',
      '为什么选择 ${project['techStack'] ?? '这个'} 技术栈？',
      '遇到过什么线上问题？如何解决的？',
      '如果重新设计，你会怎么改进？',
      '你在项目中的最大贡献是什么？',
      '这个项目的性能指标是多少？如何优化的？',
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('项目深挖练习'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('项目：${project['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (project['techStack'] != null) ...[
                const SizedBox(height: 4),
                Text('技术栈：${project['techStack']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
              const SizedBox(height: 16),
              const Text('面试官可能会问：', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...questions.map((q) => _buildDigQuestion(q)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // 显示提示，让用户自己练习
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('请对着这些问题进行口头练习，记录你的回答'),
                  duration: Duration(seconds: 3),
                ),
              );
            },
            child: const Text('开始练习'),
          ),
        ],
      ),
    );
  }

  Widget _buildDigQuestion(String question) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(question)),
        ],
      ),
    );
  }
}
