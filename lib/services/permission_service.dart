import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_colors.dart';

class PermissionService extends GetxService {
  Future<bool> ensureMic() async {
    final PermissionStatus status = await Permission.microphone.request();
    if (status.isGranted) return true;
    await _rationale(
      title: 'Microphone access',
      body:
          'VocalPolish records in-app so we can meter levels and keep your take local. Enable the microphone to continue, or import a file instead.',
    );
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    return (await Permission.microphone.status).isGranted;
  }

  Future<bool> ensureFiles() async {
    PermissionStatus status = await Permission.audio.request();
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    if (status.isGranted || status.isLimited) return true;
    await _rationale(
      title: 'File access',
      body:
          'To import vocals from this device, VocalPolish needs access to audio files. You can still record in-app without this permission.',
    );
    return (await Permission.audio.status).isGranted ||
        (await Permission.storage.status).isGranted;
  }

  Future<void> _rationale({required String title, required String body}) async {
    final Brightness b = Get.theme.brightness;
    await Get.dialog(
      AlertDialog(
        title: Text(title),
        content: Text(body, style: TextStyle(color: AppColors.muted(b))),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Not now')),
          FilledButton(onPressed: Get.back, child: const Text('Continue')),
        ],
      ),
    );
  }
}
