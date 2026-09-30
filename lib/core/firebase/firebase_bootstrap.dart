import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../firebase_options.dart';

/// Task 75: brings up the default Firebase app (project `run-it-febca`) once,
/// at startup, before anything that needs it — firebase_messaging (the next
/// task's device-token registration) first among them.
///
/// Only Android and iOS are registered in Firebase (see firebase.json /
/// firebase_options.dart); the web/macOS builds skip this rather than crash
/// on DefaultFirebaseOptions' UnsupportedError. A failure is reported to
/// Sentry and logged, never thrown — push notifications being unavailable
/// must not take the whole app down with them.
Future<void> initializeFirebase() async {
  if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
    debugPrint('Firebase: skipped — no Firebase app is registered for this platform.');
    return;
  }
  try {
    final app = await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    debugPrint('Firebase: initialized "${app.name}" for project ${app.options.projectId} (app ${app.options.appId}).');
  } catch (error, stackTrace) {
    debugPrint('Firebase: initialization FAILED — $error');
    await Sentry.captureException(error, stackTrace: stackTrace);
  }
}
