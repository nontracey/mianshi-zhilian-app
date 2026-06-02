import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../providers/localization_provider.dart';

enum AppPermissionKind { microphone, speech, camera, photos, installPackages }

class AppPermissionService {
  const AppPermissionService._();

  static Future<bool> ensureMicrophone(BuildContext context) {
    return _ensurePermission(context, AppPermissionKind.microphone);
  }

  static Future<bool> ensureSpeechRecognition(BuildContext context) async {
    if (!await _ensurePermission(context, AppPermissionKind.microphone)) {
      return false;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return true;
    }
    if (!context.mounted) return false;
    return _ensurePermission(context, AppPermissionKind.speech);
  }

  static Future<bool> ensureCamera(BuildContext context) {
    return _ensurePermission(context, AppPermissionKind.camera);
  }

  static Future<bool> ensurePhotos(BuildContext context) {
    return _ensurePermission(context, AppPermissionKind.photos);
  }

  static Future<bool> ensureInstallPackages(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _ensurePermission(context, AppPermissionKind.installPackages);
  }

  static Future<bool> _ensurePermission(
    BuildContext context,
    AppPermissionKind kind,
  ) async {
    if (kIsWeb) return true;
    if (!_usesPermissionHandler) return true;

    final permission = _permissionFor(kind);
    var status = await permission.status;
    if (_isUsable(status)) return true;

    status = await permission.request();
    if (_isUsable(status)) return true;

    if (!context.mounted) return false;
    await _showPermissionDialog(context, kind, status);
    return false;
  }

  static Permission _permissionFor(AppPermissionKind kind) {
    switch (kind) {
      case AppPermissionKind.microphone:
        return Permission.microphone;
      case AppPermissionKind.speech:
        return Permission.speech;
      case AppPermissionKind.camera:
        return Permission.camera;
      case AppPermissionKind.photos:
        return Permission.photos;
      case AppPermissionKind.installPackages:
        return Permission.requestInstallPackages;
    }
  }

  static bool get _usesPermissionHandler {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  static bool _isUsable(PermissionStatus status) {
    return status.isGranted || status.isLimited;
  }

  static Future<void> _showPermissionDialog(
    BuildContext context,
    AppPermissionKind kind,
    PermissionStatus status,
  ) async {
    final l10n = context.read<LocalizationProvider>();
    final permissionName = l10n.get(_permissionNameKey(kind));
    final shouldOpenSettings =
        status.isPermanentlyDenied || status.isRestricted || status.isLimited;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('permission_required_title')),
        content: Text(
          l10n.getp(
            shouldOpenSettings
                ? 'permission_required_open_settings_message'
                : 'permission_required_retry_message',
            {'permission': permissionName},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('permission_not_now')),
          ),
          if (shouldOpenSettings)
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await openAppSettings();
              },
              child: Text(l10n.get('permission_open_settings')),
            ),
        ],
      ),
    );
  }

  static String _permissionNameKey(AppPermissionKind kind) {
    switch (kind) {
      case AppPermissionKind.microphone:
        return 'permission_microphone_name';
      case AppPermissionKind.speech:
        return 'permission_speech_name';
      case AppPermissionKind.camera:
        return 'permission_camera_name';
      case AppPermissionKind.photos:
        return 'permission_photos_name';
      case AppPermissionKind.installPackages:
        return 'permission_install_packages_name';
    }
  }
}
