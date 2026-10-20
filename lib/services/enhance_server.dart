import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide FormData, MultipartFile, Response;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/enhance_mode.dart';
import '../utils/app_config.dart';

class ServerResult {
  const ServerResult(this.path, this.report);
  final String path;
  final Map<String, dynamic> report;
}

/// Client for the Python neural DSP service (DeepFilterNet3 + mastering).
class EnhanceServer extends GetxService {
  EnhanceServer()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(minutes: 5),
            sendTimeout: const Duration(minutes: 3),
          ),
        );

  final Dio _dio;
  final connected = false.obs;
  final engine = ''.obs;
  String host = AppConfig.pythonBaseUrl;
  String? custom;

  Dio get dio => _dio;

  List<String> get _hosts {
    final List<String> all = [
      if (custom != null) custom!,
      AppConfig.pythonBaseUrl,
      'http://127.0.0.1:8088',
      'http://10.0.2.2:8088',
    ];
    return all.toSet().toList();
  }

  Future<File> _urlFile() async => File(p.join((await getApplicationSupportDirectory()).path, 'server_url.txt'));

  @override
  void onInit() {
    super.onInit();
    _urlFile().then((File f) async {
      if (f.existsSync()) custom = (await f.readAsString()).trim();
      await ping();
    });
  }

  Future<void> setCustomUrl(String url) async {
    custom = url.trim().isEmpty ? null : url.trim().replaceAll(RegExp(r'/+$'), '');
    final File f = await _urlFile();
    if (custom == null) {
      if (f.existsSync()) await f.delete();
    } else {
      await f.writeAsString(custom!);
    }
    await ping();
  }

  Future<bool> ping() async {
    for (final String h in _hosts) {
      try {
        final Response<dynamic> res = await _dio.get<dynamic>('$h/health');
        if (res.statusCode == 200) {
          host = h;
          connected.value = true;
          engine.value = (res.data is Map ? res.data['engine'] as String? : null) ?? '';
          return true;
        }
      } catch (_) {}
    }
    connected.value = false;
    engine.value = '';
    return false;
  }

  Future<ServerResult> enhance(
    String wavPath,
    EnhanceMode mode, {
    String tone = 'natural',
    String space = 'dry',
    String level = 'enhanced',
    String? userEmail,
    required void Function(String stage, double progress) onProgress,
  }) async {
    onProgress('Uploading', 0.02);
    final FormData form = FormData.fromMap({
      'mode': mode.id,
      'eq': tone,
      'space': space,
      'level': level,
      if (userEmail != null && userEmail.isNotEmpty) 'user_email': userEmail,
      'file': await MultipartFile.fromFile(wavPath, filename: 'take.wav'),
    });
    final Response<dynamic> sub = await _dio.post<dynamic>('$host/enhance', data: form);
    final String id = sub.data['job_id'] as String;
    Map<String, dynamic> status = <String, dynamic>{};
    while (true) {
      final Response<dynamic> res = await _dio.get<dynamic>('$host/status/$id');
      status = Map<String, dynamic>.from(res.data as Map);
      onProgress((status['stage'] as String?) ?? 'Processing', ((status['progress'] as num?) ?? 0).toDouble());
      if (status['status'] == 'complete') break;
      if (status['status'] == 'failed') throw StateError((status['error'] as String?) ?? 'Processing failed');
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final Directory dir = await getTemporaryDirectory();
    final String out = p.join(dir.path, 'enhanced-$id.wav');
    onProgress('Downloading', 0.99);
    await _dio.download('$host/download/$id', out);
    if (!File(out).existsSync() || File(out).lengthSync() < 100) throw StateError('Empty result');
    debugPrint('server report: ${status['report']}');
    return ServerResult(out, Map<String, dynamic>.from((status['report'] as Map?) ?? const {}));
  }
}
