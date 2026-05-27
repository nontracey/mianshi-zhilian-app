import 'package:flutter/material.dart';

void main() => runApp(const MianshiZhilianApp());

class MianshiZhilianApp extends StatefulWidget {
  const MianshiZhilianApp({super.key});

  @override
  State<MianshiZhilianApp> createState() => _MianshiZhilianAppState();
}

class _MianshiZhilianAppState extends State<MianshiZhilianApp> {
  Color primary = const Color(0xFF0A2540);
  Color accent = const Color(0xFF00CCF9);
  ThemeMode mode = ThemeMode.system;
  bool compact = false;

  @override
  Widget build(BuildContext context) {
    final seed = ColorScheme.fromSeed(seedColor: primary);
    return MaterialApp(
      title: '面试智练',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: ThemeData(
        colorScheme: seed.copyWith(primary: primary, secondary: accent),
        scaffoldBackgroundColor: const Color(0xFFF7F9FB),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ).copyWith(primary: accent, secondary: const Color(0xFF10B981)),
        scaffoldBackgroundColor: const Color(0xFF06111F),
        useMaterial3: true,
      ),
      home: LearningShell(
        mode: mode,
        compact: compact,
        primary: primary,
        accent: accent,
        onModeChanged: (value) => setState(() => mode = value),
        onCompactChanged: (value) => setState(() => compact = value),
        onPrimaryChanged: (value) => setState(() => primary = value),
        onAccentChanged: (value) => setState(() => accent = value),
      ),
    );
  }
}

enum AppSection { dashboard, catalog, practice, mastery, profile }

class LearningShell extends StatefulWidget {
  const LearningShell({
    super.key,
    required this.mode,
    required this.compact,
    required this.primary,
    required this.accent,
    required this.onModeChanged,
    required this.onCompactChanged,
    required this.onPrimaryChanged,
    required this.onAccentChanged,
  });

  final ThemeMode mode;
  final bool compact;
  final Color primary;
  final Color accent;
  final ValueChanged<ThemeMode> onModeChanged;
  final ValueChanged<bool> onCompactChanged;
  final ValueChanged<Color> onPrimaryChanged;
  final ValueChanged<Color> onAccentChanged;

  @override
  State<LearningShell> createState() => _LearningShellState();
}

class _LearningShellState extends State<LearningShell> {
  AppSection section = AppSection.dashboard;
  String domain = 'java';
  bool showEvaluation = false;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 860;
    final body = Row(
      children: [
        if (wide) NavigationRailPanel(section: section, onSelect: setSection),
        Expanded(
          child: Column(
            children: [
              HeaderBar(
                title: sectionTitle(section),
                onProfile: () => setSection(AppSection.profile),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(widget.compact ? 16 : 24),
                  children: [currentPage()],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      body: body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: section.index,
              onDestinationSelected: (index) =>
                  setSection(AppSection.values[index]),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  label: '学习',
                ),
                NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  label: '知识',
                ),
                NavigationDestination(
                  icon: Icon(Icons.psychology_alt_outlined),
                  label: '练习',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  label: '掌握',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: '我的',
                ),
              ],
            ),
    );
  }

  void setSection(AppSection value) {
    setState(() {
      section = value;
      if (value != AppSection.practice) showEvaluation = false;
    });
  }

  Widget currentPage() {
    return switch (section) {
      AppSection.dashboard => DashboardPage(
        domain: domain,
        onDomain: setDomain,
        onPractice: () => setSection(AppSection.practice),
      ),
      AppSection.catalog => CatalogPage(
        domain: domain,
        onDomain: setDomain,
        onPractice: () => setSection(AppSection.practice),
      ),
      AppSection.practice => PracticePage(
        showEvaluation: showEvaluation,
        onEvaluate: () => setState(() => showEvaluation = true),
      ),
      AppSection.mastery => MasteryPage(domain: domain, onDomain: setDomain),
      AppSection.profile => ProfilePage(
        mode: widget.mode,
        compact: widget.compact,
        primary: widget.primary,
        accent: widget.accent,
        onModeChanged: widget.onModeChanged,
        onCompactChanged: widget.onCompactChanged,
        onPrimaryChanged: widget.onPrimaryChanged,
        onAccentChanged: widget.onAccentChanged,
      ),
    };
  }

  void setDomain(String value) => setState(() => domain = value);
}

String sectionTitle(AppSection section) => switch (section) {
  AppSection.dashboard => '学习中心',
  AppSection.catalog => '领域知识目录',
  AppSection.practice => 'AI 主动复述',
  AppSection.mastery => '掌握度看板',
  AppSection.profile => '个人中心',
};

