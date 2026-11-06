# Lua plugins

Open **Plugins** beneath **Tools**. Create a plugin with **+**, or import a
`.plugin.json` file. Each card runs its plugin when tapped. Its menu offers Edit,
Export and Delete. The editor accepts Lua source and a JSON object mapping
resource keys to text. Export optionally compresses code and resources together;
imports detect and decompress this automatically. Importing creates a new local
identity and never runs code automatically.

**Only run plugins you trust.** Plugins can change saved cards, device settings,
physical cards and emulator memory. They have the same hardware capabilities as
the GUI. Review imported source and resources before running them.

## Execution and values

Each invocation creates a fresh LuaLike runtime in a separate Dart isolate.
API calls are asynchronous internally but appear as ordinary synchronous Lua
calls. Host calls are serialized, including calls from Lua coroutines. A modal
run window keeps other GUI device operations from overlapping a plugin. Stop
terminates Lua and requests cancellation of key recovery; the modal stays open
until any in-flight host operation finishes. It cannot undo a completed write.
There is no background execution or automatic startup execution.

Errors stop the plugin and appear in its run window. Use Lua `pcall` to handle
expected API errors. Hardware operations require a connected device in normal
(non-DFU) mode. Plugin execution does not restore device modes, settings or slots:
those changes are part of the plugin's requested workflow.

The API root is `chameleon`. Tables use Lua's **1-based indexing**. Device slot
and block numbers retain the communicator's **0-based numbering** (slots 0–7).
Byte buffers are tables of integers from 0 to 255. Enum arguments use exact Dart
enum names as strings, e.g. `"mifare1K"`, `"hf"`, `"lf"`; enum results are names.
`chameleon.device.enums()` returns accepted enum names and the firmware command
name → numeric ID mapping. Card tables use the existing saved-card JSON schema
(including numeric `tag`, hex `uid`, `data`, `id`, `extra`, `color`, `atqa`, `ats`).

Lua standard math, table, string, utf8, convert and crypto libraries remain
available. Ambient `io`, `os`, `package`, `debug`, `dofile` and `loadfile` are
removed. `require` is replaced by plugin-local resource loading. This reduces
ambient capabilities; it is not a claim that the third-party Lua runtime is a
security boundary. Only the explicit host API can access GUI objects.

## Example

```lua
local ui = chameleon.ui
if not chameleon.device.connected() then
  ui.warning("Connect a Chameleon first.")
  return
end
local name = ui.input("Name this card", {required = true, default = "My card"})
if name == nil then return end
local card = chameleon.cards.read({name = name})
chameleon.cards.save(card)
ui.info("Saved " .. card.uid)
```

## User interaction

All dialogs identify the plugin by name in their title. The library exposes no
arbitrary widget, navigation or HTML API.

| Call | Behavior |
| --- | --- |
| `ui.info(message)` | Info dialog; waits for dismissal |
| `ui.warning(message)` | Warning dialog; waits for dismissal |
| `ui.error(message)` | Error dialog; waits for dismissal |
| `ui.snackbar(message)` | Shows text prefixed by the plugin name |
| `ui.input(message, options?)` | Returns a string, number, choice string or boolean; `nil` on cancel |

Input options: `type` (`"text"` default, `"number"`, `"choice"`, `"boolean"`),
`description`, `default`, `required` (nonempty text), `secret` (obscured text),
`choices` (a nonempty string array for `choice`). A choice uses a valid
`default` if supplied, otherwise the first choice. Numeric input requires a valid
number. A canceled boolean input returns `nil`, distinct from `false`.

## Resources and codecs

Resources are immutable and scoped to the running plugin. Keys are exact,
case-sensitive identifiers, not filesystem paths. Unknown keys raise an error.

| Call | Result |
| --- | --- |
| `resources.get(key)` | Resource text |
| `resources.require(key)` or `require(key)` | Evaluates a Lua text resource once per invocation; caches its return value |
| `codec.base64Encode(text)` | Base64 of UTF-8 text |
| `codec.base64Decode(base64)` | UTF-8 text |
| `codec.compress(text)` | Gzip-compressed UTF-8 text encoded as base64 |
| `codec.decompress(base64)` | Decompressed UTF-8 text |

