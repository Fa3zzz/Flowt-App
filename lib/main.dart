import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

part 'main.g.dart';



const double kFontSize = 16.0;
const TextStyle kBaseTextStyle = TextStyle(
  color: Colors.white54,
  fontSize: kFontSize,
  height: 1.4,
);
const TextStyle kLinkTextStyle = TextStyle(
  color: Color(0xFF9B30FF),
  fontSize: kFontSize,
  decoration: TextDecoration.underline,
  height: 1.4,
);


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(NoteAdapter());
  await Hive.openBox<Note>(
    'notesBox_v2',
    compactionStrategy: (total, deleted) => deleted > 20,
  );

  final notesBox = Hive.box<Note>('notesBox_v2');
  // await notesBox.clear();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF4B0082),
          foregroundColor: Colors.white,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF4B0082),
          foregroundColor: Colors.white,
        ),
      ),

      home: const NotesHome(),
    );
  }
}

@HiveType(typeId: 0)
class Note extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  String? description;

  @HiveField(2)
  final List<Map<String, String>> links;

  @HiveField(3)
  List<String> imagePaths;

  @HiveField(4)
  List<Map<String, String>> contentBlocks;

  @HiveField(5)
  DateTime lastModified;

  Note({
    required this.title,
    this.description,
    List<Map<String, String>>? links,
    this.imagePaths = const [],
    List<Map<String, String>>? contentBlocks,
    DateTime? lastModified,
  })  : links = List<Map<String, String>>.from(links ?? []),
        contentBlocks = contentBlocks ?? [],
        lastModified = lastModified ?? DateTime.now();
}

class NotesHome extends StatefulWidget {
  const NotesHome({super.key});

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  final notesBox = Hive.box<Note>('notesBox_v2');

  final List<String> _monthNameList = const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  String _sectionLabel(DateTime noteDate) {
    final now = DateTime.now();
    final diff = now.difference(noteDate).inDays;

    if (diff == 0 &&
        noteDate.day == now.day &&
        noteDate.month == now.month &&
        noteDate.year == now.year) {
      return "Today";
    } else if (diff == 1 &&
        noteDate.month == now.month &&
        noteDate.year == now.year) {
      return "Yesterday";
    } else if (noteDate.year == now.year) {
      if (noteDate.month == now.month) {
        return _monthNameList[noteDate.month - 1]; // current month
      } else {
        return _monthNameList[noteDate.month - 1]; // past months this year
      }
    } else {
      return noteDate.year.toString(); // older years (2024, etc.)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: const Text("Flowt"),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchNotesScreen()),
              );
            },
          )
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: notesBox.listenable(),
        builder: (context, Box<Note> box, _) {
          if (box.isEmpty) {
            return const Center(
              child: Text(
                "No notes yet",
                style: TextStyle(color: Colors.white54, fontSize: 18),
              ),
            );
          }

          // ✅ Sort newest first
          final notes = box.values.toList()
            ..sort((a, b) => b.lastModified.compareTo(a.lastModified));

          // ✅ Group by section
          final Map<String, List<Note>> groupedNotes = {};
          for (var note in notes) {
            final label = _sectionLabel(note.lastModified);
            groupedNotes.putIfAbsent(label, () => []).add(note);
          }

          // ✅ Order sections: Today → Yesterday → months → older years
          final orderedKeys = groupedNotes.keys.toList()
            ..sort((a, b) {
              final now = DateTime.now();

              DateTime getDate(String label) {
                if (label == "Today") return now;
                if (label == "Yesterday") return now.subtract(const Duration(days: 1));

                final monthIndex = _monthNameList.indexOf(label);
                if (monthIndex != -1) {
                  final year = now.year;
                  return DateTime(year, monthIndex + 1);
                }

                final yearNum = int.tryParse(label);
                if (yearNum != null) return DateTime(yearNum);
                return now;
              }

              return getDate(b).compareTo(getDate(a));
            });

            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: orderedKeys.length,
              itemBuilder: (context, sectionIndex) {
                final sectionTitle = orderedKeys[sectionIndex];
                final sectionNotes = groupedNotes[sectionTitle]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        sectionTitle,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: (sectionTitle == "Today" || sectionTitle == "Yesterday") ? 28 : 24,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),

                    // Group container (single block look)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.deepPurple.withAlpha((0.25 * 255).round()),
                            blurRadius: 8,
                            spreadRadius: 1,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < sectionNotes.length; i++) ...[
                            Dismissible(
                              key: ValueKey(sectionNotes[i].key),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: Colors.redAccent,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              onDismissed: (_) async {
                                await Future.delayed(const Duration(milliseconds: 100));
                                sectionNotes[i].delete();

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Note deleted'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: ListTile(
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                title: Text(
                                  sectionNotes[i].title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (sectionTitle == "2024" || int.tryParse(sectionTitle) != null)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: Text(
                                          "${sectionNotes[i].lastModified.day} ${_monthNameList[sectionNotes[i].lastModified.month - 1]}",
                                          style: const TextStyle(color: Colors.white38, fontSize: 13),
                                        ),
                                      ),
                                    Expanded(
                                      child: sectionNotes[i].description != null &&
                                              sectionNotes[i].description!.isNotEmpty
                                          ? Text(
                                              sectionNotes[i].description!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Colors.white38),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                ),
                                onTap: () async {
                                  final updatedNote = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => NoteDetailScreen(note: sectionNotes[i]),
                                    ),
                                  );
                                  if (updatedNote != null) {
                                    sectionNotes[i].title = updatedNote.title;
                                    sectionNotes[i].description = updatedNote.description;
                                    sectionNotes[i].save();
                                  }
                                },
                              ),
                            ),

                            // Divider line (except after last note)
                            if (i < sectionNotes.length - 1)
                              Container(
                                height: 0.6,
                                color: Colors.white38,
                                margin: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            );

        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF4B0082),
        onPressed: () async {
          final newNote = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddNotesScreen()),
          );

          if (newNote != null) {
            notesBox.add(newNote);
          }
        },
        child: const Icon(Icons.add, color: Colors.white54),
      ),
    );
  }
}

class SearchNotesScreen extends StatefulWidget {
  const SearchNotesScreen({super.key});

  @override
  State<SearchNotesScreen> createState() => _SearchNotesScreenState();
}

class _SearchNotesScreenState extends State<SearchNotesScreen> {
  final TextEditingController searchController = TextEditingController();
  List<Note> allNotes = [];
  List<Map<String, dynamic>> results = [];
  String? fadedHighlight; // <-- to track when highlight should fade

  @override
  void initState() {
    super.initState();
    final box = Hive.box<Note>('notesBox_v2');
    allNotes = box.values.toList();
  }

