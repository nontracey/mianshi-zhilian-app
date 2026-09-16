/// Production binary parser. PDFium handles embedded fonts and ToUnicode maps;
/// DOCX remains a local XML parser. Scans never become fabricated resume text.
library;

import 'dart:typed_data';
import 'package:pdfrx/pdfrx.dart';
import '../coach/knowledge/parser.dart';

class PdfDocumentParser implements DocumentParser {
  const PdfDocumentParser();

  @override
  Future<String> extractText(List<int> bytes, {String? fileName}) async {
    final pdf =
        (fileName ?? '').toLowerCase().endsWith('.pdf') ||
        (bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == '%PDF-');
    if (!pdf) {
      return const BuiltInDocumentParser().extractText(
        bytes,
        fileName: fileName,
      );
    }
    if (bytes.length > 30 * 1024 * 1024) {
      throw ParseException('PDF exceeds the 30 MB import limit');
    }
    PdfDocument? document;
    try {
      await pdfrxFlutterInitialize();
      document = await PdfDocument.openData(Uint8List.fromList(bytes));
      if (document.pages.length > 300) {
        throw ParseException('PDF exceeds the 300 page import limit');
      }
      final pages = <String>[];
      for (final page in document.pages) {
        final text = (await page.loadText())?.fullText.trim() ?? '';
        // Preserve page locations for later source review and citations.
        if (text.isNotEmpty) pages.add('[Page ${page.pageNumber}]\n$text');
      }
      if (pages.isEmpty) {
        throw ParseException(
          'PDF has no text layer. Paste OCR text for review.',
        );
      }
      return pages.join('\n\n');
    } on ParseException {
      rethrow;
    } catch (_) {
      throw ParseException(
        'PDF could not be opened. Unlock it or paste its text.',
      );
    } finally {
      await document?.dispose();
    }
  }
}
