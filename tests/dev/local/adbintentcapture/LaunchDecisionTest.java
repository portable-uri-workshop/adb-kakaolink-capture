package dev.local.adbintentcapture;

public final class LaunchDecisionTest {
    public static void main(String[] args) {
        assertTrue("exact target package", LaunchDecision.isKakaoTalkSend(
                "kakaolink", "send", "com.kakao.talk", null));
        assertTrue("explicit component package", LaunchDecision.isKakaoTalkSend(
                "KAKAOLINK", "SEND", null, "com.kakao.talk"));
        assertFalse("wrong scheme", LaunchDecision.isKakaoTalkSend(
                "https", "send", "com.kakao.talk", null));
        assertFalse("wrong host", LaunchDecision.isKakaoTalkSend(
                "kakaolink", "open", "com.kakao.talk", null));
        assertFalse("wrong target", LaunchDecision.isKakaoTalkSend(
                "kakaolink", "send", "example.target", "example.target"));
        assertFalse("missing values", LaunchDecision.isKakaoTalkSend(
                null, null, null, null));
        assertTrue("default observation allows", LaunchDecision.shouldAllowMatchedStart(false, true));
        assertFalse("opt-in blocking rejects queued capture",
                LaunchDecision.shouldAllowMatchedStart(true, true));
        assertTrue("queue pressure fails open",
                LaunchDecision.shouldAllowMatchedStart(true, false));
        System.out.println("LaunchDecisionTest passed");
    }

    private static void assertTrue(String label, boolean value) {
        if (!value) {
            throw new AssertionError(label + " should be true");
        }
    }

    private static void assertFalse(String label, boolean value) {
        if (value) {
            throw new AssertionError(label + " should be false");
        }
    }
}