For binary payloads use `codec.base64EncodeBytes(bytes)` and
`codec.base64DecodeBytes(text)`. `codec.compressBytes(bytes)` and
`codec.decompressBytes(text)` also round trip byte tables using gzip+base64.
Device methods accept byte tables. Binary resources
can be stored as base64 text. For example, resource `helpers.lua` can contain
`return { label = "Card utility" }` and be loaded with `require("helpers.lua")`.

## High-level workflows

All calls below are under `chameleon`.

| Call | Result / behavior |
| --- | --- |
| `cards.list()` | Saved card tables |
| `cards.save(card)` | Upserts a card by ID; returns its ID |
| `cards.read(options?)` | Reads an HF card to a saved-card table without saving it; options `name`, `keys` (array of six-byte keys). Classic uses existing dictionary checks, recovery and dump logic; Ultralight uses unauthenticated page reads. Protected Ultralight flows can use raw/auth methods below. |
| `cards.write(card, options?)` | Uses existing card writers; returns success. Classic options: `method` (`gen1`, `gen2`, `gen3`; autodetected if omitted), `keys`, `vanitySak`. Ultralight: `key` (hex password/authentication key; omitted or empty means no password). T55xx: `currentKey`, `newKey` (eight hex characters; defaults `00000000`). |
| `dictionaries.list()` | Saved dictionary tables, including `id`, `name`, `keys`, `keyLength` |
| `classic.checkKeys(keys?)` | Checks supplied six-byte keys and built-in defaults |
| `classic.recover(keys?)` | Checks keys then uses existing recovery logic |
| `classic.read(keys?)` | Checks keys, recovers missing keys, dumps blocks |
| `slots.read(name, tagType)` | Reads the active Classic/Ultralight/ISO 14443-4 emulator as a saved-card table |
| `slots.load(slot, card)` | Enables, initializes and loads an HF or LF emulator, including identity and available Ultralight metadata, names the slot and persists its data |
| `device.raw(command, bytes)` | Raw firmware command; returns `{command, status, data}` or nil |
| `device.send14ARaw(bytes, options?)` | Raw RF command; returns bytes |
| `device.connected()` | Whether a device is connected in normal mode |
| `device.enums()` | Enum names and numeric firmware commands |

Classic workflow results contain `keys` (80 entries: sector keys A then B),
`data` (256 block entries), and `allKeysFound`. Missing entries are empty tables;
not every card has 256 blocks. Use dictionary keys with, for example,
`chameleon.classic.checkKeys(chameleon.dictionaries.list()[1].keys)`.

`send14ARaw` options retain communicator names and defaults: `respTimeoutMs=100`,
`bitLen` (defaults to byte count × 8), `activateRfField=true`,
`waitResponse=true`, `appendCrc=true`, `autoSelect=true`, `keepRfField=false`,
`checkResponseCrc=true`.

LF readers `device.readEM410X()`, `readHIDProx()`, `readViking()`, `readPac()`,
`readIoProx()`, `readJablotron()` return `{uid = bytes, type = enumName}` or nil.
LF emulator setters and T55xx writes are also available below. Firmware-specific
operations outside the typed surface remain accessible through `device.raw`.

## Saved data management

Saved-data operations work offline and affect the same collections as the GUI.
All names below are prefixed with `chameleon.`. Save operations replace the
record with the supplied table; they are not partial patches. Omit `id` to
create a record; provide an existing ID to update one. Read a record first when
editing a single field. Unknown record IDs return nil from `get` and false
from `delete`/`move`. Mutations refresh the GUI.

