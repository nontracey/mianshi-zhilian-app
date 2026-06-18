part of '../topic_detail_cards.dart';

// ── sequenceDiagram ─────────────────────────────────────────

enum SeqMessageType {
  /// ->> 实线开箭头（异步消息）
  asyncSolid,
  /// -->> 虚线开箭头（返回）
  dashedReturn,
  /// -> 实线箭头（同步调用）
  sync,
  /// -x 实线叉（失败）
  fail,
}

class SeqParticipant {
  const SeqParticipant({required this.id, required this.label});

  final String id;
  final String label;
}

class SeqMessage {
  const SeqMessage({
    required this.from,
    required this.to,
    required this.label,
    required this.type,
  });

  final String from;
  final String to;
  final String label;
  final SeqMessageType type;
}

class SeqNote {
  const SeqNote({required this.text, required this.side, required this.participantIds});

  final String text;
  final String side; // left / right / over
  final List<String> participantIds;
}

class SeqBlock {
  const SeqBlock({
    required this.type,
    required this.title,
    required this.startMsgIndex,
    required this.endMsgIndex,
  });

  final String type; // loop / alt / opt
  final String title;
  final int startMsgIndex;
  final int endMsgIndex;
}

class SequenceDiagramData implements MermaidDiagram {
  const SequenceDiagramData({
    required this.source,
    required this.participants,
    required this.messages,
    this.notes = const [],
    this.blocks = const [],
  });

  @override
  final String source;
  final List<SeqParticipant> participants;
  final List<SeqMessage> messages;
  final List<SeqNote> notes;
  final List<SeqBlock> blocks;

  static const double laneWidth = 96;
  static const double msgHeight = 56;

  @override
  bool get isRenderable => participants.isNotEmpty && messages.isNotEmpty;

  static SequenceDiagramData parse(String content) {
    final source = MermaidDiagramData.cleanSource(content);
    final lines = source
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('%%'))
        .toList();

    var startIndex = 0;
    if (lines.isNotEmpty &&
        RegExp(r'^sequenceDiagram\b', caseSensitive: false).hasMatch(lines.first)) {
      startIndex = 1;
    }

    final participants = <SeqParticipant>[];
    final messages = <SeqMessage>[];
    final notes = <SeqNote>[];
    final blocks = <SeqBlock>[];
    final blockStack = <_SeqBlockFrame>[];

    void ensureParticipant(String id) {
      if (id.isEmpty) return;
      if (participants.any((p) => p.id == id)) return;
      participants.add(SeqParticipant(id: id, label: id));
    }

