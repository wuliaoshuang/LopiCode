import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Enumeration;
import java.util.List;
import java.util.zip.CRC32;
import java.util.zip.Deflater;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * 把 aapt2 link 的产物和 classes.dex 重新装成一个“每次都一模一样”的 ZIP：
 * 条目顺序固定、时间戳固定（1981-01-01 01:01:02）、不带任何附加字段、不带数据描述符。
 * 清单和 dex 压缩（DEFLATE 9 级）；resources.arsc 和 res/ 下的文件不压缩（原样存放）。
 * 顺带把图标路径里 aapt2 自动加的 -v4 去掉（见 renameInTable）。
 * 对齐不在这里做，交给官方的 zipalign。
 * 用法：java tools/Repack.java <aapt2 产物.apk> <classes.dex> <输出.apk>
 */
public final class Repack {
    private static final int DOS_TIME = (1 << 11) | (1 << 5) | 1;
    private static final int DOS_DATE = (1 << 9) | (1 << 5) | 1;

    private static final class Item {
        String name;
        byte[] data;
        boolean deflate;
        byte[] stored;
        long crc;
        int offset;
    }

    public static void main(String[] args) throws IOException {
        List<Item> items = new ArrayList<Item>();
        List<String> resNames = new ArrayList<String>();
        try (ZipFile zip = new ZipFile(args[0])) {
            for (Enumeration<? extends ZipEntry> e = zip.entries(); e.hasMoreElements(); ) {
                String name = e.nextElement().getName();
                if (name.startsWith("res/")) {
                    resNames.add(name);
                } else if (!name.equals("AndroidManifest.xml") && !name.equals("resources.arsc")) {
                    throw new IOException("aapt2 的产物里出现了没料到的文件：" + name);
                }
            }
            Collections.sort(resNames);
            items.add(item("AndroidManifest.xml", read(zip, "AndroidManifest.xml"), true));
            items.add(item("classes.dex", Files.readAllBytes(new File(args[1]).toPath()), true));
            items.add(item("resources.arsc", renameInTable(read(zip, "resources.arsc")), false));
            for (String name : resNames) {
                items.add(item(plainPath(name), read(zip, name), false));
            }
            Collections.sort(items.subList(3, items.size()), (a, b) -> a.name.compareTo(b.name));
        }

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        for (Item it : items) {
            it.offset = out.size();
            header(out, it, false);
            out.write(it.stored);
        }
        int cdStart = out.size();
        for (Item it : items) {
            header(out, it, true);
        }
        int cdSize = out.size() - cdStart;
        le32(out, 0x06054b50);
        le16(out, 0);
        le16(out, 0);
        le16(out, items.size());
        le16(out, items.size());
        le32(out, cdSize);
        le32(out, cdStart);
        le16(out, 0);
        Files.write(new File(args[2]).toPath(), out.toByteArray());
    }

    /**
     * aapt2 会给带密度的目录名自动加上 -v4（res/mipmap-mdpi-v4/），没有开关能关。
     * 打包器要按固定路径换图标，所以这里把 -v4 去掉：res/mipmap-mdpi/ic_launcher.png。
     */
    private static String plainPath(String path) {
        return path.startsWith("res/mipmap-") ? path.replace("-v4/", "/") : path;
    }

