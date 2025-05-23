/// Represents a single SMS message from an iPhone backup.
/// 
/// This model contains all relevant information about a message including:
/// - The message content and timestamp
/// - Sender and recipient information
/// - Group chat details if applicable
/// - Contact information if available
class SMSMessage {
  /// The unique identifier of the message in the iPhone backup
  final String id;
  
  /// The actual text content of the message
  final String text;
  
  /// The phone number of the sender/recipient
  final String phoneNumber;
  
  /// Whether this message was sent by the user (true) or received (false)
  final bool isFromMe;
  
  /// The timestamp when the message was sent/received
  final DateTime timestamp;
  
  /// The name of the contact associated with the phone number (if available)
  final String? contactName;
  
  /// Whether this message is part of a group chat
  final bool isGroupChat;
  
  /// The unique identifier of the chat this message belongs to
  final String chatId;
  
  /// The name of the group chat (if this is a group message)
  final String? groupName;
  
  /// List of phone numbers of all participants in the chat
  final List<String> participants;

  /// Creates a new SMSMessage instance.
  /// 
  /// [id] - The unique message identifier
  /// [text] - The message content
  /// [phoneNumber] - The phone number of the sender/recipient
  /// [isFromMe] - Whether the message was sent by the user
  /// [timestamp] - When the message was sent/received
  /// [contactName] - Optional name of the contact
  /// [isGroupChat] - Whether this is a group chat message
  /// [chatId] - The chat identifier
  /// [groupName] - Optional name of the group chat
  /// [participants] - List of all chat participants' phone numbers
  SMSMessage({
    required this.id,
    required this.text,
    required this.phoneNumber,
    required this.isFromMe,
    required this.timestamp,
    this.contactName,
    required this.isGroupChat,
    required this.chatId,
    this.groupName,
    required this.participants,
  });

  /// Creates an SMSMessage from a map of data (typically from SQLite database).
  /// 
  /// [map] - A map containing the message data with the following keys:
  ///   - id: The message identifier
  ///   - text: The message content
  ///   - phoneNumber: The sender/recipient phone number
  ///   - isFromMe: Whether sent by user (1) or received (0)
  ///   - timestamp: Message timestamp in milliseconds
  ///   - contactName: Optional contact name
  ///   - isGroupChat: Whether this is a group message (1) or not (0)
  ///   - chatId: The chat identifier
  ///   - groupName: Optional group chat name
  ///   - participants: List of participant phone numbers
  factory SMSMessage.fromMap(Map<String, dynamic> map) {
    return SMSMessage(
      id: map['id'].toString(),
      text: map['text'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      isFromMe: map['isFromMe'] == 1,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      contactName: map['contactName'],
      isGroupChat: map['isGroupChat'] == 1,
      chatId: map['chatId'].toString(),
      groupName: map['groupName'],
      participants: List<String>.from(map['participants'] ?? []),
    );
  }

  /// Converts the SMSMessage to a map for database storage.
  /// 
  /// Returns a map with all message properties as key-value pairs.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'phoneNumber': phoneNumber,
      'isFromMe': isFromMe ? 1 : 0,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'contactName': contactName,
      'isGroupChat': isGroupChat ? 1 : 0,
      'chatId': chatId,
      'groupName': groupName,
      'participants': participants,
    };
  }

  @override
  String toString() {
    final formattedTime = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    final sender = isFromMe ? 'Me' : (contactName ?? phoneNumber);
    return '[$formattedTime] $sender: $text';
  }
} 