import 'dart:convert';

// Rewarded-ad helpers -- pure functions, so the chat screen's ad flow
// can be tested without the ad SDK or the network.
//
// Why the user id matters: Google calls Ollie's server directly when
// an ad is really finished (AdMob server-side verification), and the
// server only trusts that signed callback, not the app's own report.
// For the callback to say which account earned the reward, the app
// attaches the user's id to the ad before showing it.

/// The signed-in user's id, read from the `sub` claim of the access
/// token the server issued at login (auth.py's create_access_token).
/// Null if there's no token or it can't be read. Only read here, never
/// trusted for anything else -- the server checks the real token.
String? userIdFromAccessToken(String? token) {
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final sub = payload is Map ? payload['sub'] : null;
    return sub is String && sub.isNotEmpty ? sub : null;
  } catch (_) {
    return null;
  }
}

enum AdRewardOutcome { granted, limitReached, notConfirmed }

/// After the ad SDK reports a finished ad: tells the server, then --
/// if the server is waiting for Google's own confirmation -- checks
/// back every [interval] until the bonus is running, up to
/// [maxChecks] times (Google normally confirms within a few seconds).
///
/// [report] is POST /premium/watch-ad, [status] is
/// GET /premium/ad-bonus-status.
Future<AdRewardOutcome> confirmAdReward({
  required Future<Map<String, dynamic>> Function() report,
  required Future<Map<String, dynamic>> Function() status,
  Duration interval = const Duration(milliseconds: 1500),
  int maxChecks = 10,
}) async {
  final reported = await report();
  // Servers from before verification existed answer
  // {"success": true, ...} with no granted/pending fields -- that
  // always meant the bonus was granted.
  final legacyGrant =
      reported['success'] == true && !reported.containsKey('granted') && !reported.containsKey('pending');
  if (reported['granted'] == true || legacyGrant) return AdRewardOutcome.granted;
  if (reported['limit_reached'] == true) return AdRewardOutcome.limitReached;
  if (reported['pending'] != true) return AdRewardOutcome.notConfirmed;

  for (var i = 0; i < maxChecks; i++) {
    await Future<void>.delayed(interval);
    final current = await status();
    if (current['active'] == true) return AdRewardOutcome.granted;
    if (dailyAdLimitReached(current)) return AdRewardOutcome.limitReached;
  }
  return AdRewardOutcome.notConfirmed;
}

/// Whether today's ad rewards are used up, from /ad-bonus-status.
bool dailyAdLimitReached(Map<String, dynamic> status) {
  final watched = status['ads_watched_today'];
  final limit = status['daily_ad_limit'];
  return watched is int && limit is int && status['active'] != true && watched >= limit;
}
