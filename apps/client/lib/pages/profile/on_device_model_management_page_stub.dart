import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mianshi_zhilian/providers/localization_provider.dart';

class OnDeviceModelManagementPage extends StatelessWidget {
  const OnDeviceModelManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('on_device_model_management'))),
      body: Center(child: Text(l10n.get('on_device_stt_web_unsupported'))),
    );
  }
}
