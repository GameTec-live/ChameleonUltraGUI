---@meta
-- Editor declarations only. Never require this file in a plugin.
-- Mirrors lib/plugins/{api,device_api,saved_data_api,settings_api,recovery_api,runtime}.dart.
-- Arrays are 1-based; device slots and blocks remain 0-based.
---@alias Bytes integer[]
---@alias TagType "unknown"|"em410X"|"em410X16"|"em410X32"|"em410X64"|"em410XElectra"|"pac"|"viking"|"jablotron"|"hidProx"|"ioProx"|"idteck"|"mifareMini"|"mifare1K"|"mifare2K"|"mifare4K"|"ntag210"|"ntag212"|"ntag213"|"ntag215"|"ntag216"|"ultralight"|"ultralightC"|"ultralight11"|"ultralight21"|"hf14a4"
---@alias TagFrequency "unknown"|"lf"|"hf"
---@alias AnimationSetting "full"|"minimal"|"none"|"symmetric"
---@alias MifareWriteMode "normal"|"denied"|"deceive"|"shadow"
---@alias Mf1PrngType "static"|"weak"|"hard"
---@alias ButtonType "a"|"b"
---@alias ButtonConfig "disable"|"cycleForward"|"cycleBackward"|"cloneUID"|"chargeStatus"|"nfcFieldGenerator"
---@alias NTLevel "static"|"weak"|"hard"|"backdoor"|"unknown"
---@alias DarksideResult "vulnerable"|"fixed"|"cantFixNT"|"luckAuthOK"|"notSendingNACK"|"tagChanged"
---@alias BatteryCondition "critical"|"low"|"fair"|"good"|"excellent"|"unknown"

---@class CardData
---@field uid Bytes
---@field sak integer
---@field atqa Bytes
---@field ats Bytes

---@class ChameleonMessage
---@field command integer
---@field status integer
---@field data Bytes

---@class NTDistance
---@field uid integer
---@field distance integer

---@class NestedNonce
---@field nt integer
---@field ntEnc integer
---@field parity integer

---@class SlotNames
---@field hf string
---@field lf string

---@class Darkside
---@field uid integer
---@field nt1 integer
---@field par integer
---@field ks1 integer
---@field nr integer
---@field ar integer

---@class FirmwareVersion
---@field legacyProtocol boolean
---@field version integer

---@class SlotTypes
---@field hf TagType
---@field lf TagType

---@class EnabledSlotInfo
---@field hf boolean
---@field lf boolean

---@class BatteryCharge
---@field voltage integer
---@field percent integer
---@field condition BatteryCondition?

---@class EmulatorSettings
---@field isDetectionEnabled boolean
---@field isGen1a boolean
---@field isGen2 boolean
---@field isAntiColl boolean
---@field writeMode MifareWriteMode

---@class DeviceSettings
---@field animation AnimationSetting
---@field aPress ButtonConfig
---@field bPress ButtonConfig
---@field aLongPress ButtonConfig
---@field bLongPress ButtonConfig
---@field pairingEnabled boolean
---@field key string
---@field wakeTimeSeconds integer?
---@field longPressThreshold integer?

---@class NestedNonces
---@field nonces NestedNonce[]

---@class LFCard
---@field uid Bytes
---@field type TagType

---@class CardExtra
---@field ultralightSignature? Bytes
---@field ultralightVersion? Bytes
---@field ultralightCounters? integer[]

---@class SavedCard
---@field name string
---@field uid string
---@field tag integer
---@field id? string
---@field sak? integer
---@field atqa? Bytes
---@field ats? Bytes
---@field data? Bytes[]
---@field extra? CardExtra
---@field color? string
---@field folderId? string

---@class Dictionary
---@field name string
---@field id? string
---@field keys? Bytes[]
---@field keyLength? integer
---@field color? string
---@field folderId? string

---@class Folder
---@field name string
---@field id? string
---@field parentId? string
---@field color? string

---@class ClassicResult
---@field keys Bytes[]
---@field data Bytes[]
---@field allKeysFound boolean

---@class GUISettings
---@field language string
---@field theme "system"|"light"|"dark"
---@field themeColor integer
---@field sidebar "expanded"|"auto"|"collapsed"
---@field autoScan boolean
---@field autoConnect boolean
---@field confirmDelete boolean
---@field debugMode boolean
---@field debugLogging boolean
---@field emulatedDevice boolean

