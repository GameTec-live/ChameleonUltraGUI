
import 'package:archive/archive.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/bridge/dfu.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/http.dart';
import 'package:chameleonultragui/protobuf/dfu-cc.pb.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

enum FlashFirmwareState {
  ready('Checking list with available firmware', false),
  loadFile('Load firmware file', false),
  loadingFile('Loading firmware file', true),
  unpackFile('Unpacking firmware file', false),
  validateFirmware('Validating firmware', false),
  checkDeviceMode('Checking if device is in DFU mode', false),
  changeDeviceMode('Switching device to DFU mode', false),
  startFlash('Preparing flash', false),
  flashDat('Flashing .dat file', true),
  flashBin('Flashing .bin file', true),
  disconnect('Disconnecting device', false),
  done('Flash successful!', false);

  const FlashFirmwareState(this.description, this.hasProgress);

  final String description;
  final bool hasProgress;
}

class FlashFirmwareUpdateProgress {
  final FlashFirmwareState state;
  final double? progress;

  FlashFirmwareUpdateProgress(this.state, this.progress);
}

class Firmware {
  final Uint8List datFile;
  final Uint8List binFile;

  Firmware(this.datFile, this.binFile);

  factory Firmware.fromZip(Uint8List bytes) {
    Uint8List applicationDat = Uint8List(0);
    Uint8List applicationBin = Uint8List(0);

    final archive = ZipDecoder().decodeBytes(bytes);

    for (var file in archive.files) {
      if (file.isFile) {
        if (file.name == 'application.dat') {
          applicationDat = file.content;
        } else if (file.name == 'application.bin') {
          applicationBin = file.content;
        }
      }
    }

    return Firmware(applicationDat, applicationBin);
  }

  Future<void> validate() async {
    if (datFile.isEmpty || binFile.isEmpty) {
      throw ("Empty firmware file");
    }

    final metadata = Packet.fromBuffer(datFile);
    if (!metadata.hasSignedCommand()) {
      throw ("Package isn't signed");
    }

    final command = metadata.signedCommand.command;
    if (!command.hasInit()) {
      throw ("Package command doesn't have init");
    }

    final hash = command.init.hash;

    final expectedHash = hash.hash.reversed;
    final actualHash = switch (hash.hashType) {
      HashType.SHA128 => sha1,
      HashType.SHA256 => sha256,
      HashType.SHA512 => sha512,
      _ => throw ("Unsupported hash type ${hash.hashType}"),
    }
        .convert(binFile)
        .bytes;

    final areSameHashes = const IterableEquality().equals(expectedHash, actualHash);
    if (!areSameHashes) {
      throw ("Hashes don't match! expected: ${expectedHash.toList()}, actual: $actualHash");
    }
  }
}

class GithubAsset {
  final String commitHash;
  final String url;

  const GithubAsset(this.commitHash, this.url);
}

abstract class FirmwareProvider {
  Uint8List? file;

  Future<bool> ready();
  Future<bool?> updateAvailable(String version);
  Future<Uint8List?> load(Function(double progress)? onProgress);
  Future<Firmware?> get(Uint8List bytes) async {
    try {
      return Firmware.fromZip(bytes);
    } catch (_) {
      rethrow;
    }

    // return null;
  }
}

abstract class FirmwareUrlProvider extends FirmwareProvider {
  final ChameleonDevice device;
  UrlParser? urlParser;

  // ignore: unused_field
  GithubAsset? latestAsset;

  FirmwareUrlProvider(this.device, { this.urlParser });

  get assetBaseName {
    return "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app";
  }

  @override
  Future<bool?> updateAvailable(String version) async {
    final isSameCommitHash = latestAsset!.commitHash.startsWith(version);
    return !isSameCommitHash;
  }

  @override
  Future<Uint8List?> load(onProgress) async {
    final request = HttpGetRequest.fromString(
      latestAsset!.url,
      onProgress: onProgress,
      urlParser: urlParser
    );
    var bytes = await request.asBytes();
    return bytes;
  }
}

