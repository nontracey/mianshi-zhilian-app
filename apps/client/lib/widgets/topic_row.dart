import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/topic.dart';
import '../models/user_progress.dart';
import '../providers/localization_provider.dart';
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
    final l10n = context.watch<LocalizationProvider>();
    final score = progress?.score ?? 0;

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
            OutlinedButton(onPressed: onDetail, child: Text(l10n.get('knowledge_check_read'))),
            FilledButton(onPressed: onLearn, child: Text(l10n.get('learning_mode'))),
          ],
        ),
      ),
    );
  }
}
