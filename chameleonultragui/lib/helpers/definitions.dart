import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';

enum ChameleonCommand {
  // basic commands
  getAppVersion(1000),
  changeDeviceMode(1001),
  getDeviceMode(1002),
  getGitVersion(1017),
  getBatteryCharge(1025),

  // slot
  setActiveSlot(1003),
  setSlotTagType(1004),
  setSlotDataDefault(1005),
  setSlotEnable(1006),
  setSlotTagNick(1007),
  getSlotTagNick(1008),
  saveSlotNicks(1009),
  getActiveSlot(1018),
  getSlotInfo(1019),
  getEnabledSlots(1023),
  deleteSlotInfo(1024),
  getAllSlotNicks(1038),

  // bootloader
  enterBootloader(1010),

  // device info
  getDeviceChipID(1011),
  getDeviceBLEAddress(1012),

  // settings
  saveSettings(1013),
  resetSettings(1014),

  // animation
  setAnimationMode(1015),
  getAnimationMode(1016),

  factoryReset(1020), // WARNING: ERASES ALL
  getDeviceType(1033),
  getDeviceSettings(1034),
  getDeviceCapabilities(1035),

  // button config
  getButtonPressConfig(1026),
  setButtonPressConfig(1027),
  getLongButtonPressConfig(1028),
  setLongButtonPressConfig(1029),

  // BLE
  bleSetConnectKey(1030),
  bleGetConnectKey(1031),
  bleClearBondedDevices(1032),
  bleGetPairEnable(1036),
  bleSetPairEnable(1037),

  // hf reader commands
  scan14ATag(2000),
  mf1SupportDetect(2001),
  mf1NTLevelDetect(2002),
  mf1StaticNestedAcquire(2003),
  mf1DarksideAcquire(2004),
  mf1NTDistanceDetect(2005),
  mf1NestedAcquire(2006),
  mf1CheckKey(2007),
  mf1ReadBlock(2008),
  mf1WriteBlock(2009),
  mf1ManipulateValueBlock(2011),
  mf1CheckKeysOfSectors(2012), // not implemented
  mf1HardNestedAcquire(2013),
  mf1StaticEncryptedNestedAcquire(2014),
  mf1CheckKeysOnBlock(2015),
  hf14ARawCommand(2010),

  // lf commands
  scanEM410Xtag(3000),
  writeEM410XtoT5577(3001),
  writeEM410XElectraToT5577(3006),
  scanHIDProxTag(3002),
  writeHIDProxToT5577(3003),
  scanVikingTag(3004),
  writeVikingToT5577(3005),

  mf1LoadBlockData(4000),
  mf1SetAntiCollision(4001),

  // mfkey32
  mf1SetDetectionEnable(4004),
  mf1GetDetectionCount(4005),
  mf1GetDetectionResult(4006),
  mf1GetDetectionStatus(4007),

  // emulator settings
  mf1GetEmulatorConfig(4009),
  mf1GetGen1aMode(4010),
  mf1SetGen1aMode(4011),
  mf1GetGen2Mode(4012),
  mf1SetGen2Mode(4013),
  mf1GetFirstBlockColl(4014),
  mf1SetFirstBlockColl(4015),
  mf1GetWriteMode(4016),
  mf1SetWriteMode(4017),

  mf0NtagGetUidMagicMode(4019),
  mf0NtagSetUidMagicMode(4020),
  mf0NtagReadEmuPageData(4021),
  mf0NtagWriteEmuPageData(4022),
  mf0NtagGetVersionData(4023),
  mf0NtagSetVersionData(4024),
  mf0NtagGetSignatureData(4025),
  mf0NtagSetSignatureData(4026),
  mf0NtagGetCounterData(4027),
  mf0NtagSetCounterData(4028),
  mf0NtagResetAuthCount(4029),
  mf0NtagGetPageCount(4030),
  mf0NtagGetWriteMode(4031),
  mf0NtagSetWriteMode(4032),
  mf0NtagSetDetectionEnable(4033),
  mf0NtagGetDetectionCount(4034),
  mf0NtagGetDetectionLog(4035),
  mf0NtagGetDetectionEnable(4036),
  mf0NtagGetEmulatorConfig(4037),

  // read slot info
  mf1GetBlockData(4008),
  mf1GetAntiCollData(4018),

  // lf emulator
  setEM410XemulatorID(5000),
  getEM410XemulatorID(5001),

  setHIDProxEmulatorID(5002),
  getHIDProxEmulatorID(5003),

  setVikingEmulatorID(5004),
  getVikingEmulatorID(5005);

  const ChameleonCommand(this.value);
  final int value;
}

