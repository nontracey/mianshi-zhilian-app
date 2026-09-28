/// 扩展服务（远程 MCP 只读）设置页（§8.2）。
///
/// 交互契约：
/// - 没配置任何服务时明确说「未配置」，不冒充“搜到 0 条”式的空结果；
/// - 连接测试如实报告失败原因，不静默重试；
/// - Token 只写不读（显示“已填/未填”），不回传明文。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../coach/mcp/mcp_client.dart';
import '../../providers/localization_provider.dart';
import '../../services/mcp_config_service.dart';
import '../../services/safe_endpoint.dart';
import '../../theme/colors.dart';

class McpSettingsPage extends StatefulWidget {
  const McpSettingsPage({super.key});

  @override
  State<McpSettingsPage> createState() => _McpSettingsPageState();
}

class _McpSettingsPageState extends State<McpSettingsPage> {
  List<McpServerConfig> _servers = const [];
  bool _loading = true;
  final Set<String> _testing = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final service = context.read<McpConfigService>();
    final servers = await service.list();
    if (!mounted) return;
    setState(() {
      _servers = servers;
      _loading = false;
    });
  }

  Future<void> _addOrEdit([McpServerConfig? existing]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ServerDialog(existing: existing),
    );
    if (saved == true) await _reload();
  }

  Future<void> _test(McpServerConfig config) async {
    final l10n = context.read<LocalizationProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<McpConfigService>();
    setState(() => _testing.add(config.id));
    final summary = await service.testConnection(config);
    if (!mounted) return;
    setState(() => _testing.remove(config.id));
    if (!summary.ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.getp('mcp_test_failed', {'error': summary.error ?? ''}),
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.get('mcp_test_ok')),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.getp('mcp_test_summary', {
                  'total': summary.toolCount,
                  'readonly': summary.readOnlyToolCount,
                }),
              ),
              const SizedBox(height: 8),
              ...summary.tools
                  .take(8)
                  .map(
                    (t) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '• ${t.name}${t.readOnly ? '' : ' ⚠'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              if (summary.tools.any((t) => !t.readOnly)) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.get('mcp_tool_not_readonly_hint'),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(dialogContext).brightness == Brightness.dark
                        ? Colors.white54
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.get('confirm')),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(McpServerConfig config) async {
    final l10n = context.read<LocalizationProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('mcp_delete_title')),
        content: Text(l10n.getp('mcp_delete_body', {'name': config.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.get('confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<McpConfigService>().delete(config.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('mcp_settings_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l10n.get('mcp_settings_desc'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: isDark ? Colors.white54 : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                if (_servers.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(l10n.get('mcp_empty_hint')),
                    ),
                  )
                else
                  ..._servers.map(
                    (s) => Card(
                      child: ListTile(
                        title: Text(s.name),
                        subtitle: Text(
                          '${s.url}\n${s.protocolVersion}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (s.oauthClientId?.isNotEmpty == true)
                              IconButton(
                                icon: const Icon(Icons.login),
                                tooltip: l10n.get('mcp_oauth_login'),
                                onPressed: _testing.contains(s.id)
                                    ? null
                                    : () async {
                                        setState(() => _testing.add(s.id));
                                        try {
                                          await context
                                              .read<McpConfigService>()
                                              .authorize(s);
                                          await _reload();
                                        } catch (_) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  l10n.get('mcp_oauth_failed'),
                                                ),
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(
                                              () => _testing.remove(s.id),
                                            );
                                          }
                                        }
                                      },
                              ),
                            IconButton(
                              icon: _testing.contains(s.id)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.network_check, size: 20),
                              tooltip: l10n.get('mcp_test'),
                              onPressed: _testing.contains(s.id)
                                  ? null
                                  : () => _test(s),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: l10n.get('edit'),
                              onPressed: () => _addOrEdit(s),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: l10n.get('delete'),
                              onPressed: () => _delete(s),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(l10n.get('mcp_add_server')),
                  onPressed: () => _addOrEdit(),
                ),
              ],
            ),
    );
  }
}

class _ServerDialog extends StatefulWidget {
  const _ServerDialog({this.existing});

