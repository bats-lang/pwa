package com.getcapacitor;

import android.content.Intent;
import android.util.Log;
import android.webkit.WebView;

// Capacitor's Bridge, as far as intents go: onNewIntent hands the
// intent to each plugin (handleOnNewIntent), the App plugin's
// appUrlOpen among them, which passes a VIEW intent's address to the
// page. Logged, for the test to count what the plugins are given.
public class Bridge {
    private final WebView webView = new WebView();

    public WebView getWebView() {
        return webView;
    }

    public void onNewIntent(Intent intent) {
        if (Intent.ACTION_VIEW.equals(intent.getAction()) && intent.getData() != null)
            Log.i("Capacitor/AppPlugin", "appUrlOpen " + intent.getData());
    }
}
