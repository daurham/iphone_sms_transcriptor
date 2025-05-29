import 'dart:io';
import 'dart:convert';
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

  /// Exports the contact map to a JSON file for inspection
  Future<void> exportContactMap(Map<String, String> contactMap, String backupPath) async {
    final desktopPath = Platform.isWindows
        ? path.join(Platform.environment['USERPROFILE'] ?? '', 'Desktop')
        : path.join(Platform.environment['HOME'] ?? '', 'Desktop');
    
    final exportPath = path.join(desktopPath, 'contact_map_inspection.json');
    
    // Convert the map to a list of entries for better readability
    final List<Map<String, String>> contactList = contactMap.entries
        .map((entry) => {'phone': entry.key, 'name': entry.value})
        .toList();
    
    // Sort by name for easier inspection
    contactList.sort((a, b) => a['name']!.compareTo(b['name']!));
    
    final jsonString = JsonEncoder.withIndent('  ').convert(contactList);
    await File(exportPath).writeAsString(jsonString);
    // print('Contact map exported to: $exportPath');
  }

  /// Normalizes a phone number by removing all non-digit characters and handling country codes
  String normalizePhoneNumber(String phoneNumber) {
    // Remove all non-digit characters
    String digits = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    
    // If the number starts with 1 and is 11 digits, remove the 1
    if (digits.length == 11 && digits.startsWith('1')) {
      digits = digits.substring(1);
    }
    
    return digits;
  }

  /// Tries to find a contact name by checking various phone number formats
  String? findContactName(String phoneNumber, Map<String, String> contactMap) {
    // First try the exact number
    if (contactMap.containsKey(phoneNumber)) {
      return contactMap[phoneNumber];
    }

    // Normalize the input number
    final normalizedNumber = normalizePhoneNumber(phoneNumber);
    // print('Normalized number: $normalizedNumber');

    // Try to find a match by normalizing all contact numbers
    for (var entry in contactMap.entries) {
      final normalizedContactNumber = normalizePhoneNumber(entry.key);
      if (normalizedContactNumber == normalizedNumber) {
        // print('Found match: ${entry.key} -> ${entry.value}');
        return entry.value;
      }
    }

    return null;
  }

  /// Exports database schema and sample data for inspection
  Future<void> exportDatabaseInfo(Database db, String backupPath) async {
    // final desktopPath = Platform.isWindows
    //     ? path.join(Platform.environment['USERPROFILE'] ?? '', 'Desktop')
    //     : path.join(Platform.environment['HOME'] ?? '', 'Desktop');
    
    // final exportPath = path.join(desktopPath, 'sms_database_inspection.json');

    final exportPath = path.join(Directory.current.path, 'sms_database_inspection.json');
    
    // Get all tables
    final List<Map<String, dynamic>> tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'"
    );
    
    final Map<String, dynamic> databaseInfo = {
      'tables': {},
    };
    
    // For each table, get its schema and sample data
    for (var table in tables) {
      final tableName = table['name'] as String;
      
      // Get table schema
      final List<Map<String, dynamic>> schema = await db.rawQuery('PRAGMA table_info($tableName)');
      
      // Get sample data (first 5 rows)
      final List<Map<String, dynamic>> sampleData = await db.query(
        tableName,
        limit: 5,
      );
      
      databaseInfo['tables'][tableName] = {
        'schema': schema,
        'sample_data': sampleData,
      };
    }
    
    // Convert to pretty-printed JSON
    final jsonString = JsonEncoder.withIndent('  ').convert(databaseInfo);
    await File(exportPath).writeAsString(jsonString);
    print('Database info exported to: $exportPath');
  }

  /// Extracts SMS data from an iPhone backup.
  /// 
  /// This method:
  /// 1. Locates and opens the SMS database
  /// 2. Reads contact information from the AddressBook database
  /// 3. Processes group chat data
  /// 4. Extracts and formats all messages
  /// 
  /// [backupPath] - The path to the iPhone backup folder
  /// [messageLimit] - Optional limit on number of messages to process (for testing)
  /// Returns a list of SMSMessage objects containing all messages
  Future<List<SMSMessage>> extractSMSData(String backupPath, {int? messageLimit}) async {
    // Initialize SQLite for the current platform
    if (Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // Path to the SMS database in the backup
    final smsDbPath = path.join(backupPath, '3d', '3d0d7e5fb2ce288813306e4d4636395e047a3d28');
    final addressBookDbPath = path.join(backupPath, '31', '31bb7ba8914766d4ba40d6dfb6113c8b614be442');

    // print('Opening SMS database at: $smsDbPath');
    // Open the SMS database
    final db = await databaseFactory.openDatabase(smsDbPath);

    // Export database info for inspection /// TODO: Remove After Inspection
    // await exportDatabaseInfo(db, backupPath);

    // First, let's check the schema of the message table
    // print('Checking message table schema...');
    final List<Map<String, dynamic>> messageSchema = await db.rawQuery('PRAGMA table_info(message)');
    // print('Message table columns:');
    // for (var column in messageSchema) {
    //   print('${column['name']} (${column['type']})');
    // }

    // Read contact information
    final contactMap = await _readContacts(addressBookDbPath);
    
    // Export contact map for inspection
    // await exportContactMap(contactMap, backupPath);

    // Get chat information including group chats
    final Map<int, Map<String, dynamic>> chatInfo = {};
    final List<Map<String, dynamic>> chats = await db.query('chat');
    
    for (var chat in chats) {
      final chatId = chat['ROWID'] as int;
      final isGroupChat = chat['style'] == 43; // 43 indicates group chat
      
      // Get chat participants
      final List<Map<String, dynamic>> participants = await db.query(
        'chat_handle_join',
        where: 'chat_id = ?',
        whereArgs: [chatId],
      );
      
      final List<String> participantHandles = [];
      for (var participant in participants) {
        final handleId = participant['handle_id'] as int;
        final List<Map<String, dynamic>> handle = await db.query(
          'handle',
          where: 'ROWID = ?',
          whereArgs: [handleId],
        );
        if (handle.isNotEmpty) {
          participantHandles.add(handle[0]['id'] as String);
        }
      }
      
      chatInfo[chatId] = {
        'isGroupChat': isGroupChat,
        'groupName': chat['display_name'] as String?,
        'participants': participantHandles.map((p) => p.toString()).toList(),
      };
    }

    // Get messages with optional limit
    // print('Querying messages table${messageLimit != null ? ' (limit: $messageLimit)' : ''}...');
    final List<Map<String, dynamic>> messages = await db.rawQuery('''
      SELECT m.ROWID, m.text, m.handle_id, m.is_from_me, m.date, cmj.chat_id
      FROM message m
      LEFT JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
      ORDER BY m.date DESC
      ${messageLimit != null ? 'LIMIT $messageLimit' : ''}
    ''');
    // print('Found ${messages.length} messages in database');

    // Process each message
    final List<SMSMessage> smsMessages = [];
    
    for (var message in messages) {
      final handleId = message['handle_id'];
      final chatId = message['chat_id'];
      final isFromMe = message['is_from_me'] == 1;
      
      // Get the phone number for this message
      String phoneNumber;
      if (isFromMe) {
        // For messages from the user, we'll use a placeholder phone number
        // since handle_id might be null for user's messages
        phoneNumber = 'me';
      } else {
        final List<Map<String, dynamic>> handle = await db.query(
          'handle',
          where: 'ROWID = ?',
          whereArgs: [handleId],
        );
        if (handle.isEmpty) continue;
        phoneNumber = handle[0]['id'];
      }

      final contactName = isFromMe ? 'Me' : findContactName(phoneNumber, contactMap);
      
      // Get chat information
      final chat = chatInfo[chatId];
      final isGroupChat = chat?['isGroupChat'] ?? false;
      final groupName = chat?['groupName'];
      final participants = (chat?['participants'] as List<dynamic>?)?.map((p) => p.toString()).toList() ?? [phoneNumber];
      
      // Create SMSMessage object
      smsMessages.add(SMSMessage(
        id: message['ROWID'].toString(),
        text: message['text'] ?? '',
        phoneNumber: phoneNumber,
        isFromMe: isFromMe,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          ((message['date'] as int) ~/ 1000000) + 978307200000
        ),
        contactName: contactName,
        isGroupChat: isGroupChat,
        chatId: chatId?.toString() ?? 'unknown',
        groupName: groupName,
        participants: participants,
      ));
    }

    // print('Processed ${smsMessages.length} messages successfully');
    // print('Chat statistics:');
    // for (var entry in chatInfo.entries) {
      // print('Chat ${entry.key}: ${entry.value['isGroupChat'] ? 'Group' : 'Direct'} - ${entry.value['participants'].length} participants');
    // }
    
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
      // print('Opening AddressBook database at: $addressBookDbPath');
      final db = await databaseFactory.openDatabase(addressBookDbPath);

      // Get all contacts
      final List<Map<String, dynamic>> contacts = await db.query('ABPerson');
      // print('Found ${contacts.length} contacts in AddressBook');

      for (var contact in contacts) {
        final contactId = contact['ROWID'];
        // print('Processing contact ID: $contactId');

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
          // print('Contact name: $fullName');

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
                // print('Adding contact: $phoneNumber -> $fullName');
                contactMap[phoneNumber] = fullName;
              }
            }
          }
        }
      }

      await db.close();
      // print('Final contact map: $contactMap');
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

    try {
      // Get all chats
      final List<Map<String, dynamic>> chats = await db.query('chat');
      // print('Found ${chats.length} chats in database');

      for (var chat in chats) {
        final chatId = chat['ROWID'].toString();
        // print('Processing chat ID: $chatId');

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
            final phoneNumber = handle[0]['id'].toString();
            // print('Adding participant: $phoneNumber to chat $chatId');
            phoneNumbers.add(phoneNumber);
          }
        }

        // A chat is a group if it has more than 2 participants (including yourself)
        final isGroup = phoneNumbers.length > 2;
        print('Chat $chatId has ${phoneNumbers.length} participants, isGroup: $isGroup');

        chatMap[chatId] = {
          'isGroup': isGroup,
          'name': chat['display_name'],
          'participants': phoneNumbers,
        };
        // print('Chat $chatId info: ${chatMap[chatId]}');
      }
    } catch (e) {
      print('Error getting chat info: $e');
    }

    return chatMap;
  }
} 