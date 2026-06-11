import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/topic.dart';

Topic _topicWithStatus(String? status) => Topic(
  id: 'topic-${status ?? 'null'}',
  domain: 'java',
  category: 'jvm',
  title: 'Topic',
  summary: 'Summary',
  status: status,
);

void main() {
  test('normalizes topic status contract values', () {
    expect(_topicWithStatus(null).normalizedStatus, 'production');
    expect(_topicWithStatus('production').isProductionStatus, isTrue);
    expect(_topicWithStatus('staging').isStagingStatus, isTrue);
    expect(_topicWithStatus('test').isStagingStatus, isTrue);
    expect(_topicWithStatus('draft').normalizedStatus, 'draft');
    expect(_topicWithStatus('unknown').normalizedStatus, 'draft');
  });

  test('rotates recall prompts by seed and respects preferred mode', () {
    const topic = Topic(
      id: 'java.hashmap',
      domain: 'java',
      category: 'collections',
      title: 'HashMap',
      summary: 'Summary',
      recallPrompts: [
        RecallPrompt(id: 'r1', prompt: '讲原理'),
        RecallPrompt(id: 'r2', prompt: '讲扩容'),
        RecallPrompt(id: 'r3', prompt: '手写代码', mode: 'code'),
      ],
    );

    expect(topic.recallPromptAt(0)?.id, 'r1');
    expect(topic.recallPromptAt(1)?.id, 'r2');
    expect(topic.recallPromptAt(2)?.id, 'r3');
    expect(topic.recallPromptAt(3)?.id, 'r1');
    expect(topic.recallPromptAt(4, mode: 'code')?.id, 'r3');
    expect(topic.recallPromptAt(4, mode: 'voice')?.id, 'r2');
  });
}
