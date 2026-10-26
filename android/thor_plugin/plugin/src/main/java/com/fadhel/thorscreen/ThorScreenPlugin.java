package com.fadhel.thorscreen;

import android.app.Activity;
import android.app.Presentation;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Point;
import android.graphics.Rect;
import android.hardware.display.DisplayManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Display;
import android.view.MotionEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.nio.ByteBuffer;
import java.util.HashSet;
import java.util.Set;

/**
 * ThorScreen: shows frames rendered by Godot on a secondary display (the AYN Thor's bottom screen)
 * using android.app.Presentation, and reports touches on that display back to Godot.
 *
 * GDScript side (res://scripts/ui/bottom_screen.gd):
 *   var ts = Engine.get_singleton("ThorScreen")
 *   ts.displayCount()                 -> int    (1 on ordinary phones)
 *   ts.secondaryDisplaySize()         -> PackedInt32Array [w, h] ([0, 0] if none)
 *   ts.start()                        -> bool   (shows the Presentation; false if there's no second display)
 *   ts.stop()
 *   ts.isShowing()                    -> bool
 *   ts.pushFrame(rgba: PackedByteArray, w, h)   (RGBA8, w*h*4 bytes; drawn scaled to fit, nearest-neighbour)
 * Signals:
 *   touch(x: int, y: int, pressed: bool)   in frame pixels
 *   drag(x: int, y: int)                   in frame pixels, while a finger is down
 *   display_changed(count: int)            a display was connected / removed
 */
public class ThorScreenPlugin extends GodotPlugin {
    private static final String TAG = "ThorScreen";

    private final Object frameLock = new Object();
    private Bitmap frame;              // guarded by frameLock
    private int frameW = 0, frameH = 0;