---@class SettingsPatch
---@field language? string
---@field theme? "system"|"light"|"dark"
---@field themeColor? integer
---@field sidebar? "expanded"|"auto"|"collapsed"
---@field autoScan? boolean
---@field autoConnect? boolean
---@field confirmDelete? boolean
---@field debugMode? boolean
---@field debugLogging? boolean
---@field emulatedDevice? boolean

---@class SettingsOptions
---@field language string[]
---@field theme string[]
---@field themeColor string[]
---@field sidebar string[]

---@class InputOptions
---@field type? "text"|"number"|"choice"|"boolean"
---@field description? string
---@field default? string|number|boolean
---@field required? boolean
---@field secret? boolean
---@field choices? string[]

---@class ReadOptions
---@field name? string
---@field keys? Bytes[]

---@class WriteOptions
---@field method? "gen1"|"gen2"|"gen3"
---@field keys? Bytes[]
---@field vanitySak? boolean
---@field key? string
---@field currentKey? string
---@field newKey? string

---@class RawOptions
---@field respTimeoutMs? integer
---@field bitLen? integer
---@field activateRfField? boolean
---@field waitResponse? boolean
---@field appendCrc? boolean
---@field autoSelect? boolean
---@field keepRfField? boolean
---@field checkResponseCrc? boolean

---@class NestedOptions
---@field level? "weak"|"static"|"hard"
---@field slow? boolean

---@class DeviceEnums
---@field TagType TagType[]
---@field TagFrequency TagFrequency[]
---@field AnimationSetting AnimationSetting[]
---@field ButtonType ButtonType[]
---@field ButtonConfig ButtonConfig[]
---@field MifareWriteMode MifareWriteMode[]
---@field Mf1PrngType Mf1PrngType[]
---@field commands table<string, integer>
---@alias RecoveryWord integer|string

---@class DarksideItem
---@field nt1 RecoveryWord
---@field ks1 RecoveryWord
---@field par RecoveryWord
---@field nr RecoveryWord
---@field ar RecoveryWord

---@class NestedInput
---@field uid RecoveryWord
---@field distance RecoveryWord
---@field nt0 RecoveryWord
---@field nt0Enc RecoveryWord
---@field par0 RecoveryWord
---@field nt1 RecoveryWord
---@field nt1Enc RecoveryWord
---@field par1 RecoveryWord

---@class StaticNestedInput
---@field uid RecoveryWord
---@field keyType RecoveryWord
---@field nt0 RecoveryWord
---@field nt0Enc RecoveryWord
---@field nt1 RecoveryWord
---@field nt1Enc RecoveryWord

---@class StaticEncryptedNestedInput
---@field uid RecoveryWord
---@field nt RecoveryWord
---@field ntEnc RecoveryWord
---@field ntParEnc RecoveryWord

---@class Mfkey32Input
---@field uid RecoveryWord
---@field nt0 RecoveryWord
---@field nt1 RecoveryWord
---@field nr0Enc RecoveryWord
---@field ar0Enc RecoveryWord
---@field nr1Enc RecoveryWord
---@field ar1Enc RecoveryWord

---@class Mfkey64Input
---@field uid RecoveryWord
---@field nt RecoveryWord
---@field nrEnc RecoveryWord
---@field arEnc RecoveryWord
---@field atEnc RecoveryWord

---@class DarksideInput
---@field uid RecoveryWord
---@field items DarksideItem[]

chameleon = { ui = {}, cards = {}, dictionaries = {}, cardFolders = {}, dictionaryFolders = {},
  settings = {}, recovery = {}, classic = {}, slots = {}, device = {}, ultralight = {}, resources = {}, codec = {} }

---@param message string
function chameleon.ui.info(message) end

---@param message string
function chameleon.ui.warning(message) end

---@param message string
function chameleon.ui.error(message) end

---@param message string
function chameleon.ui.snackbar(message) end

---@param message string
---@param options? InputOptions
---@return string|number|boolean|nil
function chameleon.ui.input(message, options) end

---@return SavedCard[]
function chameleon.cards.list() end

---@param id string
---@return SavedCard?
function chameleon.cards.get(id) end

---@param record SavedCard
---@return string
function chameleon.cards.save(record) end

---@param id string
---@return boolean
function chameleon.cards.delete(id) end

---@param id string
---@param folderId? string
---@return boolean
function chameleon.cards.move(id, folderId) end

---@return Dictionary[]
function chameleon.dictionaries.list() end

---@param id string
---@return Dictionary?
function chameleon.dictionaries.get(id) end

