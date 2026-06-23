import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/topic.dart';

void main() {
  group('CardSource', () {
    test('fromJson svg', () {
      final source = CardSource.fromJson({
        'kind': 'svg',
        'path': 'assets/diagrams/test.svg',
      });
      expect(source.kind, 'svg');
      expect(source.path, 'assets/diagrams/test.svg');
      expect(source.content, isNull);
    });

    test('fromJson inline svg', () {
      final source = CardSource.fromJson({
        'kind': 'svg',
        'content': '<svg viewBox="0 0 10 10"></svg>',
      });
      expect(source.kind, 'svg');
      expect(source.content, startsWith('<svg'));
      expect(source.path, isNull);
    });

    test('fromJson mermaid', () {
      final source = CardSource.fromJson({
        'kind': 'mermaid',
        'content': 'flowchart LR\nA --> B',
      });
      expect(source.kind, 'mermaid');
      expect(source.content, 'flowchart LR\nA --> B');
      expect(source.path, isNull);
    });

    test('toJson 往返', () {
      final source = CardSource(kind: 'svg', path: 'assets/diagrams/test.svg');
      final restored = CardSource.fromJson(source.toJson());
      expect(restored.kind, 'svg');
      expect(restored.path, 'assets/diagrams/test.svg');
    });
  });

  group('LearningCard.toSources() 旧卡片兼容', () {
    test('旧 mermaid diagram → mermaid source', () {
      final card = LearningCard(
        type: 'diagram',
        title: '图',
        content: 'flowchart LR\nA --> B',
        format: 'mermaid',
      );
      final s = card.toSources();
      expect(s.length, 1);
      expect(s[0].kind, 'mermaid');
    });

    test('旧 mermaid + svg asset → svg 优先, mermaid 兜底', () {
      final card = LearningCard(
        type: 'diagram',
        title: '图',
        content: 'flowchart TD\nA --> B',
        format: 'mermaid',
        asset: 'assets/diagrams/backup.svg',
      );
      final s = card.toSources();
      expect(s.length, 2);
      expect(s[0].kind, 'svg');
      expect(s[1].kind, 'mermaid');
    });

    test('旧 animation asset only → svg source', () {
      final card = LearningCard(
        type: 'animation',
        title: '动图',
        content: '',
        asset: 'assets/java/memory-flow.svg',
        fallback: '文字',
      );
      final s = card.toSources();
      expect(s.length, 1);
      expect(s[0].kind, 'svg');
    });

    test('旧 animation asset + content → svg → text', () {
      final card = LearningCard(
        type: 'animation',
        title: '动图',
        content: '文字描述',
        asset: 'assets/animation.svg',
      );
      final s = card.toSources();
      expect(s.length, 2);
      expect(s[0].kind, 'svg');
      expect(s[1].kind, 'text');
    });

    test('已有 sources 字段 → 直接返回', () {
      final card = LearningCard(
        type: 'diagram',
        title: '新图',
        content: 'ignored',
        format: 'mermaid',
        asset: 'ignored.svg',
        sources: [
          CardSource(kind: 'mermaid', content: 'flowchart LR\nX --> Y'),
          CardSource(kind: 'text', content: '兜底'),
        ],
      );
      final s = card.toSources();
      expect(s.length, 2);
      expect(s[0].kind, 'mermaid');
    });

    test('空卡 → 空', () {
      final card = LearningCard(
        type: 'diagram',
        title: '空',
        content: '',
        format: null,
        asset: null,
      );
      expect(card.toSources(), isEmpty);
    });
  });

  group('sources 降级链语义', () {
    test('svg → mermaid → text 三层', () {
      final card = LearningCard(
        type: 'diagram',
        title: '图',
        content: '',
        sources: [
          CardSource(kind: 'svg', path: 'assets/diagrams/test.svg'),
          CardSource(kind: 'mermaid', content: 'flowchart LR\nA --> B'),
          CardSource(kind: 'text', content: '兜底'),
        ],
      );
      final s = card.toSources();
      expect(s.length, 3);
      expect(s[0].kind, 'svg');
      expect(s[1].kind, 'mermaid');
      expect(s[2].kind, 'text');
    });

    test('mermaid + text 两层', () {
      final card = LearningCard(
        type: 'diagram',
        title: '图',
        content: '',
        sources: [
          CardSource(
            kind: 'mermaid',
            content: 'stateDiagram-v2\n[*] --> Active',
          ),
          CardSource(kind: 'text', content: '兜底'),
        ],
      );
      final s = card.toSources();
      expect(s.length, 2);
      expect(s[0].kind, 'mermaid');
      expect(s[1].kind, 'text');
    });
  });
}
