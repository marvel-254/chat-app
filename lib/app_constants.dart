/// CI stamps every build with its release number via --dart-define
/// (build-apk.yml / pages.yml). Empty in local/debug builds.
const String buildNumber = String.fromEnvironment('BUILD_NUMBER');
