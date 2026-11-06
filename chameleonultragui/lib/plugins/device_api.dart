part of 'api.dart';

// Typed adapters deliberately retain communicator method names and signatures.
extension _DeviceMethods on PluginApi {
  void _registerDevice() {
    methods.addAll({
      'classic.getMf1NTDistance': (a) => device.getMf1NTDistance(
        a[0] as int,
        a[1] as int,
        PluginApi.bytes(a[2]),
      ),
      'classic.getMf1NestedNonces': (a) {
        final options = a.length > 5 ? a[5] as Map : const {};
        return device.getMf1NestedNonces(
          a[0] as int,
          a[1] as int,
          PluginApi.bytes(a[2]),
          a[3] as int,
          a[4] as int,
          level: NTLevel.values.byName(options['level'] as String? ?? 'weak'),
          slow: options['slow'] as bool? ?? false,
        );
      },
      'classic.mf1CheckKeysOfSectors': (a) => device.mf1CheckKeysOfSectors(
        PluginApi.bytes(a[0]),
        PluginApi.list(a[1]).map(PluginApi.bytes).toList(),
      ),
      'device.lfSniff': (a) =>
          device.lfSniff(timeoutMs: a.isEmpty ? 2000 : a[0] as int),
      'device.hf14aSniff': (a) =>
          device.hf14aSniff(timeoutMs: a.isEmpty ? 5000 : a[0] as int),
      'device.getFirmwareVersion': (a) async => device.getFirmwareVersion(),
      'classic.getMf1Darkside': (a) async => device.getMf1Darkside(
        a[0] as int,
        a[1] as int,
        a[2] as bool,
        a[3] as int,
      ),
      'slots.getSlotTagNames': (a) async => device.getSlotTagNames(),
      'slots.getSlotTagTypes': (a) async => device.getSlotTagTypes(),
      'classic.getMf1EmulatorSettings': (a) async =>
          device.getMf1EmulatorSettings(),
      'slots.getEnabledSlots': (a) async => device.getEnabledSlots(),
      'device.getBatteryCharge': (a) async => device.getBatteryCharge(),
      'device.getDeviceSettings': (a) async => device.getDeviceSettings(),
      'ultralight.mf0NtagGetEmulatorConfig': (a) async =>
          device.mf0NtagGetEmulatorConfig(),
      'device.readEM410X': (_) async => device.readEM410X(),
      'device.readHIDProx': (_) async => device.readHIDProx(),
      'device.readViking': (_) async => device.readViking(),
      'device.readPac': (_) async => device.readPac(),
      'device.readIoProx': (_) async => device.readIoProx(),
      'device.readJablotron': (_) async => device.readJablotron(),
      'device.getDeviceChipID': (a) async {
        return await device.getDeviceChipID();
      },
      'device.getDeviceBLEAddress': (a) async {
        return await device.getDeviceBLEAddress();
      },
      'device.isReaderDeviceMode': (a) async {
        return await device.isReaderDeviceMode();
      },
      'device.setReaderDeviceMode': (a) async {
        await device.setReaderDeviceMode(a[0] as bool);
        return null;
      },
      'device.scan14443aTag': (a) async {
        return await device.scan14443aTag();
      },
      'classic.detectMf1Support': (a) async {
        return await device.detectMf1Support();
      },
      'classic.getMf1NTLevel': (a) async {
        return await device.getMf1NTLevel();
      },
      'device.checkMf1Darkside': (a) async {
        return await device.checkMf1Darkside();
      },
      'classic.mf1Auth': (a) async {
        return await device.mf1Auth(
          a[0] as int,
          a[1] as int,
          PluginApi.bytes(a[2]),
        );
      },
      'classic.mf1AuthMultipleKeys': (a) async {
        return await device.mf1AuthMultipleKeys(
          a[0] as int,
          a[1] as int,
          PluginApi.list(a[2]).map(PluginApi.bytes).toList(),
        );
      },
      'classic.mf1ReadBlock': (a) async {
        return await device.mf1ReadBlock(
          a[0] as int,
          a[1] as int,
          PluginApi.bytes(a[2]),
        );
      },
      'classic.mf1WriteBlock': (a) async {
        return await device.mf1WriteBlock(
          a[0] as int,
          a[1] as int,
          PluginApi.bytes(a[2]),
          PluginApi.bytes(a[3]),
        );
      },
      'slots.activateSlot': (a) async {
        await device.activateSlot(a[0] as int);
        return null;
      },
      'slots.setSlotType': (a) async {
        await device.setSlotType(
          a[0] as int,
          TagType.values.byName(a[1] as String),
        );
        return null;
      },
      'slots.setDefaultDataToSlot': (a) async {
        await device.setDefaultDataToSlot(
          a[0] as int,
          TagType.values.byName(a[1] as String),
        );
        return null;
      },
      'slots.enableSlot': (a) async {
        await device.enableSlot(
          a[0] as int,
          TagFrequency.values.byName(a[1] as String),
          a[2] as bool,
        );
        return null;
      },
      'classic.isMf1DetectionMode': (a) async {
        return await device.isMf1DetectionMode();
      },
      'classic.setMf1DetectionStatus': (a) async {
        await device.setMf1DetectionStatus(a[0] as bool);
        return null;
      },
      'classic.getMf1DetectionCount': (a) async {
        return await device.getMf1DetectionCount();
      },
      'classic.setMf1BlockData': (a) async {
        await device.setMf1BlockData(a[0] as int, PluginApi.bytes(a[1]));
        return null;
      },
      'device.setEM410XEmulatorID': (a) async {
        await device.setEM410XEmulatorID(PluginApi.bytes(a[0]));
        return null;
      },
      'device.setHIDProxEmulatorID': (a) async {
        await device.setHIDProxEmulatorID(PluginApi.bytes(a[0]));
        return null;
      },
      'device.setVikingEmulatorID': (a) async {
        await device.setVikingEmulatorID(PluginApi.bytes(a[0]));
        return null;
      },
      'device.setPacEmulatorID': (a) async {
        await device.setPacEmulatorID(PluginApi.bytes(a[0]));
        return null;
      },
      'device.setIoProxEmulatorID': (a) async {
        await device.setIoProxEmulatorID(PluginApi.bytes(a[0]));
        return null;
      },
      'device.setJablotronEmulatorID': (a) async {
        await device.setJablotronEmulatorID(PluginApi.bytes(a[0]));
        return null;
      },
      'device.setIdteckEmulatorID': (a) async {
        await device.setIdteckEmulatorID(PluginApi.bytes(a[0]));
        return null;
      },
      'device.writeEM410XtoT55XX': (a) async {
        await device.writeEM410XtoT55XX(
          PluginApi.bytes(a[0]),
          PluginApi.bytes(a[1]),
          PluginApi.list(a[2]).map(PluginApi.bytes).toList(),
        );
        return null;
      },
      'device.writeHIDProxToT55XX': (a) async {
        await device.writeHIDProxToT55XX(
          PluginApi.bytes(a[0]),
          PluginApi.bytes(a[1]),
          PluginApi.list(a[2]).map(PluginApi.bytes).toList(),
        );
        return null;
      },
      'device.writeVikingToT55XX': (a) async {
        await device.writeVikingToT55XX(
          PluginApi.bytes(a[0]),
          PluginApi.bytes(a[1]),
          PluginApi.list(a[2]).map(PluginApi.bytes).toList(),
        );
        return null;
      },
      'device.writeJablotronToT55XX': (a) async {
        await device.writeJablotronToT55XX(
          PluginApi.bytes(a[0]),
          PluginApi.bytes(a[1]),
          PluginApi.list(a[2]).map(PluginApi.bytes).toList(),
        );
        return null;
      },
      'device.writePacToT55XX': (a) async {
        await device.writePacToT55XX(
          PluginApi.bytes(a[0]),
          PluginApi.bytes(a[1]),
          PluginApi.list(a[2]).map(PluginApi.bytes).toList(),
        );
        return null;
      },
      'device.writeIoProxToT55XX': (a) async {
        await device.writeIoProxToT55XX(
          PluginApi.bytes(a[0]),
          PluginApi.bytes(a[1]),
          PluginApi.list(a[2]).map(PluginApi.bytes).toList(),
        );
        return null;
      },
      'device.writeIdteckToT55XX': (a) async {
        await device.writeIdteckToT55XX(
          PluginApi.bytes(a[0]),
          PluginApi.bytes(a[1]),
          PluginApi.list(a[2]).map(PluginApi.bytes).toList(),
        );
        return null;
      },
      'slots.setSlotTagName': (a) async {
        await device.setSlotTagName(
          a[0] as int,
          a[1] as String,
          TagFrequency.values.byName(a[2] as String),
        );
        return null;
      },
      'slots.getSlotTagName': (a) async {
        return await device.getSlotTagName(
          a[0] as int,
          TagFrequency.values.byName(a[1] as String),
        );
      },
      'slots.deleteSlotInfo': (a) async {
        await device.deleteSlotInfo(
          a[0] as int,
          TagFrequency.values.byName(a[1] as String),
        );
        return null;
      },
      'slots.saveSlotData': (a) async {
        await device.saveSlotData();
        return null;
      },
      'device.enterDFUMode': (a) async {
        await device.enterDFUMode();
        return null;
      },
      'device.factoryReset': (a) async {
        await device.factoryReset();
        return null;
      },
      'device.saveSettings': (a) async {
        await device.saveSettings();
        return null;
      },
      'device.resetSettings': (a) async {
        await device.resetSettings();
        return null;
      },
      'device.setAnimationMode': (a) async {
        await device.setAnimationMode(
          AnimationSetting.values.byName(a[0] as String),
        );
        return null;
      },
      'device.getAnimationMode': (a) async {
        return await device.getAnimationMode();
      },
      'device.getGitCommitHash': (a) async {
        return await device.getGitCommitHash();
      },
      'slots.getActiveSlot': (a) async {
        return await device.getActiveSlot();
      },
      'classic.isMf1Gen1aMode': (a) async {
        return await device.isMf1Gen1aMode();
      },
      'classic.setMf1Gen1aMode': (a) async {
        await device.setMf1Gen1aMode(a[0] as bool);
        return null;
      },
      'classic.isMf1Gen2Mode': (a) async {
        return await device.isMf1Gen2Mode();
      },
      'classic.setMf1Gen2Mode': (a) async {
        await device.setMf1Gen2Mode(a[0] as bool);
        return null;
      },
      'classic.isMf1UseFirstBlockColl': (a) async {
        return await device.isMf1UseFirstBlockColl();
      },
      'classic.setMf1UseFirstBlockColl': (a) async {
        await device.setMf1UseFirstBlockColl(a[0] as bool);
        return null;
      },
      'classic.getMf1WriteMode': (a) async {
        return await device.getMf1WriteMode();
      },
      'classic.setMf1WriteMode': (a) async {
        await device.setMf1WriteMode(
          MifareWriteMode.values.byName(a[0] as String),
        );
        return null;
      },
      'classic.getMf1PrngType': (a) async {
        return await device.getMf1PrngType();
      },
      'classic.setMf1PrngType': (a) async {
        await device.setMf1PrngType(Mf1PrngType.values.byName(a[0] as String));
        return null;
      },
      'device.getButtonConfig': (a) async {
        return await device.getButtonConfig(
          ButtonType.values.byName(a[0] as String),
        );
      },
      'device.setButtonConfig': (a) async {
        await device.setButtonConfig(
          ButtonType.values.byName(a[0] as String),
          ButtonConfig.values.byName(a[1] as String),
        );
        return null;
      },
      'device.getLongButtonConfig': (a) async {
        return await device.getLongButtonConfig(
          ButtonType.values.byName(a[0] as String),
        );
      },
      'device.setLongButtonConfig': (a) async {
        await device.setLongButtonConfig(
          ButtonType.values.byName(a[0] as String),
          ButtonConfig.values.byName(a[1] as String),
        );
        return null;
      },
      'device.getSleepTimeout': (a) async {
        return await device.getSleepTimeout();
      },
      'device.setSleepTimeout': (a) async {
        await device.setSleepTimeout(a[0] as int);
        return null;
      },
      'device.getLongPressThreshold': (a) async {
        return await device.getLongPressThreshold();
      },
      'device.setLongPressThreshold': (a) async {
        await device.setLongPressThreshold(a[0] as int);
        return null;
      },
      'device.clearBLEBoundedDevices': (a) async {
        await device.clearBLEBoundedDevices();
        return null;
      },
      'device.getBLEConnectionKey': (a) async {
        return await device.getBLEConnectionKey();
      },
      'device.setBLEConnectKey': (a) async {
        await device.setBLEConnectKey(a[0] as String);
        return null;
      },
      'device.isBLEPairEnabled': (a) async {
        return await device.isBLEPairEnabled();
      },
      'device.setBLEPairEnabled': (a) async {
        await device.setBLEPairEnabled(a[0] as bool);
        return null;
      },
      'classic.mf1GetEmulatorBlock': (a) async {
        return await device.mf1GetEmulatorBlock(a[0] as int, a[1] as int);
      },
      'classic.mf1GetAntiCollData': (a) async {
        return await device.mf1GetAntiCollData();
      },
      'device.getEM410XEmulatorID': (a) async {
        return await device.getEM410XEmulatorID();
      },
      'device.getDeviceCapabilities': (a) async {
        return await device.getDeviceCapabilities();
      },
      'ultralight.mf0UlcAuth': (a) async {
        return await device.mf0UlcAuth(PluginApi.bytes(a[0]));
      },
      'ultralight.mf0UlcReadPages': (a) async {
        return await device.mf0UlcReadPages(
          PluginApi.bytes(a[0]),
          a[1] as int,
          a[2] as int,
        );
      },
      'ultralight.mf0UlcWritePage': (a) async {
        return await device.mf0UlcWritePage(
          PluginApi.bytes(a[0]),
          a[1] as int,
          PluginApi.bytes(a[2]),
        );
      },
      'ultralight.mf0UlcSetKey': (a) async {
        return await device.mf0UlcSetKey(
          PluginApi.bytes(a[0]),
          PluginApi.bytes(a[1]),
        );
      },
      'device.hf14aSetFieldOn': (a) async {
        await device.hf14aSetFieldOn();
        return null;
      },
      'device.hf14aSetFieldOff': (a) async {
        await device.hf14aSetFieldOff();
        return null;
      },
      'classic.mf1GetFieldOffDoReset': (a) async {
        return await device.mf1GetFieldOffDoReset();
      },
      'classic.mf1SetFieldOffDoReset': (a) async {
        await device.mf1SetFieldOffDoReset(a[0] as bool);
        return null;
      },
      'slots.deleteSlotTagNick': (a) async {
        await device.deleteSlotTagNick(
          a[0] as int,
          TagFrequency.values.byName(a[1] as String),
        );
        return null;
      },
      'device.scan14443aTagKeep': (a) async {
        return await device.scan14443aTagKeep();
      },
      'device.hf14aSetConfig': (a) async {
        await device.hf14aSetConfig(
          a[0] as int,
          a[1] as int,
          a[2] as int,
          a[3] as int,
        );
        return null;
      },
      'device.ioProxDecodeRaw': (a) async {
        return await device.ioProxDecodeRaw(PluginApi.bytes(a[0]));
      },
      'device.ioProxComposeID': (a) async {
        return await device.ioProxComposeID(
          a[0] as int,
          a[1] as int,
          a[2] as int,
        );
      },
      'device.adcGenericRead': (a) async {
        return await device.adcGenericRead();
      },
      'device.hf14a4ApduSend': (a) async {
        await device.hf14a4ApduSend(PluginApi.bytes(a[0]));
        return null;
      },
      'device.hf14a4SetAntiColl': (a) async {
        await device.hf14a4SetAntiColl(
          PluginApi.bytes(a[0]),
          PluginApi.bytes(a[1]),
          a[2] as int,
          PluginApi.bytes(a[3]),
        );
        return null;
      },
      'device.hf14a4AddStaticResponse': (a) async {
        await device.hf14a4AddStaticResponse(
          PluginApi.bytes(a[0]),
          PluginApi.bytes(a[1]),
        );
        return null;
      },
      'device.hf14a4ClearStaticResponses': (a) async {
        await device.hf14a4ClearStaticResponses();
        return null;
      },
      'device.hf14a4ReaderApdu': (a) async {
        return await device.hf14a4ReaderApdu(PluginApi.bytes(a[0]));
      },
      'device.hf14a4EmvScan': (a) async {
        return await device.hf14a4EmvScan();
      },
      'ultralight.mf0GetMagicMode': (a) async {
        return await device.mf0GetMagicMode();
      },
      'ultralight.mf0SetMagicMode': (a) async {
        await device.mf0SetMagicMode(a[0] as bool);
        return null;
      },
      'ultralight.mf0EmulatorReadPages': (a) async {
        return await device.mf0EmulatorReadPages(a[0] as int, a[1] as int);
      },
      'ultralight.mf0EmulatorWritePages': (a) async {
        await device.mf0EmulatorWritePages(a[0] as int, PluginApi.bytes(a[1]));
        return null;
      },
      'ultralight.mf0EmulatorGetVersionData': (a) async {
        return await device.mf0EmulatorGetVersionData();
      },
      'ultralight.mf0EmulatorSetVersionData': (a) async {
        await device.mf0EmulatorSetVersionData(PluginApi.bytes(a[0]));
        return null;
      },
      'ultralight.mf0EmulatorGetSignatureData': (a) async {
        return await device.mf0EmulatorGetSignatureData();
      },
      'ultralight.mf0EmulatorSetSignatureData': (a) async {
        await device.mf0EmulatorSetSignatureData(PluginApi.bytes(a[0]));
        return null;
      },
      'ultralight.mf0ResetAuthCount': (a) async {
        return await device.mf0ResetAuthCount();
      },
      'ultralight.mf0EmulatorGetPageCount': (a) async {
        return await device.mf0EmulatorGetPageCount();
      },
      'ultralight.mf0EmulatorSetCounterData': (a) async {
        await device.mf0EmulatorSetCounterData(
          a[0] as int,
          a[1] as int,
          a[2] as bool,
        );
        return null;
      },
      'ultralight.mf0NtagGetWriteMode': (a) async {
        return await device.mf0NtagGetWriteMode();
      },
      'ultralight.mf0NtagSetWriteMode': (a) async {
        await device.mf0NtagSetWriteMode(
          MifareWriteMode.values.byName(a[0] as String),
        );
        return null;
      },
      'ultralight.mf0NtagGetDetectionEnable': (a) async {
        return await device.mf0NtagGetDetectionEnable();
      },
      'ultralight.mf0NtagSetDetectionEnable': (a) async {
        await device.mf0NtagSetDetectionEnable(a[0] as bool);
        return null;
      },
      'ultralight.mf0NtagGetDetectionCount': (a) async {
        return await device.mf0NtagGetDetectionCount();
      },
      'ultralight.mf0NtagGetDetectionLog': (a) async {
        return await device.mf0NtagGetDetectionLog(a[0] as int);
      },
    });
  }
}
