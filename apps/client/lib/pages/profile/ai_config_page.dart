import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class AiConfigPage extends StatefulWidget {
  const AiConfigPage({super.key});

  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage> {
  @override
  Widget build(BuildContext context) {
    final aiProvider = context.watch<AiProvider>();
    final configs = aiProvider.configs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 配置管理'),
        actions: [
          IconButton(
            onPressed: () => _showEditDialog(context),
            icon: const Icon(Icons.add),
            tooltip: '添加配置',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (configs.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Column(
                  children: [
                    Icon(Icons.hub_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('暂无 AI 配置', style: TextStyle(fontSize: 16)),
                    SizedBox(height: 8),
                    Text('点击右上角 + 添加新配置'),
                  ],
                ),
              ),
            )
          else
            ...configs.map((config) => _ConfigCard(
                  config: config,
                  onEdit: () => _showEditDialog(context, config: config),
                  onDelete: () => _handleDelete(context, config),
                  onSetDefault: () => _handleSetDefault(context, config),
                )),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, {AiConfig? config}) {
    final isEditing = config != null;
    final nameController = TextEditingController(text: config?.name ?? '');
    final baseUrlController = TextEditingController(text: config?.baseUrl ?? '');
    final apiKeyController = TextEditingController(text: config?.apiKey ?? '');
    final modelController = TextEditingController(text: config?.model ?? '');
    bool isDefault = config?.isDefault ?? false;
    bool enabled = config?.enabled ?? true;
    String? testResult;
    bool isTesting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEditing ? '编辑配置' : '添加新配置'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      hintText: '例如：OpenAI、DeepSeek',
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
                    decoration: const InputDecoration(
                      labelText: '模型名',
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
                              final success = await aiProvider.testConnectionWithParams(
                                baseUrl: baseUrlController.text.trim(),
                                apiKey: apiKeyController.text.trim(),
                                model: modelController.text.trim(),
                              );
                              setDialogState(() {
                                testResult = success ? '连接成功' : '连接失败';
                                isTesting = false;
                              });
                            } catch (e) {
                              setDialogState(() {
                                testResult = '连接失败：$e';
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
                    label: Text(isTesting ? '测试中...' : '测试连接'),
                  ),
                  if (testResult != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      testResult!,
                      style: TextStyle(
                        color: testResult == '连接成功'
                            ? AppColors.success
                            : AppColors.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SwitchListTile(
                    value: isDefault,
                    title: const Text('设为默认'),
                    onChanged: (value) => setDialogState(() => isDefault = value),
                  ),
                  SwitchListTile(
                    value: enabled,
                    title: const Text('启用'),
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final baseUrl = baseUrlController.text.trim();
                final apiKey = apiKeyController.text.trim();
                final model = modelController.text.trim();

                if (name.isEmpty || baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
                  return;
                }

                final aiProvider = context.read<AiProvider>();
                if (isEditing) {
                  final updated = config!.copyWith(
                    name: name,
                    baseUrl: baseUrl,
                    apiKey: apiKey,
                    model: model,
                    isDefault: isDefault,
                    enabled: enabled,
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
                  );
                  aiProvider.addConfig(newConfig);
                }

                Navigator.pop(ctx);
              },
              child: const Text('保存'),
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
        title: const Text('确认删除'),
        content: Text('确定要删除配置「${config.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              context.read<AiProvider>().deleteConfig(config.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('删除'),
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
              child: const Text(
                '默认',
                style: TextStyle(
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
              child: const Text(
                '已禁用',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      children: [
        Text('模型：${config.model}'),
        const SizedBox(height: 4),
        Text('Base URL：${config.baseUrl}'),
        const SizedBox(height: 4),
        Text('状态：${config.enabled ? '已启用' : '已禁用'}'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('编辑'),
            ),
            if (!config.isDefault)
              OutlinedButton.icon(
                onPressed: onSetDefault,
                icon: const Icon(Icons.star_outline, size: 18),
                label: const Text('设为默认'),
              ),
            OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            ),
          ],
        ),
      ],
    );
  }
}
