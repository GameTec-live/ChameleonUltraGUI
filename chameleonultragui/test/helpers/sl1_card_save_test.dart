import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';
import 'package:chameleonultragui/helpers/card_save_converters.dart';

import 'sl1_profile_test.dart' show fixture;

void main() {
  test('folder bundles and duplicates preserve full profile metadata', () {
    final profile = fixture();
    profile.json['classic']['blocks'][0]['errors'] = [
      {'key': 'A', 'status': 6, 'reason': 'Synthetic failure'},
    ];
    final card = sl1ToCard(profile)..folderId = 'yellow';
    final bundle = CardFolderBundle(
      rootFolderId: 'yellow',
      folders: [CardFolder(id: 'yellow', name: 'Synthetic yellow folder')],
      cards: [card],
    );
    final restored = CardFolderBundle.fromJson(bundle.toJson()).cards.single;
    final duplicate = CardSave.fromJson(restored.toJson())..id = 'duplicate';
    expect(duplicate.sl1Profile!.export(), profile.export());
    expect(duplicate.folderId, 'yellow');
    duplicate.name = 'Renamed';
    reconcileSl1(duplicate);
    expect(
      duplicate.sl1Profile!.json['cardAuth']['verification']['status'],
      'provided',
    );
    expect(
      duplicate.sl1Profile!.json['classic']['blocks'][0]['errors'][0]['status'],
      6,
    );
    expect(duplicate.sl1Profile!.image(), hasLength(20));
  });
  test('Flipper import preserves question marks byte by byte', () {
    final source = [
      'Filetype: Flipper NFC device',
      'UID: 01 02 03 04',
      'SAK: 09',
      'ATQA: 04 00',
      for (var block = 0; block < 20; block++)
        'Block $block: ${block == 0 ? '${'00' * 15}??' : '00' * 16}',
    ].join('\n');
    final card = flipperNfcToCardSave(source);
    expect(card.data.first, isEmpty);
    expect(
      card.sl1Profile!.json['classic']['blocks'][0]['data'],
      '${'00' * 15}??',
    );
    expect(() => card.sl1Profile!.image(), throwsFormatException);
  });
}
