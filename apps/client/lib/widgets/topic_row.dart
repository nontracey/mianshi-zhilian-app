import 'package:flutter/material.dart';
import '../models/topic.dart';
import '../models/user_progress.dart';
import 'status_dot.dart';

class TopicRow extends StatelessWidget {
  const TopicRow({
    super.key,
    required this.topic,
    this.progress,
    required this.onLearn,
    required this.onDetail,
  });

  final Topic topic;
  final TopicProgress? progress;
  final VoidCallback onLearn;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    final score = progress?.score ?? 0;
    final statusText = progress?.status ?? 'new';
    final statusLabel = switch (statusText) {
      'mastered' => '已掌握',
      'learning' => '学习中',
      _ => '未开始',
    };

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: StatusDot(score: score),
        title: Text(topic.title),
        subtitle: Text(topic.summary),
        trailing: Wrap(
          spacing: 8,
          children: [
            OutlinedButton(onPressed: onDetail, child: const Text('知识查阅')),
            FilledButton(onPressed: onLearn, child: const Text('学习模式')),
          ],
        ),
      ),
    );
  }
}
