import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../utils/constants.dart';


class NoteDetailScreen extends StatefulWidget {
  final Note note;
  final String? highlightQuery;
  final int? matchGlobalOffset; 
  const NoteDetailScreen({
    super.key,
    required this.note, 
    this.highlightQuery, 
    this.matchGlobalOffset,
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
  int? _highlightBlockIndex;
  int? _highlightLocalOffset;

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
    highlightQuery = widget.highlightQuery;

    _detailScrollController = ScrollController();

    // ✅ Load or fallback blocks first
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

    // 🧠 Legacy link migration (unchanged)
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

    // 🎯 Resolve which block & offset contain the match (for precise highlight)
    if (widget.matchGlobalOffset != null) {
      final global = widget.matchGlobalOffset!;
      int running = 0;
      _highlightBlockIndex = null;
      _highlightLocalOffset = null;

      for (int bi = 0; bi < widget.note.contentBlocks.length; bi++) {
        final block = widget.note.contentBlocks[bi];
        if (block['type'] == 'text') {
          final text = (block['content'] ?? '').toString();
          final len = text.length;

          if (global >= running && global < running + len) {
            _highlightBlockIndex = bi;
            _highlightLocalOffset = global - running;
            break;
          }

          // account for '\n' separator used when joining description
          running += len + 1;
        }
      }
    }

    // 🌀 Scroll directly to the block that holds the match
    if (highlightQuery != null && highlightQuery!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_detailScrollController.hasClients) {
          final offset = (_highlightBlockIndex != null)
              ? (_highlightBlockIndex! * 72.0)
                  .clamp(0.0, _detailScrollController.position.maxScrollExtent)
              : 200.0;

          _detailScrollController.animateTo(
            offset,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
          );
        }
      });
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

    // 🧠 Use resolved highlight data from initState()
    final highlightBlock = _highlightBlockIndex;
    final highlightLocalOffset = _highlightLocalOffset ?? -1;

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
      if (query.isNotEmpty && chunk.toLowerCase().contains(query.toLowerCase())) {
        int start = 0, idx;
        while ((idx = chunk.toLowerCase().indexOf(query.toLowerCase(), start)) != -1) {
          if (idx > start) {
            spans.add(TextSpan(
              text: chunk.substring(start, idx),
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ));
          }

          // 🎯 Highlight only the one match that was clicked from search
          final absoluteStartInBlock = cursor + idx;
          final absoluteEndInBlock = absoluteStartInBlock + query.length;
          final bool shouldHighlightThisOne =
              (highlightBlock == blockIndex) &&
              (highlightLocalOffset >= absoluteStartInBlock &&
              highlightLocalOffset < absoluteEndInBlock);

          if (shouldHighlightThisOne) {
            final bgPaint = Paint()
              ..color = const Color(0xFF9B30FF).withOpacity(0.4)
              ..style = PaintingStyle.fill;

            spans.add(TextSpan(
              text: chunk.substring(idx, idx + query.length),
              style: TextStyle(
                color: Colors.white,
                background: bgPaint,
                fontWeight: FontWeight.w600,
                fontSize: 16,
                height: 1.4,
              ),
            ));
          } else {
            spans.add(TextSpan(
              text: chunk.substring(idx, idx + query.length),
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ));
          }

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
