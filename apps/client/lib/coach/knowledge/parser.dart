/// 文档解析契约（§6.3、§6.4）。PDF/DOCX 文本解析在首版依赖平台能力，
/// 未配置时明确抛错，不凭空补全经历（§6.9）。
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// 解析失败（格式不支持、损坏、扫描件无文本层等）。
class ParseException implements Exception {
  ParseException(this.message);
  final String message;
  @override
  String toString() => 'ParseException: $message';
}

/// 文档解析器：把字节提取为纯文本。
abstract class DocumentParser {
  /// 提取纯文本。失败时抛 [ParseException]。
  Future<String> extractText(List<int> bytes, {String? fileName});
}

/// 纯文本 / Markdown 提取（Markdown 直接当纯文本切块，不在此做 AST）。
class PlainTextParser implements DocumentParser {
  const PlainTextParser();

  @override
  Future<String> extractText(List<int> bytes, {String? fileName}) async {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw ParseException('文本不是有效 UTF-8，请转换编码或粘贴文本');
    }
  }
}

class MarkdownParser extends PlainTextParser {
  const MarkdownParser();
}

/// DOCX extraction stays pure Dart. Production PDF imports are delegated to
/// PDFium by PdfDocumentParser; regex extraction cannot decode embedded fonts.
class BuiltInDocumentParser implements DocumentParser {
  const BuiltInDocumentParser();

  @override
  Future<String> extractText(List<int> bytes, {String? fileName}) async {
    final name = (fileName ?? '').toLowerCase();
    if (name.endsWith('.docx') || _looksLikeZip(bytes)) {
      return _extractDocx(bytes);
    }
    if (name.endsWith('.pdf') || _looksLikePdf(bytes)) {
      return _extractPdf(bytes);
    }
    throw ParseException('不支持的文件格式，请使用 PDF、DOCX 或粘贴文本');
  }

  static bool _looksLikeZip(List<int> bytes) =>
      bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;

  static bool _looksLikePdf(List<int> bytes) =>
      bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == '%PDF-';

  static String _extractDocx(List<int> bytes) {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw ParseException('DOCX 文件损坏或不是有效的 Office 文档：$e');
    }
    final documents = archive.files
        .where((f) => f.isFile && f.name == 'word/document.xml')
        .toList();
    final document = documents.isEmpty ? null : documents.first;
    if (document == null) throw ParseException('DOCX 缺少正文文档');
    try {
      final documentXml = XmlDocument.parse(
        utf8.decode(document.content as List<int>),
      );
      const namespaces = {
        'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
        'http://purl.oclc.org/ooxml/wordprocessingml/main',
      };
      final buffer = StringBuffer();
      void visit(XmlNode node) {
        if (node is! XmlElement) return;
        final word = namespaces.contains(node.namespaceUri);
        // Only visible word-processing text: no field instructions, deleted
        // revisions or unrelated metadata. Decode entities after XML parsing.
        if (word && (node.name.local == 'del' || node.name.local == 'moveFrom'))
          return;
        if (word && node.name.local == 't') {
          buffer.write(node.innerText);
          return;
        }
        if (word && (node.name.local == 'br' || node.name.local == 'cr'))
          buffer.writeln();
        if (word && node.name.local == 'tab') buffer.write('\t');
        for (final child in node.children) {
          visit(child);
        }
        if (word && node.name.local == 'p') buffer.writeln();
      }

      visit(documentXml.rootElement);
      final text = buffer.toString().trim();
      if (text.isEmpty) throw ParseException('DOCX 没有可提取的正文，请粘贴文本');
      return text;
    } on XmlParserException {
      throw ParseException('DOCX 正文 XML 损坏，请重新导出或粘贴文本');
    } on FormatException {
      throw ParseException('DOCX 正文编码无效，请重新导出或粘贴文本');
    }
  }

  static String _extractPdf(List<int> bytes) => throw ParseException(
    'PDF requires the platform PDFium parser; use PdfDocumentParser for binary documents',
  );
}
