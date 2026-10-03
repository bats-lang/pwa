package android.content;

import android.net.Uri;
import java.util.ArrayList;

public class Intent {
    public static final String ACTION_MAIN = "android.intent.action.MAIN";
    public static final String ACTION_VIEW = "android.intent.action.VIEW";
    public static final String ACTION_SEND = "android.intent.action.SEND";
    public static final String ACTION_SEND_MULTIPLE = "android.intent.action.SEND_MULTIPLE";
    public static final String EXTRA_STREAM = "android.intent.extra.STREAM";
    public static final int FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY = 0x00100000;

    private final String action;
    private Uri data;
    private Object stream;
    private int flags;

    public Intent(String action) {
        this.action = action;
    }

    public String getAction() {
        return action;
    }

    public Intent setData(Uri data) {
        this.data = data;
        return this;
    }

    public Uri getData() {
        return data;
    }

    public Intent putExtra(String name, Object value) {
        stream = value;
        return this;
    }

    public Object getParcelableExtra(String name) {
        return stream;
    }

    @SuppressWarnings("unchecked")
    public <T> ArrayList<T> getParcelableArrayListExtra(String name) {
        return (ArrayList<T>) stream;
    }

    public Intent addFlags(int flags) {
        this.flags |= flags;
        return this;
    }

    public int getFlags() {
        return flags;
    }
}