---@param record Dictionary
---@return string
function chameleon.dictionaries.save(record) end

---@param id string
---@return boolean
function chameleon.dictionaries.delete(id) end

---@param id string
---@param folderId? string
---@return boolean
function chameleon.dictionaries.move(id, folderId) end

---@return Folder[]
function chameleon.cardFolders.list() end

---@param folder Folder
---@return string
function chameleon.cardFolders.save(folder) end

---@param id string
---@return boolean
function chameleon.cardFolders.delete(id) end

---@param id string
---@return string
function chameleon.cardFolders.export(id) end

---@param json string
---@param parentId? string
---@return string
function chameleon.cardFolders.import(json, parentId) end

---@return Folder[]
function chameleon.dictionaryFolders.list() end

---@param folder Folder
---@return string
function chameleon.dictionaryFolders.save(folder) end

---@param id string
---@return boolean
function chameleon.dictionaryFolders.delete(id) end

---@param id string
---@return string
function chameleon.dictionaryFolders.export(id) end

---@param json string
---@param parentId? string
---@return string
function chameleon.dictionaryFolders.import(json, parentId) end

---@param text string
---@param format? "json"|"pm3"|"flipperNfc"|"flipperRfid"|"mct"
---@return SavedCard
function chameleon.cards.decode(text, format) end

---@param card SavedCard
---@param format? "json"|"bin"
---@return string|Bytes
function chameleon.cards.encode(card, format) end

---@param text string
---@param name? string
---@return Dictionary
function chameleon.dictionaries.decode(text, name) end

---@param dictionary Dictionary
---@return string
function chameleon.dictionaries.encode(dictionary) end

---@param options? ReadOptions
---@return SavedCard
function chameleon.cards.read(options) end

---@param card SavedCard
---@param options? WriteOptions
---@return boolean
function chameleon.cards.write(card, options) end

---@param keys? Bytes[]
---@return ClassicResult
function chameleon.classic.checkKeys(keys) end

---@param keys? Bytes[]
---@return ClassicResult
function chameleon.classic.recover(keys) end

---@param keys? Bytes[]
---@return ClassicResult
function chameleon.classic.read(keys) end

---@param name string
---@param tagType TagType
---@return SavedCard
function chameleon.slots.read(name, tagType) end

---@param slot integer
---@param card SavedCard
function chameleon.slots.load(slot, card) end

---@param command integer
---@param bytes Bytes
---@return ChameleonMessage?
function chameleon.device.raw(command, bytes) end

---@param bytes Bytes
---@param options? RawOptions
---@return Bytes
function chameleon.device.send14ARaw(bytes, options) end

---@return boolean
function chameleon.device.connected() end

---@return DeviceEnums
function chameleon.device.enums() end

---@return GUISettings
function chameleon.settings.get() end

---@return SettingsOptions
function chameleon.settings.options() end

---@param patch SettingsPatch
---@return GUISettings
function chameleon.settings.update(patch) end

---@param input DarksideInput
---@return integer[]
function chameleon.recovery.darkside(input) end

---@param input NestedInput
---@return integer[]
function chameleon.recovery.nested(input) end

---@param input StaticNestedInput
---@return integer[]
function chameleon.recovery.staticNested(input) end

---@param input StaticEncryptedNestedInput
---@return integer[]
function chameleon.recovery.staticEncryptedNested(input) end

---@param input Mfkey32Input
---@return integer[]
function chameleon.recovery.mfkey32(input) end

---@param input Mfkey64Input
---@return integer[]
function chameleon.recovery.mfkey64(input) end

---@param input Bytes
---@return integer[]
function chameleon.recovery.hardNested(input) end

---@param key string
---@return string
function chameleon.resources.get(key) end

---@param key string
---@return unknown
function chameleon.resources.require(key) end

---@param text string
---@return string
function chameleon.codec.base64Encode(text) end

---@param text string
---@return string
function chameleon.codec.base64Decode(text) end

---@param text string
---@return string
function chameleon.codec.compress(text) end

---@param text string
---@return string
function chameleon.codec.decompress(text) end

---@param bytes Bytes
---@return string
function chameleon.codec.base64EncodeBytes(bytes) end

---@param bytes Bytes
---@return string
function chameleon.codec.compressBytes(bytes) end

---@param text string
---@return Bytes
function chameleon.codec.base64DecodeBytes(text) end

---@param text string
---@return Bytes
function chameleon.codec.decompressBytes(text) end

