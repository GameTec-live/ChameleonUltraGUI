import 'package:chameleonultragui/helpers/classic_coverage.dart';
import 'package:chameleonultragui/helpers/sl1_profile.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';

import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Recovery
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;

extension PartitionList<E> on List<E> {
  List<List<E>> partition(int size) {
    assert(size > 0);
    final out = <List<E>>[];
    for (var i = 0; i < length; i += size) {
      final end = i + size < length ? i + size : length;
      out.add(sublist(i, end));
    }
    return out;
  }
}

enum ChameleonKeyCheckmark { none, found, checking, disabled }

class MifareClassicRecovery {
  late ChameleonGUIState appState;
  late AppLocalizations localizations;
  String error;
  String state;
  bool allKeysExists;
  List<Dictionary> dictionaries;
  Dictionary? selectedDictionary;
  List<ChameleonKeyCheckmark> checkMarks;
  List<Uint8List> validKeys;
  List<Uint8List> cardData;
  List<Map<String, dynamic>> readCoverage = [];
  bool readCoverageEdited = false;
  CardData? _acquisitionIdentity;
  bool _acquisitionComplete = false;
  ClassicCoverage? _acquiredCoverage;
  final Set<String> _readVerifiedKeys = {};
  String _identity(CardData card) =>
      '${Sl1Profile.encodeBytes(card.uid)}:${Sl1Profile.encodeBytes(card.atqa)}:${card.sak}:${Sl1Profile.encodeBytes(card.ats)}';
  void bindIdentity(CardData card) {
    _acquisitionIdentity = CardData(
      uid: Uint8List.fromList(card.uid),
      atqa: Uint8List.fromList(card.atqa),
      sak: card.sak,
      ats: Uint8List.fromList(card.ats),
    );
    _acquisitionComplete = false;
    _acquiredCoverage = null;
    _readVerifiedKeys.clear();
  }

  Future<void> requireIdentity() async {
    final expected = _acquisitionIdentity;
    if (expected == null) {
      throw StateError(
        'Read session has no bound card identity; scan the card again',
      );
    }
    final current = expected.ats.isEmpty
        ? await appState.communicator!.scan14443aTag()
        : await appState.communicator!.scan14443aTagWithAts();
    if (current == null || _identity(current) != _identity(expected)) {
      _acquisitionComplete = false;
      throw StateError(
        'Card identity changed or disappeared during acquisition; scan the intended card again',
      );
    }
  }

