import 'package:flutter/material.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class ProjectDigPage extends StatefulWidget {
  const ProjectDigPage({super.key});

  @override
  State<ProjectDigPage> createState() => _ProjectDigPageState();
}

class _ProjectDigPageState extends State<ProjectDigPage> {
  final _formKey = GlobalKey<FormState>();
  final _projectNameController = TextEditingController();
  final _backgroundController = TextEditingController();
  final _techDecisionController = TextEditingController();
  final _resultController = TextEditingController();
  final _difficultyController = TextEditingController();
  final _storage = StorageService();
  
  String _selectedRole = 'developer';
  String _selectedScale = 'medium';
  final List<String> _selectedTechStack = [];
  final List<Map<String, dynamic>> _savedProjects = [];
  
  
  final List<String> _techStackOptions = [
    'Java', 'Python', 'Go', 'JavaScript', 'TypeScript',
    'Spring', 'Spring Boot', 'MyBatis', 'React', 'Vue',
    'MySQL', 'Redis', 'MongoDB', 'Kafka', 'RabbitMQ',
    'Docker', 'Kubernetes', 'AWS', '微服务', '分布式',
    'Elasticsearch', 'Nginx', 'Linux', 'Git', 'Jenkins',
  ];

  final List<String> _starTemplate = [
    'Situation（背景）：项目背景、业务场景、面临的问题',
    'Task（任务）：你的职责、需要达成的目标',
    'Action（行动）：你采取的技术方案、具体实现',
    'Result（结果）：取得的成果、数据指标、经验总结',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedProjects();
  }

  Future<void> _loadSavedProjects() async {
    final data = await _storage.loadJsonList('project_dig_projects');
    setState(() {
      _savedProjects.clear();
      _savedProjects.addAll(data);
    });
  }

  Future<void> _saveProjects() async {
    await _storage.saveJsonList('project_dig_projects', _savedProjects);
  }

