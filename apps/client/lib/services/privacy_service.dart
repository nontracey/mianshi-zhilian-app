import 'package:flutter/material.dart';
import 'package:mianshi_zhilian/widgets/privacy_dialog.dart';

class PrivacyService {
  static bool _hasConfirmed = false;
  static String? _confirmedDataType;

  static bool get hasConfirmed => _hasConfirmed;

  static Future<bool> confirmUpload({
    required BuildContext context,
    required String dataType,
    required String dataDescription,
  }) async {
    if (_hasConfirmed && _confirmedDataType == dataType) {
      return true;
    }

    final confirmed = await PrivacyConfirmDialog.show(
      context: context,
      dataType: dataType,
      dataDescription: dataDescription,
    );

    if (confirmed) {
      _hasConfirmed = true;
      _confirmedDataType = dataType;
    }

    return confirmed;
  }

  static void reset() {
    _hasConfirmed = false;
    _confirmedDataType = null;
  }
}
