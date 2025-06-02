import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

class ConfigService {
  static const String _configFileName = 'config.json';
  bool _isTestMode = false;
  String? _lastExportPath;

  bool get isTestMode => _isTestMode;
  String? get lastExportPath => _lastExportPath;

  ConfigService() {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final configFile = File(_configFileName);
      if (await configFile.exists()) {
        final contents = await configFile.readAsString();
        final config = json.decode(contents) as Map<String, dynamic>;
        _isTestMode = config['testMode'] ?? false;
        _lastExportPath = config['lastExportPath'];
      }
    } catch (e) {
      print('Error loading config: $e');
      // Default to test mode if config can't be loaded
      _isTestMode = true;
    }
  }

  Future<void> saveLastExportPath(String path) async {
    _lastExportPath = path;
    await _saveConfig();
  }

  Future<void> _saveConfig() async {
    try {
      final config = {
        'testMode': _isTestMode,
        'lastExportPath': _lastExportPath,
      };
      final configFile = File(_configFileName);
      await configFile.writeAsString(json.encode(config));
    } catch (e) {
      print('Error saving config: $e');
    }
  }

  String getDefaultExportPath() {
    if (_isTestMode) {
      // Use the current desktop-based export path
      return path.join(
        Platform.environment['USERPROFILE'] ?? '',
        'Desktop',
        'SMS_Export',
      );
    }
    // In production mode, use the last export path or default to Documents
    return _lastExportPath ?? path.join(
      Platform.environment['USERPROFILE'] ?? '',
      'Documents',
      'SMS_Export',
    );
  }
} 