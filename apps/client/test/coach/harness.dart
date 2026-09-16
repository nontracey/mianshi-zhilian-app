import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
export 'package:flutter_test/flutter_test.dart';

Future<void> expectThrowsAsync(
  FutureOr<void> Function() action,
  Matcher matcher, [
  String? reason,
]) => expectLater(Future.sync(action), throwsA(matcher), reason: reason);
