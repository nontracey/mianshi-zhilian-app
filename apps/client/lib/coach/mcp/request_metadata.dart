/// MCP 2026-07-28 Streamable HTTP metadata and header encoding.
/// https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http
library;

import 'dart:convert';

String encodeMcpHeader(String value) {
  final ascii = value.runes.every((c) => c == 9 || (c >= 32 && c <= 126));
  final sentinel = value.startsWith('=?base64?') && value.endsWith('?=');
  return ascii && value.trim() == value && !sentinel
      ? value
      : '=?base64?${base64Encode(utf8.encode(value))}?=';
}

class McpHeaderSchema {
  McpHeaderSchema(Map<String, Object?> schema) {
    final seen = <String>{};
    void visit(Object? node, List<String> path, bool reachable) {
      if (node is List) {
        for (final item in node) {
          visit(item, path, false);
        }
        return;
      }
      if (node is! Map) return;
      final header = node['x-mcp-header'];
      if (header != null) {
        if (!reachable ||
            path.isEmpty ||
            header is! String ||
            header.isEmpty ||
            !RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(header) ||
            !seen.add(header.toLowerCase()) ||
            !['string', 'integer', 'boolean'].contains(node['type'])) {
          throw const FormatException('Invalid MCP header annotation');
        }
        _fields.add((path: path, name: header, type: node['type'] as String));
      }
      for (final entry in node.entries) {
        if (entry.key == 'properties' && entry.value is Map) {
          for (final p in (entry.value as Map).entries) {
            visit(p.value, [...path, p.key as String], reachable);
          }
        } else if (entry.value is Map || entry.value is List) {
          visit(entry.value, path, false);
        }
      }
    }

    visit(schema, [], true);
  }
  final List<({List<String> path, String name, String type})> _fields = [];
  Map<String, String> headers(Map<String, Object?> arguments) {
    final result = <String, String>{};
    for (final field in _fields) {
      Object? value = arguments;
      for (final part in field.path) {
        value = value is Map ? value[part] : null;
      }
      if (value == null) continue;
      if ((field.type == 'string' && value is! String) ||
          (field.type == 'boolean' && value is! bool) ||
          (field.type == 'integer' &&
              (value is! int || value.abs() > 9007199254740991))) {
        throw const FormatException('Invalid MCP header parameter');
      }
      result['Mcp-Param-${field.name}'] = encodeMcpHeader(value.toString());
    }
    return result;
  }
}
