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
}
