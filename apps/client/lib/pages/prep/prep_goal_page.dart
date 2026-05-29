import 'package:flutter/material.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class PrepGoalPage extends StatefulWidget {
  const PrepGoalPage({super.key});

  @override
  State<PrepGoalPage> createState() => _PrepGoalPageState();
}

class _PrepGoalPageState extends State<PrepGoalPage> {
  final _formKey = GlobalKey<FormState>();
  final _companyController = TextEditingController();
  final _positionController = TextEditingController();
  final _jdController = TextEditingController();
  
  DateTime? _interviewDate;
  int _dailyMinutes = 60;
  String _currentLevel = 'intermediate';
  final List<String> _selectedTechStack = [];
  
  final List<String> _techStackOptions = [
    'Java', 'Python', 'Go', 'JavaScript', 'TypeScript',
    'React', 'Vue', 'Angular', 'Spring', 'Node.js',
    'MySQL', 'Redis', 'MongoDB', 'Kafka', 'RabbitMQ',
    'Docker', 'Kubernetes', 'AWS', '微服务', '分布式',
    '算法', '系统设计', '数据结构', '网络', '操作系统',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedGoal();
  }

  void _loadSavedGoal() {
    // TODO: 从本地存储加载已保存的目标
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
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('准备目标'),
        actions: [
          TextButton(
            onPressed: _saveGoal,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 目标公司和岗位
            _buildSectionHeader('目标信息', Icons.business_outlined, isDark),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _companyController,
              label: '目标公司',
              hint: '例如：字节跳动、阿里巴巴',
              icon: Icons.business,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _positionController,
              label: '目标岗位',
              hint: '例如：Java 高级工程师、前端开发',
              icon: Icons.work_outline,
            ),
            const SizedBox(height: 20),
            
            // 面试日期
            _buildSectionHeader('面试时间', Icons.calendar_today_outlined, isDark),
            const SizedBox(height: 12),
            _buildDatePicker(context, isDark),
            const SizedBox(height: 20),
            
            // 每日投入时间
            _buildSectionHeader('每日投入', Icons.timer_outlined, isDark),
            const SizedBox(height: 12),
            _buildDailyMinutesSelector(isDark),
            const SizedBox(height: 20),
            
            // 当前水平
            _buildSectionHeader('当前水平', Icons.assessment_outlined, isDark),
            const SizedBox(height: 12),
            _buildLevelSelector(isDark),
            const SizedBox(height: 20),
            
            // 技术栈
            _buildSectionHeader('技术栈', Icons.code_outlined, isDark),
            const SizedBox(height: 12),
            _buildTechStackSelector(isDark),
            const SizedBox(height: 20),
            
            // JD 描述
            _buildSectionHeader('岗位描述（可选）', Icons.description_outlined, isDark),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _jdController,
              label: '粘贴 JD',
              hint: '粘贴岗位描述，帮助生成个性化训练计划',
              icon: Icons.description,
              maxLines: 5,
            ),
            const SizedBox(height: 24),
            
            // 生成计划按钮
            FilledButton.icon(
              onPressed: _generatePlan,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('生成训练计划'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            
            // 提示
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '设置目标后，系统会根据面试日期自动生成冲刺计划',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.accent,
                      ),
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildDatePicker(BuildContext context, bool isDark) {
    final daysUntil = _interviewDate != null
        ? _interviewDate!.difference(DateTime.now()).inDays
        : null;

    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _interviewDate ?? DateTime.now().add(const Duration(days: 30)),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date != null) {
          setState(() => _interviewDate = date);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? const Color(0xFF263238) : const Color(0xFFE0E0E0),
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
                        : '选择面试日期',
                    style: TextStyle(
                      fontSize: 14,
                      color: _interviewDate != null
                          ? (isDark ? Colors.white : const Color(0xFF1A1A1A))
                          : (isDark ? Colors.white38 : const Color(0xFF999999)),
                    ),
                  ),
                  if (daysUntil != null)
                    Text(
                      daysUntil > 0 ? '还有 $daysUntil 天' : '已过期',
                      style: TextStyle(
                        fontSize: 12,
                        color: daysUntil > 0 ? AppColors.accent : AppColors.danger,
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
      (30, '30 分钟'),
      (60, '1 小时'),
      (90, '1.5 小时'),
      (120, '2 小时'),
      (180, '3 小时'),
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
          backgroundColor: isDark ? const Color(0xFF1A2332) : Colors.white,
          selectedColor: AppColors.accent.withValues(alpha: 0.2),
          side: BorderSide(
            color: isSelected
                ? AppColors.accent
                : (isDark ? const Color(0xFF263238) : const Color(0xFFE0E0E0)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLevelSelector(bool isDark) {
    final levels = [
      ('beginner', '入门', '刚开始学习'),
      ('intermediate', '中级', '有一定基础'),
      ('advanced', '高级', '准备冲高级岗'),
      ('expert', '专家', '准备架构师/专家岗'),
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
                  : (isDark ? const Color(0xFF263238) : const Color(0xFFE0E0E0)),
            ),
          ),
          child: RadioListTile<String>(
            value: level.$1,
            groupValue: _currentLevel,
            onChanged: (value) {
              if (value != null) {
                setState(() => _currentLevel = value);
              }
            },
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
            activeColor: AppColors.accent,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
          label: Text(tech),
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
          side: BorderSide(
            color: isSelected
                ? AppColors.accent
                : (isDark ? const Color(0xFF263238) : const Color(0xFFE0E0E0)),
          ),
        );
      }).toList(),
    );
  }

  void _saveGoal() {
    if (_formKey.currentState?.validate() ?? false) {
      // TODO: 保存到本地存储
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目标已保存')),
      );
      Navigator.of(context).pop();
    }
  }

  void _generatePlan() {
    if (_interviewDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择面试日期')),
      );
      return;
    }

    final daysUntil = _interviewDate!.difference(DateTime.now()).inDays;
    if (daysUntil <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('面试日期已过期')),
      );
      return;
    }

    // TODO: 根据配置生成训练计划
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('训练计划'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('距离面试还有 $daysUntil 天'),
              const SizedBox(height: 8),
              Text('每日投入：$_dailyMinutes 分钟'),
              const SizedBox(height: 8),
              Text('技术栈：${_selectedTechStack.join(", ")}'),
              const SizedBox(height: 16),
              const Text('建议计划：', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _buildPlanItem('第 1-7 天', '基础补齐', '复习核心技术概念'),
              _buildPlanItem('第 8-14 天', '高频冲刺', '重点练习高频面试题'),
              _buildPlanItem('第 15-21 天', '模拟面试', '进行模拟面试训练'),
              _buildPlanItem('第 22-28 天', '错题回炉', '复习薄弱知识点'),
              _buildPlanItem('最后几天', '查漏补缺', '针对性复习'),
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
              // TODO: 保存计划并开始执行
            },
            child: const Text('开始执行'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanItem(String phase, String title, String description) {
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
                  '$phase：$title',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