  void _search(String query) {
    final lower = query.toLowerCase();
    final matches = <Map<String, dynamic>>[];

    for (final note in allNotes) {
      final title = note.title.toLowerCase();
      final desc = note.description?.toLowerCase() ?? "";

      // 🟣 Match in title
      if (title.contains(lower)) {
        matches.add({
          "note": note,
          "matchType": "title",
          "highlight": query,
          "context": note.title,
        });
      }

      // 🟣 Match in description (multi-hit safe version)
      if (desc.contains(lower)) {
        final full = note.description!;
        int idx = 0;
        while (true) {
          idx = desc.indexOf(lower, idx);
          if (idx == -1) break;

          int start = full.lastIndexOf('.', idx);
          if (start == -1) start = (idx - 40).clamp(0, full.length - 1);
          int end = full.indexOf('.', idx + lower.length);
          if (end == -1) end = (idx + 250).clamp(0, full.length);

          if (end > start && end <= full.length && start >= 0) {
            final snippet = full.substring(start, end).trim();
            matches.add({
              "note": note,
              "matchType": "description",
              "highlight": query,
              "context": snippet,
              "matchIndex": idx,
            });
          }

          idx += lower.length;
        }
      }
    }

    // 🧠 Sort priority: title > description
    matches.sort((a, b) {
      if (a["matchType"] == "title" && b["matchType"] != "title") return -1;
      if (a["matchType"] != "title" && b["matchType"] == "title") return 1;
      return a["context"].toString().compareTo(b["context"].toString());
    });

    setState(() {
      results = matches;
      fadedHighlight = null;
    });

    // 🎨 Fade highlight smoothly
    if (query.isNotEmpty) {
      const fadeDuration = Duration(seconds: 2);
      const steps = 20;
      final stepTime = fadeDuration.inMilliseconds ~/ steps;

      Future.delayed(const Duration(seconds: 1), () async {
        for (int i = 0; i <= steps; i++) {
          await Future.delayed(Duration(milliseconds: stepTime));
          if (!mounted || searchController.text != query) return;
          setState(() => fadedHighlight = "$query|${1 - (i / steps)}");
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: TextField(
          controller: searchController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Search notes...",
            hintStyle: TextStyle(color: Colors.white54),
            border: InputBorder.none,
          ),
          onChanged: _search,
        ),
      ),
      body: results.isEmpty
          ? const Center(
              child: Text(
                "No matches found",
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              itemCount: results.length,
              itemBuilder: (_, i) {
                final match = results[i];
                final note = match["note"] as Note;
                final highlight = match["highlight"] as String;
                final contextText = match["context"] as String;

                final lower = contextText.toLowerCase();
                final idx = lower.indexOf(highlight.toLowerCase());
                InlineSpan textSpan;

                if (idx != -1) {
                  // Extract opacity from fadedHighlight (e.g., "query|0.6")
                  double fadeValue = 1.0;
                  if (fadedHighlight != null && fadedHighlight!.startsWith(highlight)) {
                    final parts = fadedHighlight!.split('|');
                    if (parts.length == 2) fadeValue = double.tryParse(parts[1]) ?? 1.0;
                  }

                  textSpan = TextSpan(children: [
                    TextSpan(
                      text: contextText.substring(0, idx),
                      style: const TextStyle(color: Colors.white54),
                    ),
                    TextSpan(
                      text: contextText.substring(idx, idx + highlight.length),
                      style: const TextStyle(
                        color: Color(0xFF9B30FF),
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    TextSpan(
                      text: contextText.substring(idx + highlight.length),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ]);
                } else {
                  textSpan = TextSpan(
                    text: contextText,
                    style: const TextStyle(color: Colors.white54),
                  );
                }


                return Card(
                  color: Colors.grey[900],
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    title: Text(
                      note.title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    subtitle: RichText(text: textSpan),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NoteDetailScreen(
                            note: note,
                            highlightQuery: highlight,
                            scrollToMatchIndex: match["matchIndex"], // ✅ added for precise scroll
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}


class AddNotesScreen extends StatefulWidget {
  const AddNotesScreen({super.key});

  @override
  State<AddNotesScreen> createState() => _AddNotesScreenState();
}

class _AddNotesScreenState extends State<AddNotesScreen> {
  final titleController = TextEditingController();
  final scrollController = ScrollController();
  final _uuid = const Uuid();
  final titleFocus = FocusNode();


  // each block gets a stable id
  List<Map<String, dynamic>> blocks = [
    {"id": const Uuid().v4(), "type": "text", "content": "", "controller": null}
  ];

  String? selectedText;

  // links must match Note model
  final List<Map<String, String>> links = [];

  // track selection
  int? selectedBlockIndex;
  int? selectedStart;
  int? selectedEnd;
  String? selectedBlockId;

  @override
  void initState() {
    super.initState();

    titleFocus.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    titleFocus.dispose();
    titleController.dispose();
    for (final b in blocks) {
      if (b['type'] == 'text' && b['controller'] is TextEditingController) {
        (b['controller'] as TextEditingController).dispose();
      }
    }
    super.dispose();
  }

  // --- helpers ---
  (int, int) _normalizedRange(String text, int start, int end) {
    int s = start, e = end;
    while (s < e && text[s] == ' ') s++;
    while (e > s && text[e - 1] == ' ') e--;
    return (s, e);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile == null) return;

    // ✅ Safely persist image file (works for both camera & gallery)
    final dir = await getApplicationDocumentsDirectory();
    final fileExt = pickedFile.path.split('.').last;
    final newPath = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final newFile = File(newPath);

    // 🔹 Use bytes copy for cross-platform stability
    final bytes = await pickedFile.readAsBytes();
    await newFile.writeAsBytes(bytes);
    await Future.delayed(const Duration(milliseconds: 100));

    // ⚙️ Prepare split logic
    int insertAt = blocks.length;
    String beforeText = "";
    String afterText = "";

    // 🔍 Stabilize selected block index (ensure it’s still valid)
    if (selectedBlockIndex != null &&
        selectedBlockIndex! >= 0 &&
        selectedBlockIndex! < blocks.length &&
        blocks[selectedBlockIndex!]['type'] == 'text') {
      final b = blocks[selectedBlockIndex!];
      final ctrl = b['controller'] as TextEditingController?;
      if (ctrl != null) {
        final text = ctrl.text;
        final cursor = ctrl.selection.baseOffset.clamp(0, text.length);
        beforeText = text.substring(0, cursor);
        afterText = text.substring(cursor);

        ctrl.text = beforeText;
        b['content'] = beforeText;

        insertAt = blocks.indexOf(b) + 1;
      }
    } else {
      // fallback: find last text block instead of top/bottom randomness
      final lastTextIndex = blocks.lastIndexWhere((b) => b['type'] == 'text');
      insertAt = (lastTextIndex != -1) ? lastTextIndex + 1 : blocks.length;
    }

    // ✅ Safe insertion sequence (atomic)
    setState(() {
      // 🖼 Insert image exactly after caret or last text block
      blocks.insert(insertAt, {
        "id": _uuid.v4(),
        "type": "image",
        "path": newFile.path,
      });

      // 🧱 Insert following text block to continue typing
      final newController = TextEditingController(text: afterText);
      final newFocus = FocusNode();
      newController.addListener(() {
        final idx = blocks.indexWhere((x) => x["controller"] == newController);
        if (idx != -1) blocks[idx]["content"] = newController.text;
      });

      blocks.insert(insertAt + 1, {
        "id": _uuid.v4(),
        "type": "text",
        "content": afterText,
        "controller": newController,
        "focusNode": newFocus,
      });

      // 🔁 Re-wire selection reference to the new block for next insertion
      selectedBlockIndex = insertAt + 1;
    });

    // 🎯 Auto-focus new text block
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (selectedBlockIndex != null &&
          selectedBlockIndex! >= 0 &&
          selectedBlockIndex! < blocks.length) {
        final next = blocks[selectedBlockIndex!];
        final focus = next['focusNode'] as FocusNode?;
        final ctrl = next['controller'] as TextEditingController?;
        if (focus != null && ctrl != null) {
          focus.requestFocus();
          ctrl.selection = const TextSelection.collapsed(offset: 0);
        }
      }
    });

    // 🔽 Smooth scroll to keep image visible
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    scrollController.animateTo(
      scrollController.position.maxScrollExtent + 200,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }




  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.white54),
            title: const Text("Take Photo", style: TextStyle(color: Colors.white54)),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo, color: Colors.white54),
            title: const Text("Choose from Gallery", style: TextStyle(color: Colors.white54)),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  void _openFullScreen(File file) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => GestureDetector(
        onVerticalDragEnd: (_) => Navigator.pop(context),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: InteractiveViewer(child: Image.file(file))),
        ),
      ),
    );
  }

  // ---------- Linking ----------
  Future<void> _showLinkOptions(String selected) async {
    if (selectedBlockIndex == null || selectedStart == null || selectedEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select text to link')));
      return;
    }

    final b = blocks[selectedBlockIndex!];
    final c = (b['controller'] as TextEditingController?);
    final fullText = c?.text ?? (b['content'] ?? '').toString();
    final (s, e) = _normalizedRange(fullText, selectedStart!, selectedEnd!);
    if (!(s >= 0 && e <= fullText.length && e > s)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid selection')));
      return;
    }
    final cleanSelected = fullText.substring(s, e);

    final blockId = selectedBlockId ?? (b["id"] ??= _uuid.v4()).toString();

    final existingIndex = links.indexWhere((l) =>
        l["block"] == blockId &&
        l["start"] == s.toString() &&
        l["end"] == e.toString());

    final hasExisting = existingIndex != -1;
    final existingLink = hasExisting ? links[existingIndex] : null;

    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!hasExisting) ...[
            ListTile(
              title: const Text("Link to existing note", style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.pop(context);
                _pickNoteToLink(cleanSelected, s, e);
              },
            ),
            ListTile(
              title: const Text("Create new linked note", style: TextStyle(color: Colors.white54)),
              onTap: () async {
                Navigator.pop(context);
                final newNote = Note(
                  title: cleanSelected,
                  description: "",
                  contentBlocks: [
                    {"id": _uuid.v4(), "type": "text", "content": ""}
                  ],
                  links: const [],
                );
                final key = await Hive.box<Note>('notesBox_v2').add(newNote);
                if (!mounted) return;
                setState(() {
                  links.add({
                    "id": _uuid.v4(),
                    "text": cleanSelected,
                    "noteId": key.toString(),
                    "block": blockId,
                    "start": s.toString(),
                    "end": e.toString(),
                  });
                });
              },
            ),
          ] else ...[
            ListTile(
              title: const Text("Unlink", style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  if (existingLink != null) {
                    links.removeWhere((l) => l["id"] == existingLink["id"]);
                  }
                });
              },
            ),
          ]
        ]),
      ),
    );
  }

  void _pickNoteToLink(String selected, int s, int e) {
    final notesBox = Hive.box<Note>('notesBox_v2');
    final others = notesBox.values.toList();

    // 🛡️ Guard: ensure selection context exists
    if (selectedBlockIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a text block before linking')),
      );
      return;
    }

    // 🧠 Get safe block + persistent id
    final b = blocks[selectedBlockIndex!];
    if (b['id'] == null || (b['id'] as String).isEmpty) {
      b['id'] = const Uuid().v4();
    }
    final blockId = b['id'].toString();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Select Note to Link"),
        content: SizedBox(
          width: double.maxFinite,
          child: others.isEmpty
              ? const Text("No other notes available")
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: others.length,
                  itemBuilder: (_, i) {
                    final n = others[i];
                    return ListTile(
                      title: Text(n.title),
                      onTap: () {
                        setState(() {
                          links.add({
                            "id": const Uuid().v4(),
                            "text": selected,
                            "noteId": n.key.toString(),
                            "block": blockId,
                            "start": s.toString(),
                            "end": e.toString(),
                          });
                        });
                        Navigator.pop(context);

                        if (!mounted) return;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Linked successfully'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        });
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }


  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Add Note"),
        actions: [
          if (selectedText != null)
            IconButton(
              icon: const Icon(Icons.link, color: Colors.white54),
              onPressed: () async => await _showLinkOptions(selectedText!),
            )
          else if (!titleFocus.hasFocus) // 👈 hide image button when typing title
            IconButton(
              icon: const Icon(Icons.image_outlined, color: Colors.white54),
              onPressed: _showImageOptions,
            ),
        ],
      ),
      body: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.3),
                    blurRadius: 12,
                    spreadRadius: 2,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: TextField(
                controller: titleController,
                focusNode: titleFocus,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22, // ⬆️ bigger font
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: "Title",
                  hintStyle: const TextStyle(
                    color: Colors.white38,
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // --- note blocks ---
            ...blocks.asMap().entries.map((entry) {
              final index = entry.key;
              final b = entry.value;

              if (b["type"] == "text") {
                if (b["controller"] == null) {
                  final c = TextEditingController(text: b["content"] ?? "");
                  final f = FocusNode();

                  f.addListener(() {
                    if (f.hasFocus) {
                      setState(() => selectedBlockIndex = index);
                    }
                  });

                  c.addListener(() {
                    b["content"] = c.text;

                    // 🧹 Auto-delete empty text block when backspaced fully (except first block)
                    if (c.text.isEmpty && blocks.length > 1) {
                      final currentIndex = blocks.indexOf(b);

                      if (currentIndex > 0) {
                        if (b['focusNode'] != null &&
                            (b['focusNode'] as FocusNode).hasFocus) {
                          setState(() {
                            blocks.removeAt(currentIndex);
                          });

                          final prevIndex = currentIndex - 1;
                          if (prevIndex >= 0 &&
                              blocks[prevIndex]['type'] == 'text' &&
                              blocks[prevIndex]['controller'] is TextEditingController) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              final prevCtrl = blocks[prevIndex]['controller'] as TextEditingController;
                              prevCtrl.selection =
                                  TextSelection.collapsed(offset: prevCtrl.text.length);
                              (blocks[prevIndex]['focusNode'] as FocusNode?)?.requestFocus();
                            });
                          }

                          if (blocks.isEmpty) {
                            setState(() {
                              blocks.add({
                                "id": _uuid.v4(),
                                "type": "text",
                                "content": "",
                                "controller": TextEditingController(),
                                "focusNode": FocusNode(),
                              });
                            });
                          }
                        }
                      }
                    }

                    // 🧠 Selection handling (unchanged)
                    final sel = c.selection;
                    if (sel.start != sel.end &&
                        sel.start >= 0 &&
                        sel.end <= c.text.length) {
                      final (s, e) = _normalizedRange(c.text, sel.start, sel.end);
                      if (e > s) {
                        setState(() {
                          selectedText = c.text.substring(s, e);
                          selectedBlockIndex = index;
                          selectedBlockId = (b["id"] ??= _uuid.v4()).toString();
                          selectedStart = s;
                          selectedEnd = e;
                        });
                      }
                    } else if (selectedText != null) {
                      setState(() {
                        selectedText = null;
                        selectedBlockIndex = null;
                        selectedBlockId = null;
                        selectedStart = null;
                        selectedEnd = null;
                      });
                    }
                  });

                  b["controller"] = c;
                  b["focusNode"] = f;
                }

                final c = b["controller"] as TextEditingController;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: c,
                    focusNode: b["focusNode"],
                    style: kBaseTextStyle,
                    decoration: InputDecoration(
                      hintText: index == 0 ? "Description…" : "",
                      hintStyle: const TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                    keyboardType: TextInputType.multiline,
                    maxLines: null,
                  ),
                );
              } else if (b["type"] == "image") {
                final file = File(b["path"]);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      GestureDetector(
                        onTap: () => _openFullScreen(file),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(file,
                              width: double.infinity, fit: BoxFit.cover),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => setState(() => blocks.removeAt(index)),
                      ),
                    ],
                  ),
                );
              }

              return const SizedBox.shrink();
            }),

            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF4B0082),
        onPressed: () {
          final imagePaths = blocks
              .where((b) => b["type"] == "image")
              .map<String>((b) => (b["path"] ?? "").toString())
              .toList();

          final contentBlocks = blocks.map<Map<String, String>>((b) {
            if (b['id'] == null || (b['id'] as String).isEmpty) {
              b['id'] = _uuid.v4();
            }
            final id = b['id'].toString();
            final type = (b['type'] ?? 'text').toString();

            if (type == 'text') {
              return {"id": id, "type": "text", "content": (b["content"] ?? "").toString()};
            } else if (type == 'image') {
              return {"id": id, "type": "image", "path": (b["path"] ?? "").toString()};
            }
            return {"id": id, "type": "text", "content": ""};
          }).toList();

          // ✅ Keep description as the *first text block* only (like a summary)
          final firstTextBlock = contentBlocks.firstWhere(
            (b) => b["type"] == "text" && (b["content"] ?? "").trim().isNotEmpty,
            orElse: () => {"content": ""},
          );
          final description = firstTextBlock["content"] ?? "";

          final cleanLinks = links
              .where((l) => l.containsKey("block") && l.containsKey("start") && l.containsKey("end"))
              .toList();

          final newNote = Note(
            title: titleController.text.trim(),
            description: description.isNotEmpty ? description : null,
            imagePaths: imagePaths,
            contentBlocks: contentBlocks,
            links: cleanLinks.cast<Map<String, String>>(),
          );

          newNote.lastModified = DateTime.now();
          Navigator.pop(context, newNote);
        },
        child: const Icon(Icons.check, color: Colors.white54),
      ),
    );
  }
}

