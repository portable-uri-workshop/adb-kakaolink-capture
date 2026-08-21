package dev.local.adbintentcapture;

/** Pure-Java matching policy shared by the monitor and local regression tests. */
final class LaunchDecision {
    private static final String KAKAOLINK_SCHEME = "kakaolink";
    private static final String KAKAOLINK_SEND_HOST = "send";
    private static final String KAKAOTALK_PACKAGE = "com.kakao.talk";

    private LaunchDecision() {}

    static boolean isKakaoTalkSend(
            String scheme,
            String host,
            String targetPackage,
            String componentPackage) {
        if (!equalsIgnoreCase(KAKAOLINK_SCHEME, scheme)
                || !equalsIgnoreCase(KAKAOLINK_SEND_HOST, host)) {
            return false;
        }

        return equalsIgnoreCase(KAKAOTALK_PACKAGE, targetPackage)
                || equalsIgnoreCase(KAKAOTALK_PACKAGE, componentPackage);
    }

    static boolean shouldAllowMatchedStart(boolean blockLaunch) {
        return !blockLaunch;
    }

    private static boolean equalsIgnoreCase(String expected, String actual) {
        return actual != null && expected.equalsIgnoreCase(actual);
    }
}
