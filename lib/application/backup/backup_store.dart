import 'dart:io';

import 'backup_manifest.dart';

class BackupAccount {
  const BackupAccount({required this.userId, required this.email});

  final String userId;
  final String email;
}

abstract interface class BackupStore {
  Future<BackupStoreSession?> openSession({required bool interactive});
}

abstract interface class BackupStoreSession {
  BackupAccount get account;

  Future<BackupManifest?> readLatestManifest();

  Future<void> uploadBackup({
    required File databaseFile,
    required BackupManifest manifest,
  });

  Future<File?> downloadLatestDatabase({required Directory destination});
}

class BackupStoreException implements Exception {
  const BackupStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}
