# Shared Android signing key for CI test builds

`debug.keystore` is a standard Android *debug* key (store/key password
`android`, alias `androiddebugkey`) — not a secret. CI copies it to
`~/.android/debug.keystore` before building, so every APK published to the
Releases page has the same signature and installs as an update over the
previous build (keeping the app's saved data).

Do not use it for Play Store releases; create a private upload key for that.
