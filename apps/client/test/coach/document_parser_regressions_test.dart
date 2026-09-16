import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/coach/knowledge/parser.dart';

List<int> docx(String xml) {
  final bytes = utf8.encode(xml);
  return ZipEncoder().encode(
    Archive()..addFile(ArchiveFile('word/document.xml', bytes.length, bytes)),
  )!;
}

void main() {
  const parser = BuiltInDocumentParser();
  test(
    'DOCX preserves literal angle brackets, alternate namespace prefix and paragraphs',
    () async {
      final bytes = docx(
        '<x:document xmlns:x="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<x:body><x:p><x:r><x:t>List&lt;String&gt; &amp; XML</x:t></x:r></x:p>'
        '<x:p><x:r><x:t>second</x:t><x:tab/><x:t>column</x:t></x:r></x:p>'
        '</x:body></x:document>',
      );
      expect(
        await parser.extractText(bytes, fileName: 'resume.docx'),
        'List<String> & XML\nsecond\tcolumn',
      );
    },
  );
  test('DOCX ignores deleted revisions and field instructions', () async {
    final bytes = docx(
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body><w:p><w:del><w:r><w:delText>deleted fact</w:delText></w:r></w:del>'
      '<w:r><w:instrText>HYPERLINK secret</w:instrText><w:t>visible fact</w:t></w:r>'
      '</w:p></w:body></w:document>',
    );
    expect(await parser.extractText(bytes), 'visible fact');
  });
  test(
    'invalid text encoding is rejected instead of importing mojibake',
    () async {
      await expectLater(
        const PlainTextParser().extractText([0xff, 0xfe, 0xd8]),
        throwsA(isA<ParseException>()),
      );
    },
  );
  test(
    'unsupported PDF font encoding cannot masquerade as resume facts',
    () async {
      await expectLater(
        parser.extractText(
          utf8.encode('%PDF-1.4 /Subtype /Type0\n(garbage) Tj'),
          fileName: 'resume.pdf',
        ),
        throwsA(isA<ParseException>()),
      );
    },
  );
  test(
    'binary PDF requires the production parser instead of accepting invalid syntax',
    () async {
      await expectLater(
        parser.extractText(
          utf8.encode('%PDF-1.4\n(First) Tj'),
          fileName: 'resume.pdf',
        ),
        throwsA(isA<ParseException>()),
      );
    },
  );
}
