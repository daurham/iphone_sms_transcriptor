import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import '../models/sms_message.dart';

/// Supported export formats for SMS messages
enum ExportFormat {
  txt,
  csv,
  json,
}

/// Service responsible for exporting SMS messages to text files.
/// 
/// This service handles:
/// - Grouping messages by conversation
/// - Formatting messages for export
/// - Creating and managing export directories
/// - Writing messages to text files
class SMSService {
  /// Exports SMS messages to files in the specified format.
  /// 
  /// This method:
  /// 1. Groups messages by conversation (group chat or direct message)
  /// 2. Creates an export directory if it doesn't exist
  /// 3. Writes each conversation to a separate file in the specified format
  /// 4. Returns the path where files were exported
  /// 
  /// [messages] - List of SMS messages to export
  /// [format] - The format to export the messages in
  /// [exportPath] - Optional path where files should be exported
  /// Returns the path where files were exported
  Future<String> exportToFiles(List<SMSMessage> messages, ExportFormat format, {String? exportPath}) async {
    print('Starting export of ${messages.length} messages in $format format');
    
    // Group messages by chat_id
    final Map<String, List<SMSMessage>> conversations = {};

    for (var message in messages) {
      final key = message.chatId;
      if (!conversations.containsKey(key)) {
        conversations[key] = [];
      }
      conversations[key]!.add(message);
    }

    // Create export directory with numbered folder
    final baseExportDir = exportPath ?? await _getDefaultExportPath();
    final exportDir = await _getNextExportDirectory(baseExportDir);
    
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
        displayName = firstMessage.contactName ?? firstMessage.phoneNumber;
      }

      final safeFileName = displayName
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
          .replaceAll(RegExp(r'\s+'), '_');
      
      // Get file extension based on format
      final extension = format.toString().split('.').last;
      final filePath = path.join(exportDir, '$safeFileName.$extension');
      
      final file = File(filePath);

      // Sort messages by timestamp
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Export based on format
      String content;
      switch (format) {
        case ExportFormat.txt:
          content = _formatAsText(messages, isGroupChat, groupName, participants);
          break;
        case ExportFormat.csv:
          content = _formatAsCsv(messages, isGroupChat, groupName, participants);
          break;
        case ExportFormat.json:
          content = _formatAsJson(messages, isGroupChat, groupName, participants);
          break;
      }

      try {
        await file.writeAsString(content);
      } catch (e) {
        print('Error writing file $filePath: $e');
      }
    }

    return exportDir;
  }

  /// Formats messages as plain text
  String _formatAsText(List<SMSMessage> messages, bool isGroupChat, String? groupName, List<String> participants) {
    final buffer = StringBuffer();
    
    if (isGroupChat) {
      buffer.writeln('Group Chat: ${groupName ?? "Unnamed Group"}');
      buffer.writeln('Participants:');
      for (var participant in participants) {
        final contactName = messages
            .firstWhere((m) => m.phoneNumber == participant, orElse: () => messages.first)
            .contactName;
        buffer.writeln('- ${contactName ?? participant}');
      }
      buffer.writeln('-' * 50);
      buffer.writeln();
    }

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

    return buffer.toString();
  }

  /// Formats messages as CSV
  String _formatAsCsv(List<SMSMessage> messages, bool isGroupChat, String? groupName, List<String> participants) {
    final buffer = StringBuffer();
    
    // Add header
    buffer.writeln('Timestamp,Sender,Message,Is Group Chat,Group Name,Participants');
    
    for (var message in messages) {
      final timestamp = message.timestamp;
      final formattedTime = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
      
      final sender = message.isFromMe 
          ? 'Me' 
          : (message.contactName ?? message.phoneNumber);
      
      // Escape fields that might contain commas
      final escapedText = message.text.replaceAll('"', '""');
      final escapedGroupName = (groupName ?? '').replaceAll('"', '""');
      final escapedParticipants = participants.join(';').replaceAll('"', '""');
      
      buffer.writeln('"$formattedTime","$sender","$escapedText","$isGroupChat","$escapedGroupName","$escapedParticipants"');
    }

    return buffer.toString();
  }

  /// Formats messages as JSON
  String _formatAsJson(List<SMSMessage> messages, bool isGroupChat, String? groupName, List<String> participants) {
    final Map<String, dynamic> data = {
      'isGroupChat': isGroupChat,
      'groupName': groupName,
      'participants': participants,
      'messages': messages.map((m) => {
        'timestamp': m.timestamp.toIso8601String(),
        'sender': m.isFromMe ? 'Me' : (m.contactName ?? m.phoneNumber),
        'text': m.text,
        'isFromMe': m.isFromMe,
      }).toList(),
    };

    return JsonEncoder.withIndent('  ').convert(data);
  }

  /// Gets the default export path in the user's desktop directory.
  Future<String> _getDefaultExportPath() async {
    final desktopPath = Platform.isWindows
        ? path.join(Platform.environment['USERPROFILE'] ?? '', 'Desktop')
        : path.join(Platform.environment['HOME'] ?? '', 'Desktop');
        
    return path.join(desktopPath, 'iPhone_SMS_Export');
  }

  /// Finds the next available numbered export directory.
  Future<String> _getNextExportDirectory(String basePath) async {
    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) {
      return path.join(basePath, 'exported_sms_records_1');
    }

    int counter = 1;
    while (true) {
      final dirPath = path.join(basePath, 'exported_sms_records_$counter');
      if (!await Directory(dirPath).exists()) {
        return dirPath;
      }
      counter++;
    }
  }
} 