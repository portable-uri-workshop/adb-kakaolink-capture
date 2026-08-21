package dev.local.adbintentcapture;

import android.app.IActivityController;
import android.content.Intent;
import android.net.Uri;
import android.util.Base64;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;

/**
 * Shell-side, no-root ActivityController that reports KakaoLink data URIs.
 *
 * The controller never blocks an activity start: every callback returns the
 * platform's normal/continue result. Raw URIs are emitted only to stdout as
 * Base64 so that the PC wrapper can copy them without shell quoting damage.
 */
public final class IntentCaptureMonitor extends IActivityController.Stub {
    private static final String OUTPUT_PREFIX = "KAKAOLINK_CAPTURE\t";

    private static Object activityManager;
    private static Method setActivityController;
    private static boolean blockLaunch;

    public static void main(String[] args) {
        blockLaunch = hasArgument(args, "--block-launch");
        IntentCaptureMonitor controller = new IntentCaptureMonitor();
        boolean registered = false;

        try {
            activityManager = getActivityManagerService();
            setActivityController = findSetActivityController();
            setController(controller);
            registered = true;

            System.out.println("KAKAOLINK_MONITOR_READY");
            System.out.flush();

            BufferedReader input = new BufferedReader(
                    new InputStreamReader(System.in, StandardCharsets.UTF_8));
            String line;
            while ((line = input.readLine()) != null) {
                String command = line.trim();
                if ("q".equalsIgnoreCase(command)
                        || "quit".equalsIgnoreCase(command)
                        || "exit".equalsIgnoreCase(command)) {
                    break;
                }
            }
        } catch (Throwable error) {
            System.err.println("KAKAOLINK_MONITOR_ERROR\t"
                    + error.getClass().getName() + "\t" + safe(error.getMessage()));
            error.printStackTrace(System.err);
            System.err.flush();
            System.exit(1);
        } finally {
            if (registered) {
                try {
                    setController(null);
                } catch (Throwable error) {
                    System.err.println("KAKAOLINK_MONITOR_UNREGISTER_ERROR\t"
                            + error.getClass().getName() + "\t" + safe(error.getMessage()));
                    System.err.flush();
                }
            }
        }
    }

    @Override
    public boolean activityStarting(Intent intent, String targetPackage) {
        try {
            Uri data = intent == null ? null : intent.getData();
            String componentPackage = intent == null || intent.getComponent() == null
                    ? null
                    : intent.getComponent().getPackageName();
            if (data == null || !LaunchDecision.isKakaoTalkSend(
                    data.getScheme(), data.getHost(), targetPackage, componentPackage)) {
                return true;
            }

            String rawUri = data.toString();
            String encodedUri = Base64.encodeToString(
                    rawUri.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
            String action = intent.getAction();
            String component = intent.getComponent() == null
                    ? ""
                    : intent.getComponent().flattenToShortString();

            System.out.println(OUTPUT_PREFIX
                    + encodedUri + "\t"
                    + safe(action) + "\t"
                    + safe(targetPackage) + "\t"
                    + safe(component));
            System.out.flush();
            return LaunchDecision.shouldAllowMatchedStart(blockLaunch);
        } catch (Throwable error) {
            System.err.println("KAKAOLINK_CAPTURE_ERROR\t"
                    + error.getClass().getName() + "\t" + safe(error.getMessage()));
            System.err.flush();
            // A monitor failure must never break normal device navigation.
            return true;
        }
    }

    @Override
    public boolean activityResuming(String pkg) {
        return true;
    }

    @Override
    public boolean appCrashed(
            String processName,
            int pid,
            String shortMsg,
            String longMsg,
            long timeMillis,
            String stackTrace) {
        return true;
    }

    @Override
    public int appEarlyNotResponding(String processName, int pid, String annotation) {
        return 0;
    }

    @Override
    public int appNotResponding(String processName, int pid, String processStats) {
        return 0;
    }

    @Override
    public int systemNotResponding(String message) {
        return -1;
    }

    private static Object getActivityManagerService() throws Exception {
        Class<?> activityManagerClass = Class.forName("android.app.ActivityManager");
        Method getService = activityManagerClass.getDeclaredMethod("getService");
        getService.setAccessible(true);
        return getService.invoke(null);
    }

    private static Method findSetActivityController() throws Exception {
        Class<?> interfaceClass = Class.forName("android.app.IActivityManager");
        Class<?> controllerClass = Class.forName("android.app.IActivityController");
        Method method = interfaceClass.getMethod(
                "setActivityController", controllerClass, boolean.class);
        method.setAccessible(true);
        return method;
    }

    private static void setController(IActivityController controller) throws Exception {
        setActivityController.invoke(activityManager, controller, false);
    }

    private static String safe(String value) {
        if (value == null) {
            return "";
        }
        return value.replace('\t', ' ').replace('\r', ' ').replace('\n', ' ');
    }

    private static boolean hasArgument(String[] args, String expected) {
        if (args == null) {
            return false;
        }
        for (String argument : args) {
            if (expected.equalsIgnoreCase(argument)) {
                return true;
            }
        }
        return false;
    }
}
