# 语音双缓冲流水线（Voice Chunk Pipeline）

本应用使用**生产者-消费者双缓冲流水线**模式处理语音录制与转写，确保用户能够连续说话而不必等待前一块转写完成。

核心架构由 `VoiceInputButton` 和 `_VoiceInputButtonState` 实现。

## 目录

1. [架构总览](#1-架构总览)
2. [Session 生命周期](#2-session-生命周期)
3. [Chunk Queue（生产者-消费者模型）](#3-chunk-queue生产者-消费者模型)
4. [VAD 录制策略](#4-vad-录制策略)
5. [AI 语音转写流水线](#5-ai-语音转写流水线)
6. [本机 sherpa-onnx 离线流水线](#6-本机-sherpa-onnx-离线流水线)
7. [系统语音（无缓冲，单次结果）](#7-系统语音无缓冲单次结果)
8. [Provider 解析链](#8-provider-解析链)
9. [状态管理](#9-状态管理)
10. [文本清洗](#10-文本清洗)
11. [闲置释放策略](#11-闲置释放策略)
12. [错误处理](#12-错误处理)

## 1. 架构总览

```
                    ┌─────────────────────┐
                    │  录音线程（生产者）    │
                    │  _runAiChunkLoop /   │
                    │  _runSherpaOnnxChunkLoop
                    └─────────┬───────────┘
                              │ 每录制一块 → _enqueueTranscription()
                              ▼
                    ┌─────────────────────┐
                    │    _chunkQueue      │  ← Queue<_VoiceChunkJob>
                    │  (FIFO 顺序队列)     │
                    └─────────┬───────────┘
                              │ _consumeTranscriptionQueue()
                              ▼
                    ┌─────────────────────┐
                    │  转写线程（消费者）    │
                    │  _transcribeAiChunk /│
                    │  _transcribeSherpaChunk
                    └─────────┬───────────┘
                              │ _emitText(_cleanTranscriptionText())
                              ▼
                    ┌─────────────────────┐
                    │  业务输入区域         │
                    │  widget.onResult()   │
                    └─────────────────────┘
```

- **生产者**：`_runAiChunkLoop` 或 `_runSherpaOnnxChunkLoop`，不间断录制，每录完一个 VAD 块就入队。
- **消费者**：`_consumeTranscriptionQueue`，从队首取出顺序转写，保证输出顺序与录制顺序一致。
- **双缓冲**：录制下一块的同时，上一块正在被转写，用户无需等待。

## 2. Session 生命周期

每次用户点击录音按钮开始一次新的语音输入即开启一个 session。

```
idle → preparing → recording → stopping → idle
                    ↑               ↓
                    └── transcribing ┘（停止后队列未空时）
```

### `_sessionId` 机制

```dart
int _sessionId = 0;
```

每次 `_startListening()` 调用都执行 `++_sessionId`。所有异步回调（录制完成、转写完成）入口都检查 `_isCurrentSession(sessionId)`，确保旧 session 的回调不会影响新 session。

```dart
bool _isCurrentSession(int sessionId) => _sessionId == sessionId;
bool _isCurrentRecordingSession(int sessionId) =>
    _isCurrentSession(sessionId) && _running;
```

关键保护点：

| 检查点 | 防止的问题 |
|--------|-----------|
| `_startSystemListening` 中的权限回调后 | 用户快速停止再开始，旧权限回调覆盖新 session |
| `_runAiChunkLoop` 循环顶部 `_isCurrentRecordingSession(sessionId)` | 用户停止后 producer 立即退出 |
| `_recordVadChunk` 中 `_running` 检查 | VAD 录制中的音频块在停止后丢弃 |
| `_enqueueTranscription` 中 `_isCurrentSession(job.sessionId)` | 停止后的残留 chunk 不入队 |
| `_consumeTranscriptionQueue` 中 `_isCurrentSession(job.sessionId)` | 旧队列中的 chunk 不写入输入区域 |

### dispose 保护

`dispose()` 也会递增 `_sessionId`，确保所有异步回调在 widget 销毁后不再执行：

```dart
@override
void dispose() {
  _sessionId++;
  _running = false;
  _discardQueuedChunks();
  // ...
}
```

## 3. Chunk Queue（生产者-消费者模型）

### 数据结构

```dart
final Queue<_VoiceChunkJob> _chunkQueue = Queue<_VoiceChunkJob>();
```

`_VoiceChunkJob` 是一个 tagged union，包含 sessionId、chunkPath 和区分 AI/sherpa 两种转写源的数据：

```dart
class _VoiceChunkJob {
  final int sessionId;
  final String chunkPath;
  final _VoiceChunkKind kind;
  final AiProvider? aiProvider;  // kind == ai 时
  final AiConfig? config;        // kind == ai 时
  final OnDeviceSttService? service; // kind == sherpa 时
}
```

### 入队：`_enqueueTranscription`

```dart
void _enqueueTranscription(_VoiceChunkJob job) {
  if (!_isCurrentSession(job.sessionId)) {
    unawaited(deleteFileAtPath(job.chunkPath));  // 旧 session 的 chunk 直接删除
    return;
  }
  _chunkQueue.add(job);
  if (!_running) {
    _setStateKind(VoiceInputState.transcribing);
    _setStatusMessage('voice_transcribing');
  } else if (_chunkQueue.length > 1) {
    _setStatusMessage('voice_transcribing_background');
  }
  if (!_consumerRunning) unawaited(_consumeTranscriptionQueue());
}
```

- 如果用户已停止但队列未空，状态切换为 `transcribing`。
- 队列长度 > 1 时显示 `voice_transcribing_background` 提示"后台转写中"。

### 消费：`_consumeTranscriptionQueue`

```dart
Future<void> _consumeTranscriptionQueue() async {
  if (_consumerRunning) return;  // 防重入
  _consumerRunning = true;
  try {
    while (_chunkQueue.isNotEmpty) {
      final job = _chunkQueue.removeFirst();  // FIFO 顺序消费
      // ... 转写 ...
    }
  } finally {
    _consumerRunning = false;
    _finishSessionIfReady();
  }
}
```

- `_consumerRunning` 防止多个消费者并发。
- 使用 `removeFirst()` 保证队列按录制顺序消费，文本写入顺序正确。
- `_finishSessionIfReady()` 在消费者结束时检查是否可以进入 idle。

### 清空队列：`_discardQueuedChunks`

```dart
void _discardQueuedChunks() {
  while (_chunkQueue.isNotEmpty) {
    final job = _chunkQueue.removeFirst();
    unawaited(deleteFileAtPath(job.chunkPath));
  }
}
```

在停止、错误、dispose 时调用，删除所有未处理的临时 WAV 文件。

## 4. VAD 录制策略

### `_recordVadChunk`

使用 `AudioRecorder`（`package:record`）录制 WAV 格式（16kHz, mono）音频块。核心是**振幅检测 VAD**：

```dart
const pollInterval = Duration(milliseconds: 80);
const warmupChecks = 4;     // 让录音器稳定再判断噪声
const minSpeechChecks = 3;  // ~240ms 连续语音避免误触发
const maxSilentChecks = 12; // ~960ms 持续静音认为句子结束
const maxTotalChecks = 150; // ~12s 最大块时长
const noSpeechChecks = 100; // ~8s 内无语音则旋转文件
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `warmupChecks` | 4 | 启动后跳过前 4 次检测（~320ms 预热） |
| `minSpeechChecks` | 3 | 至少检测到 3 次连续语音才认为有效（~240ms） |
| `maxSilentChecks` | 12 | 语音后连续 12 次静音即结束当前块（~960ms） |
| `maxTotalChecks` | 150 | 每块最长录制约 12 秒 |
| `noSpeechChecks` | 100 | 8 秒无语音就旋转文件 |

### 振幅检测：`_isSpeechAmplitude`

```dart
bool _isSpeechAmplitude(double value) {
  if (value.isNaN || value.isInfinite) return false;
  if (value <= 0) return value > -45;     // dBFS 风格
  if (value <= 1) return value >= 0.018;  // 归一化线性值
  return value >= 8;                      // 正数 dB 风格兜底
}
```

`package:record` 的 `getAmplitude()` 在不同平台返回不同量纲的值。该函数兼容三种情况：

| 值域 | 平台典型 | 语音阈值 |
|------|---------|---------|
| `<= 0` | dBFS 风格（macOS） | `> -45` |
| `(0, 1]` | 归一化线性值（Android） | `>= 0.018` |
| `> 1` | 正数 dB 兜底 | `>= 8` |

### 块有效性判断

- `speechChecks >= minSpeechChecks` 时才保留块，否则删除文件返回 null。
- 无语音的块被完全丢弃，不会进入转写队列。
- 生产者循环中 `chunkPath == null` 时 `continue`，继续录制下一块。

## 5. AI 语音转写流水线

### 启动

```dart
_producerRunning = true;
unawaited(_runAiChunkLoop(sessionId, aiProvider, config));
```

### 生产者循环：`_runAiChunkLoop`

```dart
Future<void> _runAiChunkLoop(int sessionId, AiProvider aiProvider, AiConfig config) async {
  try {
    while (_isCurrentRecordingSession(sessionId)) {
      final chunkPath = await _recordVadChunk();
      if (!_isCurrentSession(sessionId)) break;
      if (chunkPath == null) { if (_running) continue; break; }
      _enqueueTranscription(_VoiceChunkJob.ai(
        sessionId: sessionId, chunkPath: chunkPath,
        aiProvider: aiProvider, config: config,
      ));
    }
  } catch (e) { /* 错误处理 */ }
  finally {
    if (_isCurrentSession(sessionId)) {
      _producerRunning = false;
      _finishSessionIfReady();
    }
  }
}
```

### 消费者转写：`_transcribeAiChunk`

```dart
Future<String> _transcribeAiChunk(AiProvider aiProvider, AiConfig config, String chunkPath) async {
  final bytes = await readBytesFromPath(chunkPath);
  try { await deleteFileAtPath(chunkPath); } catch (_) {}
  return aiProvider.transcribeAudio(config: config, audioBytes: bytes);
}
```

- 读取 WAV 文件字节 → 删除临时文件 → 调用 `AiProvider.transcribeAudio`（请求 `/audio/transcriptions` 或 `/chat/completions` 音频输入端点）。
- 转写结果经 `_cleanTranscriptionText` 清洗后传入 `_emitText`。

## 6. 本机 sherpa-onnx 离线流水线

### 启动

```dart
_producerRunning = true;
unawaited(_runSherpaOnnxChunkLoop(sessionId, service));
```

### 生产者循环：`_runSherpaOnnxChunkLoop`

与 AI 流水线结构相同，但调用 `_transcribeSherpaChunk`：

```dart
final text = await _transcribeSherpaChunk(job.chunkPath, job.service!);
```

### 消费者转写：`_transcribeSherpaChunk`

三步：

1. **读取 WAV 文件** → `readBytesFromPath` → 删除临时文件。
2. **WAV → Float32List**：`_wavBytesToFloat32List` 解析 WAV 头部（44 字节）后，将 16-bit PCM 样本转为 [-1.0, 1.0] 的 `Float32List`。
3. **调用离线引擎**：`service.transcribe(samples, 16000)` → `_cleanTranscriptionText(result.text)`。

### 服务复用

```dart
final serviceKey = '$engine|$whisperModel|${modelDir.path}';
```

- 同一引擎+模型+目录的服务实例可跨 session 复用。
- 调用 `_disposeSherpaOnnxService()` 释放后再创建新实例。
- `_sherpaIdleDisposeTimer` 在 2 分钟闲置后自动释放。

## 7. 系统语音（无缓冲，单次结果）

系统语音不走 chunk 队列，直接监听 `onResult` 回调：

```dart
await _speech.listen(
  onResult: (result) {
    final words = result.recognizedWords;
    final delta = _deltaFromCumulative(words, _lastSystemText);
    _lastSystemText = words;
    _emitText(delta);
  },
);
```

`_deltaFromCumulative` 计算增量文本（因为系统语音回调返回的是累计文本）：

```dart
String _deltaFromCumulative(String current, String previous) {
  if (current.isEmpty) return '';
  if (previous.isNotEmpty && current.startsWith(previous)) {
    return current.substring(previous.length);
  }
  return current == previous ? '' : current;
}
```

停止时直接 `_speech.stop()`，不需要等待队列。

## 8. Provider 解析链

`_resolveProvider` 根据 `sttMode` 解析要使用的语音提供商：

```
                    ┌──────────────┐
                    │ sttMode      │
                    └──────┬───────┘
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
     sherpa_onnx    fixed_ai_config   follow_current_ai
          │               │               │
          ▼               ▼               ▼
    sherpa-onnx     AiConfig(id=fixed)  AiConfig(id=selected)
          │
          └─────────── auto ───────────────┘
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
    selected AI (可转写)   fixed AI (可转写)
          │                   │
          ▼                   ▼
    default AI (可转写)   sherpa-onnx 兜底 (auto)
          │
          ▼
    system 兜底 (auto)

    ── none ──→ 不可用
```

| 模式 | 优先级 | 兜底 |
|------|--------|------|
| `sherpa_onnx` | 直接使用 sherpa-onnx | 无 |
| `fixed_ai_config` | 固定 AI 配置 | 无 |
| `follow_current_ai` | 跟随练习 AI 配置 | 无 |
| `auto` | 当前 AI → 固定 AI → 默认 AI → sherpa-onnx → 系统语音 | 逐级降级 |
| `system` | 直接使用系统语音 | 无 |

## 9. 状态管理

```dart
enum VoiceInputState {
  idle,
  preparing,
  recording,
  transcribing,
  stopping,
  error,
}
```

| 状态 | 含义 | 进入条件 |
|------|------|---------|
| `idle` | 空闲，按钮可点击开始 | 初始 / 错误处理后自动恢复 |
| `preparing` | 正在初始化语音链路 | 点击开始后，权限/配置检查中 |
| `recording` | 正在录制音频 | producer 循环运行中 |
| `transcribing` | 停止后仍有队列数据在转写 | 用户停止但 _chunkQueue 未空 |
| `stopping` | 用户点击停止，正在清理 | 用户点击停止按钮 |
| `error` | 发生错误 | 权限失败 / 初始化失败 / 转写错误 |

状态变化通过 `_setStateKind()` 统一管理，自动触发 `onListeningChanged` 和 `onStateChanged` 回调。

`_lastNotifiedState` 去重，避免重复通知相同状态。

## 10. 文本清洗

### `_cleanTranscriptionText`

```dart
String _cleanTranscriptionText(String text) {
  final cleaned = text
      .replaceAll(RegExp(r'<\|[^>]*\|>'), '')    // 去除 SenseVoice 标签
      .replaceAll(RegExp(r'\s+'), ' ')            // 合并空白
      .trim();
  final lower = cleaned.toLowerCase();
  const silenceHallucinations = {
    '谢谢观看',
    '感谢观看',
    '字幕由 amara.org 社区提供',
    'thanks for watching',
  };
  return silenceHallucinations.contains(lower) ? '' : cleaned;
}
```

| 处理 | 说明 |
|------|------|
| 去除 `<\|...\|>` 标签 | SenseVoice 等引擎输出的情感/语种标签 |
| 合并连续空白 | 转写结果中常见的多余空格 |
| 幻觉文本过滤 | 常见静音段幻觉（"谢谢观看"等）直接丢弃 |

## 11. 闲置释放策略

### sherpa-onnx 闲置释放

```dart
void _scheduleSherpaIdleDispose() {
  _sherpaIdleDisposeTimer?.cancel();
  _sherpaIdleDisposeTimer = Timer(const Duration(minutes: 2), () {
    unawaited(_disposeSherpaOnnxService());
  });
}
```

- 每轮 session 结束后（`_finishSessionIfReady` 进入 idle 时）重置 2 分钟计时器。
- 新 session 开始时取消计时器（复用已加载的服务）。
- `_disposeSherpaOnnxService` 调用 `service.dispose()` 释放 native 资源。

### dispose 时完整清理

```dart
_speech.stop();
_recorder.dispose();
_sherpaIdleDisposeTimer?.cancel();
_disposeSherpaOnnxService();
```

## 12. 错误处理

### 错误消息路由

```dart
String _messageKeyForError(Object error) {
  final text = error.toString();
  if (text.contains('401') || text.contains('403')) return 'ai_test_auth_error';
  if (text.contains('404')) return 'ai_test_not_found';
  if (text.contains('429')) return 'ai_test_rate_limited';
  if (text.contains('timeout')) return 'ai_test_timeout';
  return 'voice_recognize_failed';
}
```

- 基于错误文本匹配返回 l10n key，用户侧看到本地化错误消息。
- `_showErrorDetail` 同时显示 SnackBar 和记录 `AppLog`。

### 降级策略

| 错误场景 | 降级行为 |
|---------|---------|
| 权限拒绝 | 状态 → error → idle，用户可继续文字输入 |
| AI 配置鉴权失败 | 显示本地化错误，状态 → error → idle |
| sherpa-onnx 初始化失败 | 显示本地化错误，释放服务实例 |
| 系统语音不可用 | 显示 `system_speech_unsupported` |
| 转写块失败 | `AppLog` 记录警告，单块静默失败不阻塞整轮 |

### 线程安全

- `_consumerRunning` / `_producerRunning` 分别跟踪两个线程，防止竞态。
- `_finishSessionIfReady()` 只在两个线程都停止且队列为空时才进入 idle。
- 所有文件操作（读、删）包裹在 `try/catch` 中，不因临时文件清理失败而阻塞流程。

---

## 相关文档

- [design.md §17](design.md#17-语音识别实现) — 语音识别整体设计和平台约束