import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/sms_message.dart';

/// Service responsible for reading and extracting data from iPhone backups.
/// 
/// This service handles:
/// - Locating and reading the SMS database
/// - Extracting contact information
/// - Processing group chat data
/// - Converting raw database data into SMSMessage objects
class BackupService {
  /// The default path where iPhone backups are stored on Windows
  static const String defaultBackupPath = 'C:\\Users\\%USERNAME%\\AppData\\Roaming\\Apple Computer\\MobileSync\\Backup';

  /// Extracts SMS data from an iPhone backup.
  /// 
  /// This method:
  /// 1. Locates and opens the SMS database
  /// 2. Reads contact information from the AddressBook database
  /// 3. Processes group chat data
  /// 4. Extracts and formats all messages
  /// 
  /// [backupPath] - The path to the iPhone backup folder
  /// Returns a list of SMSMessage objects containing all messages
  Future<List<SMSMessage>> extractSMSData(String backupPath) async {
    // Initialize SQLite for the current platform
    if (Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // Path to the SMS database in the backup
    final smsDbPath = path.join(backupPath, '3d', '3d0d7e5fb2ce288813306e4d4636395e047a3d28');
    final addressBookDbPath = path.join(backupPath, '31', '31bb7ba8914766d4ba40d6dfb6113c8b614be442');

    // Open the SMS database
    final db = await databaseFactory.openDatabase(smsDbPath);

    // Read contact information
    final contactMap = await _readContacts(addressBookDbPath);

    // Get chat information
    final chatMap = await _getChatInfo(db);

    // Get all messages
    final List<Map<String, dynamic>> messages = await db.query(
      'message',
      orderBy: 'date',
    );

    // Process each message
    final List<SMSMessage> smsMessages = [];
    for (var message in messages) {
      // Get the phone number for this message
      final handleId = message['handle_id'];
      final List<Map<String, dynamic>> handle = await db.query(
        'handle',
        where: 'ROWID = ?',
        whereArgs: [handleId],
      );

      if (handle.isNotEmpty) {
        final phoneNumber = handle[0]['id'];
        final contactName = contactMap[phoneNumber];

        // Check if this is a group chat
        final chatId = message['cache_roomname'] != null ? message['cache_roomname'] : 'direct_$phoneNumber';
        final isGroupChat = chatMap[chatId]?['isGroup'] ?? false;
        final groupName = chatMap[chatId]?['name'];
        final participants = chatMap[chatId]?['participants'] ?? [phoneNumber];

        // Create SMSMessage object
        smsMessages.add(SMSMessage(
          id: message['ROWID'].toString(),
          text: message['text'] ?? '',
          phoneNumber: phoneNumber,
          isFromMe: message['is_from_me'] == 1,
          timestamp: DateTime.fromMillisecondsSinceEpoch(message['date'] + 978307200000), // Convert from Apple's timestamp
          contactName: contactName,
          isGroupChat: isGroupChat,
          chatId: chatId,
          groupName: groupName,
          participants: participants,
        ));
      }
    }

    await db.close();
    return smsMessages;
  }

  /// Reads contact information from the AddressBook database.
  /// 
  /// [addressBookDbPath] - Path to the AddressBook database
  /// Returns a map of phone numbers to contact names
  Future<Map<String, String>> _readContacts(String addressBookDbPath) async {
    final Map<String, String> contactMap = {};

    try {
      final db = await databaseFactory.openDatabase(addressBookDbPath);

      // Get all contacts
      final List<Map<String, dynamic>> contacts = await db.query('ABPerson');

      for (var contact in contacts) {
        final contactId = contact['ROWID'];

        // Get the contact's name
        final List<Map<String, dynamic>> names = await db.query(
          'ABPerson',
          columns: ['First', 'Last'],
          where: 'ROWID = ?',
          whereArgs: [contactId],
        );

        if (names.isNotEmpty) {
          final firstName = names[0]['First'] ?? '';
          final lastName = names[0]['Last'] ?? '';
          final fullName = [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

          if (fullName.isNotEmpty) {
            // Get the contact's phone numbers
            final List<Map<String, dynamic>> phoneNumbers = await db.query(
              'ABMultiValue',
              where: 'record_id = ? AND property = ?',
              whereArgs: [contactId, 3], // 3 is the property ID for phone numbers
            );

            for (var phone in phoneNumbers) {
              final phoneNumber = phone['value'];
              if (phoneNumber != null) {
                contactMap[phoneNumber] = fullName;
              }
            }
          }
        }
      }

      await db.close();
    } catch (e) {
      print('Error reading contacts: $e');
    }

    return contactMap;
  }

  /// Gets information about all chats from the SMS database.
  /// 
  /// [db] - The open SMS database
  /// Returns a map of chat IDs to chat information
  Future<Map<String, Map<String, dynamic>>> _getChatInfo(Database db) async {
    final Map<String, Map<String, dynamic>> chatMap = {};

    // Get all chats
    final List<Map<String, dynamic>> chats = await db.query('chat');

    for (var chat in chats) {
      final chatId = chat['ROWID'].toString();
      final isGroup = chat['chat_identifier']?.toString().contains(',') ?? false;

      // Get chat participants
      final List<Map<String, dynamic>> participants = await db.query(
        'chat_handle_join',
        where: 'chat_id = ?',
        whereArgs: [chatId],
      );

      final List<String> phoneNumbers = [];
      for (var participant in participants) {
        final handleId = participant['handle_id'];
        final List<Map<String, dynamic>> handle = await db.query(
          'handle',
          where: 'ROWID = ?',
          whereArgs: [handleId],
        );

        if (handle.isNotEmpty) {
          phoneNumbers.add(handle[0]['id']);
        }
      }

      chatMap[chatId] = {
        'isGroup': isGroup,
        'name': chat['display_name'],
        'participants': phoneNumbers,
      };
    }

    return chatMap;
  }
} 