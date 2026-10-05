package app;

import android.content.Intent;
import android.webkit.WebView;
import androidx.core.view.WindowInsetsCompat;
import java.util.List;

// The activity hands the page whether each system bar is shown, at each
// window insets dispatch (bats-lang/quire#314), as the window's own
// insets have them (not the insets the web view is given, which
// Capacitor's SystemBars rewrites, below API 30 to none): to bridge's
// batsNative.systemBars, the latest once the page has it, and the web
// view still takes the insets itself. Run by tests/android/activity.sh
// on the MainActivity.java pwa writes, against Capacitor's
// BridgeActivity.
public class SystemBarsReported {
    static int failures = 0;

    static void expect(boolean holds, String what) {
        System.out.println((holds ? "ok   " : "FAIL ") + what);
        if (!holds) failures++;
    }

    static String report(boolean status, boolean navigation) {
        return "(globalThis.batsNative && globalThis.batsNative.systemBars ? globalThis.batsNative.systemBars("
            + status + "," + navigation + ") : false)";
    }

    // A dispatch: the window's own insets, and those the web view is
    // given, rewritten to none above it as Capacitor's SystemBars does
    static void dispatch(WebView view, boolean status, boolean navigation) {
        view.dispatchApplyWindowInsets(new WindowInsetsCompat(status, navigation), new WindowInsetsCompat(false, false));
    }

    static String last(List<String> scripts) {
        return scripts.isEmpty() ? "" : scripts.get(scripts.size() - 1);
    }

    public static void main(String[] args) throws Exception {
        MainActivity activity = new MainActivity();
        activity.setIntent(new Intent(Intent.ACTION_MAIN));
        activity.onCreate(null);
        WebView view = activity.getBridge().getWebView();

        dispatch(view, true, true);
        expect(last(view.scripts).equals(report(true, true)), "both bars shown in the window: the page is told so, whatever the web view is given: " + last(view.scripts));
        expect(view.insetsTaken == 1, "and the web view takes the insets itself");

        dispatch(view, false, false);
        expect(last(view.scripts).equals(report(false, false)), "both hidden: the page is told so");

        // the system shows the bars again (a swipe from the edge)
        dispatch(view, true, true);
        expect(last(view.scripts).equals(report(true, true)), "shown by the system: the page is told so");

        dispatch(view, true, false);
        expect(last(view.scripts).equals(report(true, false)), "the status bar alone: the page is told so");
        expect(view.insetsTaken == 4, "and the web view took each dispatch's insets");

        // a page without bridge yet: the report is handed again until it
        // is taken, and the latest is the one handed
        view.answer = "null";
        int before = view.scripts.size();
        dispatch(view, false, true);
        expect(view.scripts.size() - before > 1, "a page without the bridge is handed the report again");
        view.answer = "true";
        dispatch(view, false, false);
        expect(last(view.scripts).equals(report(false, false)), "and once it has it, the next report is taken");

        System.exit(failures == 0 ? 0 : 1);
    }
}
