import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.util.zip.CRC32;
import java.util.zip.Deflater;

/**
 * 画默认图标：石板灰圆角方块上一个白色的“网页窗口”。全部由这段代码算出来，不用任何外来素材。
 * 用法：java tools/IconGen.java <res 目录>
 * 只在想换默认图标时才跑；画出来的 PNG 已经提交在 res/mipmap-*，build.sh 不会重画。
 */
public final class IconGen {
    private static final String[] DENSITY = {"mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"};
    private static final int[] SIZE = {48, 72, 96, 144, 192};
    private static final int SS = 8; // 每个像素取 8×8 个采样点做抗锯齿

    public static void main(String[] args) throws IOException {
        File res = new File(args[0]);
        for (int i = 0; i < SIZE.length; i++) {
            File dir = new File(res, "mipmap-" + DENSITY[i]);
            dir.mkdirs();
            Files.write(new File(dir, "ic_launcher.png").toPath(), png(SIZE[i]));
        }
    }

    /** 圆角矩形的“到边界的距离”：负数在里面。 */
    private static double roundRect(double x, double y, double x0, double y0, double x1, double y1, double r) {
        double cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
        double dx = Math.abs(x - cx) - ((x1 - x0) / 2 - r);
        double dy = Math.abs(y - cy) - ((y1 - y0) / 2 - r);
        double outside = Math.hypot(Math.max(dx, 0), Math.max(dy, 0));
        return outside + Math.min(Math.max(dx, dy), 0) - r;
    }

    /** 0＝透明，1＝底色，2＝白。坐标在 0..1。 */
    private static int shade(double x, double y) {
        if (roundRect(x, y, 0.04, 0.04, 0.96, 0.96, 0.21) > 0) {
            return 0;
        }
        double win = roundRect(x, y, 0.23, 0.28, 0.77, 0.72, 0.07);
        if (win > 0) {
            return 1;
        }
        boolean border = win > -0.05;
        boolean titleBar = y < 0.42;
        return border || titleBar ? 2 : 1;
    }

    private static byte[] png(int size) throws IOException {
        byte[] raw = new byte[size * (1 + size * 4)];
        int p = 0;
        for (int py = 0; py < size; py++) {
            raw[p++] = 0; // 每行不做滤波
            for (int px = 0; px < size; px++) {
                int base = 0, white = 0;
                for (int sy = 0; sy < SS; sy++) {
                    for (int sx = 0; sx < SS; sx++) {
                        int s = shade((px + (sx + 0.5) / SS) / size, (py + (sy + 0.5) / SS) / size);
                        if (s == 1) base++;
                        if (s == 2) white++;
                    }
                }
                int covered = base + white;
                int total = SS * SS;
                if (covered == 0) {
                    p += 4;
                    continue;
                }
                // 底色 #475569，白 #FFFFFF；颜色按覆盖比例混合，透明度按覆盖面积。
                raw[p++] = (byte) Math.round((0x47 * base + 255.0 * white) / covered);
                raw[p++] = (byte) Math.round((0x55 * base + 255.0 * white) / covered);
                raw[p++] = (byte) Math.round((0x69 * base + 255.0 * white) / covered);
                raw[p++] = (byte) Math.round(255.0 * covered / total);
            }
        }
        Deflater deflater = new Deflater(9);
        deflater.setInput(raw);
        deflater.finish();
        ByteArrayOutputStream idat = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        while (!deflater.finished()) {
            idat.write(buf, 0, deflater.deflate(buf));
        }
        deflater.end();

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.write(new byte[] {(byte) 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'});
        ByteArrayOutputStream ihdr = new ByteArrayOutputStream();
        DataOutputStream d = new DataOutputStream(ihdr);
        d.writeInt(size);
        d.writeInt(size);
        d.write(new byte[] {8, 6, 0, 0, 0}); // 8 位、RGBA、不隔行
        chunk(out, "IHDR", ihdr.toByteArray());
        chunk(out, "IDAT", idat.toByteArray());
        chunk(out, "IEND", new byte[0]);
        return out.toByteArray();
    }

    private static void chunk(ByteArrayOutputStream out, String type, byte[] data) throws IOException {
        DataOutputStream d = new DataOutputStream(out);
        d.writeInt(data.length);
        byte[] t = type.getBytes("US-ASCII");
        d.write(t);
        d.write(data);
        CRC32 crc = new CRC32();
        crc.update(t);
        crc.update(data);
        d.writeInt((int) crc.getValue());
    }
}
