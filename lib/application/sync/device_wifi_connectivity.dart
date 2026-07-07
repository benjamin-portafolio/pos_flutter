abstract interface class DeviceWifiConnectivity {
  Future<bool> isWifiConnected();

  Stream<bool> get wifiConnectionChanges;
}