class NoteDetailScreen extends StatefulWidget {
  final Note note;
  final String? highlightQuery;
  final int? scrollToMatchIndex; 
  const NoteDetailScreen({
    super.key,
    required this.note, 
    this.highlightQuery, 
    this.scrollToMatchIndex,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late TextEditingController titleController;
  bool isEditingTitle = false;
  bool isEditingDescription = false;
  String? highlightQuery;
  double highlightOpacity = 1.0;
  String? _lastBlockIdForLink;
  int? _viewCaretOffset;
  int? _pendingInsertBlockIndex;
  int? _pendingInsertCaretOffset;

  late ScrollController _detailScrollController;


  String? selectedText;
  int? selectedBlockIndex;
  int? selectedStart;
  int? selectedEnd;

  List<Map<String, dynamic>> blocks = [];

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.note.title);
    highlightQuery = widget.highlightQuery?.toLowerCase();

    _detailScrollController = ScrollController();

    // 👇 Handle fade + scroll only once
    if (highlightQuery != null && highlightQuery!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final primaryScrollController = PrimaryScrollController.of(context);
        if (primaryScrollController.hasClients) {
          // 🎯 Scroll directly to match index if available
          final offset = widget.scrollToMatchIndex != null
              ? (widget.scrollToMatchIndex! * 12.0)
                  .clamp(0.0, primaryScrollController.position.maxScrollExtent)
                  .toDouble() // ✅ fix: convert num → double
              : 200.0;

          primaryScrollController.animateTo(
            offset,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
          );
        }
      });

