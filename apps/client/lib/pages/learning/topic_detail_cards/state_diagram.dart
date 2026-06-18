part of '../topic_detail_cards.dart';

// ── stateDiagram / stateDiagram-v2 ──────────────────────────

class StateNode {
  const StateNode({
    required this.id,
    required this.label,
    this.isStart = false,
    this.isEnd = false,
  });

  final String id;
  final String label;
  final bool isStart;
  final bool isEnd;
}

class StateTransition {
  const StateTransition({required this.from, required this.to, this.label});

  final StateNode from;
  final StateNode to;
  final String? label;
}

class StateDiagramData implements MermaidDiagram {
  const StateDiagramData({required this.source, required this.transitions});

  @override
  final String source;
  final List<StateTransition> transitions;

  static const String startId = '__start__';
  static const String endId = '__end__';

  @override
  bool get isRenderable => transitions.isNotEmpty;

  static StateDiagramData parse(String content) {
    final source = MermaidDiagramData.cleanSource(content);
    final lines = source
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('%%'))
        .toList();

    var startIndex = 0;
    if (lines.isNotEmpty &&
        RegExp(r'^stateDiagram(-v2)?\b', caseSensitive: false).hasMatch(lines.first)) {
      startIndex = 1;
    }

    // 第一遍：收集 state "label" as id 命名声明
    final stateLabels = <String, String>{};
    for (final line in lines.skip(startIndex)) {
      final m = RegExp(r'^state\s+"(.+?)"\s+as\s+(\w+)\s*$').firstMatch(line);
      if (m != null) {
        stateLabels[m.group(2)!] = m.group(1)!;
      }
    }

    StateNode node(String id, {bool isStart = false, bool isEnd = false}) {
      return StateNode(
        id: id,
        label: stateLabels[id] ?? id,
        isStart: isStart,
        isEnd: isEnd,
      );
    }

    final transitions = <StateTransition>[];
    for (final line in lines.skip(startIndex)) {
      // [*] --> X [: label]  起始转移
      final startTrans = RegExp(r'^\[\*\]\s*-->\s*(\w+)(?:\s*:\s*(.+))?\s*$').firstMatch(line);
      if (startTrans != null) {
        final toId = startTrans.group(1)!;
        transitions.add(StateTransition(
          from: node(startId, isStart: true),
          to: node(toId),
          label: startTrans.group(2),
        ));
        continue;
      }
      // X --> [*] [: label]  终止转移
      final endTrans = RegExp(r'^(\w+)\s*-->\s*\[\*\](?:\s*:\s*(.+))?\s*$').firstMatch(line);
      if (endTrans != null) {
        final fromId = endTrans.group(1)!;
        transitions.add(StateTransition(
          from: node(fromId),
          to: node(endId, isEnd: true),
          label: endTrans.group(2),
        ));
        continue;
      }
      // X --> Y [: label]  普通转移
      final normal = RegExp(r'^(\w+)\s*-->\s*(\w+)(?:\s*:\s*(.+))?\s*$').firstMatch(line);
      if (normal != null) {
        transitions.add(StateTransition(
          from: node(normal.group(1)!),
          to: node(normal.group(2)!),
          label: normal.group(3),
        ));
        continue;
      }
      // state "label" as id 已在第一遍处理；note left/right of X : text 暂不渲染
    }

    return StateDiagramData(source: source, transitions: transitions);
  }
}

class _StateDiagramView extends StatelessWidget {
  const _StateDiagramView({required this.data});

  final StateDiagramData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTypeTag(),
        const SizedBox(height: 16),
        for (var i = 0; i < data.transitions.length; i++) ...[
          _buildTransitionRow(data.transitions[i]),
          if (i < data.transitions.length - 1) const SizedBox(height: 10),
        ],
      ],
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
          Icon(Icons.device_hub, size: 16, color: AppColors.accent),
          SizedBox(width: 6),
          Text(
            'STATE',
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

  Widget _buildTransitionRow(StateTransition t) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          _buildStateNode(t.from),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_forward, color: AppColors.accent, size: 20),
                if (t.label != null && t.label!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      t.label!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _buildStateNode(t.to),
        ],
      ),
    );
  }

  Widget _buildStateNode(StateNode node) {
    if (node.isStart) {
      // 起始态：实心圆点
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
        ),
      );
    }
    if (node.isEnd) {
      // 终止态：双圆环（实心 + 外环）
      return Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.accent, width: 2),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.34)),
      ),
      child: Text(
        node.label,
        textAlign: TextAlign.center,
        softWrap: true,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
