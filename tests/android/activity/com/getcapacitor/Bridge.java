package com.getcapacitor;

import android.content.Intent;
import android.webkit.WebView;

public class Bridge {
    private final WebView webView = new WebView();

    public WebView getWebView() {
        return webView;
    }

    public void onNewIntent(Intent intent) {}
}