    for (final line in lines.skip(startIndex)) {
      // participant X [as "Lbl"] / actor X [as "Lbl"]
      final pMatch = RegExp(
        r'^(?:participant|actor)\s+(\w+)(?:\s+as\s+"?([^"]+?)"?\s*)?$',
      ).firstMatch(line);
      if (pMatch != null) {
        final id = pMatch.group(1)!;
        final label = pMatch.group(2) ?? id;
        if (!participants.any((p) => p.id == id)) {
          participants.add(SeqParticipant(id: id, label: label));
        }
        continue;
      }

      // 消息：A->>B: msg / A-->>B: msg / A->B: msg / A-xB: msg
      final mMatch = RegExp(
        r'^(\w+)\s*(->>|-->>|->|-x)\s*(\w+)\s*:\s*(.+)$',
      ).firstMatch(line);
      if (mMatch != null) {
        final from = mMatch.group(1)!;
        final arrow = mMatch.group(2)!;
        final to = mMatch.group(3)!;
        final label = mMatch.group(4)!.trim();
        final type = switch (arrow) {
          '->>' => SeqMessageType.asyncSolid,
          '-->>' => SeqMessageType.dashedReturn,
          '->' => SeqMessageType.sync,
          '-x' => SeqMessageType.fail,
          _ => SeqMessageType.sync,
        };
        ensureParticipant(from);
        ensureParticipant(to);
        messages.add(SeqMessage(from: from, to: to, label: label, type: type));
        continue;
      }

      // Note over A,B: text / Note left of A: text / Note right of A: text
      final noteOver = RegExp(
        r'^Note\s+over\s+(\w+(?:\s*,\s*\w+)*)\s*:\s*(.+)$',
      ).firstMatch(line);
      if (noteOver != null) {
        final ids = noteOver.group(1)!.split(',').map((s) => s.trim()).toList();
        final text = noteOver.group(2)!.trim();
        for (final id in ids) {
          ensureParticipant(id);
        }
        notes.add(SeqNote(text: text, side: 'over', participantIds: ids));
        continue;
      }
      final noteSide = RegExp(
        r'^Note\s+(left|right)\s+of\s+(\w+)\s*:\s*(.+)$',
      ).firstMatch(line);
      if (noteSide != null) {
        final side = noteSide.group(1)!;
        final id = noteSide.group(2)!;
        final text = noteSide.group(3)!.trim();
        ensureParticipant(id);
        notes.add(SeqNote(text: text, side: side, participantIds: [id]));
        continue;
      }

      // loop/alt/opt title
      final blockOpen = RegExp(r'^(loop|alt|opt)\s+(.+)$').firstMatch(line);
      if (blockOpen != null) {
        final type = blockOpen.group(1)!;
        final title = blockOpen.group(2)!.trim();
        blockStack.add(_SeqBlockFrame(
          type: type,
          title: title,
          startMsgIndex: messages.length,
        ));
        continue;
      }

      // end（块结束）
      if (RegExp(r'^end$').hasMatch(line)) {
        if (blockStack.isNotEmpty) {
          final frame = blockStack.removeLast();
          blocks.add(SeqBlock(
            type: frame.type,
            title: frame.title,
            startMsgIndex: frame.startMsgIndex,
            endMsgIndex: messages.length - 1,
          ));
        }
        continue;
      }
      // else 分支：alt 的分支分隔，当前简化为不单独建模（块边框统一画在 alt 范围）
    }

    return SequenceDiagramData(
      source: source,
      participants: participants,
      messages: messages,
      notes: notes,
      blocks: blocks,
    );
  }
}

class _SeqBlockFrame {
  _SeqBlockFrame({required this.type, required this.title, required this.startMsgIndex});

  final String type;
  final String title;
  final int startMsgIndex;
}

class _SequenceDiagramView extends StatelessWidget {
  const _SequenceDiagramView({required this.data});

  final SequenceDiagramData data;

