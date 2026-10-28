import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'controllers/admin_controller.dart';
import 'controllers/mix_controller.dart';
import 'controllers/studio_controller.dart';
import 'services/enhance_server.dart';
import 'services/mix_engine_service.dart';
import 'services/native_engine.dart';
import 'services/permission_service.dart';
import 'theme/app_theme.dart';
import 'utils/app_localization.dart';
import 'views/admin_view.dart';
import 'views/splash_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Get.put<AppPreferencesController>(AppPreferencesController(), permanent: true);
  Get.put<NativeEngine>(NativeEngine(), permanent: true);
  Get.put<MixEngineService>(MixEngineService(), permanent: true);
  Get.put<EnhanceServer>(EnhanceServer(), permanent: true);
  Get.put<PermissionService>(PermissionService(), permanent: true);
  Get.put<StudioController>(StudioController(), permanent: true);
  Get.put<MixController>(MixController(), permanent: true);
  Get.put<AdminController>(AdminController(), permanent: true);
  runApp(const VocalPolishApp());
}

class VocalPolishApp extends StatelessWidget {
  const VocalPolishApp({super.key});

  @override
  Widget build(BuildContext context) {
    final AppPreferencesController prefs = Get.find<AppPreferencesController>();
    return Obx(
      () => GetMaterialApp(
        title: 'VocalPolish',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: prefs.themeMode.value,
        home: kIsWeb ? const AdminView() : const SplashView(),
      ),
    );
  }
}
