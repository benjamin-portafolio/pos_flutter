import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/offer_pricing_availability.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/data/local/sync/sync_capability_file_store.dart';

void main() {
  test(
    'capacidad por endpoint, persistencia offline, revocación y standalone sin lectura',
    () async {
      final dir = await Directory.systemTemp.createTemp('offer-capabilities-');
      addTearDown(() => dir.delete(recursive: true));
      final config = AppConfigController(
        AppConfig.initial.copyWith(mode: AppMode.serverSync),
      );
      addTearDown(config.dispose);
      final endpoint = SyncEndpointConfig(
        initialBaseUrl: 'http://localhost:1234',
      );
      final store = SyncCapabilityFileStore(directoryProvider: () async => dir);
      OfferPricingAvailability policy() => OfferPricingAvailability(
        config: config,
        endpoint: endpoint,
        store: store,
      );
      await expectLater(policy().requireCompatible(), throwsStateError);
      await store.write(endpoint.baseUrl, ['offer_pricing_v2']);
      await policy().requireCompatible();
      endpoint.updateFromInput('localhost:5678');
      await expectLater(policy().requireCompatible(), throwsStateError);
      endpoint.updateFromInput('localhost:1234');
      await policy().requireCompatible();
      await store.write(endpoint.baseUrl, []);
      await expectLater(policy().requireCompatible(), throwsStateError);
      config.update(config.config.copyWith(mode: AppMode.standalone));
      final offline = OfferPricingAvailability(
        config: config,
        endpoint: endpoint,
        store: SyncCapabilityFileStore(
          directoryProvider: () async =>
              throw StateError('standalone no lee capacidad'),
        ),
      );
      await offline.requireCompatible();
    },
  );
}
