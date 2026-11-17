// Unit tests for lib/utils/ad_reward.dart -- the rewarded-ad
// confirmation flow, against both server modes: verification off
// (the server grants on the app's report) and on (it waits for
// Google's signed callback, so the app checks back).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ollie_app/utils/ad_reward.dart';

String _token(Map<String, dynamic> payload) {
  String part(Map<String, dynamic> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(payload)}.signature';
}

/// A fake server: the first report returns [report]; every status
/// check returns the next entry of [statuses] (repeating the last).
({Future<Map<String, dynamic>> Function() report, Future<Map<String, dynamic>> Function() status, int Function() checks})
    _server(Map<String, dynamic> report, [List<Map<String, dynamic>> statuses = const []]) {
  var checks = 0;
  return (
    report: () async => report,
    status: () async {
      final s = statuses.isEmpty ? <String, dynamic>{} : statuses[checks < statuses.length ? checks : statuses.length - 1];
      checks++;
      return s;
    },
    checks: () => checks,
  );
}

Future<AdRewardOutcome> _confirm(dynamic server) => confirmAdReward(
      report: server.report,
      status: server.status,
      interval: Duration.zero,
      maxChecks: 5,
    );

void main() {
  group('userIdFromAccessToken', () {
    test('reads the sub claim the server put in the token', () {
      expect(userIdFromAccessToken(_token({'sub': '0b8f6c1e-2d4a-4f5b-9c3e-7a1d2b3c4d5e', 'type': 'access'})),
          '0b8f6c1e-2d4a-4f5b-9c3e-7a1d2b3c4d5e');
    });

    test('works whatever padding the payload needs', () {
      for (final id in ['a', 'ab', 'abc', 'abcd']) {
        expect(userIdFromAccessToken(_token({'sub': id})), id);
      }
    });

    test('null for no token, garbage, or a token without sub', () {
      expect(userIdFromAccessToken(null), isNull);
      expect(userIdFromAccessToken('not-a-jwt'), isNull);
      expect(userIdFromAccessToken('a.!!!.c'), isNull);
      expect(userIdFromAccessToken(_token({'type': 'access'})), isNull);
      expect(userIdFromAccessToken(_token({'sub': ''})), isNull);
    });
  });

  group('verification off: the server grants on the report', () {
    test('granted straight away, no checking back', () async {
      final server = _server({'granted': true, 'pending': false});
      expect(await _confirm(server), AdRewardOutcome.granted);
      expect(server.checks(), 0);
    });

    test('a server from before verification existed still counts as granted', () async {
      final server = _server({'success': true, 'message': 'bonus messages unlocked', 'minutes': 10});
      expect(await _confirm(server), AdRewardOutcome.granted);
      expect(server.checks(), 0);
    });

    test('daily limit (429) is reported as such', () async {
      expect(await _confirm(_server({'granted': false, 'limit_reached': true})), AdRewardOutcome.limitReached);
    });
  });

  group('verification on: waiting for Google', () {
    test('granted as soon as the bonus shows up', () async {
      final server = _server({'granted': false, 'pending': true}, [
        {'active': false, 'ads_watched_today': 0, 'daily_ad_limit': 3},
        {'active': false, 'ads_watched_today': 0, 'daily_ad_limit': 3},
        {'active': true, 'ads_watched_today': 1, 'daily_ad_limit': 3},
      ]);
      expect(await _confirm(server), AdRewardOutcome.granted);
      expect(server.checks(), 3);
    });

    test('already confirmed by the time the app reports', () async {
      expect(await _confirm(_server({'granted': true, 'pending': false})), AdRewardOutcome.granted);
    });

    test('Google refused it because today\'s limit was already used', () async {
      final server = _server({'granted': false, 'pending': true}, [
        {'active': false, 'ads_watched_today': 3, 'daily_ad_limit': 3},
      ]);
      expect(await _confirm(server), AdRewardOutcome.limitReached);
    });

    test('gives up after maxChecks rather than waiting forever', () async {
      final server = _server({'granted': false, 'pending': true}, [
        {'active': false, 'ads_watched_today': 0, 'daily_ad_limit': 3},
      ]);
      expect(await _confirm(server), AdRewardOutcome.notConfirmed);
      expect(server.checks(), 5);
    });
  });

  test('dailyAdLimitReached only when the limit is used and no bonus runs', () {
    expect(dailyAdLimitReached({'active': false, 'ads_watched_today': 3, 'daily_ad_limit': 3}), isTrue);
    expect(dailyAdLimitReached({'active': true, 'ads_watched_today': 3, 'daily_ad_limit': 3}), isFalse);
    expect(dailyAdLimitReached({'active': false, 'ads_watched_today': 2, 'daily_ad_limit': 3}), isFalse);
    expect(dailyAdLimitReached({}), isFalse);
  });
}
