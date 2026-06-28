import 'models/sync_event.dart';

typedef EventHandler = Future<void> Function(SyncEvent event);
