import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../coach/persistence/extension_records.dart';
import '../../providers/coach_provider.dart';
import '../../providers/localization_provider.dart';
import '../../providers/web_download/web_download_stub.dart'
    if (dart.library.html) '../../providers/web_download/web_download_web.dart'
    as web_download;
import '../../services/coach_legacy_migration.dart';
import '../../services/storage_service.dart';
import 'coach_widgets.dart';

class LegacyArchivePage extends StatefulWidget {
  const LegacyArchivePage({super.key});
  @override
  State<LegacyArchivePage> createState() => _LegacyArchivePageState();
}

class _LegacyArchivePageState extends State<LegacyArchivePage> {
  late Future<List<CoachExtensionRecord>> _records;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final coach = context.read<CoachProvider>();
    _records = coach.store.listExtensions(
      coach.profileId,
      CoachExtensionKind.legacyMigration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return CoachPageScaffold(
      title: l10n.get('coach_legacy_title'),
      subtitle: l10n.get('coach_legacy_note'),
      children: [
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        final coach = context.read<CoachProvider>();
                        await migrateLegacyPracticeData(
                          storage: StorageService(),
                          store: coach.store,
                          profileId: coach.profileId,
                        );
                        await coach.reload();
                      } finally {
                        if (mounted) {
                          setState(() {
                            _busy = false;
                            _refresh();
                          });
                        }
                      }
                    },
              icon: const Icon(Icons.refresh),
              label: Text(l10n.get('coach_legacy_retry')),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.download),
              label: Text(l10n.get('coach_legacy_export')),
            ),
          ],
        ),
        FutureBuilder<List<CoachExtensionRecord>>(
          future: _records,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LinearProgressIndicator();
            return Column(
              children: [
                for (final record in snapshot.data!)
                  ExpansionTile(
                    title: Text(record.id),
                    subtitle: Text(record.updatedAt.toLocal().toString()),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          const JsonEncoder.withIndent('  ').convert(
                            record.value['snapshotJson'] is String
                                ? jsonDecode(
                                    record.value['snapshotJson'] as String,
                                  )
                                : record.value,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _export() async {
    final records = await _records;
    final text = const JsonEncoder.withIndent('  ').convert({
      'kind': 'coach-legacy-archive',
      'schemaVersion': 1,
      'records': records.map((r) => r.toJson()).toList(),
    });
    if (kIsWeb) {
      web_download.downloadFile('coach-legacy-archive.json', text);
      return;
    }
    await FilePicker.platform.saveFile(
      fileName: 'coach-legacy-archive.json',
      bytes: Uint8List.fromList(utf8.encode(text)),
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
  }
}