---@return string
function chameleon.device.getDeviceChipID() end

---@return string
function chameleon.device.getDeviceBLEAddress() end

---@return boolean
function chameleon.device.isReaderDeviceMode() end

---@param readerMode boolean
function chameleon.device.setReaderDeviceMode(readerMode) end

---@return CardData?
function chameleon.device.scan14443aTag() end

---@return boolean
function chameleon.classic.detectMf1Support() end

---@return NTLevel
function chameleon.classic.getMf1NTLevel() end

---@return DarksideResult
function chameleon.device.checkMf1Darkside() end

---@param block integer
---@param keyType integer
---@param key Bytes
---@return boolean
function chameleon.classic.mf1Auth(block, keyType, key) end

---@param block integer
---@param keyType integer
---@param keys Bytes[]
---@return Bytes?
function chameleon.classic.mf1AuthMultipleKeys(block, keyType, keys) end

---@param block integer
---@param keyType integer
---@param key Bytes
---@return Bytes
function chameleon.classic.mf1ReadBlock(block, keyType, key) end

---@param block integer
---@param keyType integer
---@param key Bytes
---@param data Bytes
---@return boolean
function chameleon.classic.mf1WriteBlock(block, keyType, key, data) end

---@param slot integer
function chameleon.slots.activateSlot(slot) end

---@param slot integer
---@param type TagType
function chameleon.slots.setSlotType(slot, type) end

---@param slot integer
---@param type TagType
function chameleon.slots.setDefaultDataToSlot(slot, type) end

---@param slot integer
---@param frequency TagFrequency
---@param status boolean
function chameleon.slots.enableSlot(slot, frequency, status) end

---@return boolean
function chameleon.classic.isMf1DetectionMode() end

---@param status boolean
function chameleon.classic.setMf1DetectionStatus(status) end

---@return integer
function chameleon.classic.getMf1DetectionCount() end

---@param startBlock integer
---@param blocks Bytes
function chameleon.classic.setMf1BlockData(startBlock, blocks) end

---@param uid Bytes
function chameleon.device.setEM410XEmulatorID(uid) end

---@param uid Bytes
function chameleon.device.setHIDProxEmulatorID(uid) end

---@param uid Bytes
function chameleon.device.setVikingEmulatorID(uid) end

---@param uid Bytes
function chameleon.device.setPacEmulatorID(uid) end

---@param uid Bytes
function chameleon.device.setIoProxEmulatorID(uid) end

---@param uid Bytes
function chameleon.device.setJablotronEmulatorID(uid) end

---@param uid Bytes
function chameleon.device.setIdteckEmulatorID(uid) end

---@param uid Bytes
---@param newKey Bytes
---@param oldKeys Bytes[]
function chameleon.device.writeEM410XtoT55XX(uid, newKey, oldKeys) end

---@param uid Bytes
---@param newKey Bytes
---@param oldKeys Bytes[]
function chameleon.device.writeHIDProxToT55XX(uid, newKey, oldKeys) end

---@param uid Bytes
---@param newKey Bytes
---@param oldKeys Bytes[]
function chameleon.device.writeVikingToT55XX(uid, newKey, oldKeys) end

---@param uid Bytes
---@param newKey Bytes
---@param oldKeys Bytes[]
function chameleon.device.writeJablotronToT55XX(uid, newKey, oldKeys) end

---@param uid Bytes
---@param newKey Bytes
---@param oldKeys Bytes[]
function chameleon.device.writePacToT55XX(uid, newKey, oldKeys) end

---@param uid Bytes
---@param newKey Bytes
---@param oldKeys Bytes[]
function chameleon.device.writeIoProxToT55XX(uid, newKey, oldKeys) end

---@param uid Bytes
---@param newKey Bytes
---@param oldKeys Bytes[]
function chameleon.device.writeIdteckToT55XX(uid, newKey, oldKeys) end

---@param index integer
---@param name string
---@param frequency TagFrequency
function chameleon.slots.setSlotTagName(index, name, frequency) end

---@param index integer
---@param frequency TagFrequency
---@return string
function chameleon.slots.getSlotTagName(index, frequency) end

---@param index integer
---@param frequency TagFrequency
function chameleon.slots.deleteSlotInfo(index, frequency) end

function chameleon.slots.saveSlotData() end

function chameleon.device.enterDFUMode() end

function chameleon.device.factoryReset() end

function chameleon.device.saveSettings() end

function chameleon.device.resetSettings() end

