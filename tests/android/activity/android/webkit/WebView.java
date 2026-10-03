package android.webkit;

// A page that has bridge's batsNative: every call answers true
public class WebView {
    public void evaluateJavascript(String script, ValueCallback<String> callback) {
        callback.onReceiveValue("true");
    }
}
