import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/sms_message.dart';

/// Service responsible for exporting SMS messages to text files.
/// 
/// This service handles:
/// - Grouping messages by conversation
/// - Formatting messages for export
/// - Creating and managing export directories
/// - Writing messages to text files
class SMSService {
  /// Exports SMS messages to text files.
  /// 
  /// This method:
  /// 1. Groups messages by conversation (group chat or direct message)
  /// 2. Creates an export directory if it doesn't exist
  /// 3. Writes each conversation to a separate text file
  /// 4. Returns the path where files were exported
  /// 
  /// [messages] - List of SMS messages to export
  /// [exportPath] - Optional path where files should be exported
  /// Returns the path where files were exported
  Future<String> exportToTextFiles(List<SMSMessage> messages, {String? exportPath}) async {
    print('Starting export of ${messages.length} messages');
    
    // Group messages by chat_id
    final Map<String, List<SMSMessage>> conversations = {};

    for (var message in messages) {
      // Use chat_id as the key for grouping
      final key = message.chatId;
      
      if (!conversations.containsKey(key)) {
        conversations[key] = [];
      }
      conversations[key]!.add(message);
    }

    // print('Grouped into ${conversations.length} conversations');

    // Create export directory with numbered folder
    final baseExportDir = exportPath ?? await _getDefaultExportPath();
    // print('Base export directory: $baseExportDir');
    
    final exportDir = await _getNextExportDirectory(baseExportDir);
    // print('Final export directory: $exportDir');
    
    final directory = Directory(exportDir);
    if (!await directory.exists()) {
      print('Creating export directory');
      await directory.create(recursive: true);
    }

    // Export each conversation
    for (var entry in conversations.entries) {
      final messages = entry.value;
      if (messages.isEmpty) continue;

      // Get conversation info from first message
      final firstMessage = messages.first;
      final isGroupChat = firstMessage.isGroupChat;
      final groupName = firstMessage.groupName;
      final participants = firstMessage.participants;

      // Create safe filename
      String displayName;
      if (isGroupChat) {
        displayName = 'Group Chat: ${groupName ?? "Unnamed Group"}';
      } else {
        // For direct messages, use the contact name or phone number
        displayName = firstMessage.contactName ?? firstMessage.phoneNumber;
      }

      final safeFileName = displayName
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
          .replaceAll(RegExp(r'\s+'), '_');
      
      final filePath = path.join(exportDir, '$safeFileName.txt');
      // print('Writing to file: $filePath');
      
      final file = File(filePath);

      // Write messages to file
      final buffer = StringBuffer();
      
      // Add header for group chats
      if (isGroupChat) {
        buffer.writeln('Group Chat: ${groupName ?? "Unnamed Group"}');
        buffer.writeln('Participants:');
        for (var participant in participants) {
          // Try to find contact name for participant
          final contactName = messages
              .firstWhere((m) => m.phoneNumber == participant, orElse: () => messages.first)
              .contactName;
          buffer.writeln('- ${contactName ?? participant}');
        }
        buffer.writeln('-' * 50);
        buffer.writeln();
      }

      // Sort messages by timestamp
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Write each message
      for (var message in messages) {
        final timestamp = message.timestamp;
        final formattedTime = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
        
        final sender = message.isFromMe 
            ? 'Me' 
            : (message.contactName ?? message.phoneNumber);
            
        buffer.writeln('[$formattedTime] $sender:');
        buffer.writeln(message.text);
        buffer.writeln();
      }

      try {
        await file.writeAsString(buffer.toString());
        // print('Successfully wrote file: $filePath');
      } catch (e) {
        print('Error writing file $filePath: $e');
      }
    }

    // print('Export completed to: $exportDir');
    return exportDir;
  }

  /// Gets the default export path in the user's desktop directory.
  /// 
  /// Returns the path to the default export directory
  Future<String> _getDefaultExportPath() async {
    final desktopPath = Platform.isWindows
        ? path.join(Platform.environment['USERPROFILE'] ?? '', 'Desktop')
        : path.join(Platform.environment['HOME'] ?? '', 'Desktop');
        
    return path.join(desktopPath, 'iPhone_SMS_Export');
  }

  /// Finds the next available numbered export directory.
  /// 
  /// This method:
  /// 1. Checks for existing numbered directories in the base path
  /// 2. Returns the path for the next available number
  /// 
  /// [basePath] - The base directory where numbered folders should be created
  /// Returns the path for the next available numbered directory
  Future<String> _getNextExportDirectory(String basePath) async {
    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) {
      return path.join(basePath, 'exported_sms_records_1');
    }

    // Get all existing numbered directories
    final existingDirs = await baseDir
        .list()
        .where((entity) => 
            entity is Directory && 
            entity.path.contains('exported_sms_records_'))
        .map((entity) => entity.path)
        .toList();

    // Extract numbers from directory names
    final numbers = existingDirs
        .map((dir) {
          final match = RegExp(r'exported_sms_records_(\d+)$')
              .firstMatch(path.basename(dir));
          return match != null ? int.tryParse(match.group(1)!) : null;
        })
        .where((num) => num != null)
        .map((num) => num!)
        .toList();

    // Find the next available number
    int nextNumber = 1;
    if (numbers.isNotEmpty) {
      numbers.sort();
      nextNumber = numbers.last + 1;
    }

    return path.join(basePath, 'exported_sms_records_$nextNumber');
  }
} 