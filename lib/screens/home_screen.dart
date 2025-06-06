import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as path;
import '../services/backup_service.dart';
import '../services/sms_service.dart';
import '../services/config_service.dart';

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
  bool isProcessing = false;     // Flag to track if backup is being processed
  String? exportLocation;        // Path where files were actually exported
  ExportFormat selectedFormat = ExportFormat.txt;  // Selected export format
  final ConfigService _configService = ConfigService();

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
        // If default path exists, use its parent directory (the Backup folder)
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
        final smsDbPath = File(path.join(selectedDirectory, '3d', '3d0d7e5fb2ce288813306e4d4636395e047a3d28'));
        
        if (!smsDbPath.existsSync()) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selected folder does not appear to be a valid iPhone backup folder'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        setState(() {
          selectedBackupPath = selectedDirectory;
        });
      }
    } catch (e) {
      print('Error selecting folder: ${e.toString()}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting folder: ${e.toString()}'),
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
      print('Error opening export folder: ${uri.toString()}');
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
  /// 3. Exports the data to files in the selected format using SMSService
  /// 4. Updates the UI with the export location
  Future<void> processBackup() async {
    if (selectedBackupPath == null) {
      print('No backup path selected');
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
      final smsService = SMSService(configService: _configService);

      // Extract SMS data from backup
      final smsData = await backupService.extractSMSData(selectedBackupPath!);
      
      // Export to files in selected format
      final exportPath = await smsService.exportToFiles(smsData, selectedFormat);

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
      print('Error processing backup: ${e.toString()}');
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
  /// 2. A card for selecting the export format
  /// 3. A button to process the backup
  /// 4. A card showing the export location and open folder button
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('iPhone SMS Transcriptor'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: Container(
        color: Theme.of(context).colorScheme.background,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Backup folder selection card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.backup,
                                color: Theme.of(context).colorScheme.primary,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Select iPhone Backup',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Default location: ${BackupService.defaultBackupPath}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              FilledButton.icon(
                                onPressed: selectBackupFolder,
                                icon: const Icon(Icons.folder_open),
                                label: const Text('Choose Backup Folder'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Tooltip(
                                message: 'Select the folder containing your iPhone backup.\n'
                                    'Example path: C:\\Users\\YourName\\AppData\\Roaming\\Apple Computer\\MobileSync\\Backup\\00008110-001919682E91A01E\n'
                                    'The folder should contain numbered folders (like "3d", "31", etc.)',
                                child: Icon(
                                  Icons.info_outline,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                          if (selectedBackupPath != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Selected: ${selectedBackupPath!.split(Platform.pathSeparator).last}',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Export format selection card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.format_list_bulleted,
                                color: Theme.of(context).colorScheme.primary,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Export Format',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Text (.txt)'),
                                selected: selectedFormat == ExportFormat.txt,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      selectedFormat = ExportFormat.txt;
                                    });
                                  }
                                },
                              ),
                              ChoiceChip(
                                label: const Text('CSV (.csv)'),
                                selected: selectedFormat == ExportFormat.csv,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      selectedFormat = ExportFormat.csv;
                                    });
                                  }
                                },
                              ),
                              ChoiceChip(
                                label: const Text('JSON (.json)'),
                                selected: selectedFormat == ExportFormat.json,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      selectedFormat = ExportFormat.json;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Process backup button
                  if (selectedBackupPath != null) ...[
                    Center(
                      child: FilledButton.icon(
                        onPressed: isProcessing ? null : processBackup,
                        icon: const Icon(Icons.download),
                        label: const Text('Export SMS Data'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
                          textStyle: Theme.of(context).textTheme.titleMedium,
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    // Loading indicator
                    if (isProcessing) ...[
                      const SizedBox(height: 24),
                      Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Processing backup...',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  // Export location card
                  if (exportLocation != null) ...[
                    const SizedBox(height: 24),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.folder_zip,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Export Complete',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.folder_outlined,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Location: $exportLocation',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: FilledButton.icon(
                                onPressed: openExportFolder,
                                icon: const Icon(Icons.folder_open),
                                label: const Text('Open Export Folder'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                  foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                                ),
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
          ),
        ),
      ),
    );
  }
} 