class FirmwareGithubNightlyProvider extends FirmwareUrlProvider {
  final String branchName;

  FirmwareGithubNightlyProvider(
    super.device,
    { super.urlParser, this.branchName = 'main' }
  );

  @override
  Future<bool> ready() async {
    latestAsset = null;

    final request = HttpGetRequest.fromString(
      'https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/actions/artifacts',
      urlParser: urlParser
    );

    final response = await request.asJson();

    final artifacts = response!['artifacts'];
    if (artifacts == null || artifacts is! List) {
      String error = 'Unknown error occured';
      if (response.containsKey("message")) {
        error = response["message"];
      }

      throw error;
    }

    for (var artifact in artifacts) {
      if (artifact["name"] == assetBaseName && artifact["workflow_run"]["head_branch"] == branchName) {
        final artifactId = artifact["id"];
        final workflowRunId = artifact["workflow_run"]["id"];

        latestAsset = GithubAsset(
          artifact["workflow_run"]["head_sha"],
          'https://nightly.link/RfidResearchGroup/ChameleonUltra/suites/$workflowRunId/artifacts/$artifactId'
        );

        return true;
      }
    }

    return false;
  }
}

class FirmwareGithubReleasesProvider extends FirmwareUrlProvider {
  FirmwareGithubReleasesProvider(super.device, { super.urlParser });

  @override
  Future<bool> ready() async {
    latestAsset = null;

    final request = HttpGetRequest.fromString(
      'https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases',
      urlParser: urlParser
    );

    final response = await request.asJson();
    if (response is! List || response.isEmpty) {
      String error = 'Unknown error occured';
      if (response.containsKey("message")) {
        error = response["message"];
      }

      throw error;
    }

    final expectedAssetName = "$assetBaseName.zip";
    final lastestRelease = response[0];
    for (var file in lastestRelease["assets"]) {
      if (file["name"] == expectedAssetName) {
        latestAsset = GithubAsset(
          lastestRelease['target_commitish'],
          file["browser_download_url"],
        );
        return true;
      }
    }

    return false;
  }
}

class FirmwareZipFileProvider extends FirmwareProvider {
  final Uint8List bytes;

  FirmwareZipFileProvider(this.bytes);

  @override
  Future<bool> ready() async => bytes.isNotEmpty;

  @override
  Future<bool?> updateAvailable(String version) async => true;

  @override
  Future<Uint8List?> load(onProgress) async => bytes;
}

class FirmwareFlasher {
  @protected
  final AbstractSerial connector;
  @protected
  final FirmwareProvider provider;

  FirmwareFlasher(this.connector, this.provider);

  bool _isReady = false;

  factory FirmwareFlasher.fromGithubNightly(AbstractSerial connector) {
    final instance = FirmwareFlasher(connector, FirmwareGithubNightlyProvider(connector.device));
    return instance;
  }

  factory FirmwareFlasher.fromGithubLatest(AbstractSerial connector) {
    final instance = FirmwareFlasher(connector, FirmwareGithubReleasesProvider(connector.device));
    return instance;
  }

  factory FirmwareFlasher.fromZipFile(AbstractSerial connector, Uint8List bytes) {
    final instance = FirmwareFlasher(connector, FirmwareZipFileProvider(bytes));
    return instance;
  }

  String? get availableFirmwareVersion {
    var p = provider;

    if (p is FirmwareUrlProvider) {
      return p.latestAsset!.commitHash.substring(0, 8);
    }

    return null;
  }

  @protected
  ready() async {
    if (!_isReady) {
      _isReady = await provider.ready();
    }

    return _isReady;
  }

  Future<bool?> updateAvailable(String version) async {
    final isReady = await ready();
    if (!isReady) {
      return null;
    }

    return provider.updateAvailable(version);
  }

