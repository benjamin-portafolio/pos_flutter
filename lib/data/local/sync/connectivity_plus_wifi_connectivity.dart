import 'package:connectivity_plus/connectivity_plus.dart';

import '../../../application/sync/device_wifi_connectivity.dart';

class ConnectivityPlusWifiConnectivity implements DeviceWifiConnectivity {
  ConnectivityPlusWifiConnectivity({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> isWifiConnected() async {
    final results = await _connectivity.checkConnectivity();
    return _hasWifi(results);
  }

  @override
  Stream<bool> get wifiConnectionChanges {
    return _connectivity.onConnectivityChanged.map(_hasWifi).distinct();
  }

  bool _hasWifi(List<ConnectivityResult> results) {
    return results.contains(ConnectivityResult.wifi);
  }
}
