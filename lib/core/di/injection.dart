import 'package:get_it/get_it.dart';

import 'application_dependencies.dart';
import 'data_dependencies.dart';

final getIt = GetIt.instance;

Future<void> setupDependencyInjection() async {
  final bootstrap = await registerDataDependencies(getIt);
  registerApplicationDependencies(
    getIt,
    deviceId: bootstrap.deviceId,
    storedSyncBaseUrl: bootstrap.storedSyncBaseUrl,
  );
}