  Future<void> flash(void Function(FlashFirmwareUpdateProgress updateProgress) onStateProgress) async {
    bool isBLE = connector.portName.contains(":");
    if (isBLE) {
      throw ("BLE DFU not yet supported");
    }

    // Prepare the firmware provider, for urls this means downloading the latest release info
    onStateProgress(FlashFirmwareUpdateProgress(FlashFirmwareState.ready, null));
    final isReady = await ready();
    if (!isReady) {
      return;
    }

    // Load the file, for urls this means downloading the file
    onStateProgress(FlashFirmwareUpdateProgress(FlashFirmwareState.loadFile, null));
    final bytes = await provider.load((progress) => 
      onStateProgress(FlashFirmwareUpdateProgress(FlashFirmwareState.loadingFile, progress))
    );
    if (bytes == null) {
      return;
    }

    // Unzip the file
    onStateProgress(FlashFirmwareUpdateProgress(FlashFirmwareState.unpackFile, null));
    final firmware = await provider.get(bytes);
    if (firmware == null) {
      return;
    }

    try {
      // Validate the firmware files from the zip
      onStateProgress(FlashFirmwareUpdateProgress(FlashFirmwareState.validateFirmware, null));
      await firmware.validate();
    } catch (error) {
      return;
    }

    // Switch the device to DFU mode if it's not already
    onStateProgress(FlashFirmwareUpdateProgress(FlashFirmwareState.checkDeviceMode, null));
    final changedMode = await enterDFUModeIfNeeded();
    if (changedMode) {
      onStateProgress(FlashFirmwareUpdateProgress(FlashFirmwareState.changeDeviceMode, null));

      if (kIsWeb) {
        // It's not likely we can wait on the DFU device on web as the
        // user first needs to pair it
        return;
      }

      // Wait for the device to reconnect
      await waitForDFUDevice();
    }

    // Start flashing the firmware
    onStateProgress(FlashFirmwareUpdateProgress(FlashFirmwareState.startFlash, null));
    await flashFirmware(firmware, (type, progress) {
      if (type == 1) {
        onStateProgress(FlashFirmwareUpdateProgress(FlashFirmwareState.flashDat, progress));
      } else {
        onStateProgress(FlashFirmwareUpdateProgress(FlashFirmwareState.flashBin, progress));
      }
    });

    // Disconnect the device and wait for it to reconnect as a Chameleon
    onStateProgress(FlashFirmwareUpdateProgress(FlashFirmwareState.disconnect, null));
    await connector.performDisconnect();
    await asyncSleep(500); // allow exit DFU mode

    // Done!
    onStateProgress(FlashFirmwareUpdateProgress(FlashFirmwareState.done, null));
  }

  @protected
  Future<bool> enterDFUModeIfNeeded() async {
    bool isInDFUMode = connector.connectionType == ConnectionType.dfu;

    if (connector.connected && !isInDFUMode) {
      var communicator = ChameleonCommunicator(port: connector);
      await communicator.enterDFUMode();

      await connector.performDisconnect();
      return true;
    }

    return false;
  }

  @protected
  Future<void> waitForDFUDevice({ int timeoutInSeconds = 10 }) async {
    List<ChameleonDevicePort> chameleons = [];
    for (var tries = 0; tries <= timeoutInSeconds * 4; tries++) { // Wait max seconds for a device to enter DFU mode & reconnect
      await asyncSleep(250);

      chameleons = await connector.availableChameleons(true);
      if (chameleons.isNotEmpty) {
        break; 
      }
    }

    if (chameleons.isEmpty) {
      throw ("No Chameleon in DFU mode after waiting for 10 seconds");
    } else if (chameleons.length > 1) {
      throw ("More than one Chameleon in DFU. Please connect only one at a time");
    }

    await connector.connectSpecificDevice(chameleons[0].port);
  }

  @protected
  flashFirmware(Firmware firmware, void Function(int, double) onProgress) async {
    final dfu = ChameleonDFU(port: connector);
    await connector.finishRead();
    await connector.open();
    await dfu.setPRN();
    await dfu.getMTU();
    await dfu.flashFirmware(0x01, firmware.datFile, (progress) => onProgress(1, progress / 100));
    await dfu.flashFirmware(0x02, firmware.binFile, (progress) => onProgress(2, progress / 100));
  }
}