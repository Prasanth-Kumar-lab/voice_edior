import 'dart:async';
import 'dart:convert';
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

/// Client for the Python neural DSP service (DeepFilterNet3 + mastering + JWT auth).
class EnhanceServer extends GetxService {
  EnhanceServer()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(minutes: 5),
            sendTimeout: const Duration(minutes: 3),
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          if (_accessToken != null && _accessToken!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $_accessToken';
          }
          handler.next(options);
        },
        onError: (DioException error, ErrorInterceptorHandler handler) async {
          if (error.response?.statusCode == 401 &&
              _refreshToken != null &&
              _refreshToken!.isNotEmpty &&
              !error.requestOptions.path.contains('/api/auth/')) {
            final bool refreshed = await tryRefreshToken();
            if (refreshed && _accessToken != null) {
              final RequestOptions req = error.requestOptions;
              req.headers['Authorization'] = 'Bearer $_accessToken';
              try {
                final Response<dynamic> cloneRes = await _dio.fetch<dynamic>(req);
                return handler.resolve(cloneRes);
              } catch (_) {}
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final connected = false.obs;
  final wakingUp = false.obs;
  final activeJobId = ''.obs;
  final lastCompletedJobId = ''.obs;
  final engine = ''.obs;
  String host = AppConfig.pythonBaseUrl;
  String? custom;

  String? _accessToken;
  String? _refreshToken;
  bool _refreshing = false;

  Dio get dio => _dio;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;

  List<String> get _hosts {
    final List<String> all = [
      AppConfig.pythonBaseUrl,
      if (custom != null &&
          custom!.isNotEmpty &&
          !custom!.contains('192.168.') &&
          !custom!.contains('10.0.2.2') &&
          !custom!.contains('127.0.0.1') &&
          !custom!.contains('localhost'))
        custom!,
    ];
    return all.toSet().toList();
  }

  Future<File> _urlFile() async =>
      File(p.join((await getApplicationSupportDirectory()).path, 'server_url.txt'));

  Future<File> _tokenFile() async =>
      File(p.join((await getApplicationSupportDirectory()).path, 'auth_tokens.json'));

  @override
  void onInit() {
    super.onInit();
    _initStorage();
  }

  Future<void> _initStorage() async {
    try {
      final File uf = await _urlFile();
      if (uf.existsSync()) {
        final String saved = (await uf.readAsString()).trim();
        if (saved.contains('192.168.') ||
            saved.contains('10.0.2.2') ||
            saved.contains('127.0.0.1') ||
            saved.contains('localhost')) {
          await uf.delete();
          custom = null;
        } else {
          custom = saved;
        }
      }
    } catch (_) {}
    try {
      final File tf = await _tokenFile();
      if (tf.existsSync()) {
        final Map<String, dynamic> map =
            jsonDecode(await tf.readAsString()) as Map<String, dynamic>;
        _accessToken = map['access_token'] as String?;
        _refreshToken = map['refresh_token'] as String?;
      }
    } catch (_) {}
    await ping();
  }

  Future<void> setTokens({required String? accessToken, required String? refreshToken}) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    try {
      final File tf = await _tokenFile();
      if (accessToken == null || accessToken.isEmpty) {
        if (tf.existsSync()) await tf.delete();
      } else {
        await tf.writeAsString(jsonEncode({
          'access_token': accessToken,
          'refresh_token': refreshToken,
        }));
      }
    } catch (_) {}
  }

  Future<void> clearTokens() => setTokens(accessToken: null, refreshToken: null);

  Future<bool> tryRefreshToken() async {
    if (_refreshing || _refreshToken == null || _refreshToken!.isEmpty) return false;
    _refreshing = true;
    try {
      final Response<dynamic> res = await _dio.post<dynamic>(
        '$host/api/auth/refresh',
        data: {'refresh_token': _refreshToken},
      );
      if (res.statusCode == 200 && res.data is Map) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(res.data as Map);
        await setTokens(
          accessToken: data['access_token'] as String?,
          refreshToken: data['refresh_token'] as String?,
        );
        return true;
      }
    } catch (_) {
      await clearTokens();
    } finally {
      _refreshing = false;
    }
    return false;
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
      final Stopwatch sw = Stopwatch()..start();
      Timer? coldTimer;
      if (h.contains('onrender.com')) {
        coldTimer = Timer(const Duration(milliseconds: 1400), () {
          wakingUp.value = true;
        });
      }
      try {
        final Response<dynamic> res = await _dio.get<dynamic>('$h/health');
        coldTimer?.cancel();
        sw.stop();
        if (res.statusCode == 200) {
          host = h;
          connected.value = true;
          wakingUp.value = false;
          engine.value = (res.data is Map ? res.data['engine'] as String? : null) ?? '';
          return true;
        }
      } catch (_) {
        coldTimer?.cancel();
      }
    }
    wakingUp.value = false;
    connected.value = false;
    engine.value = '';
    return false;
  }

  Future<void> cancelActiveJob() async {
    final String id = activeJobId.value;
    if (id.isEmpty) return;
    activeJobId.value = '';
    try {
      await _dio.post<dynamic>('$host/cancel/$id');
    } catch (_) {}
  }

  /// Fast Stage-2 cached restyle (<1s) when switching Tone / Space / Level / Strength on the Result screen.
  Future<ServerResult?> restyleCached({
    required String tone,
    required String space,
    required String level,
    required double strength,
  }) async {
    final String id = lastCompletedJobId.value;
    if (id.isEmpty) return null;
    try {
      final Response<dynamic> res = await _dio.post<dynamic>(
        '$host/restyle/$id',
        data: <String, dynamic>{
          'eq': tone,
          'space': space,
          'level': level,
          'strength': strength,
        },
      );
      if (res.statusCode == 200 && res.data is Map) {
        final Map<String, dynamic> body = Map<String, dynamic>.from(res.data as Map);
        final Directory dir = await getTemporaryDirectory();
        final String out =
            p.join(dir.path, 'enhanced-$id-${DateTime.now().millisecondsSinceEpoch}.wav');
        await _dio.download('$host/download/$id', out);
        if (File(out).existsSync() && File(out).lengthSync() > 100) {
          return ServerResult(
            out,
            Map<String, dynamic>.from((body['report'] as Map?) ?? const {}),
          );
        }
      }
    } catch (_) {}
    return null;
  }

  Future<ServerResult> enhance(
    String wavPath,
    EnhanceMode mode, {
    String tone = 'natural',
    String space = 'dry',
    String level = 'enhanced',
    double strength = 1.0,
    bool voiceIsolation = false,
    double? previewSeconds,
    String? userEmail,
    required void Function(String stage, double progress) onProgress,
  }) async {
    onProgress('Uploading', 0.02);
    final FormData form = FormData.fromMap({
      'mode': mode.id,
      'eq': tone,
      'space': space,
      'level': level,
      'strength': strength,
      'voice_isolation': voiceIsolation,
      if (previewSeconds != null && previewSeconds > 0)
        'preview_seconds': previewSeconds,
      if (userEmail != null && userEmail.isNotEmpty) 'user_email': userEmail,
      'file': await MultipartFile.fromFile(
        wavPath,
        filename: 'take.wav',
        contentType: DioMediaType('audio', 'wav'),
      ),
    });
    final Response<dynamic> sub = await _dio.post<dynamic>('$host/enhance', data: form);
    final String id = sub.data['job_id'] as String;
    activeJobId.value = id;
    Map<String, dynamic> status = <String, dynamic>{};
    while (true) {
      final Response<dynamic> res = await _dio.get<dynamic>('$host/status/$id');
      status = Map<String, dynamic>.from(res.data as Map);
      onProgress(
        (status['stage'] as String?) ?? 'Processing',
        ((status['progress'] as num?) ?? 0).toDouble(),
      );
      if (status['status'] == 'complete') break;
      if (status['status'] == 'cancelled') {
        activeJobId.value = '';
        throw StateError('Cancelled');
      }
      if (status['status'] == 'failed') {
        activeJobId.value = '';
        throw StateError((status['error'] as String?) ?? 'Processing failed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    activeJobId.value = '';
    lastCompletedJobId.value = id;
    final Directory dir = await getTemporaryDirectory();
    final String out = p.join(dir.path, 'enhanced-$id.wav');
    onProgress('Downloading', 0.99);
    await _dio.download('$host/download/$id', out);
    if (!File(out).existsSync() || File(out).lengthSync() < 100) {
      throw StateError('Empty result');
    }
    debugPrint('server report: ${status['report']}');
    return ServerResult(out, Map<String, dynamic>.from((status['report'] as Map?) ?? const {}));
  }
}
