import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class AiConfigPage extends StatefulWidget {
  const AiConfigPage({super.key});

  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();

  @override
  Widget build(BuildContext context) {
    final aiProvider = context.watch<AiProvider>();
    final configs = aiProvider.configs;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('ai_config_management')),
        actions: [
          IconButton(
            onPressed: () => _showEditDialog(context),
            icon: const Icon(Icons.add),
            tooltip: l10n.get('add_config'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (configs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    const Icon(Icons.hub_outlined, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(l10n.get('no_ai_config'), style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(l10n.get('click_top_right_add_config')),
                  ],
                ),
              ),
            )
          else
            ...configs.map(
              (config) => _ConfigCard(
                config: config,
                onEdit: () => _showEditDialog(context, config: config),
                onDelete: () => _handleDelete(context, config),
                onSetDefault: () => _handleSetDefault(context, config),
              ),
            ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, {AiConfig? config}) {
    final isEditing = config != null;
    final nameController = TextEditingController(text: config?.name ?? '');
    final baseUrlController = TextEditingController(
      text: config?.baseUrl ?? '',
    );
    final apiKeyController = TextEditingController(text: config?.apiKey ?? '');
    final modelController = TextEditingController(text: config?.model ?? '');
    bool isDefault = config?.isDefault ?? false;
    bool enabled = config?.enabled ?? true;
    bool supportsTextInput = config?.supportsTextInput ?? true;
    bool supportsImageInput = config?.supportsImageInput ?? false;
    bool supportsAudioInput = config?.supportsAudioInput ?? false;
    bool supportsMultimodal = config?.supportsMultimodal ?? false;
    bool supportsStreaming = config?.supportsStreaming ?? false;
    final usageTags = <String>{
      ...config?.usageTags ?? const ['recall'],
    };
    String? testResult;
    bool isTesting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEditing ? l10n.get('edit_config') : l10n.get('add_new_config')),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: l10n.get('name'),
                      hintText: l10n.get('example_openai_deepseek'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: baseUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Base URL',
                      hintText: 'https://api.openai.com/v1',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      hintText: 'sk-...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelController,
                    decoration: InputDecoration(
                      labelText: l10n.get('model_name'),
                      hintText: 'gpt-4o-mini',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: isTesting
                        ? null
                        : () async {
                            setDialogState(() => isTesting = true);
                            try {
                              final aiProvider = context.read<AiProvider>();
                              final success = await aiProvider
                                  .testConnectionWithParams(
                                    baseUrl: baseUrlController.text.trim(),
                                    apiKey: apiKeyController.text.trim(),
                                    model: modelController.text.trim(),
                                  );
                              setDialogState(() {
                                testResult = success ? l10n.get('connection_success') : l10n.get('connection_failed');
                                isTesting = false;
                              });
                            } catch (e) {
                              setDialogState(() {
                                testResult = '${l10n.get('connection_failed')}：$e';
                                isTesting = false;
                              });
                            }
                          },
                    icon: isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering),
                    label: Text(isTesting ? l10n.get('testing') : l10n.get('test_connect')),
                  ),
                  if (testResult != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      testResult!,
                      style: TextStyle(
                        color: testResult == l10n.get('connection_success')
                            ? AppColors.success
                            : AppColors.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SwitchListTile(
                    value: isDefault,
                    title: Text(l10n.get('set_as_default')),
                    onChanged: (value) =>
                        setDialogState(() => isDefault = value),
                  ),
                  SwitchListTile(
                    value: enabled,
                    title: Text(l10n.get('enable')),
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.get('model_capability_statement'),
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    value: supportsTextInput,
                    title: Text(l10n.get('support_text')),
                    subtitle: Text(l10n.get('closed_not_used_for_scoring')),
                    onChanged: (value) =>
                        setDialogState(() => supportsTextInput = value),
                  ),
                  SwitchListTile(
                    value: supportsImageInput,
                    title: Text(l10n.get('support_image')),
                    onChanged: (value) => setDialogState(() {
                      supportsImageInput = value;
                      supportsMultimodal =
                          supportsImageInput || supportsAudioInput;
                    }),
                  ),
                  SwitchListTile(
                    value: supportsAudioInput,
                    title: Text(l10n.get('support_raw_audio')),
                    subtitle: Text(l10n.get('transcribe_before_scoring')),
                    onChanged: (value) => setDialogState(() {
                      supportsAudioInput = value;
                      supportsMultimodal =
                          supportsImageInput || supportsAudioInput;
                    }),
                  ),
                  SwitchListTile(
                    value: supportsStreaming,
                    title: Text(l10n.get('support_streaming')),
                    onChanged: (value) =>
                        setDialogState(() => supportsStreaming = value),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.get('usage_tag'),
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      _UsageChip(
                        label: l10n.get('recall_scoring'),
                        value: 'recall',
                        selected: usageTags.contains('recall'),
                        onSelected: (value) => setDialogState(
                          () => value
                              ? usageTags.add('recall')
                              : usageTags.remove('recall'),
                        ),
                      ),
                      _UsageChip(
                        label: l10n.get('6a21_62df_interview'),
                        value: 'mockInterview',
                        selected: usageTags.contains('mockInterview'),
                        onSelected: (value) => setDialogState(
                          () => value
                              ? usageTags.add('mockInterview')
                              : usageTags.remove('mockInterview'),
                        ),
                      ),
                      _UsageChip(
                        label: l10n.get('image_understanding'),
                        value: 'imageReview',
                        selected: usageTags.contains('imageReview'),
                        onSelected: (value) => setDialogState(
                          () => value
                              ? usageTags.add('imageReview')
                              : usageTags.remove('imageReview'),
                        ),
                      ),
                      _UsageChip(
                        label: l10n.get('8bed_97f3_8bc6_522b'),
                        value: 'stt',
                        selected: usageTags.contains('stt'),
                        onSelected: (value) => setDialogState(
                          () => value
                              ? usageTags.add('stt')
                              : usageTags.remove('stt'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.get('cancel')),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final baseUrl = baseUrlController.text.trim();
                final apiKey = apiKeyController.text.trim();
                final model = modelController.text.trim();

                if (name.isEmpty ||
                    baseUrl.isEmpty ||
                    apiKey.isEmpty ||
                    model.isEmpty) {
                  return;
                }

                final aiProvider = context.read<AiProvider>();
                if (isEditing) {
                  final updated = config.copyWith(
                    name: name,
                    baseUrl: baseUrl,
                    apiKey: apiKey,
                    model: model,
                    isDefault: isDefault,
                    enabled: enabled,
                    supportsTextInput: supportsTextInput,
                    supportsImageInput: supportsImageInput,
                    supportsAudioInput: supportsAudioInput,
                    supportsMultimodal: supportsMultimodal,
                    supportsStreaming: supportsStreaming,
                    usageTags: usageTags.toList(),
                  );
                  aiProvider.updateConfig(updated);
                } else {
                  final newConfig = AiConfig(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: name,
                    providerType: 'openai_compatible',
                    baseUrl: baseUrl,
                    apiKey: apiKey,
                    model: model,
                    isDefault: isDefault,
                    enabled: enabled,
                    supportsTextInput: supportsTextInput,
                    supportsImageInput: supportsImageInput,
                    supportsAudioInput: supportsAudioInput,
                    supportsMultimodal: supportsMultimodal,
                    supportsStreaming: supportsStreaming,
                    usageTags: usageTags.toList(),
                  );
                  aiProvider.addConfig(newConfig);
                }

                Navigator.pop(ctx);
              },
              child: Text(l10n.get('save')),
            ),
          ],
        ),
      ),
    );
  }

  void _handleDelete(BuildContext context, AiConfig config) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('confirm_delete')),
        content: Text('${l10n.get('confirm_delete_config')}「${config.name}」${l10n.get('question_mark')}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              context.read<AiProvider>().deleteConfig(config.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(l10n.get('delete')),
          ),
        ],
      ),
    );
  }

  void _handleSetDefault(BuildContext context, AiConfig config) {
    context.read<AiProvider>().setDefaultConfig(config.id);
  }
}

