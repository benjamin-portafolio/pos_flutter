import 'package:get_it/get_it.dart';

import '../../application/config/app_config.dart';
import 'application_dependencies.dart';
import 'data_dependencies.dart';

final getIt = GetIt.instance;

class DependencyBootstrap {
  const DependencyBootstrap({required this.appConfig});

  final AppConfig appConfig;
}

Future<DependencyBootstrap> setupDependencyInjection() async {
  final bootstrap = await registerDataDependencies(getIt);
  registerApplicationDependencies(
    getIt,
    deviceId: bootstrap.deviceId,
    appConfig: bootstrap.appConfig,
    storedSyncBaseUrl: bootstrap.storedSyncBaseUrl,
    requireWifiForServerDetection: bootstrap.requireWifiForServerDetection,
  );
  return DependencyBootstrap(appConfig: bootstrap.appConfig);
}
