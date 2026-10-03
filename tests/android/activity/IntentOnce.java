package app;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;
import java.io.File;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;

// The activity hands each intent's files to the page once
// (bats-lang/quire#247): as it starts, not again when it is recreated
// or started from the recent apps with the same intent, and once for
// each intent while it is open. Run by tests/android/activity.sh on
// the MainActivity.java pwa writes, against Capacitor's BridgeActivity.
public class IntentOnce {
    static int failures = 0;

    static void expect(boolean holds, String what) {
        System.out.println((holds ? "ok   " : "FAIL ") + what);
        if (!holds) failures++;
    }

    static final String HANDED = "handed to the page";

    // Waits up to five seconds for count hand-overs since since, then
    // half a second for any more; the hand-overs since since
    static int handedSince(int since, int count) throws InterruptedException {
        for (int i = 0; i < 100 && Log.count(HANDED) - since < count; i++) Thread.sleep(50);
        Thread.sleep(500);
        return Log.count(HANDED) - since;
    }

    static Intent view(String uri) {
        return new Intent(Intent.ACTION_VIEW).setData(Uri.parse(uri));
    }

    static MainActivity create(Intent intent, Bundle saved) {
        MainActivity activity = new MainActivity();
        activity.setIntent(intent);
        activity.onCreate(saved);
        return activity;
    }

    static String[] incoming() {
        String[] names = new File(Activity.cacheDir, "incoming").list();
        return names == null ? new String[0] : names;
    }

    public static void main(String[] args) throws Exception {
        Activity.cacheDir = Files.createTempDirectory("activity").toFile();
        File stale = new File(new File(Activity.cacheDir, "incoming"), "file-of-an-earlier-run.bin");
        stale.getParentFile().mkdirs();
        Files.write(stale.toPath(), new byte[] {1});

        int before = Log.count(HANDED);
        MainActivity first = create(view("content://books/first.epub"), null);
        expect(handedSince(before, 1) == 1, "started with a file, it hands it to the page once");
        String[] copies = incoming();
        expect(copies.length == 1 && !stale.exists(), "and keeps that one copy, an earlier run's gone: " + Arrays.toString(copies));
        expect(copies.length == 1
            && new String(Files.readAllBytes(new File(new File(Activity.cacheDir, "incoming"), copies[0]).toPath()))
                .equals("content://books/first.epub"),
            "the copy holds the file");

        before = Log.count(HANDED);
        create(first.getIntent(), new Bundle());
        expect(handedSince(before, 0) == 0, "recreated, it hands nothing again");
        expect(incoming().length == 1, "and keeps the copy it made");

        before = Log.count(HANDED);
        first.onNewIntent(view("content://books/second.epub"));
        expect(handedSince(before, 1) == 1, "opened with a file while open, it hands it over once");
        before = Log.count(HANDED);
        create(first.getIntent(), new Bundle());
        expect(handedSince(before, 0) == 0, "recreated after that, it hands nothing again");

        before = Log.count(HANDED);
        Intent share = new Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, Uri.parse("content://books/third.epub"));
        first.onNewIntent(share);
        expect(handedSince(before, 1) == 1, "shared a file while open, it hands it over once");

        before = Log.count(HANDED);
        Intent recent = view("content://books/first.epub").addFlags(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY);
        create(recent, null);
        expect(handedSince(before, 0) == 0, "started from the recent apps with its first intent, it hands nothing");
        expect(incoming().length == 0, "and the earlier run's copies are gone");

        before = Log.count(HANDED);
        ArrayList<Uri> two = new ArrayList<>(Arrays.asList(Uri.parse("content://books/a.epub"), Uri.parse("content://books/b.epub")));
        create(new Intent(Intent.ACTION_SEND_MULTIPLE).putExtra(Intent.EXTRA_STREAM, two), null);
        expect(handedSince(before, 2) == 2, "started with two files shared, it hands each over once");

        before = Log.count(HANDED);
        create(new Intent(Intent.ACTION_MAIN), null);
        expect(handedSince(before, 0) == 0, "started from the launcher, it hands nothing");

        System.exit(failures == 0 ? 0 : 1);
    }
}