const domainCards = [
  DomainInfo(
    'java',
    'Java 核心与中间件',
    'JVM、并发、集合、Spring、数据库、中间件',
    78,
    Color(0xFF0A2540),
  ),
  DomainInfo(
    'agent',
    'Agent 开发',
    'LLM、RAG、Function Calling、MCP、多 Agent',
    62,
    Color(0xFF00A6C8),
  ),
  DomainInfo(
    'algorithm',
    '算法与数据结构',
    '数组、链表、树、动态规划、回溯、图',
    45,
    Color(0xFF10B981),
  ),
];

const sampleTopics = [
  TopicInfo('java', '熟练', 'JVM 运行时数据区', '程序计数器、虚拟机栈、本地方法栈、堆、方法区。', 88),
  TopicInfo('java', '不熟练', 'GC Roots 与引用类型', '可达性分析、强软弱虚引用、对象回收判断。', 72),
  TopicInfo('java', '未掌握', '线程池核心参数', '核心线程数、队列、最大线程数、拒绝策略。', 42),
  TopicInfo('agent', '熟练', 'RAG 全流程', '切分、Embedding、召回、重排、生成和评估。', 86),
  TopicInfo('agent', '不熟练', 'MCP 协议', '工具发现、资源暴露、上下文传递和客户端集成。', 64),
  TopicInfo('algorithm', '不熟练', '动态规划状态转移', '状态定义、转移方程、初始化和空间优化。', 58),
  TopicInfo('algorithm', '未掌握', '图与最短路径', 'BFS、DFS、Dijkstra、拓扑排序。', 36),
];

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.domain,
    required this.onDomain,
    required this.onPractice,
  });

  final String domain;
  final ValueChanged<String> onDomain;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    final current = domainCards.firstWhere((item) => item.id == domain);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HeroPanel(current: current, onPractice: onPractice),
        const SizedBox(height: 20),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: domainCards
              .map(
                (item) => DomainCard(
                  info: item,
                  selected: item.id == domain,
                  onTap: () => onDomain(item.id),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 900;
            final children = [
              WorkPanel(
                title: '继续学习 ${current.title}',
                children: sampleTopics
                    .where((item) => item.domain == domain)
                    .take(3)
                    .map(TopicTile.new)
                    .toList(),
              ),
              const WorkPanel(
                title: '学习节奏',
                children: [
                  InfoRow(
                    icon: Icons.today_outlined,
                    title: '每日 3 个新知识 + 6 个复习',
                    subtitle: '本地优先保存，完成练习后批量同步。',
                  ),
                  InfoRow(
                    icon: Icons.key_outlined,
                    title: '用户自带 AI Key',
                    subtitle: 'App 端优先直连，Web 端可走 Worker 代理。',
                  ),
                ],
              ),
            ];
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children
                        .map(
                          (c) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: c,
                            ),
                          ),
                        )
                        .toList(),
                  )
                : Column(children: children);
          },
        ),
      ],
    );
  }
}

class CatalogPage extends StatelessWidget {
  const CatalogPage({
    super.key,
    required this.domain,
    required this.onDomain,
    required this.onPractice,
  });

  final String domain;
  final ValueChanged<String> onDomain;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    final current = domainCards.firstWhere((item) => item.id == domain);
    final topics = sampleTopics.where((item) => item.domain == domain).toList();
    return WorkPanel(
      title: current.title,
      trailing: DomainTabs(value: domain, onChanged: onDomain),
      children: [
        Text(current.description),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: current.progress / 100),
        const SizedBox(height: 18),
        ...topics.map(
          (topic) => TopicRow(topic: topic, onPractice: onPractice),
        ),
      ],
    );
  }
}

class PracticePage extends StatelessWidget {
  const PracticePage({
    super.key,
    required this.showEvaluation,
    required this.onEvaluate,
  });