| Call | Result / behavior |
| --- | --- |
| `cards.get(id)` / `dictionaries.get(id)` | Saved table or nil |
| `cards.save(card)` / `dictionaries.save(dictionary)` | Upserts a record, returning its ID |
| `cards.delete(id)` / `dictionaries.delete(id)` | Deletes that record; returns whether it existed |
| `cards.move(id, folderId?)` / `dictionaries.move(id, folderId?)` | Moves to an existing folder, or the root when folderId is omitted/nil |
| `cardFolders.list()` / `dictionaryFolders.list()` | Folder tables |
| `cardFolders.save(folder)` / `dictionaryFolders.save(folder)` | Creates or replaces a folder; moving is done by changing `parentId` |
| `cardFolders.delete(id)` / `dictionaryFolders.delete(id)` | Deletes the folder, all descendant folders **and their saved records** |
| `cardFolders.export(id)` / `dictionaryFolders.export(id)` | Existing GUI folder bundle as a JSON string |
| `cardFolders.import(json, parentId?)` / `dictionaryFolders.import(json, parentId?)` | Imports a bundle beneath an existing parent or the root; returns the new root ID |
| `cards.decode(text, format?)` | Parses a card without saving; formats `json` (default), `pm3`, `flipperNfc`, `flipperRfid`, `mct` |
| `cards.encode(card, format?)` | Returns saved-card JSON text (`json`, default), or an exported byte table (`bin`) |
| `dictionaries.decode(text, name?)` | Parses the existing newline-separated hex dictionary format without saving |
| `dictionaries.encode(dictionary)` | Returns newline-separated hex keys |

A new card requires `name`, `uid` and numeric `tag`; `sak`, `atqa`, `ats` and
`data` default to zero/empty. Existing optional metadata is supported. A
dictionary requires `name`; `keys` is an array of uniform four-, six- or
sixteen-byte tables. `keyLength` counts **hex characters** (8, 12 or 32), and is
inferred from keys if omitted. New empty dictionaries default to 12; an explicit
`keyLength = 0` preserves the GUI’s unspecified length for an empty dictionary. A folder has
`name`, optional `id`, `color` and `parentId`. Colors use `#RRGGBB`; omitted colors
use the GUI default. Records can specify `folderId` or omit it for the root.

Folder IDs must exist and parent relationships must be acyclic. Folder imports
validate the bundle before writing and generate fresh IDs for all imported
folders and records. Exported bundles use the existing Saved Cards formats and
can also be imported through that screen. To duplicate an individual decoded
card/dictionary, set its `id` to nil before saving it.

Deletion calls act immediately, without an extra GUI confirmation, regardless
of the GUI's `confirmDelete` preference. Plugins can request confirmation through
`ui.input(..., {type = "boolean"})`. Conversion methods return data rather than
opening file dialogs, so code can process resources entirely within a plugin.

## GUI settings

`settings.get()` returns GUI preferences, separate from device settings.
`settings.update(patch)` applies only supplied fields and returns the updated
preferences. The entire patch is validated before any preferences change;
unknown fields and unsupported values raise a Lua error. Changes persist.

| Field | Values |
| --- | --- |
| `language` | Supported BCP-47 tag, e.g. `en`, `de`, `pt-BR`; see `settings.options().language` |
| `theme` | `system`, `light`, `dark` |
| `themeColor` | Zero-based GUI palette index: 0 orange, 1 purple, 2 blue, 3 green, 4 indigo, 5 lime, 6 red, 7 yellow |
| `sidebar` | `expanded`, `auto`, `collapsed` |
| `autoScan` | Boolean: automatic card scanning |
| `autoConnect` | Boolean: connect to the first found device |
| `confirmDelete` | Boolean: normal GUI deletion confirmation |
| `debugMode` | Boolean: developer mode |
| `debugLogging` | Boolean: GUI debug logging; active when debug mode is also enabled |
| `emulatedDevice` | Boolean: demo/emulated device mode; changing it disconnects the current device and replaces the connector |

`settings.options()` returns supported languages, themes, sidebar modes and an
ordered list of color names. Palette indices are zero-based even though this
list uses Lua's one-based indexing. Language, appearance and navigation changes
refresh the GUI immediately. Existing communicator sessions retain their
previous logger until the next connection.

## Standalone recovery

The `recovery` namespace exposes the existing native solvers, without scanning
or communicating with a device. Callers supply captures; results are arrays of
48-bit candidate key integers. These fit exactly within Lua's integer/number
range and can be converted to six-byte keys as needed. No candidates produces
an empty table. Native mfkey failure sentinels are omitted; a valid zero key
is retained.

