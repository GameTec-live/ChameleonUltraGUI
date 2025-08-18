import 'package:chameleonultragui/sharedprefsprovider.dart';

/// Utility class for folder-related operations and validations
class FolderUtils {
  /// Get the full path of a folder as breadcrumb trail
  static List<CardFolder> getFolderBreadcrumbs(
      SharedPreferencesProvider provider, String? folderId) {
    List<CardFolder> breadcrumbs = [];
    String? currentId = folderId;
    
    while (currentId != null) {
      CardFolder? folder = provider.getFolder(currentId);
      if (folder != null) {
        breadcrumbs.insert(0, folder);
        currentId = folder.parentId;
      } else {
        break;
      }
    }
    
    return breadcrumbs;
  }

  /// Count cards in a folder (including subfolders if recursive)
  static int countCardsInFolder(SharedPreferencesProvider provider,
      String? folderId, {bool recursive = false}) {
    List<CardSave> cards = provider.getCardsInFolder(folderId);
    int count = cards.length;

    if (recursive) {
      List<CardFolder> subfolders = provider.getSubfolders(folderId);
      for (CardFolder subfolder in subfolders) {
        count += countCardsInFolder(provider, subfolder.id, recursive: true);
      }
    }

    return count;
  }

  /// Validate folder name
  static String? validateFolderName(String name) {
    if (name.trim().isEmpty) {
      return "Folder name cannot be empty";
    }
    if (name.length > 50) {
      return "Folder name is too long";
    }
    return null;
  }

  /// Check if a folder can be moved to prevent circular references
  static bool canMoveFolderTo(SharedPreferencesProvider provider,
      String folderId, String? targetParentId) {
    // Can't move to itself
    if (folderId == targetParentId) {
      return false;
    }

    // Can't move to a descendant
    String? currentId = targetParentId;
    while (currentId != null) {
      if (currentId == folderId) {
        return false;
      }
      CardFolder? folder = provider.getFolder(currentId);
      currentId = folder?.parentId;
    }

    return true;
  }
}
