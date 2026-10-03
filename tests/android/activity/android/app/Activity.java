package android.app;

import android.content.ContentResolver;
import android.content.Intent;
import android.os.Bundle;
import android.view.KeyEvent;
import java.io.File;

// What MainActivity takes of Android's Activity (and Context): its
// intent, its cache, its content resolver
public class Activity {
    public static final String AUDIO_SERVICE = "audio";
    public static File cacheDir;
    // Set by the test before onCreate, as Android's attach() sets it
    private Intent intent;

    protected void onCreate(Bundle savedInstanceState) {}

    protected void onNewIntent(Intent intent) {}

    public Intent getIntent() {
        return intent;
    }

    public void setIntent(Intent intent) {
        this.intent = intent;
    }

    public File getCacheDir() {
        return cacheDir;
    }

    public ContentResolver getContentResolver() {
        return new ContentResolver();
    }

    public Object getSystemService(String name) {
        return null;
    }

    public boolean dispatchKeyEvent(KeyEvent event) {
        return false;
    }
}