---@param animation AnimationSetting
function chameleon.device.setAnimationMode(animation) end

---@return AnimationSetting
function chameleon.device.getAnimationMode() end

---@return string
function chameleon.device.getGitCommitHash() end

---@return integer
function chameleon.slots.getActiveSlot() end

---@return boolean
function chameleon.classic.isMf1Gen1aMode() end

---@param gen1aMode boolean
function chameleon.classic.setMf1Gen1aMode(gen1aMode) end

---@return boolean
function chameleon.classic.isMf1Gen2Mode() end

---@param gen2Mode boolean
function chameleon.classic.setMf1Gen2Mode(gen2Mode) end

---@return boolean
function chameleon.classic.isMf1UseFirstBlockColl() end

---@param useColl boolean
function chameleon.classic.setMf1UseFirstBlockColl(useColl) end

---@return MifareWriteMode
function chameleon.classic.getMf1WriteMode() end

---@param mode MifareWriteMode
function chameleon.classic.setMf1WriteMode(mode) end

---@return Mf1PrngType
function chameleon.classic.getMf1PrngType() end

---@param type Mf1PrngType
function chameleon.classic.setMf1PrngType(type) end

---@param type ButtonType
---@return ButtonConfig
function chameleon.device.getButtonConfig(type) end

---@param type ButtonType
---@param mode ButtonConfig
function chameleon.device.setButtonConfig(type, mode) end

---@param type ButtonType
---@return ButtonConfig
function chameleon.device.getLongButtonConfig(type) end

---@param type ButtonType
---@param mode ButtonConfig
function chameleon.device.setLongButtonConfig(type, mode) end

---@return integer
function chameleon.device.getSleepTimeout() end

---@param seconds integer
function chameleon.device.setSleepTimeout(seconds) end

---@return integer
function chameleon.device.getLongPressThreshold() end

---@param milliseconds integer
function chameleon.device.setLongPressThreshold(milliseconds) end

function chameleon.device.clearBLEBoundedDevices() end

---@return string
function chameleon.device.getBLEConnectionKey() end

---@param key string
function chameleon.device.setBLEConnectKey(key) end

---@return boolean
function chameleon.device.isBLEPairEnabled() end

---@param status boolean
function chameleon.device.setBLEPairEnabled(status) end

---@param startBlock integer
---@param blockCount integer
---@return Bytes
function chameleon.classic.mf1GetEmulatorBlock(startBlock, blockCount) end

---@return CardData
function chameleon.classic.mf1GetAntiCollData() end

---@return Bytes
function chameleon.device.getEM410XEmulatorID() end

---@return integer[]
function chameleon.device.getDeviceCapabilities() end

---@param key Bytes
---@return boolean
function chameleon.ultralight.mf0UlcAuth(key) end

---@param key Bytes
---@param page integer
---@param count integer
---@return Bytes
function chameleon.ultralight.mf0UlcReadPages(key, page, count) end

---@param key Bytes
---@param page integer
---@param data Bytes
---@return boolean
function chameleon.ultralight.mf0UlcWritePage(key, page, data) end

---@param oldKey Bytes
---@param newKey Bytes
---@return boolean
function chameleon.ultralight.mf0UlcSetKey(oldKey, newKey) end

function chameleon.device.hf14aSetFieldOn() end

function chameleon.device.hf14aSetFieldOff() end

---@return boolean
function chameleon.classic.mf1GetFieldOffDoReset() end

---@param enabled boolean
function chameleon.classic.mf1SetFieldOffDoReset(enabled) end

---@param index integer
---@param frequency TagFrequency
function chameleon.slots.deleteSlotTagNick(index, frequency) end

---@return CardData[]
function chameleon.device.scan14443aTagKeep() end

---@param bcc integer
---@param cl2 integer
---@param cl3 integer
---@param rats integer
function chameleon.device.hf14aSetConfig(bcc, cl2, cl3, rats) end

---@param raw8 Bytes
---@return Bytes
function chameleon.device.ioProxDecodeRaw(raw8) end

---@param version integer
---@param facility integer
---@param card integer
---@return Bytes
function chameleon.device.ioProxComposeID(version, facility, card) end

---@return Bytes
function chameleon.device.adcGenericRead() end

---@param response Bytes
function chameleon.device.hf14a4ApduSend(response) end

---@param uid Bytes
---@param atqa Bytes
---@param sak integer
---@param ats Bytes
function chameleon.device.hf14a4SetAntiColl(uid, atqa, sak, ats) end

