class AppConfig {
  AppConfig._();

  /// Default DSP service address. Deployed live on Render with HTTPS and MongoDB.
  static const String pythonBaseUrl = String.fromEnvironment(
    'PYTHON_BASE_URL',
    defaultValue: 'https://voice-edior.onrender.com',
  );
}
