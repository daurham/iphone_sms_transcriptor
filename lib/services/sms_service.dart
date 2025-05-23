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
    // Group messages by conversation
    final Map<String, List<SMSMessage>> conversations = {};
    
    for (var message in messages) {
      // Use group name for group chats, phone number for direct messages
      final key = message.isGroupChat 
          ? 'Group_${message.groupName ?? "Chat"}'
          : message.phoneNumber;
          
      if (!conversations.containsKey(key)) {
        conversations[key] = [];
      }
      conversations[key]!.add(message);
    }

    // Create export directory
    final exportDir = exportPath ?? await _getDefaultExportPath();
    await Directory(exportDir).create(recursive: true);

    // Export each conversation
    for (var entry in conversations.entries) {
      final conversationKey = entry.key;
      final messages = entry.value;

      // Create safe filename
      final safeFileName = conversationKey
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
          .replaceAll(RegExp(r'\s+'), '_');
      
      final filePath = path.join(exportDir, '$safeFileName.txt');
      final file = File(filePath);

      // Write messages to file
      final buffer = StringBuffer();
      
      // Add header for group chats
      if (messages.first.isGroupChat) {
        buffer.writeln('Group Chat: ${messages.first.groupName}');
        buffer.writeln('Participants:');
        for (var participant in messages.first.participants) {
          buffer.writeln('- $participant');
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

      await file.writeAsString(buffer.toString());
    }

    return exportDir;
  }

  /// Gets the default export path in the user's documents directory.
  /// 
  /// Returns the path to the default export directory
  Future<String> _getDefaultExportPath() async {
    final documentsPath = Platform.isWindows
        ? path.join(Platform.environment['USERPROFILE'] ?? '', 'Documents')
        : path.join(Platform.environment['HOME'] ?? '', 'Documents');
        
    return path.join(documentsPath, 'iPhone_SMS_Export');
  }
} 