package android.net;

public class Uri {
    private final String text;

    private Uri(String text) {
        this.text = text;
    }

    public static Uri parse(String text) {
        return new Uri(text);
    }

    public String getScheme() {
        int colon = text.indexOf(':');
        return colon < 0 ? null : text.substring(0, colon);
    }

    public String getLastPathSegment() {
        return text.substring(text.lastIndexOf('/') + 1);
    }

    @Override
    public String toString() {
        return text;
    }
}
