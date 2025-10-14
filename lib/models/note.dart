import 'package:hive/hive.dart';

part 'note.g.dart';

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
