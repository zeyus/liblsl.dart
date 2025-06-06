// lib/main.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import 'src/config/app_config.dart';
import 'src/data/timing_manager.dart';
import 'src/ui/home_page.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FullScreen.ensureInitialized();
  await WakelockPlus.enable();
  var logLevel = -2;
  if (kDebugMode) {
    // Enable verbose logging for debugging
    logLevel = 0;
  }
  final lslConfig = LSLApiConfig(ipv6: IPv6Mode.disable, logLevel: logLevel);
  if (kDebugMode) {
    print('Complete LSL Configuration:');
    print(lslConfig.toIniString());
  }

  LSL.setConfigContent(lslConfig);

  if (Platform.isAndroid || Platform.isIOS || Platform.isFuchsia) {
    // Enable full-screen mode for mobile platforms
    FullScreen.setFullScreen(true);
    // request permissions.
    final notificationStatus = await Permission.notification.request();
    final nearbyDevicesStatus = await Permission.location.request();
    if (notificationStatus.isDenied || nearbyDevicesStatus.isDenied) {
      // Handle the case where permissions are denied
      if (kDebugMode) {
        print('Notification permission status: $notificationStatus');
        print('Nearby devices permission status: $nearbyDevicesStatus');
      }
    } else {
      // Permissions granted, proceed with app initialization
      if (kDebugMode) {
        print('Notification permission granted: $notificationStatus');
        print('Nearby devices permission granted: $nearbyDevicesStatus');
      }
    }
  }
  // Load configuration
  final config = await AppConfig.load();

  // Initialize TimingManager
  final timingManager = TimingManager(config);

  // Initialize LSL library
  if (kDebugMode) {
    print('LSL Library Version: ${LSL.version}');
    print('LSL Library Info: ${LSL.libraryInfo()}');
  }

  await EasyLocalization.ensureInitialized();

  runApp(
    EasyLocalization(
      supportedLocales: [Locale('en'), Locale('da')],
      path: 'assets/translations',
      fallbackLocale: Locale('en'),
      useOnlyLangCode: true,
      useFallbackTranslations: true,
      child: LSLTimingApp(config: config, timingManager: timingManager),
    ),
  );
}

class LSLTimingApp extends StatelessWidget {
  final AppConfig config;
  final TimingManager timingManager;

  const LSLTimingApp({
    super.key,
    required this.config,
    required this.timingManager,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LSL Timing Tests',
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: HomePage(config: config, timingManager: timingManager),
    );
  }
}
