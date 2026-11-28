import 'package:flutter/foundation.dart';
import '../../../application/config/app_config.dart';

bool canAdministerServer(AppMode mode) =>
    !kIsWeb &&
    mode == AppMode.serverSync &&
    {
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }.contains(defaultTargetPlatform);
