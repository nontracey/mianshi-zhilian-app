@TestOn('vm')
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:mianshi_zhilian/services/pdf_document_parser.dart';
import 'package:mianshi_zhilian/coach/knowledge/parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
    final platform = Platform.isMacOS
        ? 'macos'
        : Platform.isWindows
        ? 'windows'
        : 'linux';
    final library = Platform.isMacOS
        ? 'libpdfium.dylib'
        : Platform.isWindows
        ? 'pdfium.dll'
        : 'libpdfium.so';
    final asset = File(
      Platform.environment['COACH_PDFIUM_LIBRARY_PATH'] ??
          'build/native_assets/$platform/$library',
    );
    if (asset.existsSync()) Pdfrx.pdfiumModulePath = asset.absolute.path;
  });
  test(
    'PDFium extracts compressed CJK and Latin glyphs with page locations',
    () async {
      final bytes = await File(
        'test/fixtures/coach/synthetic_resume.pdf',
      ).readAsBytes();
      final text = await const PdfDocumentParser().extractText(
        bytes,
        fileName: 'resume.pdf',
      );
      expect(text, contains('合成测试简历'));
      expect(text, contains('订单服务'));
      expect(text, contains('20%'));
      expect(text, contains('[Page 2]'));
    },
  );
  test(
    'PDF without a text layer is rejected rather than inventing content',
    () async {
      final bytes = await File('test/fixtures/coach/no_text.pdf').readAsBytes();
      await expectLater(
        const PdfDocumentParser().extractText(bytes, fileName: 'scan.pdf'),
        throwsA(isA<ParseException>()),
      );
    },
  );
}
