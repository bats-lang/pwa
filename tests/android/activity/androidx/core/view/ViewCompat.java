package androidx.core.view;

import android.view.View;

// androidx's ViewCompat, as far as window insets go
public class ViewCompat {
    public static void setOnApplyWindowInsetsListener(View view, OnApplyWindowInsetsListener listener) {
        view.insetsListener = listener;
    }

    public static WindowInsetsCompat onApplyWindowInsets(View view, WindowInsetsCompat insets) {
        return view.onApplyWindowInsets(insets);
    }
}
