/// CI stamps every build with its release number via --dart-define
/// (build-apk.yml / pages.yml). Empty in local/debug builds.
const String buildNumber = String.fromEnvironment('BUILD_NUMBER');

/// Semantic version from pubspec.yaml, injected by scripts/build.sh and CI.
/// The updater compares this with GitHub release tags; an empty value disables
/// update prompts for unstamped local builds.
const String appVersion = String.fromEnvironment('APP_VERSION');