| Call | Input table fields |
| --- | --- |
| `recovery.darkside(input)` | `uid`, `items` (array of `{nt1, ks1, par, nr, ar}`) |
| `recovery.nested(input)` | `uid`, `distance`, `nt0`, `nt0Enc`, `par0`, `nt1`, `nt1Enc`, `par1` |
| `recovery.staticNested(input)` | `uid`, `keyType` (0x60/0x61), `nt0`, `nt0Enc`, `nt1`, `nt1Enc` |
| `recovery.staticEncryptedNested(input)` | `uid`, `nt`, `ntEnc`, `ntParEnc` |
| `recovery.mfkey32(input)` | `uid`, `nt0`, `nt1`, `nr0Enc`, `ar0Enc`, `nr1Enc`, `ar1Enc` |
| `recovery.mfkey64(input)` | `uid`, `nt`, `nrEnc`, `arEnc`, `atEnc` |
| `recovery.hardNested(bytes)` | Byte table: six-byte header (UID, target block, key type) followed by nine-byte nonce records, as used by the existing hardnested helper |

32-bit fields accept unsigned integers or hexadecimal strings (optional `0x`
prefix). Nested parity fields are 0–7. Darkside `ks1` and `par` accept 64-bit
hexadecimal strings; use strings for values above 2^53−1 so they cannot lose
precision in Lua. Other required fields cannot be omitted. Hardnested input
must contain at least one complete nonce record. All searches use the existing
shared native queue and cancellation mechanism. **Stop** cancels the search and
waits for the native worker to settle, including a request still waiting in the
queue. The native recovery library must be available in the application build.

## Importable examples

See [small example plugins](plugins/examples/README.md) for ready-to-import JSON
files: counting cards, switching theme, choosing language, saving a tiny
dictionary from a resource, and running offline nested recovery.

## Typed device operations

The following adapters call the existing communicator directly. Prefix every
call with `chameleon.`. Signatures use Dart type names for clarity:
`Uint8List` means a Lua byte table, `List<Uint8List>` means an array of byte
tables, `void` returns nil, `CardData` returns `{uid, sak, atqa, ats}`.
Enum return values are strings. A `?` result can be nil. These low-level methods
do not implicitly change the reader mode; set it explicitly when needed.

