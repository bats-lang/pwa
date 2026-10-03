package android.util;

import java.util.ArrayList;
import java.util.List;

// Keeps every line logged, for the test to count
public class Log {
    public static final List<String> lines = new ArrayList<>();

    public static synchronized int i(String tag, String message) {
        lines.add(message);
        return 0;
    }

    public static synchronized int w(String tag, String message) {
        lines.add(message);
        return 0;
    }

    public static synchronized int w(String tag, String message, Throwable error) {
        lines.add(message + ": " + error);
        return 0;
    }

    public static synchronized int count(String text) {
        int n = 0;
        for (String line : lines) if (line.contains(text)) n++;
        return n;
    }
}
