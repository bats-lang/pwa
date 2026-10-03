package android.media;

public class AudioManager {
    public static final int ADJUST_RAISE = 1;
    public static final int ADJUST_LOWER = -1;
    public static final int USE_DEFAULT_STREAM_TYPE = Integer.MIN_VALUE;
    public static final int FLAG_SHOW_UI = 1;

    public void adjustSuggestedStreamVolume(int direction, int stream, int flags) {}
}
