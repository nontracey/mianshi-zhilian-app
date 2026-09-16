import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/embedding_config_service.dart';
import '../../providers/localization_provider.dart';

class EmbeddingSettingsPage extends StatefulWidget {
  const EmbeddingSettingsPage({super.key});
  @override
  State<EmbeddingSettingsPage> createState() => _EmbeddingSettingsPageState();
}

class _EmbeddingSettingsPageState extends State<EmbeddingSettingsPage> {
  final _url = TextEditingController(),
      _model = TextEditingController(),
      _key = TextEditingController(),
      _dimension = TextEditingController();
  bool _enabled = false, _saving = false;
  @override
  void initState() {
    super.initState();
    final service = context.read<EmbeddingConfigService>();
    _url.text = service.endpoint;
    _model.text = service.model;
    _dimension.text = service.dimension == 0
        ? ''
        : service.dimension.toString();
    _enabled = service.enabled;
  }

  @override
  void dispose() {
    for (final c in [_url, _model, _key, _dimension]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('coach_embedding_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.get('coach_embedding_note')),
          SwitchListTile(
            title: Text(l10n.get('coach_embedding_enable')),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          TextField(
            controller: _url,
            decoration: InputDecoration(
              labelText: l10n.get('coach_embedding_endpoint'),
              hintText: 'https://example.com/v1/embeddings',
            ),
          ),
          TextField(
            controller: _model,
            decoration: InputDecoration(labelText: l10n.get('model_name')),
          ),
          TextField(
            controller: _dimension,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.get('coach_embedding_dimension'),
            ),
          ),
          TextField(
            controller: _key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.get('coach_embedding_key'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      await context.read<EmbeddingConfigService>().save(
                        endpoint: _url.text,
                        model: _model.text,
                        dimension: int.tryParse(_dimension.text) ?? 0,
                        enabled: _enabled,
                        key: _key.text.isEmpty ? null : _key.text,
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.get('coach_embedding_failed')),
                          ),
                        );
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: Text(l10n.get('save')),
          ),
        ],
      ),
    );
  }
}
