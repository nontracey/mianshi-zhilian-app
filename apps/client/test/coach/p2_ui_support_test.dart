/// P2 UI 支撑层的纯 Dart 单测：提示词组装、无模型 JD 兜底解析、HTML 正文净化。
///
/// 全部不依赖 Flutter：`CoachRulesLoader`（rootBundle）不在覆盖范围内，
/// 这里只测可注入规则文本的 `CoachPromptBuilder`。
library;

import 'package:mianshi_zhilian/coach/application/prompt_builder.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/goal.dart';
import 'package:mianshi_zhilian/coach/domain/resume.dart';
import 'package:mianshi_zhilian/coach/jobs/jd_import_service.dart';
import 'package:mianshi_zhilian/services/http_jd_fetcher.dart';

import 'harness.dart';

// ── 演示数据（合成，非真实个人资料）────────────────────────────────

GoalRequirement _req(
  String id,
  String title,
  Importance importance, {
  String? depth,
}) => GoalRequirement(
  id: id,
  goalId: 'demo-goal',
  profileId: 'demo-profile',
  type: RequirementType.hardRequirement,
  title: title,
  importance: importance,
  suggestedDepth: depth,
);

ResumeClaim _claim(String id, String statement, ClaimStatus status) =>
    ResumeClaim(
      id: id,
      profileId: 'demo-profile',
      resumeId: 'demo-resume',
      statement: statement,
      status: status,
    );

