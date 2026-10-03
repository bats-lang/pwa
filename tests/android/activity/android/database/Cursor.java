package android.database;

import java.io.Closeable;

public interface Cursor extends Closeable {
    boolean moveToFirst();

    int getColumnIndex(String column);

    String getString(int column);

    void close();
}