    /**
     * 资源表（resources.arsc）开头的全局字符串池里记着每个文件的路径，要跟着一起改。
     * 只重写这个字符串池（UTF-8 格式），后面的内容按序号引用字符串，原样照抄。
     * 结构：表头 12 字节（类型 0x0002、头长、总长、包数）＋字符串池块（类型 0x0001、头长 28、块长、
     * 字符串数、样式数、标志、字符串区起点、样式区起点）＋每个字符串的偏移＋字符串区。
     * build.sh 会用 aapt2 dump 再核对一遍改完的表能被官方工具读出来、路径是对的。
     */
    private static byte[] renameInTable(byte[] arsc) throws IOException {
        ByteBuffer in = ByteBuffer.wrap(arsc).order(ByteOrder.LITTLE_ENDIAN);
        if (in.getShort(0) != 0x0002 || in.getShort(2) != 12 || in.getInt(4) != arsc.length) {
            throw new IOException("resources.arsc 的表头不是预期的样子");
        }
        int pool = 12;
        int poolSize = in.getInt(pool + 4);
        int count = in.getInt(pool + 8);
        int styles = in.getInt(pool + 12);
        int flags = in.getInt(pool + 16);
        int stringsStart = in.getInt(pool + 20);
        if (in.getShort(pool) != 0x0001 || in.getShort(pool + 2) != 28 || styles != 0 || (flags & 0x100) == 0) {
            throw new IOException("resources.arsc 的字符串池不是预期的样子（应为 UTF-8、无样式）");
        }
        ByteArrayOutputStream data = new ByteArrayOutputStream();
        int[] offsets = new int[count];
        for (int i = 0; i < count; i++) {
            int p = pool + stringsStart + in.getInt(pool + 28 + 4 * i);
            int[] pos = {p};
            readLength(arsc, pos); // 按 UTF-16 算的长度
            int bytes = readLength(arsc, pos);
            String text = plainPath(new String(arsc, pos[0], bytes, StandardCharsets.UTF_8));
            byte[] utf8 = text.getBytes(StandardCharsets.UTF_8);
            offsets[i] = data.size();
            writeLength(data, text.length());
            writeLength(data, utf8.length);
            data.write(utf8);
            data.write(0);
        }
        while (data.size() % 4 != 0) {
            data.write(0);
        }
        int newPoolSize = 28 + 4 * count + data.size();
        ByteBuffer out = ByteBuffer.allocate(arsc.length - poolSize + newPoolSize).order(ByteOrder.LITTLE_ENDIAN);
        out.put(arsc, 0, pool + 28);
        for (int o : offsets) {
            out.putInt(o);
        }
        out.put(data.toByteArray());
        out.put(arsc, pool + poolSize, arsc.length - pool - poolSize);
        out.putInt(4, out.capacity());
        out.putInt(pool + 4, newPoolSize);
        out.putInt(pool + 20, 28 + 4 * count);
        return out.array();
    }

    private static int readLength(byte[] b, int[] pos) {
        int first = b[pos[0]++] & 0xff;
        return (first & 0x80) == 0 ? first : ((first & 0x7f) << 8) | (b[pos[0]++] & 0xff);
    }

    private static void writeLength(ByteArrayOutputStream out, int n) {
        if (n > 0x7f) {
            out.write(0x80 | (n >>> 8));
        }
        out.write(n & 0xff);
    }

    private static byte[] read(ZipFile zip, String name) throws IOException {
        ZipEntry e = zip.getEntry(name);
        if (e == null) {
            throw new IOException("aapt2 的产物里缺 " + name);
        }
        try (InputStream in = zip.getInputStream(e)) {
            return in.readAllBytes();
        }
    }

    private static Item item(String name, byte[] data, boolean deflate) {
        Item it = new Item();
        it.name = name;
        it.data = data;
        it.deflate = deflate;
        CRC32 crc = new CRC32();
        crc.update(data);
        it.crc = crc.getValue();
        if (deflate) {
            Deflater d = new Deflater(9, true);
            d.setInput(data);
            d.finish();
            ByteArrayOutputStream o = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            while (!d.finished()) {
                o.write(buf, 0, d.deflate(buf));
            }
            d.end();
            it.stored = o.toByteArray();
        } else {
            it.stored = data;
        }
        return it;
    }

    private static void header(ByteArrayOutputStream out, Item it, boolean central) {
        byte[] name = it.name.getBytes(StandardCharsets.UTF_8);
        int version = it.deflate ? 20 : 10;
        if (central) {
            le32(out, 0x02014b50);
            le16(out, version); // 制作方版本
        } else {
            le32(out, 0x04034b50);
        }
        le16(out, version);
        le16(out, 0x0800); // 文件名是 UTF-8
        le16(out, it.deflate ? 8 : 0);
        le16(out, DOS_TIME);
        le16(out, DOS_DATE);
        le32(out, (int) it.crc);
        le32(out, it.stored.length);
        le32(out, it.data.length);
        le16(out, name.length);
        le16(out, 0); // 附加字段
        if (central) {
            le16(out, 0); // 注释
            le16(out, 0); // 起始磁盘
            le16(out, 0); // 内部属性
            le32(out, 0); // 外部属性
            le32(out, it.offset);
        }
        out.write(name, 0, name.length);
    }

    private static void le16(ByteArrayOutputStream out, int v) {
        out.write(v & 0xff);
        out.write((v >>> 8) & 0xff);
    }

    private static void le32(ByteArrayOutputStream out, int v) {
        le16(out, v & 0xffff);
        le16(out, (v >>> 16) & 0xffff);
    }
}
