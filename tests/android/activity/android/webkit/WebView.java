package android.webkit;

import android.view.View;
import java.util.ArrayList;
import java.util.List;

// A page: every call answers answer, true once it has bridge's batsNative
// (null before, as an undefined call's answer reads); each script run is
// kept, for the test to read
public class WebView extends View {
    public String answer = "true";
    public final List<String> scripts = new ArrayList<>();

    public void evaluateJavascript(String script, ValueCallback<String> callback) {
        scripts.add(script);
        callback.onReceiveValue(answer);
    }
}
