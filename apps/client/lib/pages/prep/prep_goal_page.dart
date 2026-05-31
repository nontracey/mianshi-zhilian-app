import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class PrepGoalPage extends StatefulWidget {
  const PrepGoalPage({super.key});

  @override
  State<PrepGoalPage> createState() => _PrepGoalPageState();
}

class _PrepGoalPageState extends State<PrepGoalPage> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  final _formKey = GlobalKey<FormState>();
  final _companyController = TextEditingController();
  final _positionController = TextEditingController();
  final _jdController = TextEditingController();
  final _storage = StorageService();

  DateTime? _interviewDate;
  int _dailyMinutes = 60;
  String _currentLevel = 'intermediate';
  final List<String> _selectedTechStack = [];
  bool _isLoading = true;

  final List<String> _techStackOptions = [
    'Java',
    'Python',
    'Go',
    'JavaScript',
    'TypeScript',
    'React',
    'Vue',
    'Angular',
    'Spring',
    'Node.js',
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
    'algorithm',
    'system_design',
    'data_structure',
    'network',
    'operating_system',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedGoal();
  }

  Future<void> _loadSavedGoal() async {
    final data = await _storage.loadJsonObject('prep_goal');
    if (data != null && mounted) {
      setState(() {
        _companyController.text = data['company'] ?? '';
        _positionController.text = data['position'] ?? '';
        _jdController.text = data['jd'] ?? '';
        _dailyMinutes = data['dailyMinutes'] ?? 60;
        _currentLevel = data['currentLevel'] ?? 'intermediate';
        _selectedTechStack.clear();
        if (data['techStack'] != null) {
          _selectedTechStack.addAll((data['techStack'] as List).cast<String>());
        }
        if (data['interviewDate'] != null) {
          _interviewDate = DateTime.tryParse(data['interviewDate']);
        }
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveGoal() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await _storage.saveJsonObject('prep_goal', {
      'company': _companyController.text.trim(),
      'position': _positionController.text.trim(),
      'jd': _jdController.text.trim(),
      'dailyMinutes': _dailyMinutes,
      'currentLevel': _currentLevel,
      'techStack': _selectedTechStack,
      'interviewDate': _interviewDate?.toIso8601String(),
      'savedAt': DateTime.now().toIso8601String(),
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('goal_already_save'))));
    }
  }

  Future<void> _generatePlan() async {
    if (_interviewDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('please_first_select_interview_day'))),
      );
      return;
    }

    final daysUntil = _interviewDate!.difference(DateTime.now()).inDays;
    if (daysUntil <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('interview_day_already_pass'))),
      );
      return;
    }

    // 根据天数生成训练计划
    final plan = _buildTrainingPlan(daysUntil);

    // 保存计划
    await _storage.saveJsonObject('training_plan', {
      'interviewDate': _interviewDate!.toIso8601String(),
      'dailyMinutes': _dailyMinutes,
      'phases': plan,
      'createdAt': DateTime.now().toIso8601String(),
    });

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('training_plan')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.getp('distance_offline_interview_still_has_days_day_2', {
                  'days': daysUntil.toString(),
                }),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.getp('daily_send_enter_minutes_min_1_2', {
                  'minutes': _dailyMinutes.toString(),
                }),
              ),
              if (_selectedTechStack.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.getp('tech_stack_techstack_2', {
                    'techStack': _selectedTechStack.join(', '),
                  }),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                l10n.get('training_plan_1'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...plan.map(
                (p) => _buildPlanItem(
                  p['phaseKey'] as String,
                  p['titleKey'] as String,
                  p['descKey'] as String,
                ),
              ),
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.get('plan_already_save_start_execute_action'),
                  ),
                ),
              );
            },
            child: Text(l10n.get('start_execute_action')),
          ),
        ],
      ),
    );
  }

  List<Map<String, String>> _buildTrainingPlan(int days) {
    if (days <= 7) {
      return [
        {
          'phaseKey': 'prep_phase_days_1_3',
          'titleKey': 'high_freq_sprint',
          'descKey': 'prep_phase_high_freq_sprint',
        },
        {
          'phaseKey': 'prep_phase_days_4_5',
          'titleKey': 'mock_interview',
          'descKey': 'prep_phase_mock_interview',
        },
        {
          'phaseKey': 'prep_phase_last_2_days',
          'titleKey': 'check_leak_supplement_lack',
          'descKey': 'prep_phase_fill_gaps',
        },
      ];
    } else if (days <= 14) {
      return [
        {
          'phaseKey': 'prep_phase_days_1_5',
          'titleKey': 'basic_fill_gap',
          'descKey': 'prep_phase_foundation',
        },
        {
          'phaseKey': 'prep_phase_days_6_10',
          'titleKey': 'high_freq_sprint',
          'descKey': 'prep_phase_high_freq_sprint',
        },
        {
          'phaseKey': 'prep_phase_days_11_14',
          'titleKey': 'mock_interview',
          'descKey': 'prep_phase_mock_interview',
        },
      ];
    } else if (days <= 30) {
      return [
        {
          'phaseKey': 'prep_phase_days_1_7',
          'titleKey': 'basic_fill_gap',
          'descKey': 'prep_phase_foundation',
        },
        {
          'phaseKey': 'prep_phase_days_8_14',
          'titleKey': 'high_freq_sprint',
          'descKey': 'prep_phase_high_freq_sprint',
        },
        {
          'phaseKey': 'prep_phase_days_15_21',
          'titleKey': 'mock_interview',
          'descKey': 'prep_phase_mock_interview',
        },
        {
          'phaseKey': 'prep_phase_days_22_28',
          'titleKey': 'wrong_question_back_furnace',
          'descKey': 'prep_phase_wrong_review',
        },
        {
          'phaseKey': 'prep_phase_last_days',
          'titleKey': 'check_leak_supplement_lack',
          'descKey': 'prep_phase_fill_gaps',
        },
      ];
    } else {
      return [
        {
          'phaseKey': 'prep_phase_weeks_1_2',
          'titleKey': 'basic_fill_gap',
          'descKey': 'prep_phase_foundation',
        },
        {
          'phaseKey': 'prep_phase_weeks_3_4',
          'titleKey': 'high_freq_sprint',
          'descKey': 'prep_phase_high_freq_sprint',
        },
        {
          'phaseKey': 'prep_phase_weeks_5_6',
          'titleKey': 'mock_interview',
          'descKey': 'prep_phase_mock_interview',
        },
        {
          'phaseKey': 'prep_phase_weeks_7_8',
          'titleKey': 'wrong_question_back_furnace',
          'descKey': 'prep_phase_wrong_review',
        },
        {
          'phaseKey': 'prep_phase_final_stage',
          'titleKey': 'check_leak_supplement_lack',
          'descKey': 'prep_phase_fill_gaps',
        },
      ];
    }
  }

  @override
  void dispose() {
    _companyController.dispose();
    _positionController.dispose();
    _jdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.get('preparation_goal'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('preparation_goal')),
        actions: [
          TextButton(onPressed: _saveGoal, child: Text(l10n.get('save'))),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader(
              l10n.get('goal_info'),
              Icons.business_outlined,
              isDark,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _companyController,
              label: l10n.get('goal_company'),
              hint: l10n.get('example_bytedance_alibaba'),
              icon: Icons.business,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _positionController,
              label: l10n.get('goal_position'),
              hint: l10n.get('example_if_java_senior_engineer_frontend_dev'),
              icon: Icons.work_outline,
            ),
            const SizedBox(height: 20),

            _buildSectionHeader(
              l10n.get('interview_time'),
              Icons.calendar_today_outlined,
              isDark,
            ),
            const SizedBox(height: 12),
            _buildDatePicker(context, isDark),
            const SizedBox(height: 20),

            _buildSectionHeader(
              l10n.get('daily_send_enter'),
              Icons.timer_outlined,
              isDark,
            ),
            const SizedBox(height: 12),
            _buildDailyMinutesSelector(isDark),
            const SizedBox(height: 20),

            _buildSectionHeader(
              l10n.get('current_water_flat'),
              Icons.assessment_outlined,
              isDark,
            ),
            const SizedBox(height: 12),
            _buildLevelSelector(isDark),
            const SizedBox(height: 20),

            _buildSectionHeader(
              l10n.get('tech_stack'),
              Icons.code_outlined,
              isDark,
            ),
            const SizedBox(height: 12),
            _buildTechStackSelector(isDark),
            const SizedBox(height: 20),

            _buildSectionHeader(
              l10n.get('position_description_optional_select'),
              Icons.description_outlined,
              isDark,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _jdController,
              label: l10n.get('paste_jd'),
              hint: l10n.get(
                'paste_position_description_help_life_achievement_capability_transform_tra',
              ),
              icon: Icons.description,
              maxLines: 5,
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _generatePlan,
              icon: const Icon(Icons.auto_awesome),
              label: Text(l10n.get('life_achievement_training_plan')),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.get(
                        'settings_goal_after_system_will_root_data_interview_day',
                      ),
                      style: TextStyle(fontSize: 12, color: AppColors.accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
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
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildDatePicker(BuildContext context, bool isDark) {
    final daysUntil = _interviewDate?.difference(DateTime.now()).inDays;

    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate:
              _interviewDate ?? DateTime.now().add(const Duration(days: 30)),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date != null) setState(() => _interviewDate = date);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? const Color(0xFF30363D) : const Color(0xFFE0E0E0),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 20,
              color: isDark ? Colors.white54 : const Color(0xFF666666),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _interviewDate != null
                        ? '${_interviewDate!.year}-${_interviewDate!.month.toString().padLeft(2, '0')}-${_interviewDate!.day.toString().padLeft(2, '0')}'
                        : l10n.get('select_interview_day'),
                    style: TextStyle(
                      fontSize: 14,
                      color: _interviewDate != null
                          ? (isDark ? Colors.white : const Color(0xFF1A1A1A))
                          : (isDark ? Colors.white38 : const Color(0xFF999999)),
                    ),
                  ),
                  if (daysUntil != null)
                    Text(
                      daysUntil > 0
                          ? l10n.getp('still_has_days_day_2', {
                              'days': daysUntil.toString(),
                            })
                          : l10n.get('already_pass_day'),
                      style: TextStyle(
                        fontSize: 12,
                        color: daysUntil > 0
                            ? AppColors.accent
                            : AppColors.danger,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: isDark ? Colors.white38 : const Color(0xFF999999),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyMinutesSelector(bool isDark) {
    final options = [
      (30, l10n.get('time_30_min_2')),
      (60, l10n.get('time_1_hour_2')),
      (90, l10n.get('time_1_5_hour_2')),
      (120, l10n.get('time_2_hour_2')),
      (180, l10n.get('time_3_hour_2')),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = _dailyMinutes == option.$1;
        return ChoiceChip(
          selected: isSelected,
          label: Text(option.$2),
          onSelected: (_) => setState(() => _dailyMinutes = option.$1),
        );
      }).toList(),
    );
  }

  Widget _buildLevelSelector(bool isDark) {
    final levels = [
      ('beginner', l10n.get('beginner'), l10n.get('just_start_study')),
      (
        'intermediate',
        l10n.get('intermediate'),
        l10n.get('has_one_fixed_basic'),
      ),
      (
        'advanced',
        l10n.get('senior'),
        l10n.get('preparation_rush_senior_position'),
      ),
      (
        'expert',
        l10n.get('expert'),
        l10n.get('preparation_architect_expert_position'),
      ),
    ];

    return Column(
      children: levels.map((level) {
        final isSelected = _currentLevel == level.$1;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppColors.accent
                  : (isDark
                        ? const Color(0xFF30363D)
                        : const Color(0xFFE0E0E0)),
            ),
          ),
          child: ListTile(
            leading: Radio<String>(
              value: level.$1,
              // ignore: deprecated_member_use
              groupValue: _currentLevel,
              // ignore: deprecated_member_use
              onChanged: (value) {
                if (value != null) setState(() => _currentLevel = value);
              },
              activeColor: AppColors.accent,
            ),
            title: Text(
              level.$2,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            subtitle: Text(
              level.$3,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : const Color(0xFF666666),
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            onTap: () => setState(() => _currentLevel = level.$1),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTechStackSelector(bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _techStackOptions.map((tech) {
        final isSelected = _selectedTechStack.contains(tech);
        return FilterChip(
          selected: isSelected,
          label: Text(_techStackLabel(tech)),
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedTechStack.add(tech);
              } else {
                _selectedTechStack.remove(tech);
              }
            });
          },
        );
      }).toList(),
    );
  }

  String _techStackLabel(String tech) {
    const localizedTechKeys = {
      'microservice',
      'distributed',
      'algorithm',
      'system_design',
      'data_structure',
      'network',
      'operating_system',
    };
    return localizedTechKeys.contains(tech) ? l10n.get(tech) : tech;
  }

  Widget _buildPlanItem(String phaseKey, String titleKey, String descKey) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6, right: 8),
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.getp('prep_phase_title', {
                    'phase': l10n.get(phaseKey),
                    'title': l10n.get(titleKey),
                  }),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  l10n.get(descKey),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
