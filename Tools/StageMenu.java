// StageDisc menu runtime. MIT license; see LICENSE in the source distribution.
import java.awt.*;
import java.awt.event.KeyEvent;
import java.io.InputStream;
import java.io.DataInputStream;
import java.io.ByteArrayInputStream;
import java.util.zip.InflaterInputStream;
import org.dvb.ui.DVBBufferedImage;
import java.io.ByteArrayOutputStream;
import java.util.Properties;
import java.util.Vector;
import javax.tv.xlet.Xlet;
import javax.tv.xlet.XletContext;
import javax.media.*;
import org.havi.ui.HScene;
import org.havi.ui.HSceneFactory;
import org.dvb.event.*;
import org.bluray.media.AudioControl;
import org.bluray.media.PlaybackControl;

public final class StageMenu extends Container implements Xlet, UserEventListener, ControllerListener {
    private HScene scene;
    private Player player;
    private Properties settings;
    private Image picture;
    private int page = 0, selection = 0;
    private boolean playing = false;
    private boolean alive = true;
    private double startSeconds = 0;
    private int currentPlaylist = 1;
    private boolean started = false;
    private final Vector actions = new Vector();
    private Thread menuThread;

    private void dispatch(Runnable action) {
        synchronized (actions) {
            if (alive) { actions.addElement(action); actions.notifyAll(); }
        }
    }
    private void startMenuThread() {
        // Created by initXlet, this worker inherits the application's BD-J
        // context. The global AWT event thread can lose that context when
        // decoding images after playback, even when image bytes are in memory.
        menuThread = new Thread(new Runnable() { public void run() {
            while (alive) {
                Runnable action;
                synchronized (actions) {
                    while (alive && actions.isEmpty()) {
                        try { actions.wait(); } catch (InterruptedException interrupted) { return; }
                    }
                    if (!alive) return;
                    action = (Runnable) actions.elementAt(0); actions.removeElementAt(0);
                }
                try { action.run(); } catch (Throwable error) { error.printStackTrace(); }
            }
        } }, "StageDisc menu actions");
        menuThread.start();
    }

