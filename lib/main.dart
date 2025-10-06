import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart'; // ✅ this goes before the part

part 'main.g.dart'; // ✅ this must be last


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
  await Hive.openBox<Note>('notesBox_v2');

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF4B0082),
          foregroundColor: Colors.white54,
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

  Note({
    required this.title,
    this.description,
    List<Map<String, String>>? links,
    this.imagePaths = const [],
    List<Map<String, String>>? contentBlocks,
  })  : links = List<Map<String, String>>.from(links ?? []),
        contentBlocks = contentBlocks ?? [];
}



class NotesHome extends StatefulWidget {
  const NotesHome({super.key});

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  final notesBox = Hive.box<Note>('notesBox_v2');

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
              child: Text("No notes yet",
                  style: TextStyle(color: Colors.white54, fontSize: 18)),
            );
          }

          return ListView.builder(
            itemCount: box.length,
            itemBuilder: (context, index) {
              final note = box.getAt(index)!;

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
                  margin:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  color: Colors.grey[900],
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    title: Text(
                      note.title,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
        // find a snippet containing the word
        final idx = desc.indexOf(lower);
        if (idx != -1) {
          // capture sentence snippet around it
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

    // Prioritize title matches, then by relevance
    matches.sort((a, b) {
      if (a["matchType"] == "title" && b["matchType"] != "title") return -1;
      if (a["matchType"] != "title" && b["matchType"] == "title") return 1;
      return a["context"].toString().compareTo(b["context"].toString());
    });

    setState(() => results = matches);
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

                // build highlight span
                final lower = contextText.toLowerCase();
                final idx = lower.indexOf(highlight.toLowerCase());

                InlineSpan textSpan;
                if (idx != -1) {
                  textSpan = TextSpan(children: [
                    TextSpan(
                        text: contextText.substring(0, idx),
                        style: const TextStyle(color: Colors.white54)),
                    TextSpan(
                        text: contextText.substring(idx, idx + highlight.length),
                        style: const TextStyle(
                            color: Color(0xFF9B30FF),
                            fontWeight: FontWeight.bold)),
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
    if (pickedFile != null) {
      setState(() {
        // add image + empty text (both with ids)
        blocks.add({"id": _uuid.v4(), "type": "image", "path": pickedFile.path});
        blocks.add({"id": _uuid.v4(), "type": "text", "content": "", "controller": null});
      });

      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
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
    final blockId = selectedBlockId ?? (blocks[selectedBlockIndex!]["id"] ??= _uuid.v4()).toString();

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
                        if (selectedBlockIndex == null) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Select text to link')));
                          return;
                        }
                        setState(() {
                          links.add({
                            "id": _uuid.v4(),
                            "text": selected,
                            "noteId": n.key.toString(),
                            "block": blockId,
                            "start": s.toString(),
                            "end": e.toString(),
                          });
                        });
                        Navigator.pop(context);
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
            ...blocks.asMap().entries.map((entry) {
              final index = entry.key;
              final b = entry.value;

              if (b["type"] == "text") {
                if (b["controller"] == null) {
                  final c = TextEditingController(text: b["content"] ?? "");
                  c.addListener(() {
                    b["content"] = c.text;
                    final sel = c.selection;
                    if (sel.start != sel.end && sel.start >= 0 && sel.end <= c.text.length) {
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
                          child: Image.file(file, width: double.infinity, fit: BoxFit.cover),
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
            final id = (b['id'] ??= _uuid.v4()).toString();
            final type = (b['type'] ?? '').toString();
            if (type == 'text') {
              return {"id": id, "type": "text", "content": (b["content"] ?? "").toString()};
            } else if (type == 'image') {
              return {"id": id, "type": "image", "path": (b["path"] ?? "").toString()};
            }
            return {"id": id, "type": "text", "content": ""};
          }).toList();

          final description = contentBlocks
              .where((b) => b["type"] == "text")
              .map((b) => b["content"] ?? "")
              .join("\n");

          final cleanLinks = links
              .where((l) => l.containsKey("block") && l.containsKey("start") && l.containsKey("end"))
              .toList();

          final newNote = Note(
            title: titleController.text,
            description: description.isNotEmpty ? description : null,
            imagePaths: imagePaths,
            contentBlocks: contentBlocks,
            links: cleanLinks.cast<Map<String, String>>(),
          );

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

    // Legacy map links → list of maps (kept as strings)
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

    if (highlightQuery != null && highlightQuery!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final scrollable = Scrollable.of(context);
        scrollable?.position.animateTo(
          200, // tweak offset to match first match
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      });
    }

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
        // 🔹 Update the active block when user focuses/taps inside it
        setState(() {
          selectedBlockIndex = blocks.indexOf(b);
        });
      } else {
        // 🔹 Clear selection only if user leaves this block
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
      b['content'] = c.text;
      widget.note.description = blocks
          .where((e) => e['type'] == 'text')
          .map((e) => (e['content'] ?? '') as String)
          .join("\n");

      // Track selection live
      if (isEditingDescription && f.hasFocus) {
        final sel = c.selection;
        if (sel.start != sel.end &&
            sel.start >= 0 &&
            sel.end <= c.text.length) {
          final (s, e) = _normalizedRange(c.text, sel.start, sel.end);
          if (e > s) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                selectedText = c.text.substring(s, e);
                selectedBlockIndex = blocks.indexOf(b);
                selectedStart = s;
                selectedEnd = e;
              });
            });
          }
        } else {
          if (selectedText != null &&
              selectedBlockIndex == blocks.indexOf(b)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                selectedText = null;
                selectedStart = null;
                selectedEnd = null;
              });
            });
          }
        }
      }
    });
  }



  void _attachControllers() {
    for (final b in blocks) {
      if (b['type'] == 'text') {
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
    return blocks.map((b) {
      final type = (b['type'] ?? 'text').toString();
      final id = b['id']?.toString() ?? const Uuid().v4();

      if (type == 'text') {
        final txt = (b['controller'] is TextEditingController)
            ? (b['controller'] as TextEditingController).text
            : (b['content'] ?? '').toString();
        return {"id": id, "type": "text", "content": txt};
      } else if (type == 'image') {
        return {"id": id, "type": "image", "path": (b['path'] ?? '').toString()};
      }
      return {"id": id, "type": "text", "content": ""};
    }).toList();
  }


  void _safeSave(Note note) {
    final sanitized = _sanitizeBlocks();
    note.contentBlocks = sanitized;
    note.description = sanitized
        .where((b) => b['type'] == 'text')
        .map((b) => b['content'] ?? '')
        .join("\n");

    // ✅ Deep-copy links BEFORE clearing so we don't clear the source we're copying from
    final List<Map<String, String>> linksCopy = widget.note.links
        .map((l) => Map<String, String>.from(l))
        .toList();

    note.links
      ..clear()
      ..addAll(linksCopy);

    note.save();
  }




  // ---------- Image insertion ----------


  Future<void> _pickImage(ImageSource source) async {
    // ensure there's a text block target (same logic you had)
    if (selectedBlockIndex == null) {
      final idx = blocks.indexWhere((b) => (b['type'] ?? 'text') == 'text');
      if (idx != -1) {
        setState(() => selectedBlockIndex = idx);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No text box available to attach image.')),
        );
        return;
      }
    }

    final picker = ImagePicker();

    Future<XFile?> tryPick() async {
      try {
        return await picker.pickImage(source: source);
      } on PlatformException catch (e) {
        debugPrint('pickImage error: ${e.code} ${e.message}');
        return null;
      }
    }

    // 1) Try the picker first (lets iOS/Android drive permission flow)
    XFile? picked = await tryPick();

    // 2) If the picker couldn’t open/return a file, request minimal permission and retry once
    if (picked == null) {
      if (Platform.isIOS) {
        if (source == ImageSource.camera) {
          await Permission.camera.request();
        } else {
          // Limited access is fine for picking
          await Permission.photos.request();
        }
      } else if (Platform.isAndroid) {
        if (source == ImageSource.camera) {
          await Permission.camera.request();
        } else {
          // On Android 13+ this usually isn’t required for picker, but request just in case
          await Permission.storage.request();
        }
      }

      picked = await tryPick();
      if (picked == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission denied')),
        );
        return;
      }
    }

    // 3) Insert image + new text block (your existing behavior)
    setState(() {
      int insertAt;
      if (selectedBlockIndex != null &&
          selectedBlockIndex! >= 0 &&
          selectedBlockIndex! < blocks.length) {
        insertAt = selectedBlockIndex! + 1;
      } else {
        insertAt = blocks.length; // 👈 append at end if nothing selected
      }

      blocks.insert(insertAt, {"type": "image", "path": picked!.path});
      blocks.insert(insertAt + 1, {
        "type": "text",
        "content": "",
        "controller": TextEditingController(),
        "focusNode": FocusNode(),
        "_wired": true,
      });
    });

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
    final lower = text.toLowerCase();
    final query = highlightQuery?.toLowerCase() ?? '';

    final ranges = _rangesForBlock(text, blockIndex);

    void addNormalSpan(String chunk) {
      if (query.isNotEmpty && chunk.toLowerCase().contains(query)) {
        int start = 0, idx;
        while ((idx = chunk.toLowerCase().indexOf(query, start)) != -1) {
          if (idx > start) {
            spans.add(TextSpan(
                text: chunk.substring(start, idx),
                style: const TextStyle(color: Colors.white54, fontSize: 16)));
          }
          spans.add(TextSpan(
            text: chunk.substring(idx, idx + query.length),
            style: const TextStyle(
              color: Color(0xFF9B30FF),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ));
          start = idx + query.length;
        }
        if (start < chunk.length) {
          spans.add(TextSpan(
              text: chunk.substring(start),
              style: const TextStyle(color: Colors.white54, fontSize: 16)));
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

      if (rStart > cursor) {
        addNormalSpan(text.substring(cursor, rStart));
      }

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

    if (cursor < text.length) {
      addNormalSpan(text.substring(cursor));
    }

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
    final others =
        notesBox.values.where((n) => n.key != widget.note.key).toList();

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
                            "block": "$selectedBlockIndex",
                            "start": "$s",
                            "end": "$e",
                          });
                        });
                        _safeSave(widget.note);
                        Navigator.pop(context);
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

      int firstTextIndex = blocks.indexWhere((b) => (b['type'] ?? 'text') == 'text');
      if (firstTextIndex == -1) {
        final nb = {
          "type": "text",
          "content": "",
          "controller": TextEditingController(),
          "focusNode": FocusNode(),
        };
        _wireTextBlock(nb);
        blocks.add(nb);
        firstTextIndex = blocks.length - 1;
        _safeSave(widget.note);
      } else {
        _wireTextBlock(blocks[firstTextIndex]);
      }

      // ✅ Always select the first text block
      selectedBlockIndex = firstTextIndex;

      // ✅ Explicitly set focus and selection
      final f = blocks[firstTextIndex]['focusNode'] as FocusNode?;
      final c = blocks[firstTextIndex]['controller'] as TextEditingController?;
      f?.requestFocus();
      c?.selection = TextSelection.collapsed(offset: c.text.length);
    });

    // ✅ Also schedule a post-frame safety check
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (selectedBlockIndex == null && blocks.isNotEmpty) {
          final fallback = blocks.indexWhere((b) => b['type'] == 'text');
          if (fallback != -1) {
            setState(() => selectedBlockIndex = fallback);
          }
        }
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
                    widget.note.title = titleController.text;
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
                        if (sel.start != sel.end &&
                            sel.start >= 0 &&
                            sel.end <= text.length) {
                          final (s, e) = _normalizedRange(text, sel.start, sel.end);
                          setState(() {
                            selectedText = text.substring(s, e);
                            selectedBlockIndex = i;
                            selectedStart = s;
                            selectedEnd = e;
                          });
                        } else {
                          setState(() {
                            selectedText = null;
                            selectedStart = null;
                            selectedEnd = null;
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
                          icon: const Icon(Icons.close, color: Colors.red, size: 22),
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
                          icon: const Icon(Icons.fullscreen, color: Colors.white70, size: 24),
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
          _safeSave(widget.note);
          setState(() {
            isEditingTitle = false;
            isEditingDescription = false;
            selectedBlockIndex = null;
            selectedStart = null;
            selectedEnd = null;
            selectedText = null;
          });
          if(Navigator.canPop(context)){
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