enum TagType {
  unknown(0),
  em410X(100),
  em410X16(101),
  em410X32(102),
  em410X64(103),
  em410XElectra(104),
  viking(170),
  hidProx(200),
  mifareMini(1000),
  mifare1K(1001),
  mifare2K(1002),
  mifare4K(1003),
  ntag210(1107),
  ntag212(1108),
  ntag213(1100),
  ntag215(1101),
  ntag216(1102),
  ultralight(1103),
  ultralightC(1104),
  ultralight11(1105),
  ultralight21(1106);

  const TagType(this.value);
  final int value;
}

enum TagFrequency {
  unknown(0),
  lf(1),
  hf(2);

  const TagFrequency(this.value);
  final int value;
}

enum AnimationSetting {
  full(0),
  minimal(1),
  none(2),
  symmetric(3);

  const AnimationSetting(this.value);
  final int value;
}

enum MifareWriteMode {
  normal(0),
  denied(1),
  deceive(2),
  shadow(3);

  const MifareWriteMode(this.value);
  final int value;
}

enum ButtonType {
  a(65), // ord('A')
  b(66); // ord('B')

  const ButtonType(this.value);
  final int value;
}

enum ButtonConfig {
  disable(0),
  cycleForward(1),
  cycleBackward(2),
  cloneUID(3),
  chargeStatus(4);

  const ButtonConfig(this.value);
  final int value;
}

class CardData {
  Uint8List uid;
  int sak;
  Uint8List atqa;
  Uint8List ats;

  CardData(
      {required this.uid,
      required this.sak,
      required this.atqa,
      required this.ats});
}

class ChameleonMessage {
  int command;
  int status;
  Uint8List data;

  ChameleonMessage(
      {required this.command, required this.status, required this.data});
}

enum NTLevel { static, weak, hard, backdoor, unknown }

enum DarksideResult {
  vulnerable,
  fixed,
  cantFixNT,
  luckAuthOK,
  notSendingNACK,
  tagChanged,
}

class NTDistance {
  int uid;
  int distance;

  NTDistance({required this.uid, required this.distance});
}

class NestedNonce {
  int nt;
  int ntEnc;
  int parity;

  NestedNonce({required this.nt, required this.ntEnc, required this.parity});
}

class SlotNames {
  String hf;
  String lf;

  SlotNames({this.hf = '', this.lf = ''});
}

class NestedNonces {
  List<NestedNonce> nonces;

  List<int> getNoncesInfo() {
    Map<int, bool> map = {};
    int firstByteSum = 0;
    int firstByteNum = 0;

    void processNonce(int value, int parity) {
      int key = value >> 24;
      if (!(map[key] ?? false)) {
        firstByteSum += evenParity32((value & 0xff000000) | (parity & 0x08));
        map[key] = true;
        firstByteNum++;
      }
    }

    for (NestedNonce nonce in nonces) {
      processNonce(nonce.nt, nonce.parity >> 4);
      processNonce(nonce.ntEnc, nonce.parity & 0x0F);
    }

    return [firstByteSum, firstByteNum];
  }

  Uint8List getHardNested(int uid) {
    // format:
    // 0-3 bytes - uid
    // 4 byte - target block (unused)
    // 5 byte - target key type (unused)
    // next is loop with all nonces
    // 0-3 bytes - nt
    // 4-8 bytes - ntEnc
    // 9 byte - parity
    Uint8List list = Uint8List(6 + nonces.length * 9);
    list.setRange(0, 4, u32ToBytes(uid));
    int pointer = 6;
    for (NestedNonce nonce in nonces) {
      list.setRange(pointer, pointer + 4, u32ToBytes(nonce.nt));
      list.setRange(pointer + 4, pointer + 8, u32ToBytes(nonce.ntEnc));
      list[pointer + 8] = nonce.parity;
      pointer += 9;
    }

    return list;
  }

  NestedNonces({required this.nonces});
}

class Darkside {
  int uid;
  int nt1;
  int par;
  int ks1;
  int nr;
  int ar;

  Darkside(
      {required this.uid,
      required this.nt1,
      required this.par,
      required this.ks1,
      required this.nr,
      required this.ar});
}

class DetectionResult {
  int block;
  int type;
  bool isNested;
  int uid;
  int nt;
  int nr;
  int ar;

  DetectionResult(
      {required this.block,
      required this.type,
      required this.isNested,
      required this.uid,
      required this.nt,
      required this.nr,
      required this.ar});
}

class FirmwareVersion {
  bool legacyProtocol;
  int version;

  FirmwareVersion({required this.legacyProtocol, required this.version});
}

class SlotTypes {
  TagType hf;
  TagType lf;

  bool match({TagType type = TagType.unknown}) {
    return hf == type || lf == type;
  }

  bool notMatch({TagType type = TagType.unknown}) {
    return hf != type || lf != type;
  }

  SlotTypes({this.hf = TagType.unknown, this.lf = TagType.unknown});
}

class EnabledSlotInfo {
  bool hf;
  bool lf;

  bool any() {
    return hf || lf;
  }

