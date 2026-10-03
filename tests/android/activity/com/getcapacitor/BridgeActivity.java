package com.getcapacitor;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

// Capacitor 8's BridgeActivity, as far as intents go
// (android/capacitor/src/main/java/com/getcapacitor/BridgeActivity.java
// at 8.1.0): onCreate ends in load(), which hands the activity's intent
// to onNewIntent, recreated or not
public class BridgeActivity extends Activity {
    protected Bridge bridge;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        this.load();
    }

    protected void load() {
        bridge = new Bridge();
        this.onNewIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        if (this.bridge == null || intent == null) {
            return;
        }
        this.bridge.onNewIntent(intent);
    }
}
