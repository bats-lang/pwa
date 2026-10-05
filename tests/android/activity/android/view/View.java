package android.view;

import androidx.core.view.OnApplyWindowInsetsListener;
import androidx.core.view.WindowInsetsCompat;

// A view, as far as window insets go: dispatch hands them to the
// listener set on it, else to the view's own onApplyWindowInsets, as
// View.dispatchApplyWindowInsets does; the insets the view took itself
// are counted. The window's own insets (getRootWindowInsets) are set
// with each dispatch, apart from the insets the view is given, which a
// listener above it may have rewritten (Capacitor's SystemBars)
public class View {
    public OnApplyWindowInsetsListener insetsListener;
    public WindowInsetsCompat rootInsets;
    public int insetsTaken = 0;

    public WindowInsetsCompat onApplyWindowInsets(WindowInsetsCompat insets) {
        insetsTaken++;
        return insets;
    }

    public WindowInsetsCompat dispatchApplyWindowInsets(WindowInsetsCompat window, WindowInsetsCompat insets) {
        rootInsets = window;
        return insetsListener != null ? insetsListener.onApplyWindowInsets(this, insets) : onApplyWindowInsets(insets);
    }
}
