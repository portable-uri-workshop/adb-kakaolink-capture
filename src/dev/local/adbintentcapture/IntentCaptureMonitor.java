package dev.local.adbintentcapture;

import android.app.IActivityController;
import android.content.Intent;
import android.net.Uri;
import android.util.Base64;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;

/**
 * Shell-side, no-root ActivityController that reports KakaoLink data URIs.
 *
 * Matching records are queued from the Binder callback and encoded/written by
 * a dedicated thread. Queue pressure and oversized records always fail open.
 */
public final class IntentCaptureMonitor extends IActivityController.Stub {
    private static final String OUTPUT_PREFIX = "KAKAOLINK_CAPTURE\t";
    private static final int QUEUE_CAPACITY = 16;
    private static final int MAX_URI_UTF8_BYTES = 64 * 1024;
    private static final String[] STOP_RECORD = new String[0];
    private static final ArrayBlockingQueue<String[]> CAPTURES =
            new ArrayBlockingQueue<>(QUEUE_CAPACITY);

    private static Object activityManager;
    private static Method setActivityController;
    private static boolean blockLaunch;
    private static Thread writerThread;
    private static volatile boolean writerFailed;

    public static void main(String[] args) {
        blockLaunch = hasArgument(args, "--block-launch");
        IntentCaptureMonitor controller = new IntentCaptureMonitor();
        boolean registered = false;
        int exitCode = 0;

        try {
            writerThread = new Thread(new CaptureWriter(), "kakaolink-capture-writer");
            writerThread.setDaemon(true);
            writerThread.start();

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
            exitCode = 1;
        } finally {
            if (registered) {
                try {
                    setController(null);
                } catch (Throwable error) {
                    System.err.println("KAKAOLINK_MONITOR_UNREGISTER_ERROR\t"
                            + error.getClass().getName() + "\t" + safe(error.getMessage()));
                    System.err.flush();
                    exitCode = 1;
                }
            }
            stopWriter();
        }
        if (exitCode != 0) {
            System.exit(exitCode);
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
            if (rawUri.getBytes(StandardCharsets.UTF_8).length > MAX_URI_UTF8_BYTES
                    || writerFailed
                    || writerThread == null
                    || !writerThread.isAlive()) {
                return true;
            }
            String action = intent.getAction();
            String component = intent.getComponent() == null
                    ? ""
                    : intent.getComponent().flattenToShortString();

            boolean queued = CAPTURES.offer(new String[] {
                    rawUri, safe(action), safe(targetPackage), safe(component)
            });
            return LaunchDecision.shouldAllowMatchedStart(blockLaunch, queued);
        } catch (Throwable ignored) {
            // A callback failure must never break normal device navigation.
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

    private static void stopWriter() {
        if (writerThread == null) {
            return;
        }
        try {
            if (!CAPTURES.offer(STOP_RECORD, 1, TimeUnit.SECONDS)) {
                writerThread.interrupt();
            }
            writerThread.join(3000);
            if (writerThread.isAlive()) {
                writerThread.interrupt();
                writerThread.join(1000);
            }
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
        }
    }

    private static final class CaptureWriter implements Runnable {
        @Override
        public void run() {
            try {
                while (true) {
                    String[] record = CAPTURES.take();
                    if (record == STOP_RECORD) {
                        return;
                    }
                    String encodedUri = Base64.encodeToString(
                            record[0].getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
                    System.out.println(OUTPUT_PREFIX
                            + encodedUri + "\t"
                            + record[1] + "\t"
                            + record[2] + "\t"
                            + record[3]);
                    System.out.flush();
                }
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
            } catch (Throwable error) {
                writerFailed = true;
                System.err.println("KAKAOLINK_WRITER_ERROR\t"
                        + error.getClass().getName() + "\t" + safe(error.getMessage()));
                System.err.flush();
            }
        }
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
