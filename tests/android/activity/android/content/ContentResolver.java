package android.content;

import android.database.Cursor;
import android.net.Uri;
import java.io.ByteArrayInputStream;
import java.io.FileNotFoundException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

// Each content URI's bytes are its own text; no names
public class ContentResolver {
    public Cursor query(Uri uri, String[] projection, String selection, String[] arguments, String order) {
        return null;
    }

    public InputStream openInputStream(Uri uri) throws FileNotFoundException {
        return new ByteArrayInputStream(uri.toString().getBytes(StandardCharsets.UTF_8));
    }
}
