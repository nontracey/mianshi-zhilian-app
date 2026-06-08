import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/connectivity_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isOnline = context.watch<ConnectivityProvider>().isOnline;
    if (isOnline) return const SizedBox.shrink();
    final l10n = context.watch<LocalizationProvider>();
    return MaterialBanner(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      content: Text(
        l10n.get('network_offline'),
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      backgroundColor: Colors.orange.shade100,
      leading: const Icon(Icons.wifi_off, color: Colors.orange),
      actions: const [SizedBox.shrink()],
    );
  }
}