  @override
  Widget build(BuildContext context) {
    final width = data.participants.length * SequenceDiagramData.laneWidth;
    final msgAreaHeight = data.messages.length * SequenceDiagramData.msgHeight;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTypeTag(),
            const SizedBox(height: 12),
            _buildHeader(),
            const SizedBox(height: 4),
            SizedBox(
              height: msgAreaHeight > 0 ? msgAreaHeight : 40,
              child: Stack(
                children: [
                  _buildLifelines(msgAreaHeight),
                  _buildMessages(),
                  ..._buildBlocks(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_horiz, size: 16, color: AppColors.accent),
          SizedBox(width: 6),
          Text(
            'SEQUENCE',
            style: TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        for (final p in data.participants)
          SizedBox(
            width: SequenceDiagramData.laneWidth,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
              ),
              child: Text(
                p.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 生命线：每个 participant 列一条竖虚线
  Widget _buildLifelines(double height) {
    return CustomPaint(
      painter: _LifelinePainter(
        count: data.participants.length,
        laneWidth: SequenceDiagramData.laneWidth,
        color: AppColors.accent.withValues(alpha: 0.3),
        height: height,
      ),
      size: Size.infinite,
    );
  }

  Widget _buildMessages() {
    return Column(
      children: [
        for (final msg in data.messages) _buildMessageRow(msg),
      ],
    );
  }

  Widget _buildMessageRow(SeqMessage msg) {
    final fromIdx = data.participants.indexWhere((p) => p.id == msg.from);
    final toIdx = data.participants.indexWhere((p) => p.id == msg.to);
    if (fromIdx < 0 || toIdx < 0) {
      return SizedBox(height: SequenceDiagramData.msgHeight);
    }
    final lo = fromIdx < toIdx ? fromIdx : toIdx;
    final hi = fromIdx < toIdx ? toIdx : fromIdx;
    final isRightward = fromIdx < toIdx;

    return SizedBox(
      height: SequenceDiagramData.msgHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: (lo + 0.5) * SequenceDiagramData.laneWidth,
            ),
            child: SizedBox(
              width: (hi - lo) * SequenceDiagramData.laneWidth,
              child: Text(
                msg.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 16,
            child: Row(
              children: List.generate(data.participants.length, (i) {
                if (i < lo || i > hi) {
                  return SizedBox(width: SequenceDiagramData.laneWidth);
                }
                if (i == lo) {
                  return SizedBox(
                    width: SequenceDiagramData.laneWidth,
                    child: Align(
                      alignment: isRightward ? Alignment.centerRight : Alignment.centerLeft,
                      child: _arrowEnd(isRightward, msg.type),
                    ),
                  );
                }
                if (i == hi) {
                  return SizedBox(
                    width: SequenceDiagramData.laneWidth,
                    child: Align(
                      alignment: isRightward ? Alignment.centerLeft : Alignment.centerRight,
                      child: _arrowHead(isRightward, msg.type),
                    ),
                  );
                }
                return SizedBox(
                  width: SequenceDiagramData.laneWidth,
                  child: Center(child: _arrowLine(msg.type)),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _arrowEnd(bool isRightward, SeqMessageType type) {
    final isDashed = type == SeqMessageType.dashedReturn;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isRightward) Icon(Icons.chevron_left, size: 14, color: _arrowColor(type)),
        Container(
          width: 14,
          height: 2,
          color: _arrowColor(type),
          child: isDashed
              ? Row(
                  children: List.generate(
                    3,
                    (_) => const Expanded(child: SizedBox()),
                  ),
                )
              : null,
        ),
      ],
    );
  }

  Widget _arrowHead(bool isRightward, SeqMessageType type) {
    if (type == SeqMessageType.fail) {
      return Icon(Icons.close, size: 14, color: _arrowColor(type));
    }
    return Icon(
      isRightward ? Icons.chevron_right : Icons.chevron_left,
      size: 14,
      color: _arrowColor(type),
    );
  }

  Widget _arrowLine(SeqMessageType type) {
    final isDashed = type == SeqMessageType.dashedReturn;
    if (isDashed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(4, (i) => Container(
          width: 4,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          color: _arrowColor(type),
        )),
      );
    }
    return Container(width: 40, height: 2, color: _arrowColor(type));
  }

  Color _arrowColor(SeqMessageType type) {
    return switch (type) {
      SeqMessageType.fail => AppColors.categoryRed,
      SeqMessageType.dashedReturn => AppColors.categoryAmber,
      _ => AppColors.accent,
    };
  }

  /// 块边框（loop/alt/opt）：按 startMsgIndex/endMsgIndex 定位
  List<Widget> _buildBlocks() {
    final result = <Widget>[];
    for (final b in data.blocks) {
      if (b.endMsgIndex < b.startMsgIndex) continue;
      final top = b.startMsgIndex * SequenceDiagramData.msgHeight;
      final height = (b.endMsgIndex - b.startMsgIndex + 1) * SequenceDiagramData.msgHeight;
      result.add(
        Positioned(
          left: 4,
          top: top,
          right: 4,
          height: height,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.categoryPurple.withValues(alpha: 0.5),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.only(left: 8, top: 2),
            alignment: Alignment.topLeft,
            child: Text(
              '${b.type}: ${b.title}',
              style: TextStyle(
                color: AppColors.categoryPurple,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                background: Paint()..color = AppColors.codeBgDark,
              ),
            ),
          ),
        ),
      );
    }
    return result;
  }
}

class _LifelinePainter extends CustomPainter {
  const _LifelinePainter({
    required this.count,
    required this.laneWidth,
    required this.color,
    required this.height,
  });

  final int count;
  final double laneWidth;
  final Color color;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < count; i += 1) {
      final x = (i + 0.5) * laneWidth;
      // 虚线：每 4px 画 3px
      var y = 0.0;
      while (y < height) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, y + 3),
          paint,
        );
        y += 6;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LifelinePainter oldDelegate) =>
      oldDelegate.count != count ||
      oldDelegate.laneWidth != laneWidth ||
      oldDelegate.color != color ||
      oldDelegate.height != height;
}