class _ConfigCard extends StatelessWidget {
  const _ConfigCard({
    required this.config,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  final AiConfig config;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return WorkPanel(
      title: config.name,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (config.isDefault)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l10n.get('default'),
                style: const TextStyle(
                  color: AppColors.success,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (!config.enabled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l10n.get('already_disable'),
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      children: [
        Text('${l10n.get('model')}：${config.model}'),
        const SizedBox(height: 4),
        Text('Base URL：${config.baseUrl}'),
        const SizedBox(height: 4),
        Text('${l10n.get('capability')}：${config.capabilityLabels.map((k) => l10n.get(k)).join(' · ')}'),
        const SizedBox(height: 4),
        Text('${l10n.get('usage_purpose')}：${config.usageTags.join('、')}'),
        const SizedBox(height: 4),
        Text('${l10n.get('status')}：${config.enabled ? l10n.get('already_enable') : l10n.get('already_disable')}'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(l10n.get('edit')),
            ),
            if (!config.isDefault)
              OutlinedButton.icon(
                onPressed: onSetDefault,
                icon: const Icon(Icons.star_outline, size: 18),
                label: Text(l10n.get('set_as_default')),
              ),
            OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(l10n.get('delete')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _UsageChip extends StatelessWidget {
  const _UsageChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String value;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
    );
  }
}
