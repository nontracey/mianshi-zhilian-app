import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/pages/learning/topic_detail_cards.dart';

void main() {
  group('MermaidDiagramData.parse classDef', () {
    test('内联 :::ok / :::warn 提取到 className', () {
      final data = MermaidDiagramData.parse('flowchart LR\nA:::ok --> B:::warn');
      expect(data.edges.length, 1);
      expect(data.edges.first.source.className, 'ok');
      expect(data.edges.first.target.className, 'warn');
    });

    test('class A,B ok 声明回填到未标 className 的节点', () {
      final data = MermaidDiagramData.parse('flowchart LR\nA --> B\nclass A,B ok');
      expect(data.edges.length, 1);
      expect(data.edges.first.source.className, 'ok');
      expect(data.edges.first.target.className, 'ok');
    });

    test('classDef 声明行被跳过，不当作边或节点', () {
      final data = MermaidDiagramData.parse(
        'flowchart LR\nclassDef ok fill:#10b981,stroke:#059669,color:#fff\nA:::ok --> B',
      );
      expect(data.edges.length, 1);
      expect(data.edges.first.source.className, 'ok');
      expect(data.edges.first.target.className, isNull);
    });

    test('class 声明不覆盖已内联的 :::className', () {
      final data = MermaidDiagramData.parse(
        'flowchart LR\nA:::warn --> B\nclass A fail',
      );
      expect(data.edges.first.source.className, 'warn');
    });
  });

  group('MermaidDiagramData.parse subgraph', () {
    test('两个顶层 subgraph 收集到 nodeIds', () {
      final data = MermaidDiagramData.parse(
        'flowchart TD\n'
        'subgraph g1 [组一]\nA --> B\nend\n'
        'subgraph g2 [组二]\nC --> D\nend\n'
        'A --> C',
      );
      expect(data.subgraphs.length, 2);
      expect(data.subgraphs[0].id, 'g1');
      expect(data.subgraphs[0].title, '组一');
      expect(data.subgraphs[0].nodeIds, containsAll(['A', 'B']));
      expect(data.subgraphs[1].nodeIds, containsAll(['C', 'D']));
      // A-->C 跨组，A/C 仍归到各自组
      expect(data.edges.length, 3);
    });

    test('嵌套 subgraph 2 层', () {
      final data = MermaidDiagramData.parse(
        'flowchart TD\n'
        'subgraph outer [外层]\n'
        'A --> B\n'
        'subgraph inner [内层]\nC --> D\nend\n'
        'end\n',
      );
      expect(data.subgraphs.length, 1);
      expect(data.subgraphs[0].id, 'outer');
      expect(data.subgraphs[0].children.length, 1);
      expect(data.subgraphs[0].children.first.id, 'inner');
      expect(data.subgraphs[0].children.first.nodeIds, containsAll(['C', 'D']));
      // A/B 归 outer 自身 nodeIds（parse 时记到栈顶 frame）
      expect(data.subgraphs[0].nodeIds, containsAll(['A', 'B']));
    });

    test('subgraph 无标题时 title=id', () {
      final data = MermaidDiagramData.parse(
        'flowchart TD\nsubgraph grp1\nA --> B\nend\n',
      );
      expect(data.subgraphs.length, 1);
      expect(data.subgraphs[0].title, 'grp1');
    });

    test('无 subgraph 时 subgraphs 为空（零回归）', () {
      final data = MermaidDiagramData.parse('flowchart LR\nA --> B');
      expect(data.subgraphs, isEmpty);
    });
  });

  group('StateDiagramData.parse', () {
    test('起止态 + 冒号标签 + 普通转移', () {
      final data = StateDiagramData.parse(
        'stateDiagram-v2\n'
        '[*] --> Active\n'
        'Active --> Inactive : sleep\n'
        'Inactive --> [*]',
      );
      expect(data.transitions.length, 3);
      // 第一条：start -> Active
      expect(data.transitions[0].from.isStart, isTrue);
      expect(data.transitions[0].to.id, 'Active');
      expect(data.transitions[0].label, isNull);
      // 第二条：Active -> Inactive, label=sleep
      expect(data.transitions[1].from.id, 'Active');
      expect(data.transitions[1].to.id, 'Inactive');
      expect(data.transitions[1].label, 'sleep');
      // 第三条：Inactive -> end
      expect(data.transitions[2].from.id, 'Inactive');
      expect(data.transitions[2].to.isEnd, isTrue);
    });

    test('state "label" as id 命名', () {
      final data = StateDiagramData.parse(
        'stateDiagram-v2\n'
        'state "长标签" as S1\n'
        '[*] --> S1\n'
        'S1 --> [*]',
      );
      expect(data.transitions[0].to.label, '长标签');
    });

    test('无转移时 isRenderable=false', () {
      final data = StateDiagramData.parse('stateDiagram-v2\n');
      expect(data.isRenderable, isFalse);
    });
  });

  group('parseMermaidDiagram dispatcher', () {
    test('flowchart 头部分派到 MermaidDiagramData', () {
      final d = parseMermaidDiagram('flowchart LR\nA --> B');
      expect(d, isA<MermaidDiagramData>());
    });
    test('stateDiagram-v2 头部分派到 StateDiagramData', () {
      final d = parseMermaidDiagram('stateDiagram-v2\n[*] --> A');
      expect(d, isA<StateDiagramData>());
    });
    test('sequenceDiagram 头部分派到 SequenceDiagramData', () {
      final d = parseMermaidDiagram('sequenceDiagram\nA->>B: hi');
      expect(d, isA<SequenceDiagramData>());
    });
    test('未知头部退到 MermaidDiagramData（ASCII 兜底）', () {
      final d = parseMermaidDiagram('unknownDiagram\nfoo');
      expect(d, isA<MermaidDiagramData>());
    });
  });

  group('SequenceDiagramData.parse', () {
    test('participant 声明 + 3 条消息', () {
      final data = SequenceDiagramData.parse(
        'sequenceDiagram\n'
        'participant Alice\n'
        'participant Bob\n'
        'Alice->>Bob: 请求\n'
        'Bob-->>Alice: 响应\n'
        'Alice->>Bob: 确认',
      );
      expect(data.participants.length, 2);
      expect(data.participants[0].id, 'Alice');
      expect(data.participants[1].id, 'Bob');
      expect(data.messages.length, 3);
      expect(data.messages[0].type, SeqMessageType.asyncSolid);
      expect(data.messages[1].type, SeqMessageType.dashedReturn);
      expect(data.messages[1].label, '响应');
    });

    test('消息里出现的 participant 自动补全', () {
      final data = SequenceDiagramData.parse(
        'sequenceDiagram\n'
        'Alice->>Bob: hi',
      );
      expect(data.participants.length, 2);
      expect(data.participants.any((p) => p.id == 'Alice'), isTrue);
      expect(data.participants.any((p) => p.id == 'Bob'), isTrue);
    });

    test('loop 块记录 startMsgIndex/endMsgIndex', () {
      final data = SequenceDiagramData.parse(
        'sequenceDiagram\n'
        'participant A\n'
        'participant B\n'
        'A->>B: 开始\n'
        'loop 重试\n'
        'A->>B: 询问\n'
        'B-->>A: 未就绪\n'
        'end\n'
        'A->>B: 结束',
      );
      expect(data.messages.length, 4);
      expect(data.blocks.length, 1);
      expect(data.blocks[0].type, 'loop');
      expect(data.blocks[0].title, '重试');
      expect(data.blocks[0].startMsgIndex, 1);
      expect(data.blocks[0].endMsgIndex, 2);
    });

    test('4 种消息类型映射', () {
      final data = SequenceDiagramData.parse(
        'sequenceDiagram\n'
        'participant A\n'
        'participant B\n'
        'A->>B: async\n'
        'B-->>A: return\n'
        'A->B: sync\n'
        'A-xB: fail',
      );
      expect(data.messages[0].type, SeqMessageType.asyncSolid);
      expect(data.messages[1].type, SeqMessageType.dashedReturn);
      expect(data.messages[2].type, SeqMessageType.sync);
      expect(data.messages[3].type, SeqMessageType.fail);
    });

    test('participant as 带引号别名', () {
      final data = SequenceDiagramData.parse(
        'sequenceDiagram\n'
        'participant A as "客户端"\n'
        'A->>A: 自调用',
      );
      expect(data.participants[0].label, '客户端');
    });

    test('无消息时 isRenderable=false', () {
      final data = SequenceDiagramData.parse('sequenceDiagram\nparticipant A');
      expect(data.isRenderable, isFalse);
    });
  });

  group('MermaidDiagramView 渲染 smoke', () {
    Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('flowchart 渲染不崩 + 找到 MERMAID 标签', (tester) async {
      final card = LearningCard(
        type: 'diagram',
        title: '图',
        content: 'flowchart LR\nA --> B',
        format: 'mermaid',
      );
      await tester.pumpWidget(_wrap(MermaidDiagramView(card: card)));
      expect(find.text('MERMAID'), findsOneWidget);
    });

    testWidgets('含 classDef + subgraph 的 flowchart 渲染不崩', (tester) async {
      final card = LearningCard(
        type: 'diagram',
        title: '图',
        content: 'flowchart TD\nsubgraph g1 [组一]\nA:::ok --> B:::warn\nend\nA --> C',
        format: 'mermaid',
      );
      await tester.pumpWidget(_wrap(MermaidDiagramView(card: card)));
      expect(find.text('组一'), findsOneWidget);
    });

    testWidgets('stateDiagram 渲染不崩 + 找到 STATE 标签', (tester) async {
      final card = LearningCard(
        type: 'diagram',
        title: '状态机',
        content: 'stateDiagram-v2\n[*] --> Active\nActive --> Inactive : sleep\nInactive --> [*]',
        format: 'mermaid',
      );
      await tester.pumpWidget(_wrap(MermaidDiagramView(card: card)));
      expect(find.text('STATE'), findsOneWidget);
      expect(find.text('sleep'), findsOneWidget);
    });

    testWidgets('sequenceDiagram 渲染不崩 + 找到 SEQUENCE 标签', (tester) async {
      final card = LearningCard(
        type: 'diagram',
        title: '时序',
        content: 'sequenceDiagram\nparticipant A\nparticipant B\nA->>B: 请求\nB-->>A: 响应',
        format: 'mermaid',
      );
      await tester.pumpWidget(_wrap(MermaidDiagramView(card: card)));
      expect(find.text('SEQUENCE'), findsOneWidget);
      expect(find.text('请求'), findsOneWidget);
    });

    testWidgets('sequenceDiagram 含 loop 块渲染不崩', (tester) async {
      final card = LearningCard(
        type: 'diagram',
        title: '时序',
        content: 'sequenceDiagram\nparticipant A\nparticipant B\nA->>B: 开始\nloop 重试\nA->>B: 询问\nend',
        format: 'mermaid',
      );
      await tester.pumpWidget(_wrap(MermaidDiagramView(card: card)));
      expect(find.text('loop: 重试'), findsOneWidget);
    });

    testWidgets('无法解析的 mermaid 退到 ASCII 兜底不崩', (tester) async {
      final card = LearningCard(
        type: 'diagram',
        title: '坏图',
        content: 'garbageNoHeader',
        format: 'mermaid',
      );
      await tester.pumpWidget(_wrap(MermaidDiagramView(card: card)));
      // 不崩即可
      expect(find.byType(MermaidDiagramView), findsOneWidget);
    });
  });
}
