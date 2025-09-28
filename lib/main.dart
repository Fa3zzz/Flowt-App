import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:flutter/gestures.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';





part 'main.g.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(NoteAdapter());
  await Hive.openBox<Note>('notesBox_v2');

  final notesBox = Hive.box<Note>('notesBox_v2');
  await notesBox.clear();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
  Map<String, int> links;

  @HiveField(3)
  List<String> imagePaths;

  @HiveField(4)
  List<Map<String, dynamic>>? contentBlocks;

  Note({
  required this.title,
  this.description,
  Map<String, int>? links,
  this.imagePaths = const [],
  List<Map<String, dynamic>>? contentBlocks,
})  : links = links ?? {},
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
        // backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text("Flowt"),
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

class AddNotesScreen extends StatefulWidget {
  const AddNotesScreen({super.key});

  @override
  State<AddNotesScreen> createState() => _AddNotesScreenState();
}

class _AddNotesScreenState extends State<AddNotesScreen> {
  final titleController = TextEditingController();
  final scrollController = ScrollController();

  List<Map<String, dynamic>> blocks = [
    {"type": "text", "content": "", "controller": null}
  ];

  String? selectedText;
  final Map<String, int> links = {};

  @override
  void dispose() {
    titleController.dispose();
    for (final b in blocks) {
      if (b['type'] == 'text' && b['controller'] is TextEditingController) {
        (b['controller'] as TextEditingController).dispose();
      }
    }
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        // Add image block at end
        blocks.add({"type": "image", "path": pickedFile.path});
        // Followed by a new empty text block
        blocks.add({"type": "text", "content": "", "controller": null});
      });

      // Scroll to bottom
      await Future.delayed(const Duration(milliseconds: 200));
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
      builder: (context) => SafeArea(
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

  Future<void> _showLinkOptions(String selected) async {
    final notesBox = Hive.box<Note>('notesBox_v2');
    final existingLink = links[selected];

    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) {
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (existingLink == null) ...[
              ListTile(
                title: const Text("Link to existing note", style: TextStyle(color: Colors.white54)),
                onTap: () {
                  Navigator.pop(context);
                  _pickNoteToLink(selected);
                },
              ),
              ListTile(
                title: const Text("Create new linked note", style: TextStyle(color: Colors.white54)),
                onTap: () async {
                  Navigator.pop(context);
                  final newNote = Note(
                    title: selected,
                    description: "",
                    contentBlocks: [
                      {"type": "text", "content": ""}
                    ],
                    links: {},
                  );
                  final key = await notesBox.add(newNote);
                  setState(() {
                    links[selected] = key;
                  });
                },
              ),
            ] else ...[
              ListTile(
                title: const Text("Unlink", style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    links.remove(selected);
                  });
                },
              ),
            ]
          ]),
        );
      },
    );
  }

  void _pickNoteToLink(String selected) {
    final notesBox = Hive.box<Note>('notesBox_v2');
    final others = notesBox.values.toList();

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
                  itemBuilder: (context, i) {
                    final n = others[i];
                    return ListTile(
                      title: Text(n.title),
                      onTap: () {
                        setState(() {
                          links[selected] = n.key as int;
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
          else
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
              style: const TextStyle(color: Colors.white54),
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
                    if (sel.start != sel.end &&
                        sel.start >= 0 &&
                        sel.end <= c.text.length) {
                      final s = c.text.substring(sel.start, sel.end);
                      if (s.trim().isNotEmpty) {
                        if (selectedText != s) setState(() => selectedText = s);
                      }
                    } else {
                      if (selectedText != null) setState(() => selectedText = null);
                    }
                  });
                  b["controller"] = c;
                }
                final c = b["controller"] as TextEditingController;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: c,
                    style: const TextStyle(color: Colors.white54, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: index == 0 ? "Description……" : "",
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
                        onPressed: () {
                          setState(() {
                            blocks.removeAt(index);
                          });
                        },
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
              .map<String>((b) => b["path"] as String)
              .toList();
          final description = blocks
              .where((b) => b["type"] == "text")
              .map<String>((b) => (b["content"] ?? "") as String)
              .join("\n");

          final newNote = Note(
            title: titleController.text,
            description: description.isNotEmpty ? description : null,
            imagePaths: imagePaths,
            contentBlocks: blocks.map((b) {
              if (b['type'] == 'text') {
                return {
                  "type": "text",
                  "content": b["content"] ?? "",
                };
              }
              return b;
            }).toList(),
            links: links,
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
  const NoteDetailScreen({super.key, required this.note});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late TextEditingController titleController;
  bool isEditingTitle = false;
  bool isEditingDescription = false;
  String? selectedText;
  List<Map<String, dynamic>> blocks = [];

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.note.title);

    if (widget.note.contentBlocks != null &&
        widget.note.contentBlocks!.isNotEmpty) {
      // Deep copy
      blocks = widget.note.contentBlocks!
          .map((b) => Map<String, dynamic>.from(b))
          .toList();
    } else {
      blocks = [
        {"type": "text", "content": widget.note.description ?? ""}
      ];
      widget.note.contentBlocks = blocks;
      widget.note.save();
    }

    widget.note.links ??= {};

    // attach controllers (not stored)
    for (final b in blocks) {
      if (b['type'] == 'text') {
        final c = TextEditingController(text: (b['content'] ?? '') as String);
        c.addListener(() {
          b['content'] = c.text;

          // live update description
          widget.note.description = blocks
              .where((e) => e['type'] == 'text')
              .map((e) => (e['content'] ?? '') as String)
              .join("\n")
              .trim();

          final sel = c.selection;
          if (sel.start != sel.end &&
              sel.start >= 0 &&
              sel.end <= c.text.length) {
            final s = c.text.substring(sel.start, sel.end);
            if (s.trim().isNotEmpty) {
              if (selectedText != s) setState(() => selectedText = s);
            }
          } else {
            if (selectedText != null) setState(() => selectedText = null);
          }
        });
        b['controller'] = c;
      }
    }
  }

  @override
  void dispose() {
    for (final b in blocks) {
      if (b['type'] == 'text' && b['controller'] is TextEditingController) {
        (b['controller'] as TextEditingController).dispose();
      }
    }
    titleController.dispose();
    super.dispose();
  }

  /// 🧹 Helper: sanitize before saving to Hive
  List<Map<String, dynamic>> _sanitizeBlocks() {
    return blocks.map((b) {
      if (b['type'] == 'text') {
        return {
          'type': 'text',
          'content': (b['controller'] != null)
              ? (b['controller'] as TextEditingController).text
              : (b['content'] ?? ''),
        };
      }
      return b;
    }).toList();
  }

  void _safeSave(Note note) {
    final sanitized = _sanitizeBlocks();
    note.contentBlocks = sanitized;
    note.description = sanitized
        .where((b) => b['type'] == 'text')
        .map((b) => b['content'] ?? '')
        .join("\n")
        .trim();
    note.save();
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

  Future<void> _showLinkOptions(String selected) async {
    final notesBox = Hive.box<Note>('notesBox_v2');
    final existingLink = widget.note.links[selected];

    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (existingLink == null) ...[
            ListTile(
              title: const Text("Link to existing note",
                  style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.pop(context);
                _pickNoteToLink(selected);
              },
            ),
            ListTile(
              title: const Text("Create new linked note",
                  style: TextStyle(color: Colors.white54)),
              onTap: () async {
                Navigator.pop(context);

                // 🧹 sanitize before any save
                _safeSave(widget.note);

                final newNote = Note(
                  title: selected,
                  description: "",
                  contentBlocks: [
                    {"type": "text", "content": ""}
                  ],
                  links: {},
                );

                final key = await notesBox.add(newNote);
                setState(() {
                  widget.note.links[selected] = key;
                });

                // save sanitized parent again
                _safeSave(widget.note);

                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => NoteDetailScreen(note: newNote)),
                );
              },
            ),
          ] else ...[
            ListTile(
              title: const Text("Unlink",
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  widget.note.links.remove(selected);
                });
                _safeSave(widget.note);
              },
            ),
          ]
        ]),
      ),
    );
  }

  void _pickNoteToLink(String selected) {
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
                  itemBuilder: (context, i) {
                    final n = others[i];
                    return ListTile(
                      title: Text(n.title),
                      onTap: () {
                        setState(() {
                          widget.note.links[selected] = n.key as int;
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

  List<InlineSpan> _buildDescriptionSpans(String text) {
    final spans = <InlineSpan>[];
    int start = 0;
    final occurrences = <MapEntry<int, String>>[];

    widget.note.links.forEach((snippet, _) {
      if (snippet.isEmpty) return;
      int from = 0;
      while (true) {
        final idx = text.indexOf(snippet, from);
        if (idx == -1) break;
        occurrences.add(MapEntry(idx, snippet));
        from = idx + snippet.length;
      }
    });

    occurrences.sort((a, b) => a.key.compareTo(b.key));

    for (final occ in occurrences) {
      final index = occ.key;
      final snippet = occ.value;
      if (index < start) continue;

      if (index > start) {
        spans.add(TextSpan(
          text: text.substring(start, index),
          style: const TextStyle(color: Colors.white54),
        ));
      }

      final noteId = widget.note.links[snippet];
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () {
              final target = Hive.box<Note>('notesBox_v2').get(noteId);
              if (target != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => NoteDetailScreen(note: target)),
                );
              }
            },
            onLongPress: () async => await _showLinkOptions(snippet),
            child: Text(
              snippet,
              style: const TextStyle(
                color: Color(0xFF9B30FF),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      );

      start = index + snippet.length;
    }

    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: const TextStyle(color: Colors.white54),
      ));
    }

    return spans.isEmpty
        ? [TextSpan(text: text, style: const TextStyle(color: Colors.white54))]
        : spans;
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
                style: const TextStyle(color: Colors.white),
                onSubmitted: (_) => setState(() => isEditingTitle = false),
              )
            : GestureDetector(
                onTap: () => setState(() => isEditingTitle = true),
                child: Text(widget.note.title),
              ),
        actions: [
          if (selectedText != null)
            IconButton(
              icon: const Icon(Icons.link, color: Colors.white54),
              onPressed: () async => await _showLinkOptions(selectedText!),
            ),
          IconButton(
            icon: Icon(isEditingDescription ? Icons.close : Icons.edit,
                color: Colors.white54),
            onPressed: () =>
                setState(() => isEditingDescription = !isEditingDescription),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: blocks.length,
        itemBuilder: (context, index) {
          final b = blocks[index];
          if (b['type'] == 'text') {
            final c = b['controller'] as TextEditingController;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: isEditingDescription
                  ? TextField(
                      controller: c,
                      maxLines: null,
                      style: const TextStyle(color: Colors.white54, fontSize: 16),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "Description……",
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                    )
                  : SelectableText.rich(
                      TextSpan(children: _buildDescriptionSpans(b['content'] ?? '')),
                      style: const TextStyle(color: Colors.white54, fontSize: 16),
                      onSelectionChanged: (sel, cause) {
                        final text = (b['content'] ?? '') as String;
                        if (sel.start != sel.end &&
                            sel.start >= 0 &&
                            sel.end <= text.length) {
                          final s = text.substring(sel.start, sel.end);
                          setState(() => selectedText = s);
                        } else {
                          setState(() => selectedText = null);
                        }
                      },
                    ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF4B0082),
        onPressed: () {
          widget.note.title = titleController.text;
          _safeSave(widget.note);
          setState(() => isEditingDescription = false);
          Navigator.pop(context, widget.note);
        },
        child: const Icon(Icons.check, color: Colors.white54),
      ),
    );
  }
}