    public void initXlet(XletContext context) {
        try {
            settings = new Properties();
            InputStream input = getClass().getResourceAsStream("/menu.properties");
            if (input == null) throw new Exception("Missing menu settings");
            settings.load(input); input.close();
            startMenuThread();
            scene = HSceneFactory.getInstance().getDefaultHScene();
            scene.setLayout(null);
            setBounds(0, 0, 1920, 1080);
            scene.add(this);
            UserEventRepository repository = new UserEventRepository("StageDisc menu");
            repository.addAllArrowKeys();
            repository.addKey(KeyEvent.VK_ENTER);
            repository.addKey(461); // VK_BACK_SPACE on BD remote
            repository.addKey(462); // menu
            repository.addKey(KeyEvent.VK_ESCAPE);
            int[] mediaKeys = {403, 404, 405, 406, 415, 19, 413, 424, 425};
            for (int i = 0; i < mediaKeys.length; i++) repository.addKey(mediaKeys[i]);
            EventManager.getInstance().addUserEventListener(this, repository);
            showMenu();
            System.out.println("StageDisc: menu initialised");
        } catch (Exception error) { error.printStackTrace(); }
    }
    public void startXlet() {
        if (scene != null) { scene.setVisible(true); requestFocus(); }
        if (!started && settings != null && "true".equals(settings.getProperty("album.autoplay"))) {
            started = true;
            new Thread(new Runnable() { public void run() { playTitle(1, 0); } }, "StageDisc album autoplay").start();
        }
    }
    public void pauseXlet() { if (player != null) player.stop(); }
    public void destroyXlet(boolean unconditional) {
        alive = false;
        synchronized (actions) { actions.removeAllElements(); actions.notifyAll(); }
        EventManager.getInstance().removeUserEventListener(this);
        closePlayer();
        if (picture != null) picture.flush();
        if (scene != null) { scene.remove(this); scene.setVisible(false); }
    }
    private int count() { return Integer.parseInt(settings.getProperty("page." + page + ".count", "1")); }
    private void closePlayer() {
        Player previous = player; player = null;
        if (previous != null) { previous.removeControllerListener(this); previous.stop(); previous.close(); }
    }
    private void showMenu() {
        closePlayer(); playing = false;
        if (scene != null) { scene.setVisible(true); setVisible(true); }
        loadPicture();
    }
    private void loadPicture() {
        try {
            InputStream source = getClass().getResourceAsStream("/page" + page + "-" + selection + ".png");
            if (source == null) throw new Exception("Menu picture missing");
            PNG decoded;
            try { decoded = decodePNG(source); } finally { source.close(); }
            DVBBufferedImage next = new DVBBufferedImage(decoded.width, decoded.height, DVBBufferedImage.TYPE_BASE);
            next.setRGB(0, 0, decoded.width, decoded.height, decoded.pixels, 0, decoded.width);
            Image previous = picture; picture = next;
            if (previous != null) previous.flush();
            repaint();
            System.out.println("StageDisc: menu page " + page + " selection " + selection);
        } catch (Exception error) { error.printStackTrace(); }
    }
    // MenuRenderer emits noninterlaced 8-bit RGB/RGBA PNGs. Decode synchronously
    // into the standard DVB image API, avoiding a player's asynchronous PNG
    // producer/MediaTracker race at startup or after a playlist ends.
    static final class PNG { int width, height; int[] pixels; }
    static PNG decodePNG(InputStream input) throws Exception {
        DataInputStream data = new DataInputStream(input);
        if (data.readLong() != 0x89504e470d0a1a0aL) throw new Exception("Invalid menu PNG");
        PNG image = new PNG(); int channels = 0;
        ByteArrayOutputStream compressed = new ByteArrayOutputStream();
        while (true) {
            int length = data.readInt(), type = data.readInt();
            if (length < 0 || length > 32000000) throw new Exception("Invalid PNG chunk size");
            byte[] chunk = new byte[length]; data.readFully(chunk); data.readInt();
            if (type == 0x49484452) {
                if (length != 13) throw new Exception("Invalid PNG header");
                DataInputStream header = new DataInputStream(new ByteArrayInputStream(chunk));
                image.width = header.readInt(); image.height = header.readInt();
                int depth = header.readUnsignedByte(), colour = header.readUnsignedByte();
                if (image.width < 1 || image.width > 1920 || image.height < 1 || image.height > 1080 || depth != 8 || (colour != 2 && colour != 6) || header.readUnsignedByte() != 0 || header.readUnsignedByte() != 0 || header.readUnsignedByte() != 0)
                    throw new Exception("Unsupported menu PNG format");
                channels = colour == 6 ? 4 : 3;
            } else if (type == 0x49444154) {
                if (compressed.size() + length > 32000000) throw new Exception("Menu PNG too large");
                compressed.write(chunk);
            } else if (type == 0x49454e44) break;
        }
        if (channels == 0) throw new Exception("Missing PNG header");
        DataInputStream pixels = new DataInputStream(new InflaterInputStream(new ByteArrayInputStream(compressed.toByteArray())));
        image.pixels = new int[image.width * image.height];
        byte[] previous = new byte[image.width * channels], row = new byte[previous.length];
        try {
            for (int y = 0; y < image.height; y++) {
                int filter = pixels.readUnsignedByte(); pixels.readFully(row);
                if (filter > 4) throw new Exception("Invalid PNG filter");
                for (int i = 0; i < row.length; i++) {
                    int left = i >= channels ? row[i - channels] & 255 : 0;
                    int up = previous[i] & 255, corner = i >= channels ? previous[i - channels] & 255 : 0;
                    int prediction = filter == 1 ? left : filter == 2 ? up : filter == 3 ? (left + up) / 2 : filter == 4 ? paeth(left, up, corner) : 0;
                    row[i] = (byte)((row[i] & 255) + prediction);
                }
                for (int x = 0; x < image.width; x++) {
                    int i = x * channels, alpha = channels == 4 ? row[i + 3] & 255 : 255;
                    image.pixels[y * image.width + x] = (alpha << 24) | ((row[i] & 255) << 16) | ((row[i + 1] & 255) << 8) | (row[i + 2] & 255);
                }
                byte[] swap = previous; previous = row; row = swap;
            }
            if (pixels.read() != -1) throw new Exception("Unexpected PNG pixel data");
        } finally { pixels.close(); }
        return image;
    }
    private static int paeth(int a, int b, int c) {
        int value = a + b - c, da = Math.abs(value - a), db = Math.abs(value - b), dc = Math.abs(value - c);
        return da <= db && da <= dc ? a : db <= dc ? b : c;
    }
    public void paint(Graphics graphics) { if (!playing && picture != null) graphics.drawImage(picture, 0, 0, 1920, 1080, this); }
    public void update(Graphics graphics) { paint(graphics); }
    public void userEventReceived(UserEvent event) {
        if (event.getType() != KeyEvent.KEY_PRESSED || !alive) return;
        final int key = event.getCode();
        // Keep BD event delivery free while the application worker switches pages.
        dispatch(new Runnable() { public void run() { handleKey(key); } });
    }
    private void handleKey(int key) {
        if (key == 461 || key == 462 || key == KeyEvent.VK_ESCAPE) { page = 0; selection = 0; showMenu(); return; }
        if (playing) {
            try {
                if (key >= 403 && key <= 406) { selectAudio(key - 402); }
                else if (key == 415 && player != null) player.start();
                else if (key == 19 && player != null) player.stop();
                else if (key == 413) showMenu();
                else if ((key == 424 || key == 425) && player != null) {
                    PlaybackControl control = (PlaybackControl) player.getControl("org.bluray.media.PlaybackControl");
                    if (control != null) {
                        if (key == 424) control.skipToNextMark(PlaybackControl.ENTRYMARK);
                        else control.skipToPreviousMark(PlaybackControl.ENTRYMARK);
                    }
                }
            } catch (Exception error) { error.printStackTrace(); }
            return;
        }
        if (key == KeyEvent.VK_UP || key == KeyEvent.VK_LEFT) { selection = (selection + count() - 1) % count(); loadPicture(); }
        else if (key == KeyEvent.VK_DOWN || key == KeyEvent.VK_RIGHT) { selection = (selection + 1) % count(); loadPicture(); }
        else if (key == KeyEvent.VK_ENTER) {
            String action = settings.getProperty("page." + page + ".button." + selection);
            if (action == null) return;
            if (action.startsWith("page:")) { page = Integer.parseInt(action.substring(5)); selection = 0; loadPicture(); }
            else if (action.startsWith("audio:")) {
                int split = action.indexOf(':', 6);
                settings.setProperty("mix." + action.substring(6, split), action.substring(split + 1));
                page = 0; selection = 0; loadPicture();
            }
            else if (action.startsWith("play:")) {
                int split = action.indexOf(':', 5);
                final int playlist = Integer.parseInt(action.substring(5, split));
                final double seconds = Double.parseDouble(action.substring(split + 1));
                new Thread(new Runnable() { public void run() { playTitle(playlist, seconds); } }, "StageDisc playback").start();
            }
        }
    }
    private synchronized void playTitle(int playlist, double seconds) {
        try {
            closePlayer(); playing = true;
            setVisible(false); scene.setVisible(false);
            String number = String.valueOf(playlist); while (number.length() < 5) number = "0" + number;
            startSeconds = seconds;
            currentPlaylist = playlist;
            player = Manager.createPlayer(new MediaLocator("bd://0.PLAYLIST:" + number));
            player.addControllerListener(this);
            player.realize();
        } catch (Exception error) {
            error.printStackTrace();
            dispatch(new Runnable() { public void run() { showMenu(); } });
        }
    }
    public void controllerUpdate(ControllerEvent event) {
        if (event.getSourceController() != player) return;
        if (event instanceof RealizeCompleteEvent) {
            if (startSeconds > 0) player.setMediaTime(new Time(startSeconds));
            player.start();
        }
        if (event instanceof PrefetchCompleteEvent || event instanceof StartEvent) {
            try { selectAudio(Integer.parseInt(settings.getProperty("mix." + currentPlaylist, "1"))); }
            catch (Exception error) { error.printStackTrace(); }
        }
        if (event instanceof EndOfMediaEvent || event instanceof ControllerErrorEvent) {
            final Controller finished = event.getSourceController();
            dispatch(new Runnable() { public void run() { if (alive && finished == player) showMenu(); } });
        }
    }
    private void selectAudio(int slot) throws Exception {
        if (player == null) return;
        AudioControl control = (AudioControl) player.getControl("org.bluray.media.AudioControl");
        if (control == null) return;
        int[] numbers = control.listAvailableStreamNumbers();
        if (slot < 1 || slot > numbers.length) return;
        control.selectStreamNumber(numbers[slot - 1]);
        settings.setProperty("mix." + currentPlaylist, String.valueOf(slot));
        System.out.println("StageDisc: selected mix " + slot + " for playlist " + currentPlaylist);
    }
}
