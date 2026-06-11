import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/pages/learning/dashboard_widgets.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('NextBestAction recommends a new topic for fresh users', (
    tester,
  ) async {
    String? openedTopicId;
    final topic = _topic(id: 'java.intro', title: 'Java 入门');

    await tester.pumpWidget(
      _wrap(
        NextBestAction(
          reviewTopics: const [],
          weakTopics: const [],
          newTopics: [topic],
          onTopicTap: (id) => openedTopicId = id,
        ),
      ),
    );

    expect(find.text('Java 入门'), findsOneWidget);
    expect(find.text('每日新学'), findsOneWidget);

    await tester.tap(find.text('开始学习'));
    expect(openedTopicId, 'java.intro');
  });

  testWidgets('NextBestAction prioritizes due review and opens review flow', (
    tester,
  ) async {
    var reviewOpened = false;
    String? openedTopicId;
    final reviewTopic = _topic(id: 'java.review', title: '需要复习的主题');
    final newTopic = _topic(id: 'java.new', title: '新主题');

    await tester.pumpWidget(
      _wrap(
        NextBestAction(
          reviewTopics: [reviewTopic],
          weakTopics: const [],
          newTopics: [newTopic],
          onTopicTap: (id) => openedTopicId = id,
          onReview: () => reviewOpened = true,
        ),
      ),
    );

    expect(find.text('需要复习的主题'), findsOneWidget);
    expect(find.text('新主题'), findsNothing);
    expect(find.text('待复习'), findsOneWidget);

    await tester.tap(find.text('开始复习'));
    expect(reviewOpened, isTrue);
    expect(openedTopicId, isNull);
  });
}

Widget _wrap(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => LocalizationProvider(initialLanguage: 'zh'),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Topic _topic({required String id, required String title}) {
  return Topic(
    id: id,
    domain: 'java',
    category: 'base',
    title: title,
    summary: '',
    estimatedMinutes: 15,
  );
}
