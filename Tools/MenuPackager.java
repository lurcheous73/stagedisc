// Packages the precompiled menu runtime and native-rendered assets for BD-J.
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.jar.*;
import net.java.bd.tools.bdjo.*;

public final class MenuPackager {
    public static void main(String[] args) throws Exception {
        if (args.length != 3) throw new IllegalArgumentException("disc-root menu-assets menu-runtime.jar");
        Path root = Paths.get(args[0]).resolve("BDMV");
        Files.createDirectories(root.resolve("JAR"));
        Files.createDirectories(root.resolve("BDJO"));
        Path jar = root.resolve("JAR/00000.jar");
        Manifest manifest = new Manifest(); manifest.getMainAttributes().putValue("Manifest-Version", "1.0");
        try (JarOutputStream output = new JarOutputStream(Files.newOutputStream(jar), manifest);
             JarFile runtime = new JarFile(args[2])) {
            Enumeration<JarEntry> entries = runtime.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                if (entry.isDirectory() || entry.getName().startsWith("META-INF")) continue;
                output.putNextEntry(new JarEntry(entry.getName()));
                try (InputStream input = runtime.getInputStream(entry)) { copy(input, output); }
                output.closeEntry();
            }
            try (DirectoryStream<Path> assets = Files.newDirectoryStream(Paths.get(args[1]))) {
                for (Path asset : assets) {
                    output.putNextEntry(new JarEntry(asset.getFileName().toString()));
                    Files.copy(asset, output); output.closeEntry();
                }
            }
        }
        String xml = "<?xml version='1.0' encoding='UTF-8'?>" +
            "<bdjo><appCacheInfo><entries><language>*.*</language><name>00000</name><type>1</type></entries></appCacheInfo>" +
            "<applicationManagementTable><applications><applicationDescriptor>" +
            "<profiles><majorVersion>1</majorVersion><microVersion>0</microVersion><minorVersion>0</minorVersion><profile>1</profile></profiles>" +
            "<priority>128</priority><binding>TITLE_BOUND_DISC_BOUND</binding><visibility>V_01</visibility>" +
            "<iconLocator></iconLocator><iconFlags>0</iconFlags><baseDirectory>00000</baseDirectory><classpathExtension></classpathExtension>" +
            "<initialClassName>StageMenu</initialClassName></applicationDescriptor>" +
            "<applicationId>0x0001</applicationId><controlCode>1</controlCode><organizationId>0x53544744</organizationId><type>1</type>" +
            "</applications></applicationManagementTable><fileAccessInfo></fileAccessInfo><keyInterestTable>0</keyInterestTable>" +
            "<tableOfAccessiblePlayLists><accessToAllFlag>true</accessToAllFlag><autostartFirstPlayListFlag>false</autostartFirstPlayListFlag></tableOfAccessiblePlayLists>" +
            "<terminalInfo><defaultFontFile>00000</defaultFontFile><initialHaviConfig>HD_1920_1080</initialHaviConfig>" +
            "<menuCallMask>false</menuCallMask><titleSearchMask>false</titleSearchMask><mouseInterest>false</mouseInterest><mouseSupported>false</mouseSupported></terminalInfo><version>V_0200</version></bdjo>";
        BDJO bdjo = BDJOReader.readXML(xml);
        try (OutputStream output = Files.newOutputStream(root.resolve("BDJO/00000.bdjo"))) { BDJOWriter.writeBDJO(bdjo, output); }
        System.out.println("Installed StageDisc Java menu.");
    }
    private static void copy(InputStream input, OutputStream output) throws IOException {
        byte[] buffer = new byte[65536]; int count;
        while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
    }
}
