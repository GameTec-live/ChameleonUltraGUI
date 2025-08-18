import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/widgets.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

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


  /// Validate folder name with localization
  static String? validateFolderNameLocalized(BuildContext context, String name) {
    final localizations = AppLocalizations.of(context)!;
    if (name.trim().isEmpty) {
      return localizations.folder_name_cannot_be_empty;
    }
    if (name.length > 50) {
      return localizations.folder_name_too_long;
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
