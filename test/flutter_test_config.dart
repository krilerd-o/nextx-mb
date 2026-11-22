import 'dart:async';

import 'package:nextx_mobile/core/ai_consent.dart';

/// Runs before every test file. Tests of other features open AI screens with the AI consent already
/// given; test/r98_store_readiness_test.dart turns it off to test the consent itself.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AiConsent.debugAssumeGranted = true;
  await testMain();
}