    private DisplayManager displayManager;
    private DisplayManager.DisplayListener displayListener;
    private Presentation presentation; // UI thread only
    private FrameView frameView;       // UI thread only
    private volatile boolean wanted = false;
    private volatile boolean showing = false;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    public ThorScreenPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "ThorScreen";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> s = new HashSet<>();
        s.add(new SignalInfo("touch", Integer.class, Integer.class, Boolean.class));
        s.add(new SignalInfo("drag", Integer.class, Integer.class));
        s.add(new SignalInfo("display_changed", Integer.class));
        return s;
    }

    // ------------------------------------------------------------------ displays
    private DisplayManager dm() {
        if (displayManager == null) {
            Activity a = getActivity();
            if (a == null) return null;
            displayManager = (DisplayManager) a.getSystemService(Context.DISPLAY_SERVICE);
            if (displayManager != null && displayListener == null) {
                displayListener = new DisplayManager.DisplayListener() {
                    @Override public void onDisplayAdded(int displayId) { onDisplaysChanged(); }
                    @Override public void onDisplayRemoved(int displayId) { onDisplaysChanged(); }
                    @Override public void onDisplayChanged(int displayId) { }
                };
                displayManager.registerDisplayListener(displayListener, mainHandler);
            }
        }
        return displayManager;
    }

    /** First non-default display; prefers ones flagged for presentations. */
    private Display secondaryDisplay() {
        DisplayManager m = dm();
        if (m == null) return null;
        for (Display d : m.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)) {
            if (d.getDisplayId() != Display.DEFAULT_DISPLAY) return d;
        }
        for (Display d : m.getDisplays()) {
            if (d.getDisplayId() != Display.DEFAULT_DISPLAY) return d;
        }
        return null;
    }

    private void onDisplaysChanged() {
        Display d = secondaryDisplay();
        if (presentation != null && (d == null || presentation.getDisplay().getDisplayId() != d.getDisplayId())) {
            dismiss();
        }
        if (wanted && presentation == null && d != null) {
            show();
        }
        DisplayManager m = dm();
        emitSignal("display_changed", m == null ? 1 : m.getDisplays().length);
    }

    @UsedByGodot
    public int displayCount() {
        try {
            DisplayManager m = dm();
            return m == null ? 1 : m.getDisplays().length;
        } catch (Throwable t) {
            Log.w(TAG, "displayCount failed", t);
            return 1;
        }
    }

    @UsedByGodot
    public int[] secondaryDisplaySize() {
        try {
            Display d = secondaryDisplay();
            if (d == null) return new int[] {0, 0};
            Point p = new Point();
            d.getRealSize(p);
            return new int[] {p.x, p.y};
        } catch (Throwable t) {
            Log.w(TAG, "secondaryDisplaySize failed", t);
            return new int[] {0, 0};
        }
    }

    // ------------------------------------------------------------------ presentation
    @UsedByGodot
    public boolean start() {
        if (secondaryDisplay() == null) return false;
        wanted = true;
        mainHandler.post(this::show);
        return true;
    }

    @UsedByGodot
    public void stop() {
        wanted = false;
        mainHandler.post(this::dismiss);
    }

    @UsedByGodot
    public boolean isShowing() {
        return showing;
    }

    private void show() {
        if (presentation != null || !wanted) return;
        Activity a = getActivity();
        Display d = secondaryDisplay();
        if (a == null || d == null || a.isFinishing()) return;
        try {
            frameView = new FrameView(a);
            Presentation p = new Presentation(a, d);
            p.setContentView(frameView);
            p.setCancelable(false);
            Window w = p.getWindow();
            if (w != null) {
                // Don't take input focus: the pad / keys must keep going to the game on the main screen.
                // Touches are still delivered to a non-focusable window.
                w.addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                        | WindowManager.LayoutParams.FLAG_FULLSCREEN);
                w.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
            }
            p.setOnDismissListener(dialog -> {
                if (presentation == dialog) {
                    presentation = null;
                    frameView = null;
                    showing = false;
                }
            });
            p.show();
            presentation = p;
            showing = true;
        } catch (Throwable t) {      // WindowManager.InvalidDisplayException, BadTokenException, ...
            Log.w(TAG, "Couldn't show the presentation", t);
            presentation = null;
            frameView = null;
            showing = false;
        }
    }

    private void dismiss() {
        Presentation p = presentation;
        presentation = null;
        frameView = null;
        showing = false;
        if (p != null) {
            try {
                p.dismiss();
            } catch (Throwable t) {
                Log.w(TAG, "dismiss failed", t);
            }
        }
    }

    // ------------------------------------------------------------------ frames
    /** Called from Godot's thread with RGBA8 pixels (w*h*4 bytes). */
    @UsedByGodot
    public void pushFrame(byte[] rgba, int w, int h) {
        if (rgba == null || w <= 0 || h <= 0 || rgba.length < w * h * 4) return;
        synchronized (frameLock) {
            if (frame == null || frameW != w || frameH != h) {
                frame = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
                frameW = w;
                frameH = h;
            }
            // ARGB_8888 is stored as R,G,B,A bytes in memory: the same layout as Godot's FORMAT_RGBA8.
            frame.copyPixelsFromBuffer(ByteBuffer.wrap(rgba, 0, w * h * 4));
        }
        FrameView v = frameView;
        if (v != null) v.postInvalidate();
    }

    // ------------------------------------------------------------------ lifecycle
    @Override
    public void onMainPause() {
        super.onMainPause();
        mainHandler.post(() -> {
            boolean keep = wanted;
            dismiss();
            wanted = keep;
        });
    }

    @Override
    public void onMainResume() {
        super.onMainResume();
        mainHandler.post(() -> {
            if (wanted) show();
        });
    }

    @Override
    public void onMainDestroy() {
        wanted = false;
        mainHandler.post(() -> {
            dismiss();
            if (displayManager != null && displayListener != null) {
                displayManager.unregisterDisplayListener(displayListener);
            }
            displayListener = null;
            displayManager = null;
        });
        super.onMainDestroy();
    }

    // ------------------------------------------------------------------ view
    /** Draws the latest frame scaled to fit (integer scale when possible) and reports touches. */
    private class FrameView extends View {
        private final Paint paint = new Paint();
        private final Rect src = new Rect();
        private final Rect dst = new Rect();
        private boolean down = false;

        FrameView(Context c) {
            super(c);
            paint.setFilterBitmap(false);
            paint.setAntiAlias(false);
            setBackgroundColor(Color.BLACK);
        }

        private void layoutDst(int fw, int fh) {
            int vw = getWidth(), vh = getHeight();
            if (fw <= 0 || fh <= 0 || vw <= 0 || vh <= 0) {
                dst.set(0, 0, 0, 0);
                return;
            }
            float sc = Math.min(vw / (float) fw, vh / (float) fh);
            if (sc >= 1f) {
                float isc = (float) Math.floor(sc);
                if (isc >= 1f && sc - isc < 0.08f) sc = isc;   // nearly integer: keep pixels even
            }
            int dw = Math.round(fw * sc), dh = Math.round(fh * sc);
            int x = (vw - dw) / 2, y = (vh - dh) / 2;
            dst.set(x, y, x + dw, y + dh);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            synchronized (frameLock) {
                if (frame == null) return;
                layoutDst(frameW, frameH);
                src.set(0, 0, frameW, frameH);
                canvas.drawBitmap(frame, src, dst, paint);
            }
        }

        @Override
        public boolean onTouchEvent(MotionEvent e) {
            int fw, fh;
            synchronized (frameLock) {
                fw = frameW;
                fh = frameH;
            }
            layoutDst(fw, fh);
            if (dst.width() <= 0 || dst.height() <= 0) return true;
            int x = Math.round((e.getX() - dst.left) * fw / (float) dst.width());
            int y = Math.round((e.getY() - dst.top) * fh / (float) dst.height());
            x = Math.max(0, Math.min(fw - 1, x));
            y = Math.max(0, Math.min(fh - 1, y));
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    down = true;
                    emitSignal("touch", x, y, true);
                    break;
                case MotionEvent.ACTION_MOVE:
                    if (down) emitSignal("drag", x, y);
                    break;
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    if (down) emitSignal("touch", x, y, false);
                    down = false;
                    break;
                default:
                    break;
            }
            return true;
        }
    }
}