  final bool showEvaluation;
  final VoidCallback onEvaluate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        WorkPanel(
          title: '主动复述题',
          children: [
            const Text('请用自己的话解释 JVM 运行时数据区的划分，并说明哪些区域线程私有、哪些区域线程共享。'),
            const SizedBox(height: 12),
            TextField(
              minLines: 6,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: '在这里输入你的复述答案...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onEvaluate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('获取 AI 深度评估'),
            ),
          ],
        ),
        if (showEvaluation) ...[
          const SizedBox(height: 16),
          const WorkPanel(
            title: 'AI 评估结果',
            children: [
              ScoreBadge(score: 86),
              InfoRow(
                icon: Icons.check_circle_outline,
                title: '覆盖完整',
                subtitle: '已讲到线程私有区域、线程共享区域、堆、栈和方法区。',
              ),
              InfoRow(
                icon: Icons.tips_and_updates_outlined,
                title: '建议补充',
                subtitle: '可以补一句 JDK 8 后元空间替代永久代，避免把方法区和永久代直接等同。',
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class MasteryPage extends StatelessWidget {
  const MasteryPage({super.key, required this.domain, required this.onDomain});

  final String domain;
  final ValueChanged<String> onDomain;

  @override
  Widget build(BuildContext context) {
    final current = domainCards.firstWhere((item) => item.id == domain);
    final topics = sampleTopics.where((item) => item.domain == domain).toList()
      ..sort((a, b) => a.score.compareTo(b.score));
    return WorkPanel(
      title: '${current.title} · ${current.progress}%',
      trailing: DomainTabs(value: domain, onChanged: onDomain),
      children: [
        LinearProgressIndicator(value: current.progress / 100),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: topics.map((topic) => MasteryCard(topic: topic)).toList(),
        ),
      ],
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.mode,
    required this.compact,
    required this.primary,
    required this.accent,
    required this.onModeChanged,
    required this.onCompactChanged,
    required this.onPrimaryChanged,
    required this.onAccentChanged,
  });

  final ThemeMode mode;
  final bool compact;
  final Color primary;
  final Color accent;
  final ValueChanged<ThemeMode> onModeChanged;
  final ValueChanged<bool> onCompactChanged;
  final ValueChanged<Color> onPrimaryChanged;
  final ValueChanged<Color> onAccentChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        WorkPanel(
          title: 'AI 配置',
          children: [
            const InfoRow(
              icon: Icons.hub_outlined,
              title: 'OpenAI Compatible',
              subtitle: '支持 Base URL、API Key、模型名和连接测试。',
            ),
            TextField(
              decoration: InputDecoration(
                labelText: 'Base URL',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: '模型名',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        WorkPanel(
          title: '外观与主题',
          children: [
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
              ],
              selected: {mode},
              onSelectionChanged: (value) => onModeChanged(value.first),
            ),
            SwitchListTile(
              value: compact,
              onChanged: onCompactChanged,
              title: const Text('紧凑卡片密度'),
            ),
            Wrap(
              spacing: 10,
              children: [
                ColorButton(
                  color: const Color(0xFF0A2540),
                  selected: primary == const Color(0xFF0A2540),
                  onTap: () => onPrimaryChanged(const Color(0xFF0A2540)),
                ),
                ColorButton(
                  color: const Color(0xFF12372A),
                  selected: primary == const Color(0xFF12372A),
                  onTap: () => onPrimaryChanged(const Color(0xFF12372A)),
                ),
                ColorButton(
                  color: const Color(0xFF111827),
                  selected: primary == const Color(0xFF111827),
                  onTap: () => onPrimaryChanged(const Color(0xFF111827)),
                ),
                ColorButton(
                  color: const Color(0xFF00CCF9),
                  selected: accent == const Color(0xFF00CCF9),
                  onTap: () => onAccentChanged(const Color(0xFF00CCF9)),
                ),
                ColorButton(
                  color: const Color(0xFF10B981),
                  selected: accent == const Color(0xFF10B981),
                  onTap: () => onAccentChanged(const Color(0xFF10B981)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        const WorkPanel(
          title: '关于面试智练',
          children: [
            InfoRow(
              icon: Icons.cloud_sync_outlined,
              title: '本地优先 + 云端同步',
              subtitle: '云同步失败不会阻断学习，本地事件会等待重试。',
            ),
            InfoRow(
              icon: Icons.system_update_alt_outlined,
              title: '检查更新',
              subtitle: '读取 GitHub Releases / update.json，校验 sha256 后引导安装。',
            ),
          ],
        ),
      ],
    );
  }
}

class NavigationRailPanel extends StatelessWidget {
  const NavigationRailPanel({
    super.key,
    required this.section,
    required this.onSelect,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: Theme.of(context).colorScheme.primary,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '面试智练',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text('AI 主动回忆学习工作台', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 28),
          ...AppSection.values.map(
            (item) => NavButton(
              section: item,
              active: section == item,
              onTap: () => onSelect(item),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => onSelect(AppSection.practice),
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始今日练习'),
          ),
          const SizedBox(height: 16),
          const Text(
            '本地优先模式\n已缓存 134 个知识点\n上次同步：今天 09:18',
            style: TextStyle(color: Colors.white70, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class HeaderBar extends StatelessWidget {
  const HeaderBar({super.key, required this.title, required this.onProfile});

  final String title;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(
              width: 280,
              child: SearchBar(
                hintText: '搜索知识点、标签、面试题',
                leading: const Icon(Icons.search),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: onProfile,
              icon: const Icon(Icons.person_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class HeroPanel extends StatelessWidget {
  const HeroPanel({super.key, required this.current, required this.onPractice});

  final DomainInfo current;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Chip(label: Text('当前领域：${current.title}')),
                Text(
                  '把面试知识练成可以讲出来的答案',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '先充分学习知识解释，再进入复述训练，由 AI 按 rubric 评分、纠错和补充。',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: onPractice,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('进入复述练习'),
                ),
              ],
            ),
          ),
          StatBlock(value: '${current.progress}%', label: '领域掌握度'),
          const StatBlock(value: '134', label: '知识点'),
          const StatBlock(value: '9', label: '待复习'),
        ],
      ),
    );
  }
}

class WorkPanel extends StatelessWidget {
  const WorkPanel({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class DomainCard extends StatelessWidget {
  const DomainCard({
    super.key,
    required this.info,
    required this.selected,
    required this.onTap,
  });

  final DomainInfo info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 330,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? info.color : Theme.of(context).dividerColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(info.description),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: info.progress / 100,
                color: info.color,
              ),
              const SizedBox(height: 8),
              Text('${info.progress}% 熟练 · 点击切换领域'),
            ],
          ),
        ),
      ),
    );
  }
}

class TopicRow extends StatelessWidget {
  const TopicRow({super.key, required this.topic, required this.onPractice});

  final TopicInfo topic;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: StatusDot(score: topic.score),
        title: Text(topic.title),
        subtitle: Text(topic.summary),
        trailing: Wrap(
          spacing: 8,
          children: [
            OutlinedButton(onPressed: () {}, child: const Text('知识查阅')),
            FilledButton(onPressed: onPractice, child: const Text('学习模式')),
          ],
        ),
      ),
    );
  }
}

class TopicTile extends StatelessWidget {
  const TopicTile(this.topic, {super.key});

  final TopicInfo topic;

  @override
  Widget build(BuildContext context) => InfoRow(
    icon: Icons.menu_book_outlined,
    title: topic.title,
    subtitle: topic.summary,
  );
}

class MasteryCard extends StatelessWidget {
  const MasteryCard({super.key, required this.topic});

  final TopicInfo topic;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: WorkPanel(
        title: topic.title,
        children: [
          Text(topic.status),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: topic.score / 100,
            color: scoreColor(topic.score),
          ),
          const SizedBox(height: 8),
          Text('${topic.score} 分 · ${topic.summary}'),
        ],
      ),
    );
  }
}

class DomainTabs extends StatelessWidget {
  const DomainTabs({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: domainCards
          .map((item) => ButtonSegment(value: item.id, label: Text(item.id)))
          .toList(),
      selected: {value},
      onSelectionChanged: (next) => onChanged(next.first),
    );
  }
}

class NavButton extends StatelessWidget {
  const NavButton({
    super.key,
    required this.section,
    required this.active,
    required this.onTap,
  });

  final AppSection section;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(sectionIcon(section), color: Colors.white),
        label: Text(
          sectionTitle(section),
          style: const TextStyle(color: Colors.white),
        ),
        style: TextButton.styleFrom(
          backgroundColor: active
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.transparent,
          minimumSize: const Size.fromHeight(46),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score});

  final int score;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF10B981).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '$score 分 · 熟练',
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: Color(0xFF10B981),
      ),
    ),
  );
}