  EnabledSlotInfo({this.hf = false, this.lf = false});
}

class BatteryCharge {
  int voltage;
  int percent;

  BatteryCharge({required this.voltage, required this.percent});
}

class EmulatorSettings {
  bool isDetectionEnabled;
  bool isGen1a;
  bool isGen2;
  bool isAntiColl;
  MifareWriteMode writeMode;

  EmulatorSettings(
      {required this.isDetectionEnabled,
      required this.isGen1a,
      required this.isGen2,
      required this.isAntiColl,
      required this.writeMode});
}

class DeviceSettings {
  AnimationSetting animation;
  ButtonConfig aPress;
  ButtonConfig bPress;
  ButtonConfig aLongPress;
  ButtonConfig bLongPress;
  bool pairingEnabled;
  String key;

  DeviceSettings(
      {this.animation = AnimationSetting.none,
      this.aPress = ButtonConfig.disable,
      this.bPress = ButtonConfig.disable,
      this.aLongPress = ButtonConfig.disable,
      this.bLongPress = ButtonConfig.disable,
      this.pairingEnabled = false,
      this.key = ""});
}

enum MifareClassicValueBlockOperator {
  decrement(0xC0),
  increment(0xC1),
  restore(0xC2);

  const MifareClassicValueBlockOperator(this.value);
  final int value;
}

abstract class LFCard {
  TagType type;
  Uint8List uid;

  @override
  String toString() {
    return bytesToHexSpace(uid);
  }

  String toViewableString() {
    return toString();
  }

  LFCard({required this.type, required this.uid});
}

class EM410XCard extends LFCard {
  factory EM410XCard.fromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      return EM410XCard(type: TagType.em410X, uid: Uint8List(0));
    }

    if (bytes.length == 5 || bytes.length == 13) {
      return EM410XCard(
          type: bytes.length == 13 ? TagType.em410XElectra : TagType.em410X,
          uid: bytes);
    }

    TagType type = TagType.em410X;
    Uint8List uid = bytes;

    if (bytes.length >= 2) {
      type = numberToChameleonTag(bytesToU16(bytes.sublist(0, 2)));
      int uidLength = uidSizeForLfTag(type);
      if (uidLength > 0 && bytes.length >= uidLength + 2) {
        uid = bytes.sublist(2, 2 + uidLength);
      } else {
        uid = bytes.sublist(0, bytes.length > 5 ? 5 : bytes.length);
        type = TagType.em410X;
      }
    }

    return EM410XCard(
      type: type,
      uid: uid,
    );
  }

  factory EM410XCard.fromUID(String uid, {TagType type = TagType.em410X}) {
    return EM410XCard(type: type, uid: hexToBytes(uid));
  }

  EM410XCard({required super.type, required super.uid});
}

class HIDCard extends LFCard {
  int hidType; // u8
  int facilityCode; // u32
  int issueLevel; // u8
  int oem; // u16

  factory HIDCard.fromBytes(Uint8List bytes) {
    return HIDCard(
        hidType: bytesToU8(bytes.sublist(0, 1)),
        facilityCode: bytesToU32(bytes.sublist(1, 5)),
        uid: bytes.sublist(5, 10),
        issueLevel: bytesToU8(bytes.sublist(10, 11)),
        oem: bytesToU16(bytes.sublist(11, 13)));
  }

  factory HIDCard.fromUID(String uid) {
    return HIDCard.fromBytes(hexToBytes(uid));
  }

  @override
  String toString() {
    return bytesToHexSpace(Uint8List.fromList([
      hidType,
      ...u32ToBytes(facilityCode),
      ...uid,
      issueLevel,
      ...u16ToBytes(oem)
    ]));
  }

  @override
  String toViewableString() {
    int cnHigh = uid[0];
    int cnLow = (uid[1] << 24) | (uid[2] << 16) | (uid[3] << 8) | uid[4];

    int uidNumber = (cnHigh << 32) | cnLow;

    String out =
        '$uidNumber (${bytesToHexSpace(uid)}, ${getNameForHIDProxType(hidType)}';

    if (facilityCode != 0) {
      out += ', FC: $facilityCode';
    }

    if (issueLevel != 0) {
      out += ', IL: $issueLevel';
    }

    if (oem != 0) {
      out += ', OEM: $oem';
    }

    out += ')';

    return out;
  }

  HIDCard(
      {super.type = TagType.hidProx,
      required this.hidType,
      required this.facilityCode,
      required super.uid,
      required this.issueLevel,
      required this.oem});
}

class VikingCard extends LFCard {
  factory VikingCard.fromBytes(Uint8List bytes) {
    return VikingCard(uid: bytes);
  }

  factory VikingCard.fromUID(String uid) {
    return VikingCard.fromBytes(hexToBytes(uid));
  }

  VikingCard({
    super.type = TagType.viking,
    required super.uid,
  });
}
