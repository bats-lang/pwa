package androidx.core.view;

// Window insets, as far as the system bars' visibility goes: isVisible
// is true when every type of the mask is shown, as Android's is
public class WindowInsetsCompat {
    public static final class Type {
        public static int statusBars() { return 1; }
        public static int navigationBars() { return 2; }
        public static int systemBars() { return 3; }
    }

    private final int shown;

    public WindowInsetsCompat(boolean status, boolean navigation) {
        shown = (status ? 1 : 0) | (navigation ? 2 : 0);
    }

    public boolean isVisible(int mask) {
        return (shown & mask) == mask;
    }
}
