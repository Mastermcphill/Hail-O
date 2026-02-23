import 'package:shared_preferences/shared_preferences.dart';

class MarketplaceDevSettings {
  const MarketplaceDevSettings();

  static const String useLiveApiPreferenceKey = 'marketplace.use_live_api';

  Future<bool> readUseLiveApi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(useLiveApiPreferenceKey) ?? false;
  }

  Future<void> writeUseLiveApi(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(useLiveApiPreferenceKey, value);
  }
}
