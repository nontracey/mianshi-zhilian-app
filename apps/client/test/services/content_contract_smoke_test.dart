import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';

String _contentRoot() {
  final explicit = Platform.environment['CONTENT_REPO_PATH'];
  if (explicit != null && explicit.trim().isNotEmpty) {
    return explicit.replaceFirst(RegExp(r'[/\\]$'), '');
  }
  return '../../../mianshi-zhilian-content';
}

Map<String, dynamic> _readJson(String root, String relativePath) {
  final file = File('$root/$relativePath');
  return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  final root = _contentRoot();
  final hasContentRepo = File('$root/staging-manifest.json').existsSync();

  test(
    'app models parse the current staging content contract',
    () {
      final manifest = _readJson(root, 'staging-manifest.json');
      final manifestDomains = (manifest['domains'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      var topicCount = 0;
      var sawMermaidDiagram = false;
      var sawCodeCard = false;
      var sawCompareTable = false;
      var sawInterviewFollowUps = false;

      for (final manifestDomain in manifestDomains) {
        final manifestDomainEntry = Domain.fromJson(manifestDomain);
        expect(manifestDomainEntry.entry, isNotEmpty);

        final domain = Domain.fromJson(
          _readJson(root, manifestDomainEntry.entry!),
        );
        expect(domain.id, manifestDomainEntry.id);
        expect(domain.categories, isNotEmpty, reason: domain.id);

        for (final category in domain.categories) {
          expect(category.topics, isNotEmpty,
              reason: '${domain.id}/${category.id}');

          for (final topicPath in category.topics) {
            final rawTopic = _readJson(root, topicPath);
            final topic = Topic.fromJson(rawTopic);
            topicCount += 1;

            expect(topic.id, isNotEmpty, reason: topicPath);
            expect(topic.domainId, domain.id, reason: topicPath);
            expect(topic.categoryId, category.id, reason: topicPath);
            expect(topic.normalizedStatus, 'staging', reason: topicPath);
            expect(topic.learningCards, isNotEmpty, reason: topicPath);
            expect(topic.recallPrompts, isNotEmpty, reason: topicPath);
            expect(topic.rubric?.mustHave, isNotEmpty, reason: topicPath);

            final weights = topic.rubric?.scoreWeights;
            expect(
              weights?.keys,
              containsAll([
                'coverage',
                'accuracy',
                'interviewExpression',
                'depth',
              ]),
              reason: topicPath,
            );

            if (topic.followUps.isNotEmpty) {
              sawInterviewFollowUps = true;
            }

            for (final card in topic.learningCards) {
              if (card.type == 'diagram' && card.format == 'mermaid') {
                sawMermaidDiagram = true;
                expect(
                  card.content.trimLeft(),
                  matches(RegExp(
                      r'^(?:(?:flowchart|graph)\s+(?:TB|TD|BT|RL|LR)\b|stateDiagram(?:-v2)?\b|sequenceDiagram\b)')),
                  reason: topicPath,
                );
              }
              if (card.type == 'code') {
                sawCodeCard = true;
                expect(card.language, isNotEmpty, reason: topicPath);
              }
              if (card.type == 'compareTable') {
                sawCompareTable = true;
                expect(
                  card.content.isNotEmpty ||
                      (card.columns.isNotEmpty && card.rows.isNotEmpty),
                  isTrue,
                  reason: topicPath,
                );
              }
            }
          }
        }
      }

      expect(topicCount, manifest['topicCount']);
      expect(sawMermaidDiagram, isTrue);
      expect(sawCodeCard, isTrue);
      expect(sawCompareTable, isTrue);
      expect(sawInterviewFollowUps, isTrue);
    },
    skip: hasContentRepo
        ? false
        : 'Set CONTENT_REPO_PATH or keep mianshi-zhilian-content next to the app repo.',
  );
}