Future<void> main() async {
  group('CoachPromptBuilder', () {
    const builder = CoachPromptBuilder();

    test('缺 core 规则时使用内置兜底，保留不编造/不越权底线', () {
      final prompt = builder.buildSystemPrompt(
        mode: SessionMode.learning,
        rules: const {},
      );
      expect(prompt, contains('不编造'));
      expect(prompt, contains('不越权'));
    });

    test('注入的 core 与模式段都会出现在提示词中', () {
      final prompt = builder.buildSystemPrompt(
        mode: SessionMode.review,
        rules: const {
          CoachRuleSection.core: 'CORE_MARKER',
          CoachRuleSection.review: 'REVIEW_MARKER',
        },
      );
      expect(prompt, contains('CORE_MARKER'));
      expect(prompt, contains('REVIEW_MARKER'));
    });

    test('模式规则缺失时回退到英文模式 token，不出现空段', () {
      final prompt = builder.buildSystemPrompt(
        mode: SessionMode.interview,
        rules: const {CoachRuleSection.core: 'CORE'},
      );
      expect(prompt, contains('## 当前模式'));
      // interview 的 promptToken 即枚举名。
      expect(prompt, contains('interview'));
    });

    test('只选当前模式的规则段，不串入其它模式', () {
      final prompt = builder.buildSystemPrompt(
        mode: SessionMode.learning,
        rules: const {
          CoachRuleSection.core: 'CORE',
          CoachRuleSection.learning: 'LEARNING_MARKER',
          CoachRuleSection.review: 'REVIEW_MARKER',
          CoachRuleSection.interview: 'INTERVIEW_MARKER',
        },
      );
      expect(prompt, contains('LEARNING_MARKER'));
      expect(prompt.contains('REVIEW_MARKER'), isFalse);
      expect(prompt.contains('INTERVIEW_MARKER'), isFalse);
    });

    test('没有简历素材时不注入项目段', () {
      final prompt = builder.buildSystemPrompt(
        mode: SessionMode.learning,
        rules: const {
          CoachRuleSection.core: 'CORE',
          CoachRuleSection.project: 'PROJECT_MARKER',
        },
      );
      expect(prompt.contains('PROJECT_MARKER'), isFalse);
    });

    test('有简历素材时注入项目段', () {
      final prompt = builder.buildSystemPrompt(
        mode: SessionMode.learning,
        rules: const {
          CoachRuleSection.core: 'CORE',
          CoachRuleSection.project: 'PROJECT_MARKER',
        },
        context: CoachContext(
          confirmedClaims: [_claim('c1', '做过订单拆分', ClaimStatus.confirmed)],
        ),
      );
      expect(prompt, contains('PROJECT_MARKER'));
    });

    test('目标、要求与资料引用进入上下文段；要求按重要度降序', () {
      final prompt = builder.buildSystemPrompt(
        mode: SessionMode.review,
        rules: const {CoachRuleSection.core: 'CORE'},
        context: CoachContext(
          goalTitle: '后端开发工程师',
          company: '演示科技有限公司',
          location: '杭州',
          requirements: [
            _req('r1', '了解 Redis', Importance.low),
            _req('r2', '精通 JVM 调优', Importance.high, depth: '故障与取舍'),
            _req('r3', '熟悉 MQ', Importance.medium),
          ],
          citations: const [
            PromptCitation(
              sourceTitle: '演示资料',
              location: '第 3 章',
              snippet: 'B+ 树高度\n通常在 3-4 层',
            ),
          ],
        ),
      );
      expect(prompt, contains('演示科技有限公司'));
      expect(prompt, contains('后端开发工程师'));
      expect(prompt, contains('杭州'));
      // 引用出处与压平成单行的片段
      expect(prompt, contains('《演示资料》第 3 章'));
      expect(prompt, contains('B+ 树高度 通常在 3-4 层'));
      // 重要度：high 出现在 low 之前
      final highAt = prompt.indexOf('精通 JVM 调优');
      final lowAt = prompt.indexOf('了解 Redis');
      expect(highAt >= 0 && lowAt > highAt, isTrue);
      expect(prompt, contains('故障与取舍'));
      // 重要度用英文 token，避免把 UI 文案写进提示词
      expect(prompt, contains('required'));
    });

    test('已确认与待确认主张分段标注，待确认明确禁止当事实', () {
      final prompt = builder.buildSystemPrompt(
        mode: SessionMode.review,
        rules: const {CoachRuleSection.core: 'CORE'},
        context: CoachContext(
          confirmedClaims: [_claim('c1', '负责订单服务的拆分', ClaimStatus.confirmed)],
          pendingClaims: [_claim('c2', '主导过千万级 QPS 改造', ClaimStatus.pending)],
        ),
      );
      expect(prompt, contains('可作为事实使用'));
      expect(prompt, contains('不得当作事实'));
      expect(prompt, contains('负责订单服务的拆分'));
      expect(prompt, contains('主导过千万级 QPS 改造'));
    });

    test('信息缺口段提示主动追问而非替用户补全', () {
      final prompt = builder.buildSystemPrompt(
        mode: SessionMode.learning,
        rules: const {CoachRuleSection.core: 'CORE'},
        context: const CoachContext(missingInfoNotes: ['用户未说明项目中的具体职责边界']),
      );
      expect(prompt, contains('已知信息缺口'));
      expect(prompt, contains('不要替用户补全'));
    });

    test('模拟模式强制标注出题依据类型', () {
      final prompt = builder.buildSystemPrompt(
        mode: SessionMode.interview,
        rules: const {CoachRuleSection.core: 'CORE'},
        context: const CoachContext(goalTitle: '后端开发工程师'),
      );
      expect(prompt, contains('jdAndResume'));
      expect(prompt, contains('jdOnly'));
      expect(prompt, contains('resumeOnly'));
      expect(prompt, contains('不得凭空出题'));
    });

    test('非模拟模式不写作出题依据约束', () {
      final prompt = builder.buildSystemPrompt(
        mode: SessionMode.review,
        rules: const {CoachRuleSection.core: 'CORE'},
        context: const CoachContext(goalTitle: '后端开发工程师'),
      );
      expect(prompt.contains('不得凭空出题'), isFalse);
    });
  });

  group('HeuristicJdParser（无模型兜底）', () {
    const parser = HeuristicJdParser();

    test('识别「岗位名称：」并提取岗位标题', () async {
      final r = await parser.parse('岗位名称：后端开发工程师\n任职要求：\n- 熟悉 Java');
      expect(r.title, '后端开发工程师');
    });

    test('任职要求段内逐行转成草稿，且标记为推断项待确认', () async {
      final r = await parser.parse(
        '任职要求：\n'
        '1. 精通 Java 并发编程\n'
        '2. 熟悉 MySQL 索引优化\n'
        '3. 有分布式系统经验者优先',
      );
      expect(r.requirements.length, 3);
      expect(r.requirements.first.statement, '精通 Java 并发编程');
      expect(r.requirements.first.inferred, isTrue);
      expect(r.requirements.first.inferenceRationale, isNotNull);
    });

    test('命中「岗位职责」后停止收集', () async {
      final r = await parser.parse(
        '任职要求：\n'
        '- 熟悉 Java\n'
        '岗位职责：\n'
        '- 负责订单系统开发\n'
        '- 参与需求评审',
      );
      expect(r.requirements.length, 1);
      expect(r.requirements.first.statement, '熟悉 Java');
    });

    test('没有段落标题时，项目符号行仍被收集', () async {
      final r = await parser.parse(
        '- 熟悉 Kafka\n'
        '* 熟悉 Docker',
      );
      expect(r.requirements.length, 2);
      expect(r.requirements.first.statement, '熟悉 Kafka');
    });

    test('按线索推断重要度：精通→high，优先→low，其余→medium', () async {
      final r = await parser.parse(
        '任职要求：\n'
        '- 精通 JVM 内存模型\n'
        '- 熟悉 MQ 的基本使用\n'
        '- 有微服务经验者优先',
      );
      expect(r.requirements[0].importance, Importance.high);
      expect(r.requirements[1].importance, Importance.medium);
      expect(r.requirements[2].importance, Importance.low);
    });

    test('超过 maxRequirements 时截断', () async {
      const limited = HeuristicJdParser(maxRequirements: 2);
      final r = await limited.parse(
        '任职要求：\n'
        '- 熟悉 Java 并发编程\n'
        '- 熟悉 MySQL 索引优化\n'
        '- 熟悉 Kafka 消息队列\n'
        '- 熟悉 Docker 容器化',
      );
      expect(r.requirements.length, 2);
    });

    test('过短的行被忽略，避免把标题行当要求', () async {
      final r = await parser.parse(
        '任职要求：\n'
        '- 熟悉 Java\n'
        '- 着\n' // 去掉项目符号后仅 1 字，噪声
        '- 熟悉 MySQL',
      );
      expect(r.requirements.length, 2);
    });

    test('纯职责描述不会产出要求', () async {
      final r = await parser.parse('岗位职责：\n负责后端服务开发与维护');
      expect(r.requirements.length, 0);
    });
  });

  group('HttpJdFetcher.stripHtml', () {
    test('移除 script 与 style 内容', () {
      final text = HttpJdFetcher.stripHtml(
        '<html><head><style>.a{color:red}</style>'
        '<script>var x = 1;</script></head>'
        '<body>任职要求</body></html>',
      );
      expect(text.contains('var x'), isFalse);
      expect(text.contains('color:red'), isFalse);
      expect(text, contains('任职要求'));
    });

    test('块级标签转换为换行，保留段落结构', () {
      final text = HttpJdFetcher.stripHtml(
        '<p>第一段</p><p>第二段</p><ul><li>要点一</li><li>要点二</li></ul>',
      );
      final lines = text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      expect(lines, ['第一段', '第二段', '要点一', '要点二']);
    });

    test('解码常见 HTML 实体并折叠空白', () {
      final text = HttpJdFetcher.stripHtml(
        '<div>A&nbsp;&nbsp;B&amp;C &lt;T&gt; &#39;q&#39;</div>',
      );
      expect(text, contains('A B&C <T> '));
      expect(text, contains("'q'"));
    });

    test('折叠多余空行，不留下连续空行', () {
      final text = HttpJdFetcher.stripHtml('<p>A</p><br><br><br><p>B</p>');
      expect(text.contains('\n\n'), isFalse);
      expect(text, contains('A'));
      expect(text, contains('B'));
    });

    test('净化结果可直接交给兜底解析器', () async {
      final html =
          '<div><h3>任职要求</h3><ul>'
          '<li>精通 Java 并发</li><li>熟悉 MySQL 索引</li></ul></div>';
      final plain = HttpJdFetcher.stripHtml(html);
      final parsed = await const HeuristicJdParser().parse(plain);
      expect(parsed.requirements.length, 2);
      expect(parsed.requirements.first.statement, '精通 Java 并发');
    });
  });
}
