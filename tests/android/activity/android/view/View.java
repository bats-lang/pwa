package android.view;

import androidx.core.view.OnApplyWindowInsetsListener;
import androidx.core.view.WindowInsetsCompat;

// A view, as far as window insets go: dispatch hands them to the
// listener set on it, else to the view's own onApplyWindowInsets, as
// View.dispatchApplyWindowInsets does; the insets the view took itself
// are counted
public class View {
    public OnApplyWindowInsetsListener insetsListener;
    public int insetsTaken = 0;

    public WindowInsetsCompat onApplyWindowInsets(WindowInsetsCompat insets) {
        insetsTaken++;
        return insets;
    }

    public WindowInsetsCompat dispatchApplyWindowInsets(WindowInsetsCompat insets) {
        return insetsListener != null ? insetsListener.onApplyWindowInsets(this, insets) : onApplyWindowInsets(insets);
    }
}
