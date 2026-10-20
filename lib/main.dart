import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'controllers/admin_controller.dart';
import 'controllers/studio_controller.dart';
import 'services/enhance_server.dart';
import 'services/native_engine.dart';
import 'services/permission_service.dart';
import 'theme/app_theme.dart';
import 'views/admin_view.dart';
import 'views/splash_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Get.put<NativeEngine>(NativeEngine(), permanent: true);
  Get.put<EnhanceServer>(EnhanceServer(), permanent: true);
  Get.put<PermissionService>(PermissionService(), permanent: true);
  Get.put<StudioController>(StudioController(), permanent: true);
  Get.put<AdminController>(AdminController(), permanent: true);
  runApp(const VocalPolishApp());
}

class VocalPolishApp extends StatelessWidget {
  const VocalPolishApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'VocalPolish',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: kIsWeb ? const AdminView() : const SplashView(),
    );
  }
}
