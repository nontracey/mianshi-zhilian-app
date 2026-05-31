import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class ProjectDigPage extends StatefulWidget {
  const ProjectDigPage({super.key});

  @override
  State<ProjectDigPage> createState() => _ProjectDigPageState();
}

class _ProjectDigPageState extends State<ProjectDigPage> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
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
    'Java',
    'Python',
    'Go',
    'JavaScript',
    'TypeScript',
    'Spring',
    'Spring Boot',
    'MyBatis',
    'React',
    'Vue',
    'MySQL',
    'Redis',
    'MongoDB',
    'Kafka',
    'RabbitMQ',
    'Docker',
    'Kubernetes',
    'AWS',
    'microservice',
    'distributed',
    'Elasticsearch',
    'Nginx',
    'Linux',
    'Git',
    'Jenkins',
  ];

  List<({String code, String textKey})> get _starTemplate => [
    (code: 'Situation', textKey: 'star_situation_summary'),
    (code: 'Task', textKey: 'star_task_summary'),
    (code: 'Action', textKey: 'star_action_summary'),
    (code: 'Result', textKey: 'star_result_summary'),
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
        title: Text(l10n.get('project_deep_dig_training')),
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

  String _techStackLabel(String tech) {
    const localizedTechKeys = {'microservice', 'distributed'};
    return localizedTechKeys.contains(tech) ? l10n.get(tech) : tech;
  }

  Widget _buildSTARGuide(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.school_outlined,
                size: 20,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.get('star_rule'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.accent,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _showSTARGuide(context),
                child: Text(l10n.get('detail_finger_south')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._starTemplate.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.code,
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
                      l10n.get(item.textKey),
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
          _buildSectionHeader(
            l10n.get('project_info'),
            Icons.work_outline,
            isDark,
          ),
          const SizedBox(height: 12),

          // 项目名称
          TextFormField(
            controller: _projectNameController,
            decoration: InputDecoration(
              labelText: l10n.get('project_name'),
              hintText: l10n.get(
                'example_if_electric_commerce_second_kill_system_distributed_cache_solut',
              ),
              prefixIcon: const Icon(Icons.folder_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            validator: (v) => v?.trim().isEmpty == true
                ? l10n.get('please_input_project_name')
                : null,
          ),
          const SizedBox(height: 16),

          // 你的角色
          _buildSectionHeader(
            l10n.get('your_role'),
            Icons.person_outline,
            isDark,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                [
                      ('developer', l10n.get('dev_engineer')),
                      ('tech_lead', l10n.get('tech_lead')),
                      ('architect', l10n.get('architect')),
                      ('pm', l10n.get('project_manager')),
                    ]
                    .map(
                      (role) => ChoiceChip(
                        label: Text(role.$2),
                        selected: _selectedRole == role.$1,
                        onSelected: (_) =>
                            setState(() => _selectedRole = role.$1),
                        backgroundColor: isDark
                            ? const Color(0xFF1A2332)
                            : Colors.white,
                        selectedColor: AppColors.accent.withValues(alpha: 0.2),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 16),

          // 项目规模
          _buildSectionHeader(
            l10n.get('project_plan_mode'),
            Icons.scale_outlined,
            isDark,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                [
                      ('small', l10n.get('small_type_1_3_people')),
                      ('medium', l10n.get('in_type_4_10_people')),
                      ('large', l10n.get('large_type_10_people_by_upper')),
                    ]
                    .map(
                      (scale) => ChoiceChip(
                        label: Text(scale.$2),
                        selected: _selectedScale == scale.$1,
                        onSelected: (_) =>
                            setState(() => _selectedScale = scale.$1),
                        backgroundColor: isDark
                            ? const Color(0xFF1A2332)
                            : Colors.white,
                        selectedColor: AppColors.accent.withValues(alpha: 0.2),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 16),

          // 技术栈
          _buildSectionHeader(
            l10n.get('tech_stack'),
            Icons.code_outlined,
            isDark,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _techStackOptions.map((tech) {
              final isSelected = _selectedTechStack.contains(tech);
              return FilterChip(
                label: Text(_techStackLabel(tech)),
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
                backgroundColor: isDark
                    ? const Color(0xFF1A2332)
                    : Colors.white,
                selectedColor: AppColors.accent.withValues(alpha: 0.2),
                checkmarkColor: AppColors.accent,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // STAR 详细描述
          _buildSectionHeader(
            l10n.get('star_detail_description'),
            Icons.description_outlined,
            isDark,
          ),
          const SizedBox(height: 8),

          // Situation - 背景
          TextFormField(
            controller: _backgroundController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l10n.get('situation_background'),
              hintText: l10n.get(
                'project_background_business_service_scenario_aspect_interim_problem',
              ),
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
              labelText: l10n.get('task_task'),
              hintText: l10n.get('your_role_responsibility_goal'),
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
              labelText: l10n.get('action_action'),
              hintText: l10n.get(
                'tech_solution_tool_body_implementation_encounter_to_difficult_7',
              ),
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
              labelText: l10n.get('result_result'),
              hintText: l10n.get('achieved_results_data_metrics_experience'),
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
      (l10n.get('tech_decision'), l10n.get('project_question_tech_decision')),
      (
        l10n.get('difficult_point_attack_gram'),
        l10n.get('project_question_biggest_challenge'),
      ),
      (
        l10n.get('performance_optimize'),
        l10n.get('project_question_performance_optimization'),
      ),
      (
        l10n.get('fault_trouble_handle_principle'),
        l10n.get('project_question_incident_handling'),
      ),
      (
        l10n.get('architecture_design'),
        l10n.get('project_question_architecture_design'),
      ),
      (
        l10n.get('team_collaboration'),
        l10n.get('project_question_team_collaboration'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          l10n.get('common_deep_dig_problem'),
          Icons.help_outline,
          isDark,
        ),
        const SizedBox(height: 12),
        ...questions.map(
          (q) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF15202E) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF263238)
                    : const Color(0xFFE8E8E8),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                  child: Text(q.$2, style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSavedProjects(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          l10n.get('already_save_project'),
          Icons.folder_outlined,
          isDark,
        ),
        const SizedBox(height: 12),
        ..._savedProjects.map(
          (project) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF15202E) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF263238)
                    : const Color(0xFFE8E8E8),
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
                          color: isDark
                              ? Colors.white54
                              : const Color(0xFF666666),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.play_circle_outline,
                    color: AppColors.accent,
                  ),
                  onPressed: () => _startDigPractice(project),
                ),
              ],
            ),
          ),
        ),
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
            label: Text(l10n.get('save_and_start_deep_dig_practice')),
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
            label: Text(l10n.get('random_machine_project_deep_dig_practice')),
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
        title: Text(l10n.get('star_rule_detail_understand')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.get('star_situation_title'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(l10n.get('star_situation_desc')),
              SizedBox(height: 12),
              Text(
                l10n.get('star_task_title'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(l10n.get('star_task_desc')),
              SizedBox(height: 12),
              Text(
                l10n.get('star_action_title'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(l10n.get('star_action_desc')),
              SizedBox(height: 12),
              Text(
                l10n.get('star_result_title'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(l10n.get('star_result_desc')),
              SizedBox(height: 16),
              Text(
                l10n.get('answer_tips'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(l10n.get('project_answer_tip_data')),
              Text(l10n.get('project_answer_tip_contribution')),
              Text(l10n.get('project_answer_tip_reasoning')),
              Text(l10n.get('project_answer_tip_retrospective')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('known_channel')),
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
      l10n.get('project_question_core_challenge'),
      l10n.getp('project_question_why_tech_stack', {
        'techStack': project['techStack'],
      }),
      l10n.get('project_question_incident_resolution'),
      l10n.get('project_question_redesign'),
      l10n.get('project_question_personal_contribution'),
      l10n.get('project_question_metrics_optimization'),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('project_deep_dig_practice')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.getp('project_name_3', {'name': project['name']}),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.get('interview_official_optional_enable_will_question'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...questions.map((q) => _buildDigQuestion(q)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('close')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // 返回项目数据
              Navigator.of(context).pop(project);
            },
            child: Text(l10n.get('start_practice')),
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
        SnackBar(content: Text(l10n.get('please_first_add_project'))),
      );
      return;
    }

    // 随机选择一个项目
    final random = _savedProjects.toList()..shuffle();
    final project = random.first;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${l10n.get('already_select_project')}：${project['name']}',
        ),
      ),
    );

    _startDigPractice(project);
  }
}
