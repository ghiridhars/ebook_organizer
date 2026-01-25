import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as path;

/// Service for reading and writing EPUB metadata
class EpubMetadataService {
  static final EpubMetadataService instance = EpubMetadataService._();
  EpubMetadataService._();

  /// EPUB metadata model
  static const String dcNamespace = 'http://purl.org/dc/elements/1.1/';
  static const String opfNamespace = 'http://www.idpf.org/2007/opf';

  /// Read metadata from an EPUB file
  Future<EpubMetadata?> readMetadata(String epubPath) async {
    try {
      final file = File(epubPath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find the OPF file path from container.xml
      final opfPath = _findOpfPath(archive);
      if (opfPath == null) return null;

      // Read and parse the OPF file
      final opfFile = archive.findFile(opfPath);
      if (opfFile == null) return null;

      final opfContent = String.fromCharCodes(opfFile.content as List<int>);
      final document = XmlDocument.parse(opfContent);

      return _parseMetadata(document);
    } catch (e) {
      print('Error reading EPUB metadata: $e');
      return null;
    }
  }

  /// Write metadata to an EPUB file
  Future<bool> writeMetadata(String epubPath, EpubMetadata metadata) async {
    try {
      final file = File(epubPath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find the OPF file path
      final opfPath = _findOpfPath(archive);
      if (opfPath == null) return false;

      // Find and parse the OPF file
      final opfFileIndex = archive.files.indexWhere((f) => f.name == opfPath);
      if (opfFileIndex == -1) return false;

      final opfFile = archive.files[opfFileIndex];
      final opfContent = String.fromCharCodes(opfFile.content as List<int>);
      final document = XmlDocument.parse(opfContent);

      // Update the metadata in the document
      _updateMetadata(document, metadata);

      // Create new archive with updated OPF
      final newArchive = Archive();
      for (final archiveFile in archive.files) {
        if (archiveFile.name == opfPath) {
          // Replace with updated OPF content
          final newOpfContent = document.toXmlString(pretty: true, indent: '  ');
          final newOpfBytes = newOpfContent.codeUnits;
          newArchive.addFile(ArchiveFile(
            opfPath,
            newOpfBytes.length,
            newOpfBytes,
          ));
        } else {
          // Keep other files unchanged
          newArchive.addFile(archiveFile);
        }
      }

      // Create backup before writing
      final backupPath = '$epubPath.backup';
      await file.copy(backupPath);

      // Write the new EPUB
      final newBytes = ZipEncoder().encode(newArchive);
      if (newBytes == null) {
        return false;
      }
      await file.writeAsBytes(newBytes);

      // Remove backup on success
      await File(backupPath).delete();

      return true;
    } catch (e) {
      print('Error writing EPUB metadata: $e');
      // Try to restore backup if it exists
      final backupFile = File('$epubPath.backup');
      if (await backupFile.exists()) {
        await backupFile.copy(epubPath);
        await backupFile.delete();
      }
      return false;
    }
  }

  /// Find the OPF file path from container.xml
  String? _findOpfPath(Archive archive) {
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) return null;

    try {
      final containerContent = String.fromCharCodes(containerFile.content as List<int>);
      final document = XmlDocument.parse(containerContent);

      // Find rootfile element with media-type="application/oebps-package+xml"
      final rootfiles = document.findAllElements('rootfile');
      for (final rootfile in rootfiles) {
        final mediaType = rootfile.getAttribute('media-type');
        if (mediaType == 'application/oebps-package+xml') {
          return rootfile.getAttribute('full-path');
        }
      }

      // Fallback: just get the first rootfile
      if (rootfiles.isNotEmpty) {
        return rootfiles.first.getAttribute('full-path');
      }
    } catch (e) {
      print('Error parsing container.xml: $e');
    }

    return null;
  }

  /// Parse metadata from OPF document
  EpubMetadata _parseMetadata(XmlDocument document) {
    final metadata = document.findAllElements('metadata').firstOrNull;
    if (metadata == null) {
      return EpubMetadata();
    }

    String? findDcElement(String name) {
      // Try with dc: prefix
      var elements = metadata.findElements('dc:$name');
      if (elements.isEmpty) {
        // Try without prefix but in DC namespace
        elements = metadata.findAllElements(name).where((e) => 
          e.name.namespaceUri == dcNamespace || 
          e.name.local == name
        );
      }
      return elements.firstOrNull?.innerText;
    }

    List<String> findAllDcElements(String name) {
      var elements = metadata.findElements('dc:$name');
      if (elements.isEmpty) {
        elements = metadata.findAllElements(name).where((e) => 
          e.name.namespaceUri == dcNamespace || 
          e.name.local == name
        );
      }
      return elements.map((e) => e.innerText).where((t) => t.isNotEmpty).toList();
    }

    return EpubMetadata(
      title: findDcElement('title'),
      creator: findDcElement('creator'),
      description: findDcElement('description'),
      publisher: findDcElement('publisher'),
      language: findDcElement('language'),
      date: findDcElement('date'),
      subjects: findAllDcElements('subject'),
      rights: findDcElement('rights'),
      identifier: findDcElement('identifier'),
    );
  }

  /// Update metadata in OPF document
  void _updateMetadata(XmlDocument document, EpubMetadata metadata) {
    final metadataElement = document.findAllElements('metadata').firstOrNull;
    if (metadataElement == null) return;

    // Helper to update or create a DC element
    void updateDcElement(String name, String? value) {
      if (value == null || value.isEmpty) return;

      // Find existing element
      var elements = metadataElement.findElements('dc:$name');
      if (elements.isEmpty) {
        elements = metadataElement.findAllElements(name).where((e) => 
          e.name.namespaceUri == dcNamespace || 
          e.name.local == name
        );
      }

      if (elements.isNotEmpty) {
        // Update existing element
        final element = elements.first;
        element.children.clear();
        element.children.add(XmlText(value));
      } else {
        // Create new element with dc: prefix
        final newElement = XmlElement(
          XmlName('dc:$name'),
          [],
          [XmlText(value)],
        );
        metadataElement.children.add(newElement);
      }
    }

    // Helper to update multiple DC elements (like subjects)
    void updateDcElements(String name, List<String> values) {
      if (values.isEmpty) return;

      // Remove existing elements
      metadataElement.children.removeWhere((node) {
        if (node is XmlElement) {
          return node.name.local == name || 
                 node.name.toString() == 'dc:$name';
        }
        return false;
      });

      // Add new elements
      for (final value in values) {
        if (value.isNotEmpty) {
          final newElement = XmlElement(
            XmlName('dc:$name'),
            [],
            [XmlText(value)],
          );
          metadataElement.children.add(newElement);
        }
      }
    }

    // Update metadata fields
    updateDcElement('title', metadata.title);
    updateDcElement('creator', metadata.creator);
    updateDcElement('description', metadata.description);
    updateDcElement('publisher', metadata.publisher);
    updateDcElement('language', metadata.language);
    updateDcElement('date', metadata.date);
    updateDcElement('rights', metadata.rights);
    updateDcElements('subject', metadata.subjects);
  }

  /// Check if a file is an EPUB
  static bool isEpub(String filePath) {
    return path.extension(filePath).toLowerCase() == '.epub';
  }
}

/// EPUB metadata model
class EpubMetadata {
  final String? title;
  final String? creator; // Author
  final String? description;
  final String? publisher;
  final String? language;
  final String? date;
  final List<String> subjects; // Categories/Tags
  final String? rights;
  final String? identifier;

  EpubMetadata({
    this.title,
    this.creator,
    this.description,
    this.publisher,
    this.language,
    this.date,
    this.subjects = const [],
    this.rights,
    this.identifier,
  });

  EpubMetadata copyWith({
    String? title,
    String? creator,
    String? description,
    String? publisher,
    String? language,
    String? date,
    List<String>? subjects,
    String? rights,
    String? identifier,
  }) {
    return EpubMetadata(
      title: title ?? this.title,
      creator: creator ?? this.creator,
      description: description ?? this.description,
      publisher: publisher ?? this.publisher,
      language: language ?? this.language,
      date: date ?? this.date,
      subjects: subjects ?? this.subjects,
      rights: rights ?? this.rights,
      identifier: identifier ?? this.identifier,
    );
  }

  @override
  String toString() {
    return 'EpubMetadata(title: $title, creator: $creator, subjects: $subjects)';
  }
}
