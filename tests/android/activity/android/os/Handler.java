package android.os;

// Runs what is posted at once, on the poster's thread
public class Handler {
    public Handler(Looper looper) {}

    public boolean post(Runnable runnable) {
        runnable.run();
        return true;
    }

    public boolean postDelayed(Runnable runnable, long delay) {
        runnable.run();
        return true;
    }
}
