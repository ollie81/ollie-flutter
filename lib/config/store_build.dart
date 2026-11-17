// Which store this build is for. The Google Play bundle is built with
// --dart-define=PLAY_STORE=true (see .github/workflows/main.yml); the
// APK that's shared directly is built without it.
const bool isPlayStoreBuild = bool.fromEnvironment('PLAY_STORE');

// Voice -- hold-to-talk messages and hearing Ollie's replies -- isn't
// on the Play Store yet. There the mic shows "coming soon" and the
// reply speakers are hidden; the directly shared APK keeps full voice.
const bool voiceComingSoon = isPlayStoreBuild;
