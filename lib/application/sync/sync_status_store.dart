import 'models/sync_local_status.dart';

abstract interface class SyncStatusStore {
  Stream<SyncLocalStatus> watch();
}