  @override
  void dispose() {
    _projectNameController.dispose();
    _backgroundController.dispose();
    _techDecisionController.dispose();
    _resultController.dispose();
    _difficultyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('项目深挖训练'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showSTARGuide(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // STAR 模板说明
          _buildSTARGuide(context, isDark),
          const SizedBox(height: 20),
          
          // 项目信息表单
          _buildProjectForm(context, isDark),
          const SizedBox(height: 20),
          
          // 常见深挖问题
          _buildCommonQuestions(context, isDark),
          const SizedBox(height: 20),
          
          // 已保存的项目
          if (_savedProjects.isNotEmpty) ...[
            _buildSavedProjects(context, isDark),
            const SizedBox(height: 20),
          ],
          
          // AI 深挖练习按钮
          _buildStartButton(context),
        ],
      ),
    );
  }

  Widget _buildSTARGuide(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.school_outlined, size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text(
                'STAR 法则',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.accent,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _showSTARGuide(context),
                child: const Text('详细指南'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._starTemplate.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.substring(0, item.indexOf('（')),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.substring(item.indexOf('（')),
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildProjectForm(BuildContext context, bool isDark) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('项目信息', Icons.work_outline, isDark),
          const SizedBox(height: 12),
          
          // 项目名称
          TextFormField(
            controller: _projectNameController,
            decoration: InputDecoration(
              labelText: '项目名称',
              hintText: '例如：电商秒杀系统、分布式缓存方案',
              prefixIcon: const Icon(Icons.folder_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            validator: (v) => v?.trim().isEmpty == true ? '请输入项目名称' : null,
          ),
          const SizedBox(height: 16),
          
          // 你的角色
          _buildSectionHeader('你的角色', Icons.person_outline, isDark),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ('developer', '开发工程师'),
              ('tech_lead', '技术负责人'),
              ('architect', '架构师'),
              ('pm', '项目经理'),
            ].map((role) => ChoiceChip(
              label: Text(role.$2),
              selected: _selectedRole == role.$1,
              onSelected: (_) => setState(() => _selectedRole = role.$1),
              backgroundColor: isDark ? const Color(0xFF1A2332) : Colors.white,
              selectedColor: AppColors.accent.withValues(alpha: 0.2),
            )).toList(),
          ),
          const SizedBox(height: 16),
          
          // 项目规模
          _buildSectionHeader('项目规模', Icons.scale_outlined, isDark),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ('small', '小型（1-3人）'),
              ('medium', '中型（4-10人）'),
              ('large', '大型（10人以上）'),
            ].map((scale) => ChoiceChip(
              label: Text(scale.$2),
              selected: _selectedScale == scale.$1,
              onSelected: (_) => setState(() => _selectedScale = scale.$1),
              backgroundColor: isDark ? const Color(0xFF1A2332) : Colors.white,
              selectedColor: AppColors.accent.withValues(alpha: 0.2),
            )).toList(),
          ),
          const SizedBox(height: 16),
          
          // 技术栈
          _buildSectionHeader('技术栈', Icons.code_outlined, isDark),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _techStackOptions.map((tech) {
              final isSelected = _selectedTechStack.contains(tech);
              return FilterChip(
                label: Text(tech),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedTechStack.add(tech);
                    } else {
                      _selectedTechStack.remove(tech);
                    }
                  });
                },
                backgroundColor: isDark ? const Color(0xFF1A2332) : Colors.white,
                selectedColor: AppColors.accent.withValues(alpha: 0.2),
                checkmarkColor: AppColors.accent,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          
          // STAR 详细描述
          _buildSectionHeader('STAR 详细描述', Icons.description_outlined, isDark),
          const SizedBox(height: 8),
          
          // Situation - 背景
          TextFormField(
            controller: _backgroundController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Situation（背景）',
              hintText: '项目背景、业务场景、面临的问题',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Task - 任务
          TextFormField(
            controller: _techDecisionController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Task（任务）',
              hintText: '你的职责、需要达成的目标',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Action - 行动
          TextFormField(
            controller: _difficultyController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Action（行动）',
              hintText: '技术方案、具体实现、遇到的难点及解决方案',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Result - 结果
          TextFormField(
            controller: _resultController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Result（结果）',
              hintText: '取得的成果、数据指标、经验总结',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  Widget _buildCommonQuestions(BuildContext context, bool isDark) {
    final questions = [
      ('技术决策', '为什么选择这个技术方案？考虑过哪些替代方案？'),
      ('难点攻克', '项目中遇到的最大技术难点是什么？如何解决的？'),
      ('性能优化', '做过哪些性能优化？效果如何？'),
      ('故障处理', '线上出过什么故障？如何排查和解决的？'),
      ('架构设计', '系统的整体架构是怎样的？为什么这样设计？'),
      ('团队协作', '如何协调团队成员？遇到分歧怎么处理？'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('常见深挖问题', Icons.help_outline, isDark),
        const SizedBox(height: 12),
        ...questions.map((q) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF15202E) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF263238) : const Color(0xFFE8E8E8),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  q.$1,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  q.$2,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildSavedProjects(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('已保存项目', Icons.folder_outlined, isDark),
        const SizedBox(height: 12),
        ..._savedProjects.map((project) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF15202E) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF263238) : const Color(0xFFE8E8E8),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      project['techStack'] ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : const Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.play_circle_outline, color: AppColors.accent),
                onPressed: () => _startDigPractice(project),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildStartButton(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saveAndPractice,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存并开始深挖练习'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _startRandomDig(context),
            icon: const Icon(Icons.shuffle),
            label: const Text('随机项目深挖练习'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  void _showSTARGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('STAR 法则详解'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('S - Situation（背景）', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('描述项目的背景和业务场景，让面试官理解项目的上下文。'),
              SizedBox(height: 12),
              Text('T - Task（任务）', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('说明你在项目中的角色和职责，需要达成什么目标。'),
              SizedBox(height: 12),
              Text('A - Action（行动）', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('详细描述你采取的技术方案、具体实现步骤、遇到的难点及解决方案。'),
              SizedBox(height: 12),
              Text('R - Result（结果）', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('总结项目的成果、量化指标、个人收获和经验教训。'),
              SizedBox(height: 16),
              Text('回答技巧：', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('1. 用数据说话：性能提升XX%、响应时间降低XXms'),
              Text('2. 突出个人贡献：我负责、我设计、我实现'),
              Text('3. 展示思考过程：为什么选择这个方案'),
              Text('4. 总结经验教训：学到了什么、可以改进什么'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndPractice() async {
    if (_formKey.currentState?.validate() ?? false) {
      final project = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': _projectNameController.text,
        'role': _selectedRole,
        'scale': _selectedScale,
        'techStack': _selectedTechStack.join(', '),
        'background': _backgroundController.text,
        'task': _techDecisionController.text,
        'action': _difficultyController.text,
        'result': _resultController.text,
        'createdAt': DateTime.now().toIso8601String(),
      };
      
      setState(() {
        _savedProjects.add(project);
      });
      
      await _saveProjects();
      
      // 返回项目数据给调用方
      if (mounted) {
        Navigator.of(context).pop(project);
      }
    }
  }

  void _startDigPractice(Map<String, dynamic> project) {
    final questions = [
      '这个项目的核心技术难点是什么？',
      '为什么选择 ${project['techStack']} 技术栈？',
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
              // 返回项目数据
              Navigator.of(context).pop(project);
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

  void _startRandomDig(BuildContext context) {
    if (_savedProjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加项目')),
      );
      return;
    }

    // 随机选择一个项目
    final random = _savedProjects.toList()..shuffle();
    final project = random.first;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已选择项目：${project['name']}')),
    );
    
    _startDigPractice(project);
  }
}
