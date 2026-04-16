import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'router/app_router.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ApiService().initialize();
  await AuthService().initialize();
  runApp(
    const ProviderScope(
      child: PocketShopApp(),
    ),
  );
}

class PocketShopApp extends ConsumerWidget {
  const PocketShopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authInitializationProvider);
    final router = ref.watch(goRouterProvider);

    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: AppConstants.appName,
          theme: AppTheme.lightTheme,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
