import 'package:shared_preferences/shared_preferences.dart';

/// Centralized, in-app-configurable Snipe-IT connection settings.
///
/// Replaces the old build-time `.env` (SNIPEIT_BASE_URL / SNIPEIT_API_TOKEN)
/// approach: the URL/IP and API token are now entered inside the app (see
/// `SettingsScreen`) and persisted on-device via SharedPreferences, so
/// pointing the app at a different Snipe-IT server or rotating the API
/// token no longer requires a new build.
///
/// [init] must be awaited once, before `runApp()`, so the synchronous
/// getters below ([baseUrl] / [token]) are safe to read from anywhere
/// afterwards — including inside a Dio interceptor, which can't easily be
/// made to `await` a prefs lookup per-request.
class AppSettingsService {
  AppSettingsService._();

  static const _keyBaseUrl = 'snipeit_base_url';
  static const _keyToken = 'snipeit_api_token';

  static SharedPreferences? _prefs;

  /// Loads any previously saved settings into memory. Safe to call more
  /// than once (e.g. defensively before `save()`); only loads once.
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Strips a trailing slash so callers can safely build
  /// `'$baseUrl/api/v1/...'` without ending up with a double slash.
  static String _normalizeUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// The saved Snipe-IT server URL/IP, e.g. `http://192.168.1.10` or
  /// `https://snipeit.company.com`. Empty string if not yet configured.
  static String get baseUrl => _prefs?.getString(_keyBaseUrl) ?? '';

  /// The saved Snipe-IT Personal Access Token. Empty string if not yet
  /// configured.
  static String get token => _prefs?.getString(_keyToken) ?? '';

  /// True once both a base URL and a token have been saved. The app uses
  /// this to decide whether to land on the Scanner screen or the Settings
  /// screen on startup.
  static bool get isConfigured => baseUrl.isNotEmpty && token.isNotEmpty;

  static Future<void> save({
    required String baseUrl,
    required String token,
  }) async {
    await init();
    await _prefs!.setString(_keyBaseUrl, _normalizeUrl(baseUrl));
    await _prefs!.setString(_keyToken, token.trim());
  }

  /// Wipes the saved connection settings (e.g. a "sign out" / "reset
  /// server" action, if ever exposed in the UI).
  static Future<void> clear() async {
    await init();
    await _prefs!.remove(_keyBaseUrl);
    await _prefs!.remove(_keyToken);
  }
}