  ClassicCoverage _observedCoverage() {
    final expected = _acquisitionIdentity!;
    final count = mfClassicGetBlockCount(
      mifareClassicType,
      isEV1: isMifareClassicEV1,
    );
    final sectors = mfClassicGetSectorCount(
      mifareClassicType,
      isEV1: isMifareClassicEV1,
    );
    final c = <String, dynamic>{
      'type': isMifareClassicEV1
          ? ClassicCoverage.nativeEv1Type
          : sl1Type(mfClassicGetChameleonTagType(mifareClassicType)),
      'provenance': 'read',
      'blocks': readCoverage.take(count).toList(),
      'keys': List.generate(
        sectors,
        (_) => {
          'a': {'value': null, 'status': 'unknown', 'evidence': null},
          'b': {'value': null, 'status': 'unknown', 'evidence': null},
        },
      ),
    };
    for (var sector = 0; sector < c['keys'].length; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        final key = getSectorKey(sector, keyType);
        if (key.length == 6) {
          c['keys'][sector][keyType == 0 ? 'a' : 'b'] = {
            'value': Sl1Profile.encodeBytes(key),
            'status': _readVerifiedKeys.contains('$sector/$keyType')
                ? 'verified'
                : 'provided',
            'evidence': _readVerifiedKeys.contains('$sector/$keyType')
                ? 'Classic authenticated read for ${_identity(expected)}'
                : null,
          };
        }
        if (keyType == 1 && !_readVerifiedKeys.contains('$sector/1')) {
          final trailer = mfClassicGetSectorTrailerBlockBySector(sector);
          final observed = c['blocks'][trailer]['data'] as String;
          final b = observed.substring(20);
          if (!b.contains('?') &&
              c['blocks'][trailer]['key'] == 'A' &&
              c['blocks'][trailer]['status'] == 'read') {
            c['keys'][sector]['b'] = {
              'value': b,
              'status': 'verified',
              'evidence':
                  'Key B bytes read under trailer access conditions with Key A',
            };
          }
        }
      }
    }
    return ClassicCoverage.fromClassic(c, nativeEv1: isMifareClassicEV1);
  }

  ClassicCoverage coverageFor(CardSave card) {
    final expected = _acquisitionIdentity;
    final savedIdentity = CardData(
      uid: hexToBytes(card.uid),
      atqa: card.atqa,
      sak: card.sak,
      ats: card.ats,
    );
    if (!_acquisitionComplete ||
        expected == null ||
        _acquiredCoverage == null ||
        _identity(savedIdentity) != _identity(expected)) {
      throw StateError(
        'Acquisition is incomplete or does not match the saved identity',
      );
    }
    final coverage = _acquiredCoverage!.copy();
    if (card.tag != mfClassicGetChameleonTagType(mifareClassicType) ||
        card.data
            .skip(coverage.json['blocks'].length as int)
            .any((b) => b.isNotEmpty)) {
      throw const FormatException(
        'Card geometry differs from the canonical acquisition; retain all source observations',
      );
    }
    coverage.reconcile(card.data);
    return coverage;
  }

  Sl1Profile profileFor(CardSave card) {
    if (isMifareClassicEV1) {
      throw const FormatException(
        'Classic 1K EV1 includes 72 blocks and uses native archival coverage, not common profile v1',
      );
    }
    final coverage = coverageFor(card);
    return Sl1Profile.fromJson({
      'format': 'chameleon-sl1-profile',
      'version': 1,
      'name': card.name,
      'hf14a': {
        'uid': card.uid.replaceAll(' ', '').toUpperCase(),
        'atqa': Sl1Profile.encodeBytes(card.atqa.reversed),
        'sak': Sl1Profile.encodeBytes([card.sak]),
        'ats': Sl1Profile.encodeBytes(card.ats),
      },
      'classic': coverage.json,
      'cardAuth': null,
    });
  }

  double dumpProgress;
  double? hardnestedProgress;
  double? keyCheckProgress;
  void Function() update;
  MifareClassicType mifareClassicType;
  bool isMifareClassicEV1;

  MifareClassicRecovery(
      {required this.appState,
      required this.update,
      required this.localizations,
      this.error = '',
      this.state = '',
      this.allKeysExists = false,
      this.dictionaries = const [],
      this.dumpProgress = 0,
      this.selectedDictionary,
      this.mifareClassicType = MifareClassicType.none,
      this.isMifareClassicEV1 = false,
      List<ChameleonKeyCheckmark>? checkMarks,
      List<Uint8List>? validKeys,
      List<Uint8List>? cardData})
      : checkMarks =
            checkMarks ?? List.generate(80, (_) => ChameleonKeyCheckmark.none),
        validKeys = validKeys ?? List.generate(80, (_) => Uint8List(0)),
        cardData = cardData ?? List.generate(256, (_) => Uint8List(0)) {
    initializeEV1();
  }

  Future<bool> checkKeysOnSector(
      List<Uint8List> keys, int keyType, int sector) async {
    await requireIdentity();
    state = localizations.checking_keys(keys.length);
    Uint8List? key;
    keyCheckProgress = null;
    int chunkSize =
        appState.connector?.connectionType == ConnectionType.ble ? 32 : 64;

    if (getSectorState(sector, keyType) != ChameleonKeyCheckmark.found &&
        getSectorState(sector, keyType) != ChameleonKeyCheckmark.disabled) {
      setCheckingSector(sector, keyType);
      int totalChunks = keys.partition(chunkSize).length;

      for (var chunk in keys.partition(chunkSize)) {
        key = await appState.communicator!.mf1AuthMultipleKeys(
            mfClassicGetSectorTrailerBlockBySector(sector),
            0x60 + keyType,
            chunk,
        );
        await requireIdentity();
        if (key != null) {
          setKeyAsFound(sector, keyType, key);
          keyCheckProgress = null;
          await recheckKey(key, sector);
          return true;
        } else if (totalChunks > 10) {
          keyCheckProgress = (keyCheckProgress ?? 0) + 1 / totalChunks;
          update();
        }
      }

      if (key == null) {
        setMissingSector(sector, keyType);
      }
    }

    if (keyType == 0 &&
        getSectorState(sector, 0) == ChameleonKeyCheckmark.found &&
        getSectorState(sector, 1) != ChameleonKeyCheckmark.found &&
        getSectorState(sector, 1) != ChameleonKeyCheckmark.disabled &&
        key != null) {
      Uint8List block = await appState.communicator!.mf1ReadBlock(
          mfClassicGetSectorTrailerBlockBySector(sector), 0x60 + keyType, key);
      if (block.length == 16) {
        Uint8List bKey = block.sublist(10);
        if (bytesToHex(bKey) != bytesToHex(Uint8List(6))) {
          keyCheckProgress = null;
          await recheckKey(key, sector);
          return true;
        }
      }
    }

    setMissingSector(sector, keyType);
    keyCheckProgress = null;
    return false;
  }

  Future<void> initialize() async {
    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }

    if (_acquisitionIdentity == null) {
      final selected = await appState.communicator!.scan14443aTag();
      if (selected == null) {
        throw StateError('Card disappeared during initialization');
      }
      bindIdentity(selected);
    }
    await requireIdentity();
    var mifare = await appState.communicator!.detectMf1Support();

    if (mifare) {
      mifareClassicType = await mfClassicGetType(appState.communicator!);
    } else {
      appState.log!.e("Not Mifare Classic tag!");
    }

    isMifareClassicEV1 =
        await appState.communicator!.mf1Auth(0x45, 0x61, gMifareClassicKeys[3]);
    initializeEV1();
  }

  Future<void> recheckKey(Uint8List key, int startingSector) async {
    for (var sector = startingSector;
        sector <
            mfClassicGetSectorCount(mifareClassicType,
                isEV1: isMifareClassicEV1);
        sector++) {
      await requireIdentity();
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.none) {
          state = localizations.checking_keys(1);
          appState.log!.d(
              "Checking found key ${bytesToHex(key)} on sector $sector, key type $keyType");
          setCheckingSector(sector, keyType);

          if (await appState.communicator!.mf1Auth(
              mfClassicGetSectorTrailerBlockBySector(sector),
              0x60 + keyType,
              key)) {
            // Found valid key
            setKeyAsFound(sector, keyType, key);
          } else {
            setMissingSector(sector, keyType);
          }

          await requireIdentity();
          update();
        }
      }
    }
  }

  void initializeEV1() {
    if (isMifareClassicEV1) {
      setKeyAsFound(16, 0, gMifareClassicKeys[4]); // MFC EV1 SIGNATURE 16 A
      setKeyAsFound(16, 1, gMifareClassicKeys[5]); // MFC EV1 SIGNATURE 16 B
      setKeyAsFound(17, 0, gMifareClassicKeys[6]); // MFC EV1 SIGNATURE 17 A
      setKeyAsFound(17, 1, gMifareClassicKeys[3]); // MFC EV1 SIGNATURE 17 B
    }
  }

  Future<void> checkKeys({bool skipDefaultDictionary = false}) async {
    initializeEV1();

    for (var sector = 0;
        sector <
            mfClassicGetSectorCount(mifareClassicType,
                isEV1: isMifareClassicEV1);
        sector++) {
      List<Uint8List> keyList = [
        ...selectedDictionary!.keys,
        if (!skipDefaultDictionary)
          ...gMifareClassicKeys
              .where((key) => !selectedDictionary!.keys.contains(key))
      ];

      for (var keyType = 0; keyType < 2; keyType++) {
        await checkKeysOnSector(keyList, keyType, sector);
      }
    }

    // Key check part competed, checking found keys
    allKeysExists = true;
    for (var sector = 0;
        sector <
            mfClassicGetSectorCount(mifareClassicType,
                isEV1: isMifareClassicEV1);
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) != ChameleonKeyCheckmark.found &&
            getSectorState(sector, keyType) != ChameleonKeyCheckmark.disabled) {
          allKeysExists = false;
        }
      }
    }

    state = "";
    update();
  }

  Future<void> recoverKeys() async {
    state = localizations.checking_card_info;
    update();

    error = "";
    bool hasKey = false;
    bool hasBackdoor = await mfClassicHasBackdoor(appState.communicator!);
    (int, NestedNonces, NestedNonces, Uint8List)? backdoorInfo;
    if (hasBackdoor) {
      backdoorInfo = await appState.communicator!
          .getMf1StaticEncryptedNestedAcquire(
              sectorCount: mfClassicGetSectorCount(mifareClassicType,
                  isEV1: isMifareClassicEV1));
    }

    DarksideResult darkside = DarksideResult.fixed;
    for (var sector = 0;
        sector <
                mfClassicGetSectorCount(mifareClassicType,
                    isEV1: isMifareClassicEV1) &&
            !hasKey;
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.found) {
          hasKey = true;
          break;
        }
      }
    }

    update();

    bool isStaticEncrypted = false;

    if (hasBackdoor) {
      isStaticEncrypted = await mfClassicIsStaticEncrypted(
          appState.communicator!, 0, 4, backdoorInfo!.$4);
    }

    NTLevel prng = await appState.communicator!.getMf1NTLevel();
    update();

    if (!hasKey && !isStaticEncrypted && prng != NTLevel.static) {
      state = localizations.checking_or_running_darkside;
      update();

      try {
        setCheckingSector(0, 1);
        darkside = await appState.communicator!.checkMf1Darkside();
      } catch (_) {
        setMissingSector(0, 1);
      }

      if (darkside == DarksideResult.vulnerable) {
        // recover with darkside
        var data =
            await appState.communicator!.getMf1Darkside(0x03, 0x61, true, 15);
        var darkside = DarksideDart(uid: data.uid, items: []);
        bool found = false;
        update();

        for (var tries = 0; tries < 5 && !found; tries++) {
          darkside.items.add(DarksideItemDart(
              nt1: data.nt1,
              ks1: data.ks1,
              par: data.par,
              nr: data.nr,
              ar: data.ar));

          var keys = await recovery.darkside(darkside);
          if (keys.isNotEmpty) {
            appState.log!.d("Darkside: Found keys: $keys. Checking them...");

            if (await checkKeysOnSector(mfClassicConvertKeys(keys), 1, 0)) {
              found = true;
              hasKey = true;

              break;
            }
          } else {
            appState.log!.d("Can't find keys, retrying...");
            data = await appState.communicator!
                .getMf1Darkside(0x03, 0x61, false, 15);
          }
        }

        if (!found) {
          setMissingSector(0, 1);
        }
      }
    }

    update();

    if (!hasKey && hasBackdoor && prng == NTLevel.weak && !isStaticEncrypted) {
      state = localizations.backdoor_recovery_of_non_static_encrypted;
      setCheckingSector(0, 0);

      for (var i = 0; i < 3; i++) {
        NTDistance distance = await appState.communicator!
            .getMf1NTDistance(0, 0x64, backdoorInfo!.$4);

        NestedNonces nonces = await appState.communicator!
            .getMf1NestedNonces(0, 0x64, backdoorInfo.$4, 0, 0x60, level: prng);

        var nested = NestedDart(
            uid: distance.uid,
            distance: distance.distance,
            nt0: nonces.nonces[0].nt,
            nt0Enc: nonces.nonces[0].ntEnc,
            par0: nonces.nonces[0].parity,
            nt1: nonces.nonces[1].nt,
            nt1Enc: nonces.nonces[1].ntEnc,
            par1: nonces.nonces[1].parity);

        List<int> keys = await recovery.nested(nested);

        if (keys.isNotEmpty) {
          appState.log!.d("Found keys: $keys. Checking them...");
          if (await checkKeysOnSector(mfClassicConvertKeys(keys), 0, 0)) {
            break;
          }
        }
      }
    }

    Uint8List validKey = Uint8List(0);
    int validKeyBlock = 0;
    int validKeyType = -1;

    for (var sector = 0;
        sector <
            mfClassicGetSectorCount(mifareClassicType,
                isEV1: isMifareClassicEV1);
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.found) {
          validKey = getSectorKey(sector, keyType);
          validKeyBlock = mfClassicGetSectorTrailerBlockBySector(sector);
          validKeyType = keyType;
          if (!isStaticEncrypted) {
            isStaticEncrypted = await mfClassicIsStaticEncrypted(
                appState.communicator!, validKeyBlock, validKeyType, validKey);
          }
          break;
        }
      }
    }

    if ((isStaticEncrypted || (validKeyType == -1 && hasBackdoor)) &&
        backdoorInfo != null) {
      prng = NTLevel.backdoor;
    }

    if (validKeyType == -1 && prng != NTLevel.backdoor) {
      error = localizations.recovery_error_no_keys_darkside;
      state = "";
      return;
    }

    int tries = [NTLevel.backdoor, NTLevel.static].contains(prng) ? 1 : 5;

    for (var sector = 0;
        sector <
            mfClassicGetSectorCount(mifareClassicType,
                isEV1: isMifareClassicEV1);
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.none) {
          String attackType;

          switch (prng) {
            case NTLevel.static:
              attackType = "Static Nested";
            case NTLevel.weak:
              attackType = "Nested";
            case NTLevel.hard:
              attackType = "Hard Nested";
            case NTLevel.backdoor:
              attackType = localizations.has_backdoor_support;
            case NTLevel.unknown:
              attackType = "";
          }

          state = localizations.collecting_nonces(attackType);
          setCheckingSector(sector, keyType);

          NTDistance? distance;
          NestedNonces? nonces;

          if (prng != NTLevel.backdoor) {
            distance = await appState.communicator!
                .getMf1NTDistance(validKeyBlock, 0x60 + validKeyType, validKey);
          }

          bool found = false;
          for (var i = 0; i < tries && !found; i++) {
            List<int> keys = [];

            if (prng == NTLevel.hard) {
              hardnestedProgress = 0;
              update();

              var result = await collectHardnestedNonces(
                  validKeyBlock,
                  0x60 + validKeyType,
                  validKey,
                  mfClassicGetSectorTrailerBlockBySector(sector),
                  0x60 + keyType);

              if (result is String) {
                setMissingSector(sector, keyType);
                error = result;
                return;
              } else {
                nonces = result as NestedNonces;
              }
            } else if (prng != NTLevel.backdoor) {
              nonces = await appState.communicator!.getMf1NestedNonces(
                  validKeyBlock,
                  0x60 + validKeyType,
                  validKey,
                  mfClassicGetSectorTrailerBlockBySector(sector),
                  0x60 + keyType,
                  level: prng);
            }

            state = localizations.recovering_key(attackType);
            update();

            if (prng == NTLevel.weak) {
              var nested = NestedDart(
                  uid: distance!.uid,
                  distance: distance.distance,
                  nt0: nonces!.nonces[0].nt,
                  nt0Enc: nonces.nonces[0].ntEnc,
                  par0: nonces.nonces[0].parity,
                  nt1: nonces.nonces[1].nt,
                  nt1Enc: nonces.nonces[1].ntEnc,
                  par1: nonces.nonces[1].parity);

              keys = await recovery.nested(nested);
            } else if (prng == NTLevel.static) {
              var nested = StaticNestedDart(
                uid: distance!.uid,
                keyType: 0x60 + validKeyType,
                nt0: nonces!.nonces[0].nt,
                nt0Enc: nonces.nonces[0].ntEnc,
                nt1: nonces.nonces[1].nt,
                nt1Enc: nonces.nonces[1].ntEnc,
              );

              keys = await recovery.staticNested(nested);
            } else if (prng == NTLevel.hard) {
              var nested =
                  HardNestedDart(nonces: nonces!.getHardNested(distance!.uid));
              keys = await recovery.hardNested(nested);
            } else if (prng == NTLevel.backdoor) {
              setCheckingSector(sector, 1);

              var possibleAKeys = await recovery.staticEncryptedNested(
                  StaticEncryptedNestedDart(
                      uid: backdoorInfo!.$1,
                      nt: backdoorInfo.$2.nonces[sector].nt,
                      ntEnc: backdoorInfo.$2.nonces[sector].ntEnc,
                      ntParEnc: backdoorInfo.$2.nonces[sector].parity));

              var possibleBKeys = await recovery.staticEncryptedNested(
                  StaticEncryptedNestedDart(
                      uid: backdoorInfo.$1,
                      nt: backdoorInfo.$3.nonces[sector].nt,
                      ntEnc: backdoorInfo.$3.nonces[sector].ntEnc,
                      ntParEnc: backdoorInfo.$3.nonces[sector].parity));

              var filtered = await StaticEncryptedKeysFilterAsync.filterKeys(
                  possibleAKeys,
                  possibleBKeys,
                  backdoorInfo.$2.nonces[sector].nt,
                  backdoorInfo.$3.nonces[sector].nt);

              if (checkMarks[sector + 40] != ChameleonKeyCheckmark.found &&
                  checkMarks[sector + 40] != ChameleonKeyCheckmark.disabled &&
                  await checkKeysOnSector(
                      mfClassicConvertKeys(filtered.$2.reversed.toList()),
                      1,
                      sector)) {
                checkMarks[sector + 40] = ChameleonKeyCheckmark.found;
              }

              if (checkMarks[sector] == ChameleonKeyCheckmark.found ||
                  checkMarks[sector] == ChameleonKeyCheckmark.disabled) {
                found = true;
                break;
              } else if (await checkKeysOnSector(
                  mfClassicConvertKeys(
                      await StaticEncryptedKeysFilterAsync.findMatchingKeys(
                          backdoorInfo.$3.nonces[sector].nt,
                          bytesToU64(Uint8List.fromList(
                              [0, 0, ...validKeys[sector + 40]])),
                          backdoorInfo.$2.nonces[sector].nt,
                          possibleAKeys)),
                  0,
                  sector)) {
                found = true;
                break;
              } else if (await checkKeysOnSector(
                  mfClassicConvertKeys(filtered.$1.reversed.toList()),
                  0,
                  sector)) {
                found = true;
                break;
              }

              setMissingSector(sector, 0);
              setMissingSector(sector, 1);
            }

            if (keys.isNotEmpty) {
              appState.log!.d("Found keys: $keys. Checking them...");

              if (await checkKeysOnSector(
                  mfClassicConvertKeys(keys), keyType, sector)) {
                found = true;

                break;
              }
            } else {
              appState.log!.e("Can't find keys, retrying...");
            }
          }
        }
      }
    }

    state = "";
    allKeysExists = true;
    for (var sector = 0;
        sector <
            mfClassicGetSectorCount(mifareClassicType,
                isEV1: isMifareClassicEV1);
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) != ChameleonKeyCheckmark.found &&
            getSectorState(sector, keyType) != ChameleonKeyCheckmark.disabled) {
          allKeysExists = false;
        }
      }
    }
    update();
  }

  Future<void> dumpData() async {
    _acquisitionComplete = false;
    _acquiredCoverage = null;
    _readVerifiedKeys.clear();
    await requireIdentity();
    cardData = List.generate(256, (_) => Uint8List(0));
    readCoverageEdited = false;
    readCoverage = List.generate(
      256,
      (_) => <String, dynamic>{
        'data': '??' * 16,
        'status': 'unread',
        'key': null,
        'errors': <Map<String, dynamic>>[],
      },
    );

    for (var sector = 0;
        sector <
            mfClassicGetSectorCount(mifareClassicType,
                isEV1: isMifareClassicEV1);
        sector++) {
      await requireIdentity();
      for (var block = 0;
          block < mfClassicGetBlockCountBySector(sector);
          block++) {
        for (var keyType = 0; keyType < 2; keyType++) {
          appState.log!
              .d("Dumping sector $sector, block $block with key $keyType");

          if (getSectorKey(sector, keyType).isEmpty) {
            appState.log!.w("Skipping missing key");
            continue;
          }

          final coverage =
              readCoverage[block + mfClassicGetFirstBlockCountBySector(sector)];
          Uint8List blockData;
          try {
            blockData = await appState.communicator!.mf1ReadBlock(
              block + mfClassicGetFirstBlockCountBySector(sector),
              0x60 + keyType,
              getSectorKey(sector, keyType));
          } catch (error) {
            coverage['status'] = 'error';
            coverage['errors'].add({
              'key': keyType == 0 ? 'A' : 'B',
              'status': null,
              'reason': error.toString(),
            });
            continue;
          }
          if (blockData.length != 16) {
            coverage['status'] = 'error';
            coverage['errors'].add({
              'key': keyType == 0 ? 'A' : 'B',
              'status': appState.communicator!.lastMf1ReadStatus,
              'reason': 'Read returned no complete block',
            });
            continue;
            }
          _readVerifiedKeys.add('$sector/$keyType');
          coverage['status'] = 'read';
          coverage['key'] = keyType == 0 ? 'A' : 'B';
          coverage['data'] = Sl1Profile.encodeBytes(blockData);

          if (mfClassicGetSectorTrailerBlockBySector(sector) ==
              block + mfClassicGetFirstBlockCountBySector(sector)) {
            // Key A is masked on every trailer read. Key B is readable only
            // for trailer access conditions 000, 001 or 010, with Key A.
            final validAccess =
                (((blockData[6] & 15) ^ (blockData[7] >> 4)) == 15 &&
                ((blockData[6] >> 4) ^ (blockData[8] & 15)) == 15 &&
                ((blockData[7] & 15) ^ (blockData[8] >> 4)) == 15);
            final access =
                ((blockData[7] >> 7) & 1) * 4 +
                ((blockData[8] >> 3) & 1) * 2 +
                ((blockData[8] >> 7) & 1);
            final readableB =
                validAccess && keyType == 0 && [0, 1, 2].contains(access);
            coverage['data'] =
                '??' * 6 +
                Sl1Profile.encodeBytes(blockData.sublist(6, 10)) +
                (readableB
                    ? Sl1Profile.encodeBytes(blockData.sublist(10, 16))
                    : '??' * 6);
          }

          if (mfClassicGetSectorTrailerBlockBySector(sector) ==
              block + mfClassicGetFirstBlockCountBySector(sector)) {
            // set keys in sector trailer
            if (getSectorKey(sector, 0).isNotEmpty) {
              blockData.setRange(0, 6, getSectorKey(sector, 0));
            }

            if (getSectorKey(sector, 1).isNotEmpty &&
                (coverage['data'] as String).substring(20).contains('?')) {
              blockData.setRange(10, 16, getSectorKey(sector, 1));
            }
          }

          cardData[block + mfClassicGetFirstBlockCountBySector(sector)] =
              blockData;

          dumpProgress = (block + mfClassicGetFirstBlockCountBySector(sector)) /
              (mfClassicGetBlockCount(mifareClassicType,
                  isEV1: isMifareClassicEV1));

          update();

          break;
        }
      }
      await requireIdentity();
    }
    await requireIdentity();
    _acquisitionComplete = true;
    _acquiredCoverage = _observedCoverage();
    cardData = _acquiredCoverage!.project(fillKnownKeys: true);
  }

  Future<dynamic> collectHardnestedNonces(int block, int keyType,
      Uint8List knownKey, int targetBlock, int targetKeyType) async {
    NestedNonces nonces = NestedNonces(nonces: []);
    while (true) {
      var collectedNonces = await appState.communicator!.getMf1NestedNonces(
          block, keyType, knownKey, targetBlock, targetKeyType,
          level: NTLevel.hard);
      nonces.nonces.addAll(collectedNonces.nonces);
      List info = nonces.getNoncesInfo();
      appState.log!.d(
          "Collected ${nonces.nonces.length} nonces, sum ${info[0]}, num ${info[1]}");

      if (nonces.nonces.isEmpty) {
        return localizations.recovery_old_firmware;
      }

      hardnestedProgress = info[1] / 256;
      state = localizations.hardnested_collecting_nonces(
          (hardnestedProgress! * 256).toInt().toString());
      update();
      if (info[1] == 256) {
        if ([
          0,
          32,
          56,
          64,
          80,
          96,
          104,
          112,
          120,
          128,
          136,
          144,
          152,
          160,
          176,
          192,
          200,
          224,
          256
        ].contains(info[0])) {
          break;
        }

        appState.log!.e("Got wrong sum, trying to collect nonces again...");
        nonces.nonces = [];
      }
    }

    hardnestedProgress = null;
    return nonces;
  }

  void setKeyAsFound(int sector, int keyType, Uint8List key) {
    checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.found;
    validKeys[sector + (keyType * 40)] = key;
    update();
  }

  void setCheckingSector(int sector, int keyType) {
    if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.none) {
      checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.checking;
    }
    update();
  }

  void setMissingSector(int sector, int keyType) {
    if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.checking) {
      checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.none;
      update();
    }
  }

  Uint8List getSectorKey(int sector, int keyType) {
    return validKeys[sector + (keyType * 40)];
  }

  ChameleonKeyCheckmark getSectorState(int sector, int keyType) {
    return checkMarks[sector + (keyType * 40)];
  }
}