---@param cmd Bytes
---@param response Bytes
function chameleon.device.hf14a4AddStaticResponse(cmd, response) end

function chameleon.device.hf14a4ClearStaticResponses() end

---@param apdu Bytes
---@return Bytes
function chameleon.device.hf14a4ReaderApdu(apdu) end

---@return Bytes
function chameleon.device.hf14a4EmvScan() end

---@return boolean
function chameleon.ultralight.mf0GetMagicMode() end

---@param enabled boolean
function chameleon.ultralight.mf0SetMagicMode(enabled) end

---@param from integer
---@param count integer
---@return Bytes
function chameleon.ultralight.mf0EmulatorReadPages(from, count) end

---@param from integer
---@param data Bytes
function chameleon.ultralight.mf0EmulatorWritePages(from, data) end

---@return Bytes
function chameleon.ultralight.mf0EmulatorGetVersionData() end

---@param data Bytes
function chameleon.ultralight.mf0EmulatorSetVersionData(data) end

---@return Bytes
function chameleon.ultralight.mf0EmulatorGetSignatureData() end

---@param data Bytes
function chameleon.ultralight.mf0EmulatorSetSignatureData(data) end

---@return integer
function chameleon.ultralight.mf0ResetAuthCount() end

---@return integer
function chameleon.ultralight.mf0EmulatorGetPageCount() end

---@param index integer
---@param value integer
---@param resetTearing boolean
function chameleon.ultralight.mf0EmulatorSetCounterData(index, value, resetTearing) end

---@return MifareWriteMode
function chameleon.ultralight.mf0NtagGetWriteMode() end

---@param mode MifareWriteMode
function chameleon.ultralight.mf0NtagSetWriteMode(mode) end

---@return boolean
function chameleon.ultralight.mf0NtagGetDetectionEnable() end

---@param enabled boolean
function chameleon.ultralight.mf0NtagSetDetectionEnable(enabled) end

---@return integer
function chameleon.ultralight.mf0NtagGetDetectionCount() end

---@param index integer
---@return string[]
function chameleon.ultralight.mf0NtagGetDetectionLog(index) end

---@return FirmwareVersion
function chameleon.device.getFirmwareVersion() end

---@param targetBlock integer
---@param targetKeyType integer
---@param firstRecover boolean
---@param syncMax integer
---@return Darkside
function chameleon.classic.getMf1Darkside(targetBlock, targetKeyType, firstRecover, syncMax) end

---@return SlotNames[]
function chameleon.slots.getSlotTagNames() end

---@return SlotTypes[]
function chameleon.slots.getSlotTagTypes() end

---@return EmulatorSettings
function chameleon.classic.getMf1EmulatorSettings() end

---@return EnabledSlotInfo[]
function chameleon.slots.getEnabledSlots() end

---@return BatteryCharge
function chameleon.device.getBatteryCharge() end

---@return DeviceSettings
function chameleon.device.getDeviceSettings() end

---@return EmulatorSettings
function chameleon.ultralight.mf0NtagGetEmulatorConfig() end

---@return LFCard?
function chameleon.device.readEM410X() end

---@return LFCard?
function chameleon.device.readHIDProx() end

---@return LFCard?
function chameleon.device.readViking() end

---@return LFCard?
function chameleon.device.readPac() end

---@return LFCard?
function chameleon.device.readIoProx() end

---@return LFCard?
function chameleon.device.readJablotron() end

---@param timeoutMs? integer
---@return Bytes
function chameleon.device.lfSniff(timeoutMs) end

---@param timeoutMs? integer
---@return Bytes
function chameleon.device.hf14aSniff(timeoutMs) end

---@param block integer
---@param keyType integer
---@param knownKey Bytes
---@return NTDistance
function chameleon.classic.getMf1NTDistance(block, keyType, knownKey) end

---@param block integer
---@param keyType integer
---@param knownKey Bytes
---@param targetBlock integer
---@param targetKeyType integer
---@param options? NestedOptions
---@return NestedNonces
function chameleon.classic.getMf1NestedNonces(block, keyType, knownKey, targetBlock, targetKeyType, options) end

---@param mask Bytes
---@param keys Bytes[]
---@return table<integer, Bytes>
function chameleon.classic.mf1CheckKeysOfSectors(mask, keys) end

-- The GUI replaces package loading with exact plugin resource keys.
---@param modname string
---@return unknown
function require(modname) end
