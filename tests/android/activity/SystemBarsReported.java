package app;

import android.content.Intent;
import android.webkit.WebView;
import androidx.core.view.WindowInsetsCompat;
import java.util.List;

// The activity hands the page whether each system bar is shown, at each
// window insets dispatch (bats-lang/quire#314): to bridge's
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

    static String last(List<String> scripts) {
        return scripts.isEmpty() ? "" : scripts.get(scripts.size() - 1);
    }

    public static void main(String[] args) throws Exception {
        MainActivity activity = new MainActivity();
        activity.setIntent(new Intent(Intent.ACTION_MAIN));
        activity.onCreate(null);
        WebView view = activity.getBridge().getWebView();

        view.dispatchApplyWindowInsets(new WindowInsetsCompat(true, true));
        expect(last(view.scripts).equals(report(true, true)), "both bars shown: the page is told so: " + last(view.scripts));
        expect(view.insetsTaken == 1, "and the web view takes the insets itself");

        view.dispatchApplyWindowInsets(new WindowInsetsCompat(false, false));
        expect(last(view.scripts).equals(report(false, false)), "both hidden: the page is told so");

        // the system shows the bars again (a swipe from the edge)
        view.dispatchApplyWindowInsets(new WindowInsetsCompat(true, true));
        expect(last(view.scripts).equals(report(true, true)), "shown by the system: the page is told so");

        view.dispatchApplyWindowInsets(new WindowInsetsCompat(true, false));
        expect(last(view.scripts).equals(report(true, false)), "the status bar alone: the page is told so");
        expect(view.insetsTaken == 4, "and the web view took each dispatch's insets");

        // a page without bridge yet: the report is handed again until it
        // is taken, and the latest is the one handed
        view.answer = "null";
        int before = view.scripts.size();
        view.dispatchApplyWindowInsets(new WindowInsetsCompat(false, true));
        expect(view.scripts.size() - before > 1, "a page without the bridge is handed the report again");
        view.answer = "true";
        view.dispatchApplyWindowInsets(new WindowInsetsCompat(false, false));
        expect(last(view.scripts).equals(report(false, false)), "and once it has it, the next report is taken");

        System.exit(failures == 0 ? 0 : 1);
    }
}
