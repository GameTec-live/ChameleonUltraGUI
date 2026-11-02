import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/dump_analyzer.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';

enum ValueBlockOperation { write, increment, decrement, transfer }

/// Live card data and authentication from the standard key-recovery session.
class MifareValueBlocks {
  final ChameleonCommunicator communicator;
  final MifareClassicRecovery recovery;
  final String uid;
  final Set<int> capabilities;
  late final blocks = List<Uint8List?>.filled(blockCount, null);

  MifareValueBlocks({
    required this.communicator,
    required this.recovery,
    required this.uid,
    required this.capabilities,
  });

  int get blockCount => mfClassicGetBlockCount(
    recovery.mifareClassicType,
    isEV1: recovery.isMifareClassicEV1,
  );
  int get sectorCount => mfClassicGetSectorCount(
    recovery.mifareClassicType,
    isEV1: recovery.isMifareClassicEV1,
  );

  bool isDataBlock(int block) =>
      block > 0 &&
      block < blockCount &&
      block !=
          mfClassicGetSectorTrailerBlockBySector(
            mfClassicGetSectorByBlock(block),
          );

  int? value(int block) => blocks[block] == null
      ? null
      : MifareClassicDumpAnalyzer.valueBlockToInt(bytesToHex(blocks[block]!));

  int? address(int block) => blocks[block] == null
      ? null
      : MifareClassicDumpAnalyzer.valueBlockAddress(bytesToHex(blocks[block]!));

  /// Permission columns are read, write, increment, decrement/restore/transfer.
  int? keyTypeFor(int block, int permission) {
    if (block < 0 || block >= blockCount) return null;
    final sector = mfClassicGetSectorByBlock(block);
    final trailer = blocks[mfClassicGetSectorTrailerBlockBySector(sector)];
    var mask = 3;
    if (trailer != null && isDataBlock(block)) {
      final conditions = MifareClassicDumpAnalyzer.accessConditionValues(
        bytesToHex(trailer.sublist(6, 9)),
      );
      if (conditions != null) {
        final offset = block - mfClassicGetFirstBlockCountBySector(sector);
        final group = sector < 32 ? offset : offset ~/ 5;
        mask = MifareClassicDumpAnalyzer.dataAccessPermissions(
          conditions[group],
        )[permission];
      }
    }
    for (var type = 0; type < 2; type++) {
      if ((mask & (1 << type)) != 0 &&
          recovery.getSectorKey(sector, type).length == 6) {
        return 0x60 + type;
      }
    }
    return null;
  }

  Uint8List _key(int block, int type) => Uint8List.fromList(
    recovery.getSectorKey(mfClassicGetSectorByBlock(block), type - 0x60),
  );

  bool supports(ValueBlockOperation operation) => capabilities.contains(
    operation == ValueBlockOperation.write
        ? ChameleonCommand.mf1WriteBlock.value
        : ChameleonCommand.mf1ManipulateValueBlock.value,
  );

  bool canApply(ValueBlockOperation operation, int source, int destination) {
    if (!supports(operation) ||
        !isDataBlock(source) ||
        !isDataBlock(destination)) {
      return false;
    }
    if (operation == ValueBlockOperation.write) {
      return keyTypeFor(source, 1) != null;
    }
    return value(source) != null &&
        keyTypeFor(
              source,
              operation == ValueBlockOperation.increment ? 2 : 3,
            ) !=
            null &&
        keyTypeFor(destination, 3) != null;
  }

  Future<void> ensureCard() async {
    final l = recovery.localizations;
    if (!identical(recovery.appState.communicator, communicator)) {
      throw StateError(l.value_block_wrong_card);
    }
    await communicator.setReaderDeviceMode(true);
    final card = await communicator.scan14443aTag();
    if (card == null || bytesToHexSpace(card.uid) != uid) {
      throw StateError(l.value_block_wrong_card);
    }
  }

  Future<Uint8List?> readBlock(int block) async {
    blocks[block] = null;
    final preferred = keyTypeFor(block, 0);
    final types = {?preferred, 0x60, 0x61};
    for (final type in types) {
      final key = _key(block, type);
      if (key.length != 6) continue;
      final data = await communicator.mf1ReadBlock(block, type, key);
      if (data.length == 16) {
        blocks[block] = data;
        return data;
      }
    }
    return null;
  }

  Future<void> refresh() async {
    await ensureCard();
    // Read trailers first so automatic key selection can use the access bits.
    for (var sector = 0; sector < sectorCount; sector++) {
      await readBlock(mfClassicGetSectorTrailerBlockBySector(sector));
      final first = mfClassicGetFirstBlockCountBySector(sector);
      final count = mfClassicGetBlockCountBySector(sector);
      for (var offset = 0; offset < count - 1; offset++) {
        await readBlock(first + offset);
      }
      recovery.update();
    }
  }

  /// Never retry a mutation: a lost response may still mean the card changed.
  Future<void> apply(
    ValueBlockOperation operation,
    int source,
    int destination,
    int amount,
  ) async {
    if (!canApply(operation, source, destination)) {
      throw StateError(recovery.localizations.value_block_no_access);
    }
    if (operation == ValueBlockOperation.write) {
      RangeError.checkValueInInterval(amount, -0x80000000, 0x7FFFFFFF);
    } else if (operation != ValueBlockOperation.transfer) {
      RangeError.checkValueInInterval(amount, 0, 0x7FFFFFFF);
    }
    final sourceType = keyTypeFor(
      source,
      operation == ValueBlockOperation.write
          ? 1
          : operation == ValueBlockOperation.increment
          ? 2
          : 3,
    )!;
    final sourceKey = _key(source, sourceType);
    final destinationType = operation == ValueBlockOperation.write
        ? sourceType
        : keyTypeFor(destination, 3)!;
    final destinationKey = _key(destination, destinationType);
    await ensureCard();
    final target = operation == ValueBlockOperation.write
        ? source
        : destination;
    blocks[target] = null;
    if (operation == ValueBlockOperation.write) {
      final data = hexToBytes(
        MifareClassicDumpAnalyzer.intToValueBlock(amount, source),
      );
      if (!await communicator.mf1WriteBlock(
        source,
        sourceType,
        sourceKey,
        data,
      )) {
        throw StateError(recovery.localizations.value_block_failed);
      }
    } else {
      final operator = switch (operation) {
        ValueBlockOperation.increment =>
          MifareClassicValueBlockOperator.increment,
        ValueBlockOperation.decrement =>
          MifareClassicValueBlockOperator.decrement,
        _ => MifareClassicValueBlockOperator.restore,
      };
      await communicator.manipulateValueBlock(
        source,
        sourceType,
        sourceKey,
        operator,
        operation == ValueBlockOperation.transfer ? 0 : amount,
        destination,
        destinationType,
        destinationKey,
      );
    }
  }
}