  final McpServerConfig? existing;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _token;
  late final TextEditingController _allowed;
  late final TextEditingController _clientId;
  late final TextEditingController _scope;
  late String _version;
  bool _allowSessionMaterials = false;
  bool _hasStoredToken = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _url = TextEditingController(text: existing?.url ?? '');
    _token = TextEditingController();
    _clientId = TextEditingController(text: existing?.oauthClientId ?? '');
    _scope = TextEditingController(text: existing?.oauthScope ?? '');
    _allowed = TextEditingController(
      text: (existing?.allowedTools ?? const []).join(', '),
    );
    _version = existing?.protocolVersion ?? McpProtocolVersions.v2025_11_25;
    // 已存的 token 不回显；只提示“留空保持不变”。
    _hasStoredToken = existing?.token?.isNotEmpty == true;
    _allowSessionMaterials = existing?.allowSessionMaterials ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    _allowed.dispose();
    _clientId.dispose();
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return AlertDialog(
      title: Text(
        l10n.get(
          widget.existing == null ? 'mcp_add_server' : 'mcp_edit_server',
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.get('mcp_field_name'),
              ),
            ),
            TextField(
              controller: _url,
              decoration: InputDecoration(
                labelText: l10n.get('mcp_field_url'),
                hintText: 'https://mcp.example.com/rpc',
              ),
            ),
            const SizedBox(height: 8),
            ...[
              McpProtocolVersions.v2025_11_25,
              McpProtocolVersions.v2026_07_28,
            ].map(
              (v) => RadioListTile<String>(
                value: v,
                groupValue: _version,
                onChanged: (value) => setState(() => _version = value!),
                title: Text(v, style: const TextStyle(fontSize: 13)),
                dense: true,
              ),
            ),
            TextField(
              controller: _token,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.get('mcp_field_token'),
                hintText: _hasStoredToken
                    ? l10n.get('mcp_token_stored_hint')
                    : null,
              ),
            ),
            TextField(
              controller: _clientId,
              decoration: InputDecoration(
                labelText: l10n.get('mcp_oauth_client_id'),
              ),
            ),
            TextField(
              controller: _scope,
              decoration: InputDecoration(
                labelText: l10n.get('mcp_oauth_scope'),
              ),
            ),
            SelectableText(
              '${l10n.get('mcp_oauth_redirect')}: ${context.read<McpConfigService>().oauthRedirectUri}',
            ),
            CheckboxListTile(
              value: _allowSessionMaterials,
              onChanged: (v) =>
                  setState(() => _allowSessionMaterials = v ?? false),
              title: Text(l10n.get('mcp_allow_session_materials')),
              subtitle: Text(l10n.get('mcp_allow_session_materials_note')),
            ),
            TextField(
              controller: _allowed,
              decoration: InputDecoration(
                labelText: l10n.get('mcp_field_allowed'),
                helperText: l10n.get('mcp_field_allowed_helper'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.get('cancel')),
        ),
        FilledButton(
          onPressed: () => _save(context),
          child: Text(l10n.get('confirm')),
        ),
      ],
    );
  }

  Future<void> _save(BuildContext context) async {
    final l10n = context.read<LocalizationProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<McpConfigService>();
    final name = _name.text.trim();
    final url = _url.text.trim();
    final uri = Uri.tryParse(url);
    // MCP 请求带 Bearer token：跨公网必须 https（OAuth 自身已强制 https，
    // 这里补上手工填地址的入口）。
    if (name.isEmpty || uri == null || !isAllowedCredentialEndpoint(uri)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.get('mcp_invalid_input')),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    final allowed = _allowed.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final config = McpServerConfig(
      id: widget.existing?.id ?? 'mcp.${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      url: url,
      protocolVersion: _version,
      allowedTools: allowed,
      allowSessionMaterials: _allowSessionMaterials,
      oauthClientId: _clientId.text.trim().isEmpty
          ? null
          : _clientId.text.trim(),
      oauthScope: _scope.text.trim(),
    );
    // token 输入为空：新配置=无 token；编辑=保持原值不变。
    final ok = await service.save(
      config,
      token: _token.text.isEmpty
          ? (widget.existing == null ? '' : null)
          : _token.text,
    );
    if (!mounted) return;
    if (ok && context.mounted) Navigator.pop(context, true);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.get('mcp_token_save_failed')),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
}
