import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

void main() {
  runApp(const TreeSizeApp());
}

// ================== APP ==================
class TreeSizeApp extends StatelessWidget {
  const TreeSizeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter TreeSize',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const DriveSelectionPage(),
    );
  }
}

// ================== DRIVE SELECTION ==================
class DriveSelectionPage extends StatefulWidget {
  const DriveSelectionPage({super.key});

  @override
  State<DriveSelectionPage> createState() => _DriveSelectionPageState();
}

class _DriveSelectionPageState extends State<DriveSelectionPage> {
  List<String> drives = [];

  @override
  void initState() {
    super.initState();
    _loadDrives();
  }

  Future<void> _loadDrives() async {
    final result = await getDrives();
    if (!mounted) return;
    setState(() {
      drives = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Laufwerk/Ordner auswählen")),
      body: Column(
        children: [
          Expanded(
            child: drives.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: drives.length,
                    itemBuilder: (context, index) {
                      final drive = drives[index];
                      return ListTile(
                        title: Text(drive),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () {
                          bool autoScan = drive
                              .startsWith(Platform.environment['HOME'] ?? '');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ScanPage(rootPath: drive, autoScan: autoScan),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          Container(
            width: double.infinity,
            color: Colors.grey.shade200,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: Alignment.centerRight,
            child: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                const fallbackVersion = "1.0.0";
                String version = fallbackVersion;
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  version = snapshot.data!.version;
                }
                return Text(
                  "Autor: Christian Burau | Firma: Dataport | Version: $version",
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ================== DRIVE DETECTION ==================
Future<List<String>> getDrives() async {
  if (Platform.isWindows) {
    final result = await Process.run("wmic", ["logicaldisk", "get", "name"],
        runInShell: true);
    final lines = result.stdout.toString().split("\n");
    return lines
        .where((line) => line.trim().isNotEmpty && line.contains(":"))
        .map((line) => line.trim() + "\\")
        .toList();
  } else {
    List<String> drives = ["/"];
    final mnt = Directory("/mnt");
    if (mnt.existsSync()) {
      drives.addAll(
          mnt.listSync().whereType<Directory>().map((d) => d.path).toList());
    }
    final media = Directory("/media");
    if (media.existsSync()) {
      drives.addAll(
          media.listSync().whereType<Directory>().map((d) => d.path).toList());
    }
    final home = Platform.environment['HOME'];
    if (home != null) drives.add(home);
    return drives;
  }
}

// ================== FOLDER ENTRY ==================
class FolderEntry {
  final String path;
  int size;
  List<FolderEntry> children;
  bool isScanned;
  bool hasAccess;

  FolderEntry(this.path,
      {this.size = 0,
      List<FolderEntry>? children,
      this.isScanned = false,
      this.hasAccess = true})
      : children = children ?? [];
}

// ================== SCAN PAGE ==================
class ScanPage extends StatefulWidget {
  final String rootPath;
  final bool autoScan;
  const ScanPage({super.key, required this.rootPath, this.autoScan = false});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  List<FolderEntry> topFolders = [];
  List<FolderEntry> deniedFolders = [];
  bool isLoading = true;
  bool isScanComplete = false;

  int scannedFolders = 0;
  int totalFolders = 0;
  int deniedSize = 0;

  int driveTotal = 0;
  int totalRootSize = 0;

  @override
  void initState() {
    super.initState();
    _initDriveInfo();
    _loadTopLevelFolders();
  }

  Future<void> _initDriveInfo() async {
    final info = await getDriveInfo(widget.rootPath);
    setState(() {
      driveTotal = info['total'] ?? 0;
    });
  }

  Future<void> _loadTopLevelFolders() async {
    List<FolderEntry> folders = [];
    try {
      final dir = Directory(widget.rootPath);
      await for (var entity in dir.list(recursive: false, followLinks: false)) {
        if (entity is Directory) {
          folders.add(FolderEntry(entity.path));
        }
      }
    } catch (_) {}

    folders.sort((a, b) => b.path.compareTo(a.path));
    if (!mounted) return;
    setState(() {
      topFolders = folders;
      isLoading = false;
    });

    if (widget.autoScan) {
      await _scanTopLevel();
    }
  }

  Future<void> _scanTopLevel() async {
    setState(() {
      isLoading = true;
      scannedFolders = 0;
      totalFolders = topFolders.length;
      deniedFolders.clear();
      deniedSize = 0;
      totalRootSize = 0;
      isScanComplete = false;
    });

    for (var folder in topFolders) {
      final scanned = await compute(scanDirectory, folder.path);
      folder.size = scanned.size;
      folder.children = scanned.children;
      folder.isScanned = scanned.isScanned;
      folder.hasAccess = scanned.hasAccess;

      if (!folder.hasAccess) {
        deniedFolders.add(folder);
        deniedSize += folder.size;
      } else {
        totalRootSize += folder.size;
      }

      scannedFolders++;
      if (!mounted) return;
      setState(() {});
    }

    topFolders.sort((a, b) => b.size.compareTo(a.size));
    setState(() {
      isLoading = false;
      isScanComplete = true;
    });
  }

  Future<void> _rescanAll() async => await _scanTopLevel();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Laufwerk: ${widget.rootPath}"),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: "Erneut scannen",
              onPressed: _rescanAll),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey.shade300,
            child: Text("Gesamt: ${Utils.formatSize(driveTotal)}"),
          ),
          if (isLoading)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: LinearProgressIndicator(
                value: totalFolders > 0 ? scannedFolders / totalFolders : null,
                minHeight: 8,
                color: Colors.blue,
              ),
            ),
          if (isScanComplete)
            Container(
              width: double.infinity,
              color: Colors.green.shade200,
              padding: const EdgeInsets.all(8),
              child: const Text(
                "Scan abgeschlossen ✅",
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                ...topFolders.map((e) =>
                    FolderTile(entry: e, parentSize: totalRootSize, level: 0)),
                if (deniedFolders.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        color: Colors.red.shade200,
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          "Zugriff verweigert (${deniedFolders.length} Ordner)",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...deniedFolders.map((e) => FolderTile(
                          entry: e, parentSize: totalRootSize, level: 0)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================== FOLDER TILE ==================
class FolderTile extends StatefulWidget {
  final FolderEntry entry;
  final int parentSize;
  final int level;

  const FolderTile(
      {super.key,
      required this.entry,
      required this.parentSize,
      this.level = 0});

  @override
  State<FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<FolderTile> {
  bool isScanning = false;

  @override
  void initState() {
    super.initState();
    if (!widget.entry.isScanned && widget.entry.hasAccess) {
      _scanFolder(widget.entry);
    }
  }

  Future<void> _scanFolder(FolderEntry entry) async {
    setState(() => isScanning = true);
    final scanned = await compute(scanDirectory, entry.path);
    if (!mounted) return;

    setState(() {
      entry.size = scanned.size;
      entry.children = scanned.children;
      entry.isScanned = scanned.isScanned;
      entry.hasAccess = scanned.hasAccess;
      entry.children.sort((a, b) => b.size.compareTo(a.size));
      isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    double fraction =
        widget.parentSize > 0 ? widget.entry.size / widget.parentSize : 0.0;
    final title = widget.entry.path.split(Platform.pathSeparator).last.isEmpty
        ? widget.entry.path
        : widget.entry.path.split(Platform.pathSeparator).last;

    final bgColor = widget.entry.hasAccess
        ? (widget.level % 2 == 0 ? Colors.white : Colors.blue.shade50)
        : Colors.red.shade100;
    final textStyle = widget.entry.hasAccess
        ? const TextStyle()
        : const TextStyle(color: Colors.red, fontStyle: FontStyle.italic);

    return ExpansionTile(
      title: Container(
        color: bgColor,
        padding: EdgeInsets.only(
            left: 16.0 * widget.level, top: 4, bottom: 4, right: 4),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(title, style: textStyle)),
            Expanded(
                flex: 2,
                child: Text(Utils.formatSize(widget.entry.size),
                    style: textStyle)),
            Expanded(
                flex: 1,
                child: Text("${(fraction * 100).toStringAsFixed(1)} %",
                    style: textStyle)),
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  Container(height: 12, color: Colors.grey.shade300),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(
                        height: 12,
                        color:
                            widget.entry.hasAccess ? Colors.blue : Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      children: widget.entry.isScanned
          ? widget.entry.children
              .map((e) => FolderTile(
                  entry: e,
                  parentSize: widget.entry.size,
                  level: widget.level + 1))
              .toList()
          : [
              if (isScanning)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      const Text("Scanning…"),
                    ],
                  ),
                )
              else
                TextButton(
                  onPressed: () => _scanFolder(widget.entry),
                  child: const Text("Größe berechnen..."),
                ),
            ],
    );
  }
}

// ================== UTILS ==================
class Utils {
  static String formatSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024)
      return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
  }
}

// ================== DRIVE INFO ==================
Future<Map<String, int>> getDriveInfo(String path) async {
  if (Platform.isWindows) {
    final result = await Process.run(
        "wmic", ["logicaldisk", "get", "size,name"],
        runInShell: true);
    for (var line in result.stdout.toString().split('\n')) {
      line = line.trim();
      if (line.isEmpty || line.startsWith("Name") || !line.contains(path[0]))
        continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final size = int.tryParse(parts[1]) ?? 0;
        return {'total': size};
      }
    }
  } else {
    final stat = await Process.run('df', ['-k', path]);
    final lines = stat.stdout.toString().split('\n');
    if (lines.length > 1) {
      final parts = lines[1].split(RegExp(r'\s+'));
      if (parts.length >= 6) {
        final total = int.tryParse(parts[1])! * 1024;
        return {'total': total};
      }
    }
  }
  return {'total': 0};
}

// ================== SCAN FUNCTION ==================
Future<FolderEntry> scanDirectory(String path) async {
  int totalSize = 0;
  List<FolderEntry> children = [];
  bool access = true;

  try {
    final dir = Directory(path);
    await for (var entity in dir.list(recursive: false, followLinks: false)) {
      try {
        if (entity is File) {
          totalSize += await entity.length();
        } else if (entity is Directory) {
          final child = await scanDirectory(entity.path);
          totalSize += child.size;
          children.add(child);
        }
      } catch (_) {}
    }
  } catch (_) {
    access = false;
  }

  children.sort((a, b) => b.size.compareTo(a.size));
  return FolderEntry(path,
      size: totalSize, children: children, isScanned: true, hasAccess: access);
}
