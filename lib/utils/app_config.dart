class AppConfig {
  AppConfig._();

  /// Default DSP service address. Over USB the phone reaches the Mac with `adb reverse tcp:8088 tcp:8088`.
  /// Override at build time: --dart-define=PYTHON_BASE_URL=https://api.example.com
  static const String pythonBaseUrl = String.fromEnvironment(
    'PYTHON_BASE_URL',
    defaultValue: 'http://127.0.0.1:8088',
  );
}