| Call | Result type |
| --- | --- |
| `device.getDeviceChipID()` | `String` |
| `device.getDeviceBLEAddress()` | `String` |
| `device.isReaderDeviceMode()` | `bool` |
| `device.setReaderDeviceMode(bool readerMode)` | `void` |
| `device.scan14443aTag()` | `CardData?` |
| `classic.detectMf1Support()` | `bool` |
| `classic.getMf1NTLevel()` | `NTLevel` |
| `device.checkMf1Darkside()` | `DarksideResult` |
| `classic.mf1Auth(int block, int keyType, Uint8List key)` | `bool` |
| `classic.mf1AuthMultipleKeys(int block, int keyType, List<Uint8List> keys)` | `Uint8List?` |
| `classic.mf1ReadBlock(int block, int keyType, Uint8List key)` | `Uint8List` |
| `classic.mf1WriteBlock(int block, int keyType, Uint8List key, Uint8List data)` | `bool` |
| `slots.activateSlot(int slot)` | `void` |
| `slots.setSlotType(int slot, TagType type)` | `void` |
| `slots.setDefaultDataToSlot(int slot, TagType type)` | `void` |
| `slots.enableSlot(int slot, TagFrequency frequency, bool status)` | `void` |
| `classic.isMf1DetectionMode()` | `bool` |
| `classic.setMf1DetectionStatus(bool status)` | `void` |
| `classic.getMf1DetectionCount()` | `int` |
| `classic.setMf1BlockData(int startBlock, Uint8List blocks)` | `void` |
| `device.setEM410XEmulatorID(Uint8List uid)` | `void` |
| `device.setHIDProxEmulatorID(Uint8List uid)` | `void` |
| `device.setVikingEmulatorID(Uint8List uid)` | `void` |
| `device.setPacEmulatorID(Uint8List uid)` | `void` |
| `device.setIoProxEmulatorID(Uint8List uid)` | `void` |
| `device.setJablotronEmulatorID(Uint8List uid)` | `void` |
| `device.setIdteckEmulatorID(Uint8List uid)` | `void` |
| `device.writeEM410XtoT55XX(Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys)` | `void` |
| `device.writeHIDProxToT55XX(Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys)` | `void` |
| `device.writeVikingToT55XX(Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys)` | `void` |
| `device.writeJablotronToT55XX(Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys)` | `void` |
| `device.writePacToT55XX(Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys)` | `void` |
| `device.writeIoProxToT55XX(Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys)` | `void` |
| `device.writeIdteckToT55XX(Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys)` | `void` |
| `slots.setSlotTagName(int index, String name, TagFrequency frequency)` | `void` |
| `slots.getSlotTagName(int index, TagFrequency frequency)` | `String` |
| `slots.deleteSlotInfo(int index, TagFrequency frequency)` | `void` |
| `slots.saveSlotData()` | `void` |
| `device.enterDFUMode()` | `void` |
| `device.factoryReset()` | `void` |
| `device.saveSettings()` | `void` |
| `device.resetSettings()` | `void` |
| `device.setAnimationMode(AnimationSetting animation)` | `void` |
| `device.getAnimationMode()` | `AnimationSetting` |
| `device.getGitCommitHash()` | `String` |
| `slots.getActiveSlot()` | `int` |
| `classic.isMf1Gen1aMode()` | `bool` |
| `classic.setMf1Gen1aMode(bool gen1aMode)` | `void` |
| `classic.isMf1Gen2Mode()` | `bool` |
| `classic.setMf1Gen2Mode(bool gen2Mode)` | `void` |
| `classic.isMf1UseFirstBlockColl()` | `bool` |
| `classic.setMf1UseFirstBlockColl(bool useColl)` | `void` |
| `classic.getMf1WriteMode()` | `MifareWriteMode` |
| `classic.setMf1WriteMode(MifareWriteMode mode)` | `void` |
| `classic.getMf1PrngType()` | `Mf1PrngType` |
| `classic.setMf1PrngType(Mf1PrngType type)` | `void` |
| `device.getButtonConfig(ButtonType type)` | `ButtonConfig` |
| `device.setButtonConfig(ButtonType type, ButtonConfig mode)` | `void` |
| `device.getLongButtonConfig(ButtonType type)` | `ButtonConfig` |
| `device.setLongButtonConfig(ButtonType type, ButtonConfig mode)` | `void` |
| `device.getSleepTimeout()` | `int` |
| `device.setSleepTimeout(int seconds)` | `void` |
| `device.getLongPressThreshold()` | `int` |
| `device.setLongPressThreshold(int milliseconds)` | `void` |
| `device.clearBLEBoundedDevices()` | `void` |
| `device.getBLEConnectionKey()` | `String` |
| `device.setBLEConnectKey(String key)` | `void` |
| `device.isBLEPairEnabled()` | `bool` |
| `device.setBLEPairEnabled(bool status)` | `void` |
| `classic.mf1GetEmulatorBlock(int startBlock, int blockCount)` | `Uint8List` |
| `classic.mf1GetAntiCollData()` | `CardData` |
| `device.getEM410XEmulatorID()` | `Uint8List` |
| `device.getDeviceCapabilities()` | `List<int>` |
| `ultralight.mf0UlcAuth(Uint8List key)` | `bool` |
| `ultralight.mf0UlcReadPages(Uint8List key, int page, int count)` | `Uint8List` |
| `ultralight.mf0UlcWritePage(Uint8List key, int page, Uint8List data)` | `bool` |
| `ultralight.mf0UlcSetKey(Uint8List oldKey, Uint8List newKey)` | `bool` |
| `device.hf14aSetFieldOn()` | `void` |
| `device.hf14aSetFieldOff()` | `void` |
| `classic.mf1GetFieldOffDoReset()` | `bool` |
| `classic.mf1SetFieldOffDoReset(bool enabled)` | `void` |
| `slots.deleteSlotTagNick(int index, TagFrequency frequency)` | `void` |
| `device.scan14443aTagKeep()` | `List<CardData>` |
| `device.hf14aSetConfig(int bcc, int cl2, int cl3, int rats)` | `void` |
| `device.ioProxDecodeRaw(Uint8List raw8)` | `Uint8List` |
| `device.ioProxComposeID(int version, int facility, int card)` | `Uint8List` |
| `device.adcGenericRead()` | `Uint8List` |
| `device.hf14a4ApduSend(Uint8List response)` | `void` |
| `device.hf14a4SetAntiColl(Uint8List uid, Uint8List atqa, int sak, Uint8List ats)` | `void` |
| `device.hf14a4AddStaticResponse(Uint8List cmd, Uint8List response)` | `void` |
| `device.hf14a4ClearStaticResponses()` | `void` |
| `device.hf14a4ReaderApdu(Uint8List apdu)` | `Uint8List` |
| `device.hf14a4EmvScan()` | `Uint8List` |
| `ultralight.mf0GetMagicMode()` | `bool` |
| `ultralight.mf0SetMagicMode(bool enabled)` | `void` |
| `ultralight.mf0EmulatorReadPages(int from, int count)` | `Uint8List` |
| `ultralight.mf0EmulatorWritePages(int from, Uint8List data)` | `void` |
| `ultralight.mf0EmulatorGetVersionData()` | `Uint8List` |
| `ultralight.mf0EmulatorSetVersionData(Uint8List data)` | `void` |
| `ultralight.mf0EmulatorGetSignatureData()` | `Uint8List` |
| `ultralight.mf0EmulatorSetSignatureData(Uint8List data)` | `void` |
| `ultralight.mf0ResetAuthCount()` | `int` |
| `ultralight.mf0EmulatorGetPageCount()` | `int` |
| `ultralight.mf0EmulatorSetCounterData(int index, int value, bool resetTearing)` | `void` |
| `ultralight.mf0NtagGetWriteMode()` | `MifareWriteMode` |
| `ultralight.mf0NtagSetWriteMode(MifareWriteMode mode)` | `void` |
| `ultralight.mf0NtagGetDetectionEnable()` | `bool` |
| `ultralight.mf0NtagSetDetectionEnable(bool enabled)` | `void` |
| `ultralight.mf0NtagGetDetectionCount()` | `int` |
| `ultralight.mf0NtagGetDetectionLog(int index)` | `List<String>` |
| `classic.getMf1NTDistance(block, keyType, knownKey)` | `{uid, distance}` |
| `classic.getMf1NestedNonces(block, keyType, knownKey, targetBlock, targetKeyType, options?)` | `{nonces = {{nt, ntEnc, parity}, ...}}`; options `level` (`weak`, `static`, `hard`), `slow` (false) |
| `classic.mf1CheckKeysOfSectors(mask, keys)` | Keys indexed by firmware order `sector * 2 + keyType`; 10-byte skip mask, 1–83 six-byte keys |
| `device.lfSniff(timeoutMs?)` | Bytes; default timeout 2000 ms |
| `device.hf14aSniff(timeoutMs?)` | Bytes; default timeout 5000 ms |
| `device.getFirmwareVersion()` | `FirmwareVersion` |
| `classic.getMf1Darkside(int targetBlock, int targetKeyType, bool firstRecover, int syncMax)` | `Darkside` |
| `slots.getSlotTagNames()` | `List<SlotNames>` |
| `slots.getSlotTagTypes()` | `List<SlotTypes>` |
| `classic.getMf1EmulatorSettings()` | `EmulatorSettings` |
| `slots.getEnabledSlots()` | `List<EnabledSlotInfo>` |
| `device.getBatteryCharge()` | `BatteryCharge` |
| `device.getDeviceSettings()` | `DeviceSettings` |
| `ultralight.mf0NtagGetEmulatorConfig()` | `EmulatorSettings` |

Structured results use tables with the fields of their communicator models: firmware version (`legacyProtocol`, `version`), battery (`voltage`, `percent`, `condition`), slot names/types/enabled state (`hf`, `lf`), settings and emulator configuration. Nonce results retain `uid`, `distance`, `nonces`, `nt`, `ntEnc` and `parity` fields as applicable.

## Portable file format

```json
{
  "format": "chameleon-ultra-gui-plugin",
  "version": 1,
  "id": "uuid",
  "name": "Example",
  "description": "Description",
  "color": 4294924066,
  "encoding": "json",
  "data": {"code": "chameleon.ui.info('Hello')", "resources": {}}
}
```

With `encoding: "gzip+base64"`, `data` is a base64 string containing the gzip
encoding of the UTF-8 JSON payload `{code, resources}`. Metadata stays readable.
Unknown formats, versions and encodings are rejected. Expanded code/resources
are limited to 8 MiB; input JSON is limited to 16 MiB. Compressed imports use
streamed decompression with an expanded-size check. Plugins persist separately
from cards and dictionaries under the `plugins_v1` preference key.
