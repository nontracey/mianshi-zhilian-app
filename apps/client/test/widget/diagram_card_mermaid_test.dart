import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/pages/learning/topic_detail_cards.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';

void main() {
  testWidgets('CodeCard renders line highlight notes', (tester) async {
    final card = LearningCard(
      type: 'code',
      title: '代码高亮',
      language: 'java',
      content: 'class Demo {\\n  void run() {}\\n}',
      highlights: [
        {'line': 2, 'note': '这里是需要重点解释的调用入口。'},
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 640, child: CodeCard(card: card)),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('JAVA'), findsOneWidget);
    expect(find.textContaining('L2: 这里是需要重点解释的调用入口。'), findsOneWidget);
  });

  testWidgets('DiagramCard renders Mermaid flowcharts as diagram nodes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final l10n = LocalizationProvider(initialLanguage: 'zh');
    const card = LearningCard(
      type: 'diagram',
      title: 'Mermaid 流程',
      format: 'mermaid',
      content: '''
```mermaid
flowchart TD
  A[开始] --> B{判断}
  B -->|通过| C[完成]
```
''',
      caption: '流程图说明',
      fallback: '无法渲染时显示文本说明',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: l10n,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(width: 480, child: DiagramCard(card: card)),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('MERMAID'), findsOneWidget);
    expect(find.text('开始'), findsOneWidget);
    expect(find.text('判断'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('通过'), findsOneWidget);
    expect(find.text('流程图说明'), findsOneWidget);
    expect(find.textContaining('flowchart TD'), findsNothing);
  });

  test('MermaidDiagramData cross-line label fillback', () {
    // 模拟真实内容格式：第一行 A/B 带 label，后续行只引用 ID 不带 label
    final data = MermaidDiagramData.parse('''
flowchart TD
  A[事件风暴] --> B[识别子域]
  B --> C[划分限界上下文]
  C --> D[设计聚合]
''');

    expect(data.edges.length, 3);

    // 第一条边：A 和 B 都有 label
    expect(data.edges[0].source.label, '事件风暴');
    expect(data.edges[0].target.label, '识别子域');

    // 第二条边：B 只写 ID，应回填为 "识别子域"
    expect(data.edges[1].source.label, '识别子域');
    expect(data.edges[1].target.label, '划分限界上下文');

    // 第三条边：C 只写 ID，应回填为 "划分限界上下文"
    expect(data.edges[2].source.label, '划分限界上下文');
    expect(data.edges[2].target.label, '设计聚合');
  });
}
