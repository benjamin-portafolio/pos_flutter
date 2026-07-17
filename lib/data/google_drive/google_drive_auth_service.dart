import 'package:google_sign_in/google_sign_in.dart';

import '../../application/backup/backup_store.dart';

class GoogleDriveAuthSession {
  const GoogleDriveAuthSession({
    required this.account,
    required this.authHeaders,
  });

  final BackupAccount account;
  final Map<String, String> authHeaders;
}

class GoogleDriveAuthService {
  static const driveAppDataScope =
      'https://www.googleapis.com/auth/drive.appdata';

  final GoogleSignIn _signIn = GoogleSignIn.instance;
  bool _initialized = false;

  Future<GoogleDriveAuthSession?> authorize({required bool interactive}) async {
    try {
      await _ensureInitialized();

      final account = await _account(interactive: interactive);
      if (account == null) return null;

      final headers = await account.authorizationClient.authorizationHeaders(
        const [driveAppDataScope],
        promptIfNecessary: interactive,
      );
      if (headers == null) return null;

      return GoogleDriveAuthSession(
        account: BackupAccount(userId: account.id, email: account.email),
        authHeaders: headers,
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted ||
          error.code == GoogleSignInExceptionCode.uiUnavailable) {
        return null;
      }
      rethrow;
    } on UnsupportedError {
      return null;
    }
  }

  Future<GoogleSignInAccount?> _account({required bool interactive}) async {
    final lightweight = _signIn.attemptLightweightAuthentication();
    final lightweightAccount = lightweight == null ? null : await lightweight;
    if (lightweightAccount != null) return lightweightAccount;
    if (!interactive) return null;

    return _signIn.authenticate(scopeHint: const [driveAppDataScope]);
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _signIn.initialize();
    _initialized = true;
  }
}