class StatBlock extends StatelessWidget {
  const StatBlock({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 18),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 28,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    ),
  );
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.score});

  final int score;

  @override
  Widget build(BuildContext context) =>
      CircleAvatar(radius: 8, backgroundColor: scoreColor(score));
}

class ColorButton extends StatelessWidget {
  const ColorButton({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(24),
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          width: selected ? 4 : 1,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    ),
  );
}

IconData sectionIcon(AppSection section) => switch (section) {
  AppSection.dashboard => Icons.dashboard_outlined,
  AppSection.catalog => Icons.menu_book_outlined,
  AppSection.practice => Icons.psychology_alt_outlined,
  AppSection.mastery => Icons.bar_chart_outlined,
  AppSection.profile => Icons.person_outline,
};

Color scoreColor(int score) {
  if (score >= 85) return const Color(0xFF10B981);
  if (score >= 60) return const Color(0xFFF59E0B);
  return const Color(0xFF64748B);
}

class DomainInfo {
  const DomainInfo(
    this.id,
    this.title,
    this.description,
    this.progress,
    this.color,
  );
  final String id;
  final String title;
  final String description;
  final int progress;
  final Color color;
}

class TopicInfo {
  const TopicInfo(
    this.domain,
    this.status,
    this.title,
    this.summary,
    this.score,
  );
  final String domain;
  final String status;
  final String title;
  final String summary;
  final int score;
}
