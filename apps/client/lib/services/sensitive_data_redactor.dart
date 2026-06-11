class SensitiveDataRedactor {
  SensitiveDataRedactor._();

  static const placeholder = '[redacted]';

  static String redact(String value) {
    var redacted = value
        .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_\-]{8,}\b'), 'sk-***')
        .replaceAll(RegExp(r'\bAIza[A-Za-z0-9_\-]{30,}\b'), 'AIza***')
        .replaceAll(
          RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=\-]{8,}'),
          'Bearer $placeholder',
        )
        .replaceAllMapped(
          RegExp(r'(/Users/)[^/\s]+'),
          (match) => '${match.group(1)}$placeholder',
        )
        .replaceAllMapped(
          RegExp(r'(/home/)[^/\s]+'),
          (match) => '${match.group(1)}$placeholder',
        )
        .replaceAllMapped(
          RegExp(r'([A-Za-z]:\\Users\\)[^\\/\s]+'),
          (match) => '${match.group(1)}$placeholder',
        );

    redacted = redacted.replaceAllMapped(
      RegExp(
        r'''\b(api[_-]?key|access[_-]?token|refresh[_-]?token|auth[_-]?token|token|secret|password|authorization)\b(\s*[:=]\s*)(["']?)([^"',\s&]{8,})(["']?)''',
        caseSensitive: false,
      ),
      (match) =>
          '${match.group(1)}${match.group(2)}${match.group(3)}'
          '$placeholder${match.group(5)}',
    );

    redacted = redacted.replaceAllMapped(
      RegExp(
        r'''([?&](?:api[_-]?key|key|access[_-]?token|refresh[_-]?token|token|secret|password)=)[^&#\s]{4,}''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}$placeholder',
    );

    return redacted;
  }
}