      // ✅ Fade highlight color after a short delay
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => highlightOpacity = 0.0);
        }
      });
    }

    // Load or fallback
    if (widget.note.contentBlocks.isNotEmpty) {
      blocks = widget.note.contentBlocks
          .map((b) => Map<String, dynamic>.from(b))
          .toList();
    } else {
      blocks = [
        {"type": "text", "content": widget.note.description ?? ""}
      ];
      widget.note.contentBlocks = blocks.cast<Map<String, String>>();
      widget.note.save();
    }

    // 🧠 Legacy link migration
    if (widget.note.links is Map) {
      final oldLinks = (widget.note.links as Map).entries.map((e) {
        return {
          "id": const Uuid().v4(),
          "text": e.key.toString(),
          "noteId": e.value.toString(),
        };
      }).toList();
      widget.note.links
        ..clear()
        ..addAll(oldLinks.cast<Map<String, String>>());
      widget.note.save();
    }

    _attachControllers();
  }



  void _wireTextBlock(Map<String, dynamic> b) {
    if (b['_wired'] == true) return;

    // 🔹 Ensure each block has a stable unique ID
    b['id'] ??= const Uuid().v4();

    final c = TextEditingController(text: (b['content'] ?? '') as String);
    final f = FocusNode();
    b['controller'] = c;
    b['focusNode'] = f;
    b['_wired'] = true;

    f.addListener(() {
      if (f.hasFocus) {
        // 🔹 Mark this block as the active one when user focuses it
        setState(() => selectedBlockIndex = blocks.indexOf(b));
      } else {
        // 🔹 Clear selection when focus is lost
        setState(() {
          if (selectedBlockIndex == blocks.indexOf(b)) {
            selectedText = null;
            selectedBlockIndex = null;
            selectedStart = null;
            selectedEnd = null;
          }
        });
      }
    });

    c.addListener(() {
      // ✅ Update this block’s content live
      b['content'] = c.text;

      // ✅ Always sync the in-memory structure with Hive’s model
      widget.note.contentBlocks = _sanitizeBlocks();

      // ✅ Keep description text accurate for list previews
      widget.note.description = widget.note.contentBlocks
          .where((e) => e['type'] == 'text')
          .map((e) => e['content'] ?? '')
          .join('\n');

      // ✅ Save to Hive immediately so nothing is lost
      widget.note.save();

      // 🎯 Track selection live (for link highlighting, etc.)
      if (f.hasFocus) {
        final sel = c.selection;
        if (sel.start != sel.end &&
            sel.start >= 0 &&
            sel.end <= c.text.length) {
          final (s, e) = _normalizedRange(c.text, sel.start, sel.end);
          if (s < 0 || e > c.text.length || s >= e) return;
          if (!mounted) return;

          if (selectedStart != s || selectedEnd != e) {
            setState(() {
              selectedText = c.text.substring(s, e);
              selectedBlockIndex = blocks.indexOf(b);
              selectedStart = s;
              selectedEnd = e;
              _lastBlockIdForLink = b['id']?.toString();
            });
          }
        } else if (selectedText != null &&
            selectedBlockIndex == blocks.indexOf(b)) {
          if (!mounted) return;
          setState(() {
            selectedText = null;
            selectedStart = null;
            selectedEnd = null;
          });
        }
      }
    });
  }




  void _attachControllers() {
    for (final b in blocks) {
      if (b['type'] == 'text') {
        b['controller'] ??= TextEditingController(text: b['content'] ?? '');
        b['focusNode'] ??= FocusNode();
        _wireTextBlock(b);
      }
    }
  }


  @override
  void dispose() {
    _detailScrollController.dispose();
    for (final b in blocks) {
      if (b['type'] == 'text') {
        (b['controller'] as TextEditingController?)?.dispose();
        (b['focusNode'] as FocusNode?)?.dispose();
      }
    }
    titleController.dispose();
    super.dispose();
  }

  List<Map<String, String>> _sanitizeBlocks() {
    // ✅ Ensure all blocks are properly saved, including empty text blocks after images
    final sanitized = <Map<String, String>>[];

    for (final b in blocks) {
      final type = (b['type'] ?? 'text').toString();
      b['id'] ??= const Uuid().v4();
      final id = b['id'].toString();

      if (type == 'text') {
        // 🧠 Always capture latest text from controller if available
        final text = (b['controller'] is TextEditingController)
            ? (b['controller'] as TextEditingController).text
            : (b['content'] ?? '').toString();

        // ⚡ Preserve empty text blocks to maintain structure (so text after image persists)
        sanitized.add({
          "id": id,
          "type": "text",
          "content": text,
        });
      } else if (type == 'image') {
        sanitized.add({
          "id": id,
          "type": "image",
          "path": (b['path'] ?? '').toString(),
        });
      }
    }

    return sanitized;
  }



  void _safeSave(Note note) {
    note.lastModified = DateTime.now(); // 🕒 update modified time

    // 🧠 Always rebuild a clean, full snapshot of the current note
    final sanitized = _sanitizeBlocks();

    // ✅ Preserve even empty text blocks (to keep layout under images)
    note.contentBlocks = sanitized;

    // ✅ Description = all text joined, even empty lines for spacing
    note.description = sanitized
        .where((b) => b['type'] == 'text')
        .map((b) => b['content'] ?? '')
        .join('\n');

    // ✅ Keep a safe copy of links before replacing
    final linksCopy = widget.note.links
        .map((l) => Map<String, String>.from(l))
        .toList();

    note.links
      ..clear()
      ..addAll(linksCopy);

    // ✅ Persist the updated note to Hive
    note.save();

    // 🔹 Ensure in-memory state matches the saved structure
    setState(() {
      blocks = sanitized.map((b) => Map<String, dynamic>.from(b)).toList();
    });
  }


  // ---------- Image insertion ----------

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked == null) return;

    // 🗂️ Save image safely (camera/gallery)
    final dir = await getApplicationDocumentsDirectory();
    final ext = picked.path.split('.').last;
    final newPath = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final newFile = File(newPath);
    await newFile.writeAsBytes(await picked.readAsBytes());

    await Future.delayed(const Duration(milliseconds: 150));

    // 🧠 Use pending snapshot (from _showImageOptions) to restore caret position
    int? targetBlock = _pendingInsertBlockIndex;
    int? caretOffset = _pendingInsertCaretOffset;

    // clear pending snapshot after use
    _pendingInsertBlockIndex = null;
    _pendingInsertCaretOffset = null;

    // fallback if snapshot missing
    if (targetBlock == null ||
        targetBlock < 0 ||
        targetBlock >= blocks.length ||
        blocks[targetBlock]['type'] != 'text') {
      targetBlock = blocks.lastIndexWhere((b) => b['type'] == 'text');
      if (targetBlock == -1) targetBlock = null;
    }

    // ensure at least one text block
    if (targetBlock == null) {
      if (blocks.isEmpty) {
        final newText = {
          "id": const Uuid().v4(),
          "type": "text",
          "content": "",
          "controller": TextEditingController(),
          "focusNode": FocusNode(),
          "_wired": false,
        };
        _wireTextBlock(newText);
        setState(() => blocks.add(newText));
        targetBlock = 0;
      } else {
        targetBlock = blocks.length - 1;
      }
    }

    // ✂️ Split text at caret position
    final b = blocks[targetBlock];
    if (b['type'] == 'text' && b['controller'] is TextEditingController) {
      final ctrl = b['controller'] as TextEditingController;
      final text = ctrl.text;
      final caret = (caretOffset ?? ctrl.selection.baseOffset).clamp(0, text.length);
      final beforeText = text.substring(0, caret);
      final afterText = text.substring(caret);

      ctrl.text = beforeText;
      b['content'] = beforeText;

      final newImageBlock = {
        "id": const Uuid().v4(),
        "type": "image",
        "path": newFile.path,
      };
      final newTextBlock = {
        "id": const Uuid().v4(),
        "type": "text",
        "content": afterText,
        "controller": TextEditingController(text: afterText),
        "focusNode": FocusNode(),
        "_wired": false,
      };
      _wireTextBlock(newTextBlock);

      // ✅ Insert image + new text immediately after caret
      setState(() {
        final idx = blocks.indexOf(b);
        blocks.insert(idx + 1, newImageBlock);
        blocks.insert(idx + 2, newTextBlock);
      });

      // focus the new text block automatically
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          (newTextBlock['focusNode'] as FocusNode?)?.requestFocus();
          final ctrl2 = newTextBlock['controller'] as TextEditingController?;
          if (ctrl2 != null) {
            ctrl2.selection = const TextSelection.collapsed(offset: 0);
          }
        } catch (_) {}
      });
    } else {
      // if no valid text block, just append image + empty text
      setState(() {
        blocks.add({
          "id": const Uuid().v4(),
          "type": "image",
          "path": newFile.path,
        });
        final newTextBlock = {
          "id": const Uuid().v4(),
          "type": "text",
          "content": "",
          "controller": TextEditingController(),
          "focusNode": FocusNode(),
          "_wired": false,
        };
        _wireTextBlock(newTextBlock);
        blocks.add(newTextBlock);
      });
    }

    // 🧠 Save safely after rebuild
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _safeSave(widget.note);

    // 🔽 Smooth scroll to show the new image
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_detailScrollController.hasClients) {
        _detailScrollController.animateTo(
          _detailScrollController.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }






  void _showImageOptions() {
    // snapshot current caret & block so bottom sheet won't lose it
    try {
      if (selectedBlockIndex != null &&
          selectedBlockIndex! >= 0 &&
          selectedBlockIndex! < blocks.length &&
          blocks[selectedBlockIndex!]['type'] == 'text' &&
          blocks[selectedBlockIndex!]['controller'] is TextEditingController) {
        final ctrl = blocks[selectedBlockIndex!]['controller'] as TextEditingController;
        _pendingInsertBlockIndex = selectedBlockIndex;
        _pendingInsertCaretOffset = ctrl.selection.baseOffset.clamp(0, ctrl.text.length);
      } else {
        _pendingInsertBlockIndex = blocks.lastIndexWhere((b) => b['type'] == 'text');
        if (_pendingInsertBlockIndex == -1) _pendingInsertBlockIndex = null;
        _pendingInsertCaretOffset = null;
      }
    } catch (_) {
      _pendingInsertBlockIndex = null;
      _pendingInsertCaretOffset = null;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white54),
              title: const Text("Take Photo", style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo, color: Colors.white54),
              title: const Text("Choose from Gallery", style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }


  // ---------- Linking helpers ----------
  (int, int) _normalizedRange(String text, int start, int end) {
    int s = start, e = end;
    // trim spaces only (keep punctuation as user intent)
    while (s < e && text[s] == ' ') s++;
    while (e > s && text[e - 1] == ' ') e--;
    // clamp to safe bounds
    s = s.clamp(0, text.length);
    e = e.clamp(0, text.length);
    return (s, e);
  }

  // Build a sanitized, non-overlapping, in-bounds list of ranges for a block
  List<Map<String, dynamic>> _rangesForBlock(String text, int blockIndex) {
    final b = blocks[blockIndex];
    final blockId = b['id']?.toString() ?? blockIndex.toString();
    final L = text.length;

    final ranges = widget.note.links
        .where((l) => l["block"] == blockId)
        .map((l) => {
              ...l,
              "startInt": (int.tryParse(l["start"] ?? '') ?? 0).clamp(0, L),
              "endInt": (int.tryParse(l["end"] ?? '') ?? 0).clamp(0, L),
            })
        .where((r) => (r["endInt"] as int) > (r["startInt"] as int))
        .toList()
      ..sort((a, b) =>
          (a["startInt"] as int).compareTo(b["startInt"] as int));

    // 🔹 No overlap filtering — trust user’s exact selection
    return ranges;
  }



  // Render text with widgets at saved link ranges
  List<InlineSpan> _buildDescriptionSpans(String text, int blockIndex) {
    final spans = <InlineSpan>[];
    int cursor = 0;
    final query = highlightQuery?.toLowerCase() ?? '';

    // 🧹 Clean up dead links before rendering
    final notesBox = Hive.box<Note>('notesBox_v2');
    widget.note.links.removeWhere((l) {
      final id = int.tryParse(l["noteId"] ?? "");
      if (id == null) return true;
      return !notesBox.containsKey(id); // remove if linked note no longer exists
    });
    widget.note.save();

    final ranges = _rangesForBlock(text, blockIndex);

    void addNormalSpan(String chunk) {
      if (query.isNotEmpty && chunk.toLowerCase().contains(query)) {
        int start = 0, idx;
        while ((idx = chunk.toLowerCase().indexOf(query, start)) != -1) {
          if (idx > start) {
            spans.add(TextSpan(
              text: chunk.substring(start, idx),
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ));
          }

          // 🌈 Smooth background fade (true highlighter effect, no lift)
          final bool isFaded = highlightOpacity <= 0.01;
          final double opacity = isFaded ? 0.0 : highlightOpacity;
          final bgPaint = Paint()
            ..color = const Color(0xFF9B30FF).withOpacity(opacity * 0.35)
            ..style = PaintingStyle.fill;

          spans.add(TextSpan(
            text: chunk.substring(idx, idx + query.length),
            style: TextStyle(
              color: Colors.white54,
              background: bgPaint,
              fontWeight: FontWeight.normal,
              fontSize: 16,
              height: 1.4,
            ),
          ));

          start = idx + query.length;
        }
        if (start < chunk.length) {
          spans.add(TextSpan(
            text: chunk.substring(start),
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ));
        }
      } else {
        spans.add(TextSpan(
          text: chunk,
          style: const TextStyle(color: Colors.white54, fontSize: 16),
        ));
      }
    }

    for (final r in ranges) {
      final rStart = r["startInt"] as int;
      final rEnd = r["endInt"] as int;

      if (rStart > cursor) addNormalSpan(text.substring(cursor, rStart));

      final slice = text.substring(rStart, rEnd);
      final noteIdStr = (r["noteId"] ?? '').toString();
      final linkId = (r["id"] ?? '').toString();

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () async {
              // 🪄 Normal tap → open linked note
              final id = int.tryParse(noteIdStr);
              if (!isEditingDescription && id != null) {
                final target = Hive.box<Note>('notesBox_v2').get(id);
                if (target != null && mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NoteDetailScreen(note: target),
                    ),
                  );
                }
              }
            },
            onLongPress: () async {
              // 🧠 Long-press works in BOTH edit and view mode → show unlink
              setState(() {
                selectedText = slice;
                selectedBlockIndex = blockIndex;
                selectedStart = rStart;
                selectedEnd = rEnd;
              });
              await Future.delayed(const Duration(milliseconds: 60));
              await _showLinkOptions(slice, presetLinkId: linkId);
            },
            child: Text(
              slice,
              style: const TextStyle(
                color: Color(0xFF9B30FF),
                fontSize: 16,
                height: 1.3,
              ),
            ),
          ),
        ),
      );

      cursor = rEnd;
    }

    if (cursor < text.length) addNormalSpan(text.substring(cursor));

    return spans;
  }





  Future<void> _showLinkOptions(String selected, {String? presetLinkId}) async {
    if ((selectedBlockIndex == null || selectedStart == null || selectedEnd == null) &&
        (presetLinkId == null || presetLinkId.isEmpty)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select text to link')));
      return;
    }

    final b = blocks[selectedBlockIndex!];
    final fullText = (b['controller'] as TextEditingController?)?.text ??
        (b['content'] ?? '') as String;

    // ✅ Normalize selection
    final (ns, ne) = _normalizedRange(fullText, selectedStart!, selectedEnd!);
    if (ne <= ns) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid selection')));
      return;
    }

    final cleanSelected = fullText.substring(ns, ne);
    final blockId = b['id']?.toString() ?? selectedBlockIndex.toString();
    _lastBlockIdForLink = blockId;

    // ✅ Allow adjacency — reject only *true* overlaps
    final existingBlockRanges = _rangesForBlock(fullText, selectedBlockIndex!);
    final overlaps = existingBlockRanges.any((r) {
      final s = r["startInt"] as int;
      final e = r["endInt"] as int;
      return (ns < e && ne > s); // true overlap, adjacency allowed
    });

    // Detect existing link
    int existingIndex = -1;
    if (presetLinkId != null && presetLinkId.isNotEmpty) {
      existingIndex = widget.note.links.indexWhere((l) => l["id"] == presetLinkId);
    }
    if (existingIndex == -1) {
      existingIndex = widget.note.links.indexWhere((l) =>
          l["block"] == blockId &&
          l["start"] == "$ns" &&
          l["end"] == "$ne");
    }

    final hasExactExisting = existingIndex != -1;
    final existingLink =
        hasExactExisting ? widget.note.links[existingIndex] : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!hasExactExisting && !overlaps) ...[
            ListTile(
              title: const Text("Link to existing note",
                  style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.pop(context);
                _pickNoteToLink(cleanSelected, ns, ne);
              },
            ),
            ListTile(
              title: const Text("Create new linked note",
                  style: TextStyle(color: Colors.white54)),
              onTap: () async {
                Navigator.pop(context);
                _safeSave(widget.note);

                final newNote = Note(
                  title: cleanSelected,
                  description: "",
                  contentBlocks: [
                    {"type": "text", "content": ""}
                  ],
                  links: const [],
                );

                final key = await Hive.box<Note>('notesBox_v2').add(newNote);
                if (!mounted) return;

                setState(() {
                  widget.note.links.add({
                    "id": const Uuid().v4(),
                    "text": cleanSelected,
                    "noteId": key.toString(),
                    "block": blockId,
                    "start": "$ns",
                    "end": "$ne",
                  });

                  // Sync block content
                  b['content'] = fullText;
                  widget.note.contentBlocks = _sanitizeBlocks();
                });

                _safeSave(widget.note);
                FocusScope.of(context).unfocus(); // 👈 ensures keyboard hides first
                await Future.delayed(const Duration(milliseconds: 200));

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('New linked note "${cleanSelected}" created'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
                setState(() => isEditingDescription = false);

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NoteDetailScreen(note: newNote),
                  ),
                );
              },
            ),
          ] else if (hasExactExisting) ...[
            ListTile(
              title: const Text("Unlink",
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  widget.note.links
                      .removeWhere((l) => l["id"] == existingLink?["id"]);
                });
                _safeSave(widget.note);
              },
            ),
          ] else ...[
            ListTile(
              title: const Text(
                "Selection overlaps an existing link",
                style: TextStyle(color: Colors.orangeAccent),
              ),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ]),
      ),
    );
  }

  void _pickNoteToLink(String selected, int s, int e) {
    final notesBox = Hive.box<Note>('notesBox_v2');
    final others = notesBox.values.where((n) => n.key != widget.note.key).toList();

    // ✅ Resolve the right block robustly (index OR cached id)
    int? idx = selectedBlockIndex;
    if (idx == null || idx < 0 || idx >= blocks.length) {
      if (_lastBlockIdForLink != null && _lastBlockIdForLink!.isNotEmpty) {
        idx = blocks.indexWhere((bb) => (bb['id']?.toString() ?? '') == _lastBlockIdForLink);
      }
    }

    // Still not found? Bail gracefully (don’t crash)
    if (idx == null || idx == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select text to link')),
      );
      return;
    }

    final b = blocks[idx];
    b['id'] ??= const Uuid().v4();
    final blockId = b['id'].toString();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Select Note to Link"),
        content: SizedBox(
          width: double.maxFinite,
          child: others.isEmpty
              ? const Text("No other notes available")
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: others.length,
                  itemBuilder: (_, i) {
                    final n = others[i];
                    return ListTile(
                      title: Text(n.title),
                      onTap: () {
                        setState(() {
                          widget.note.links.add({
                            "id": const Uuid().v4(),
                            "text": selected,
                            "noteId": n.key.toString(),
                            "block": blockId,
                            "start": "$s",
                            "end": "$e",
                          });

                          // keep block content in sync for persistence
                          b['content'] =
                              (b['controller'] as TextEditingController?)?.text ??
                              (b['content'] ?? '');

                          widget.note.contentBlocks = _sanitizeBlocks();
                          _safeSave(widget.note);
                        });

                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Linked to "${n.title}"'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }


  // ---------- UI ----------
  void _enterEditMode() {
    setState(() {
      highlightQuery = null;
      isEditingDescription = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 1️⃣ Pick the block the user interacted with, or fallback
      int target = (selectedBlockIndex ?? -1);
      if (target < 0 || target >= blocks.length || (blocks[target]['type'] ?? 'text') != 'text') {
        // Prefer last text block
        target = blocks.lastIndexWhere((b) => (b['type'] ?? 'text') == 'text');
      }
      if (target == -1) {
        // ensure at least one text block exists
        final nb = {
          "type": "text",
          "content": "",
          "controller": TextEditingController(),
          "focusNode": FocusNode(),
        };
        _wireTextBlock(nb);
        setState(() {
          blocks.add(nb);
          target = blocks.length - 1;
        });
      } else {
        _wireTextBlock(blocks[target]);
      }

      final ctrl  = blocks[target]['controller'] as TextEditingController;
      final focus = blocks[target]['focusNode'] as FocusNode;

      // 2️⃣ Place caret at meaningful spot
      int caret = (_viewCaretOffset ?? selectedEnd ?? selectedStart ?? ctrl.text.length);
      if (caret < 0) caret = 0;
      if (caret > ctrl.text.length) caret = ctrl.text.length;

      focus.requestFocus();
      ctrl.selection = TextSelection.collapsed(offset: caret);

      setState(() => selectedBlockIndex = target);
    });
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: isEditingTitle
            ? TextField(
                controller: titleController,
                autofocus: true,
                style: kBaseTextStyle,
                onSubmitted: (_) {
                  setState(() {
                    isEditingTitle = false;
                    widget.note.title = titleController.text.trim();
                    widget.note.save();
                  });
                },
              )
            : GestureDetector(
                onTap: () {
                  setState(() {
                    isEditingTitle = true;
                    highlightQuery = null;
                  });
                },
                child: Text(widget.note.title),
              ),
        actions: [
          if (selectedText != null && isEditingDescription)
            IconButton(
              icon: const Icon(Icons.link, color: Colors.white54),
              onPressed: () async => await _showLinkOptions(selectedText!),
            )
          else if (isEditingDescription)
            IconButton(
              icon: const Icon(Icons.image_outlined, color: Colors.white54),
              onPressed: _showImageOptions,
            )
          else
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white54),
              onPressed: _enterEditMode,
            ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // 🧠 Only unfocus when NOT editing — avoids keyboard flicker below images
                if (!isEditingDescription && notification is ScrollUpdateNotification) {
                  FocusScope.of(context).unfocus();
                }
                return false;
              },
              child: ListView.builder(
                controller: _detailScrollController,
                padding: const EdgeInsets.all(16),
                itemCount: blocks.length,
                itemBuilder: (context, i) {
                  final b = blocks[i];
                  if (b['type'] == 'text') {
                    // Safety: ensure controller/focus/listeners exist
                    if (!(b['_wired'] == true)) {
                      _wireTextBlock(b);
                    }
                    final ctrl = (b['controller'] as TextEditingController);
                    final foc = (b['focusNode'] as FocusNode);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: isEditingDescription
                          ? TextField(
                              controller: ctrl,
                              focusNode: foc,
                              maxLines: null,
                              style: kBaseTextStyle,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText:
                                    _shouldShowHintForBlock(i) ? "Description…" : null,
                                hintStyle: const TextStyle(color: Colors.grey),
                              ),
                              onTap: () =>
                                  setState(() => selectedBlockIndex = i),
                            )
                          : RichText(
                              text: TextSpan(
                                children:
                                    _buildDescriptionSpans(b['content'] ?? '', i),
                              ),
                              textAlign: TextAlign.left,
                            ),
                    );
                  } else if (b['type'] == 'image') {
                    final file = File(b['path']);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: RepaintBoundary(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                file,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                filterQuality:
                                    FilterQuality.low, // ⚡ smoother scroll
                                cacheWidth: 800, // optimize decode size
                              ),
                            ),

                            // ❌ Delete icon — visible only in edit mode
                            if (isEditingDescription)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.red, size: 22),
                                  onPressed: () {
                                    setState(() {
                                      // 🗑️ Remove the image block
                                      blocks.removeAt(i);

                                      // 🧹 Clean up empty text blocks near deleted image
                                      if (i < blocks.length &&
                                          blocks[i]['type'] == 'text') {
                                        final nextText =
                                            (blocks[i]['content'] ?? '').trim();
                                        if (nextText.isEmpty) blocks.removeAt(i);
                                      } else if (i - 1 >= 0 &&
                                          blocks[i - 1]['type'] == 'text') {
                                        final prevText =
                                            (blocks[i - 1]['content'] ?? '').trim();
                                        if (prevText.isEmpty)
                                          blocks.removeAt(i - 1);
                                      }

                                      _safeSave(widget.note);
                                    });
                                  },
                                ),
                              ),

                            // 🔍 Fullscreen icon — visible only when NOT editing
                            if (!isEditingDescription)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton(
                                  icon: const Icon(Icons.fullscreen,
                                      color: Colors.white70, size: 24),
                                  onPressed: () => _openFullScreenImage(file),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF4B0082),
        onPressed: () {
          widget.note.title = titleController.text.trim();
          widget.note.lastModified = DateTime.now(); // 🕒 update timestamp
          _safeSave(widget.note);
          widget.note.save(); // 💾 ensure Hive writes the change

          setState(() {
            isEditingTitle = false;
            isEditingDescription = false;
            selectedBlockIndex = null;
            selectedStart = null;
            selectedEnd = null;
            selectedText = null;
          });

          if (Navigator.canPop(context)) {
            Navigator.pop(context, widget.note);
          }
        },
        child: const Icon(Icons.check, color: Colors.white54),
      ),
    );
  }

  bool _shouldShowHintForBlock(int index) {
    // Show "Description…" only if:
    // 1️⃣ It's the very first text block,
    // 2️⃣ AND the note is empty or no other non-empty text exists before it.
    if (index == 0) return blocks[index]['content'].toString().trim().isEmpty;

    // 🧠 Never show hint for text blocks after an image or any other text
    final prev = index > 0 ? blocks[index - 1] : null;
    if (prev == null) return false;
    if (prev['type'] == 'image') return false;

    // Only show if all previous text blocks are empty
    for (int i = 0; i < index; i++) {
      if (blocks[i]['type'] == 'text' &&
          (blocks[i]['content']?.toString().trim().isNotEmpty ?? false)) {
        return false;
      }
    }
    return blocks[index]['content'].toString().trim().isEmpty;
  }




  void _openFullScreenImage(File file) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close fullscreen image',
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            clipBehavior: Clip.none,
            children: [
              // 🖼 Allow full zoom overflow
              InteractiveViewer(
                panEnabled: true,
                minScale: 1.0,
                maxScale: 5.0,
                clipBehavior: Clip.none,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Image.file(file),
                  ),
                ),
              ),
              // 🔘 Exit fullscreen button
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<InlineSpan> _buildHighlightedSpans(String text) {
    if (highlightQuery == null || highlightQuery!.isEmpty) {
      return [TextSpan(text: text, style: kBaseTextStyle)];
    }
    final lower = text.toLowerCase();
    final query = highlightQuery!;
    final spans = <InlineSpan>[];
    int start = 0;
    int idx;

    while ((idx = lower.indexOf(query, start)) != -1) {
      if (idx > start) {
        spans.add(TextSpan(
            text: text.substring(start, idx), style: kBaseTextStyle));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(
          color: Color(0xFF9B30FF),
          fontWeight: FontWeight.bold,
        ),
      ));
      start = idx + query.length;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: kBaseTextStyle));
    }
    return spans;
  }
}
