import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as path;
import '../services/backup_service.dart';
import '../services/sms_service.dart';

/// The main screen of the application that handles user interaction for
/// selecting backup folders, export locations, and processing the SMS data.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // State variables to track selected paths and processing status
  String? selectedBackupPath;    // Path to the iPhone backup folder
  String? selectedExportPath;    // Path where SMS files will be exported
  bool isProcessing = false;     // Flag to track if backup is being processed
  String? exportLocation;        // Path where files were actually exported

  /// Handles the selection of the iPhone backup folder.
  /// 
  /// This method:
  /// 1. Checks if the default backup path exists
  /// 2. Opens a folder picker dialog
  /// 3. Validates that the selected folder contains the SMS database
  /// 4. Updates the UI with the selected path
  Future<void> selectBackupFolder() async {
    try {
      // Get the default backup path from BackupService
      final defaultPath = BackupService.defaultBackupPath;
      final defaultDir = Directory(defaultPath);
      
      String? selectedDirectory;
      if (defaultDir.existsSync()) {
        // If default path exists, use it as the initial directory
        // Convert path separators for Windows compatibility
        final initialPath = Platform.isWindows 
            ? defaultPath.replaceAll('/', '\\')
            : defaultPath;
            
        selectedDirectory = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Select iPhone Backup Folder',
          initialDirectory: initialPath,
        );
      } else {
        // If default path doesn't exist, try parent directory
        final parentDir = Directory(path.dirname(defaultPath));
        if (parentDir.existsSync()) {
          selectedDirectory = await FilePicker.platform.getDirectoryPath(
            dialogTitle: 'Select iPhone Backup Folder',
            initialDirectory: parentDir.path,
          );
        } else {
          // If parent doesn't exist, open from home directory
          selectedDirectory = await FilePicker.platform.getDirectoryPath(
            dialogTitle: 'Select iPhone Backup Folder',
          );
        }
      }

      if (selectedDirectory != null) {
        // Verify this is a valid iPhone backup by checking for SMS database
        final smsDbPath = Directory(path.join(selectedDirectory, '3d', '3d0d7e5fb2ce288813306e4d4636395e047a3d28'));
        if (!smsDbPath.existsSync()) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selected folder does not appear to be a valid iPhone backup folder'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        // Update only the backup path, preserving export path
        setState(() {
          selectedBackupPath = selectedDirectory;
          selectedExportPath = selectedExportPath;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting folder: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Handles the selection of the export location for SMS files.
  /// 
  /// This method:
  /// 1. Opens a folder picker dialog starting in the user's Documents folder
  /// 2. Updates the UI with the selected export path
  Future<void> selectExportFolder() async {
    try {
      // Start from user's Documents folder
      final documentsPath = Platform.isWindows
          ? path.join(Platform.environment['USERPROFILE'] ?? '', 'Documents')
          : path.join(Platform.environment['HOME'] ?? '', 'Documents');

      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Export Location',
        initialDirectory: documentsPath,
      );

      if (selectedDirectory != null) {
        // Update only the export path, preserving backup path
        setState(() {
          selectedExportPath = selectedDirectory;
          selectedBackupPath = selectedBackupPath;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting export location: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Opens the export folder in the system's file explorer.
  /// 
  /// This method:
  /// 1. Creates a URI for the export location
  /// 2. Uses url_launcher to open the folder
  Future<void> openExportFolder() async {
    if (exportLocation == null) return;

    final uri = Uri.file(exportLocation!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error opening export folder'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Processes the iPhone backup and exports SMS data.
  /// 
  /// This method:
  /// 1. Validates that a backup folder is selected
  /// 2. Extracts SMS data using BackupService
  /// 3. Exports the data to text files using SMSService
  /// 4. Updates the UI with the export location
  Future<void> processBackup() async {
    if (selectedBackupPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a backup folder first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      isProcessing = true;
    });

    try {
      final backupService = BackupService();
      final smsService = SMSService();

      // Extract SMS data from backup
      final smsData = await backupService.extractSMSData(selectedBackupPath!);
      
      // Export to text files
      final exportPath = await smsService.exportToTextFiles(
        smsData,
        exportPath: selectedExportPath,
      );

      setState(() {
        exportLocation = exportPath;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS data successfully exported!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing backup: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        isProcessing = false;
      });
    }
  }

  /// Builds the main UI of the application.
  /// 
  /// The UI consists of:
  /// 1. A card for selecting the iPhone backup folder
  /// 2. A card for selecting the export location
  /// 3. A button to process the backup
  /// 4. A card showing the export location and open folder button
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('iPhone SMS Transcriptor'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Backup folder selection card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select iPhone Backup',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Default location: ${BackupService.defaultBackupPath}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: isProcessing ? null : selectBackupFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Choose Backup Folder'),
                    ),
                    if (selectedBackupPath != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Selected: ${selectedBackupPath!.split(Platform.pathSeparator).last}',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Export location selection card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Export Location',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose where to save the exported SMS files',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: isProcessing ? null : selectExportFolder,
                      icon: const Icon(Icons.save),
                      label: const Text('Choose Export Location'),
                    ),
                    if (selectedExportPath != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Selected: ${selectedExportPath!.split(Platform.pathSeparator).last}',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Process backup button
            ElevatedButton.icon(
              onPressed: isProcessing ? null : processBackup,
              icon: const Icon(Icons.download),
              label: const Text('Export SMS Data'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            // Loading indicator
            if (isProcessing)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            // Export location card
            if (exportLocation != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Exported to: $exportLocation',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: openExportFolder,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Open Export Folder'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
} 