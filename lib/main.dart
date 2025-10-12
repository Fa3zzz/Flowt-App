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

          // ✅ Sort notes by last modified (newest first)
          final notes = box.values.toList()
            ..sort((a, b) => b.lastModified.compareTo(a.lastModified));

          // ✅ Group notes by date
          final Map<String, List<Note>> groupedNotes = {};
          for (var note in notes) {
            final noteDate = note.lastModified;
            final now = DateTime.now();
            final diff = now.difference(noteDate).inDays;

            String label;
            if (diff == 0 &&
                noteDate.day == now.day &&
                noteDate.month == now.month &&
                noteDate.year == now.year) {
              label = "Today";
            } else if (diff == 1 ||
                (now.day - noteDate.day == 1 &&
                    now.month == noteDate.month &&
                    now.year == noteDate.year)) {
              label = "Yesterday";
            } else {
              label = "${noteDate.day} ${_monthNameList[noteDate.month - 1]}, ${noteDate.year}";
            }

            groupedNotes.putIfAbsent(label, () => []).add(note);
          }

          // ✅ Build sectioned list
          // ✅ Sort section keys by recency (Today → Yesterday → older dates)
          final orderedSections = groupedNotes.entries.toList()
            ..sort((a, b) {
              DateTime parseLabel(String label) {
                if (label == "Today") return DateTime.now();
                if (label == "Yesterday") return DateTime.now().subtract(const Duration(days: 1));
                final parts = label.replaceAll(',', '').split(' ');
                final day = int.parse(parts[0]);
                final month = _monthNameList.indexOf(parts[1]) + 1;
                final year = int.parse(parts[2]);
                return DateTime(year, month, day);
              }

              return parseLabel(b.key).compareTo(parseLabel(a.key));
            });

          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: orderedSections.map((entry) {
              final sectionTitle = entry.key;
              final sectionNotes = entry.value;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      sectionTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  ...sectionNotes.map((note) {
                    return Dismissible(
                      key: Key(note.key.toString()),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => note.delete(),
                      child: Card(
                        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                        color: Colors.grey[900],
                        elevation: 2,
                        shadowColor: Colors.deepPurple.withOpacity(0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          title: Text(
                            note.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: note.description != null && note.description!.isNotEmpty
                              ? Text(
                                  note.description!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white38),
                                )
                              : null,
                          onTap: () async {
                            final updatedNote = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => NoteDetailScreen(note: note),
                              ),
                            );

                            if (updatedNote != null) {
                              note.title = updatedNote.title;
                              note.description = updatedNote.description;
                              note.save();
                            }
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ],
              );
            }).toList(),
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
        child: const Icon(
          Icons.add,
          color: Colors.white54,
        )
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

      if (title.contains(lower)) {
        matches.add({
          "note": note,
          "matchType": "title",
          "highlight": query,
          "context": note.title,
        });
      } else if (desc.contains(lower)) {
        final idx = desc.indexOf(lower);
        if (idx != -1) {
          final full = note.description!;
          int start = full.lastIndexOf('.', idx) + 1;
          if (start < 0) start = 0;
          int end = full.indexOf('.', idx);
          if (end == -1) end = full.length;
          final snippet = full.substring(start, end).trim();

          matches.add({
            "note": note,
            "matchType": "description",
            "highlight": query,
            "context": snippet,
          });
        }
      }
    }

    matches.sort((a, b) {
      if (a["matchType"] == "title" && b["matchType"] != "title") return -1;
      if (a["matchType"] != "title" && b["matchType"] == "title") return 1;
      return a["context"].toString().compareTo(b["context"].toString());
    });

    setState(() {
      results = matches;
      fadedHighlight = null; // reset fade timer
    });

    // After 3 seconds, remove highlight color but keep text
    if (query.isNotEmpty) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && searchController.text == query) {
          setState(() {
            fadedHighlight = query; // trigger fade for this query
          });
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
                  final isFaded = fadedHighlight == highlight;
                  textSpan = TextSpan(children: [
                    TextSpan(
                        text: contextText.substring(0, idx),
                        style: const TextStyle(color: Colors.white54)),
                    TextSpan(
                      text: contextText.substring(idx, idx + highlight.length),
                      style: TextStyle(
                        color: isFaded
                            ? Colors.white54 // normal text after fade
                            : const Color(0xFF9B30FF), // highlight color
                        fontWeight:
                            isFaded ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                        text: contextText.substring(idx + highlight.length),
                        style: const TextStyle(color: Colors.white54)),
                  ]);
                } else {
                  textSpan = TextSpan(
                      text: contextText,
                      style: const TextStyle(color: Colors.white54));
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
    final newPath =
        '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final newFile = File(newPath);

    // 🔹 Read + write bytes instead of copy() (fixes iOS camera temp issue)
    final bytes = await pickedFile.readAsBytes();
    await newFile.writeAsBytes(bytes);
    await Future.delayed(const Duration(milliseconds: 100)); // allow fs sync

    int insertAt = blocks.length; // default append
    String? afterText = "";

    // 🔍 Find focused text block
    if (selectedBlockIndex != null &&
        selectedBlockIndex! >= 0 &&
        selectedBlockIndex! < blocks.length) {
      final b = blocks[selectedBlockIndex!];
      if (b['type'] == 'text' && b['controller'] is TextEditingController) {
        final ctrl = b['controller'] as TextEditingController;
        final text = ctrl.text;
        final cursor = ctrl.selection.baseOffset;

        if (cursor >= 0 && cursor <= text.length) {
          // find next line boundary
          int nextLineBreak = text.indexOf('\n', cursor);
          if (nextLineBreak == -1) nextLineBreak = text.length;

          final before = text.substring(0, nextLineBreak).trimRight();
          afterText = text.substring(nextLineBreak).trimLeft();

          // update current block content
          ctrl.text = before;
          b['content'] = before;

          insertAt = selectedBlockIndex! + 1;
        }
      }
    }

    setState(() {
      // 🖼️ Insert image using the permanent saved path
      blocks.insert(insertAt, {
        "id": _uuid.v4(),
        "type": "image",
        "path": newFile.path,
      });

      // 🧱 Insert a text block after image (so user can type below)
      final newController = TextEditingController(text: afterText ?? "");
      newController.addListener(() {
        final idx = blocks.indexWhere((x) => x["controller"] == newController);
        if (idx != -1) {
          blocks[idx]["content"] = newController.text;
        }
      });

      blocks.insert(insertAt + 1, {
        "id": _uuid.v4(),
        "type": "text",
        "content": afterText ?? "",
        "controller": newController,
      });
    });

    // 🔽 Smooth scroll to bring the new image into view
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
            TextField(
              controller: titleController,
              focusNode: titleFocus,
              style: kBaseTextStyle,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[900],
                hintText: "Title",
                border: const OutlineInputBorder(),
                hintStyle: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),

            // --- note blocks ---
            ...blocks.asMap().entries.map((entry) {
              final index = entry.key;
              final b = entry.value;

              if (b["type"] == "text") {
                if (b["controller"] == null) {
                  final c = TextEditingController(text: b["content"] ?? "");
                  c.addListener(() {
                    b["content"] = c.text;
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
                }

                final c = b["controller"] as TextEditingController;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: c,
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
  const NoteDetailScreen({super.key, required this.note, this.highlightQuery});

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

    // 👇 Handle fade + scroll only once
    if (highlightQuery != null && highlightQuery!.isNotEmpty) {
      // ✅ Run scroll after the frame, safely inside ListView’s build context
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final primaryScrollController = PrimaryScrollController.of(context);
        if (primaryScrollController.hasClients) {
          primaryScrollController.animateTo(
            200,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
          );
        }
      });

      // ✅ Fade only the color (not remove the text)
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

    // Legacy map links → list of maps
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

    // 🗂️ Persist image safely for both camera & gallery
    final dir = await getApplicationDocumentsDirectory();
    final fileExt = picked.path.split('.').last;
    final newPath = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final newFile = File(newPath);

    try {
      final bytes = await picked.readAsBytes();
      await newFile.writeAsBytes(bytes);
    } catch (_) {
      return;
    }

    await Future.delayed(const Duration(milliseconds: 200));

    // 🧩 Ensure there’s at least one valid text block
    if (blocks.isEmpty) {
      final newTextBlock = {
        "id": const Uuid().v4(),
        "type": "text",
        "content": "",
        "controller": TextEditingController(),
        "focusNode": FocusNode(),
        "_wired": false,
      };
      _wireTextBlock(newTextBlock);
      setState(() {
        blocks.add(newTextBlock);
        selectedBlockIndex = 0;
      });
    }

    // 🧠 Ensure we target a valid text block
    if (selectedBlockIndex == null ||
        selectedBlockIndex! < 0 ||
        selectedBlockIndex! >= blocks.length ||
        blocks[selectedBlockIndex!]['type'] != 'text') {
      selectedBlockIndex = blocks.lastIndexWhere((b) => b['type'] == 'text');
      if (selectedBlockIndex == -1) {
        final newTextBlock = {
          "id": const Uuid().v4(),
          "type": "text",
          "content": "",
          "controller": TextEditingController(),
          "focusNode": FocusNode(),
          "_wired": false,
        };
        _wireTextBlock(newTextBlock);
        setState(() {
          blocks.add(newTextBlock);
          selectedBlockIndex = blocks.length - 1;
        });
      }
    }

    if (selectedBlockIndex == null ||
        selectedBlockIndex! < 0 ||
        selectedBlockIndex! >= blocks.length) return;

    final block = blocks[selectedBlockIndex!];
    int insertAt = selectedBlockIndex! + 1;
    String? afterText = "";

    // 🧩 Split text if caret exists
    if (block['type'] == 'text' &&
        block['controller'] is TextEditingController) {
      final ctrl = block['controller'] as TextEditingController;
      final text = ctrl.text;
      final caret = ctrl.selection.baseOffset.clamp(0, text.length);
      afterText = text.substring(caret);
      ctrl.text = text.substring(0, caret);
      block['content'] = ctrl.text;
    }

    setState(() {
      // 🖼️ Insert image (don't immediately save)
      blocks.insert(insertAt, {
        "id": const Uuid().v4(),
        "type": "image",
        "path": newFile.path,
      });

      // 🧱 Add editable block after image
      final newTextBlock = {
        "id": const Uuid().v4(),
        "type": "text",
        "content": afterText ?? "",
        "controller": TextEditingController(text: afterText ?? ""),
        "focusNode": FocusNode(),
        "_wired": false,
      };
      blocks.insert(insertAt + 1, newTextBlock);
      _wireTextBlock(newTextBlock);
    });

    // ✅ Delay save a bit for camera write completion
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    _safeSave(widget.note);
  }






  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white54),
              title: const Text(
                "Take Photo",
                style: TextStyle(color: Colors.white54),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo, color: Colors.white54),
              title: const Text(
                "Choose from Gallery",
                style: TextStyle(color: Colors.white54),
              ),
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
            onTap: () {
              final id = int.tryParse(noteIdStr);
              if (id != null) {
                final target = Hive.box<Note>('notesBox_v2').get(id);
                if (target != null) {
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
              setState(() {
                selectedText = slice;
                selectedBlockIndex = blockIndex;
                selectedStart = rStart;
                selectedEnd = rEnd;
              });
              await _showLinkOptions(slice, presetLinkId: linkId);
            },
            child: Text(
              slice,
              style: const TextStyle(
                color: Color(0xFF9B30FF),
                decoration: TextDecoration.underline,
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
    if (selectedBlockIndex == null || selectedStart == null || selectedEnd == null) {
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
        if (selectedText != null)
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
    body: ListView.builder(
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
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: "Description…",
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                    onTap: () => setState(() => selectedBlockIndex = i),
                  )
                : SelectableText.rich(
                    TextSpan(
                      children: _buildDescriptionSpans(b['content'] ?? '', i),
                    ),
                    style: const TextStyle(color: Colors.white54, fontSize: 16),
                    onSelectionChanged: (sel, cause) {
                      final text = (b['content'] ?? '') as String;

                      // Always remember which block was interacted with
                      selectedBlockIndex = i;
                      _lastBlockIdForLink = (b['id']?.toString() ?? '');

                      if (sel.start == sel.end) {
                        // 🧭 collapsed caret (single tap)
                        setState(() {
                          selectedText = null;
                          selectedStart = sel.baseOffset;
                          selectedEnd = sel.baseOffset;
                          _viewCaretOffset = sel.baseOffset;
                        });
                      } else {
                        // 📏 actual selection
                        final (s, e) = _normalizedRange(text, sel.start, sel.end);
                        setState(() {
                          selectedText = text.substring(s, e);
                          selectedStart = s;
                          selectedEnd = e;
                          _viewCaretOffset = e; // caret after selection
                        });
                      }
                    },
                  ),

          );
        } else if (b['type'] == 'image') {
          final file = File(b['path']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    file,
                    width: double.infinity,
                    fit: BoxFit.cover,
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
                          blocks.removeAt(i);
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
          );
        }
        return const SizedBox.shrink();
      },
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
