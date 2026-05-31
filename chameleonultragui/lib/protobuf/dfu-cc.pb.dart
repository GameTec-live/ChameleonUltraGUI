// This is a generated file - do not edit.
//
// Generated from dfu-cc.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'dfu-cc.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'dfu-cc.pbenum.dart';

class Hash extends $pb.GeneratedMessage {
  factory Hash({
    HashType? hashType,
    $core.List<$core.int>? hash,
  }) {
    final result = create();
    if (hashType != null) result.hashType = hashType;
    if (hash != null) result.hash = hash;
    return result;
  }

  Hash._();

  factory Hash.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Hash.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Hash',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'dfu'),
      createEmptyInstance: create)
    ..aE<HashType>(1, _omitFieldNames ? '' : 'hashType',
        fieldType: $pb.PbFieldType.QE, enumValues: HashType.values)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'hash', $pb.PbFieldType.QY);

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Hash clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Hash copyWith(void Function(Hash) updates) =>
      super.copyWith((message) => updates(message as Hash)) as Hash;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Hash create() => Hash._();
  @$core.override
  Hash createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Hash getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Hash>(create);
  static Hash? _defaultInstance;

  @$pb.TagNumber(1)
  HashType get hashType => $_getN(0);
  @$pb.TagNumber(1)
  set hashType(HashType value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasHashType() => $_has(0);
  @$pb.TagNumber(1)
  void clearHashType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get hash => $_getN(1);
  @$pb.TagNumber(2)
  set hash($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHash() => $_has(1);
  @$pb.TagNumber(2)
  void clearHash() => $_clearField(2);
}

class BootValidation extends $pb.GeneratedMessage {
  factory BootValidation({
    ValidationType? type,
    $core.List<$core.int>? bytes,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (bytes != null) result.bytes = bytes;
    return result;
  }

  BootValidation._();

  factory BootValidation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BootValidation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BootValidation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'dfu'),
      createEmptyInstance: create)
    ..aE<ValidationType>(1, _omitFieldNames ? '' : 'type',
        fieldType: $pb.PbFieldType.QE, enumValues: ValidationType.values)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'bytes', $pb.PbFieldType.QY);

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BootValidation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BootValidation copyWith(void Function(BootValidation) updates) =>
      super.copyWith((message) => updates(message as BootValidation))
          as BootValidation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BootValidation create() => BootValidation._();
  @$core.override
  BootValidation createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BootValidation getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BootValidation>(create);
  static BootValidation? _defaultInstance;

  @$pb.TagNumber(1)
  ValidationType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(ValidationType value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get bytes => $_getN(1);
  @$pb.TagNumber(2)
  set bytes($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearBytes() => $_clearField(2);
}

/// Commands data
class InitCommand extends $pb.GeneratedMessage {
  factory InitCommand({
    $core.int? fwVersion,
    $core.int? hwVersion,
    $core.Iterable<$core.int>? sdReq,
    FwType? type,
    $core.int? sdSize,
    $core.int? blSize,
    $core.int? appSize,
    Hash? hash,
    $core.bool? isDebug,
    $core.Iterable<BootValidation>? bootValidation,
  }) {
    final result = create();
    if (fwVersion != null) result.fwVersion = fwVersion;
    if (hwVersion != null) result.hwVersion = hwVersion;
    if (sdReq != null) result.sdReq.addAll(sdReq);
    if (type != null) result.type = type;
    if (sdSize != null) result.sdSize = sdSize;
    if (blSize != null) result.blSize = blSize;
    if (appSize != null) result.appSize = appSize;
    if (hash != null) result.hash = hash;
    if (isDebug != null) result.isDebug = isDebug;
    if (bootValidation != null) result.bootValidation.addAll(bootValidation);
    return result;
  }

  InitCommand._();

  factory InitCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory InitCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InitCommand',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'dfu'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'fwVersion', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'hwVersion', fieldType: $pb.PbFieldType.OU3)
    ..p<$core.int>(3, _omitFieldNames ? '' : 'sdReq', $pb.PbFieldType.KU3)
    ..aE<FwType>(4, _omitFieldNames ? '' : 'type', enumValues: FwType.values)
    ..aI(5, _omitFieldNames ? '' : 'sdSize', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'blSize', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'appSize', fieldType: $pb.PbFieldType.OU3)
    ..aOM<Hash>(8, _omitFieldNames ? '' : 'hash', subBuilder: Hash.create)
    ..aOB(9, _omitFieldNames ? '' : 'isDebug')
    ..pPM<BootValidation>(10, _omitFieldNames ? '' : 'bootValidation',
        subBuilder: BootValidation.create);

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InitCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InitCommand copyWith(void Function(InitCommand) updates) =>
      super.copyWith((message) => updates(message as InitCommand))
          as InitCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static InitCommand create() => InitCommand._();
  @$core.override
  InitCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static InitCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<InitCommand>(create);
  static InitCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get fwVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set fwVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFwVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearFwVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get hwVersion => $_getIZ(1);
  @$pb.TagNumber(2)
  set hwVersion($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHwVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearHwVersion() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$core.int> get sdReq => $_getList(2);

  @$pb.TagNumber(4)
  FwType get type => $_getN(3);
  @$pb.TagNumber(4)
  set type(FwType value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasType() => $_has(3);
  @$pb.TagNumber(4)
  void clearType() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get sdSize => $_getIZ(4);
  @$pb.TagNumber(5)
  set sdSize($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSdSize() => $_has(4);
  @$pb.TagNumber(5)
  void clearSdSize() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get blSize => $_getIZ(5);
  @$pb.TagNumber(6)
  set blSize($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasBlSize() => $_has(5);
  @$pb.TagNumber(6)
  void clearBlSize() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get appSize => $_getIZ(6);
  @$pb.TagNumber(7)
  set appSize($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAppSize() => $_has(6);
  @$pb.TagNumber(7)
  void clearAppSize() => $_clearField(7);

  @$pb.TagNumber(8)
  Hash get hash => $_getN(7);
  @$pb.TagNumber(8)
  set hash(Hash value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasHash() => $_has(7);
  @$pb.TagNumber(8)
  void clearHash() => $_clearField(8);
  @$pb.TagNumber(8)
  Hash ensureHash() => $_ensure(7);

  @$pb.TagNumber(9)
  $core.bool get isDebug => $_getBF(8);
  @$pb.TagNumber(9)
  set isDebug($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasIsDebug() => $_has(8);
  @$pb.TagNumber(9)
  void clearIsDebug() => $_clearField(9);

  @$pb.TagNumber(10)
  $pb.PbList<BootValidation> get bootValidation => $_getList(9);
}

class ResetCommand extends $pb.GeneratedMessage {
  factory ResetCommand({
    $core.int? timeout,
  }) {
    final result = create();
    if (timeout != null) result.timeout = timeout;
    return result;
  }

  ResetCommand._();

  factory ResetCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ResetCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ResetCommand',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'dfu'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'timeout', fieldType: $pb.PbFieldType.QU3);

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResetCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResetCommand copyWith(void Function(ResetCommand) updates) =>
      super.copyWith((message) => updates(message as ResetCommand))
          as ResetCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ResetCommand create() => ResetCommand._();
  @$core.override
  ResetCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ResetCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ResetCommand>(create);
  static ResetCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get timeout => $_getIZ(0);
  @$pb.TagNumber(1)
  set timeout($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTimeout() => $_has(0);
  @$pb.TagNumber(1)
  void clearTimeout() => $_clearField(1);
}

/// Command type
class Command extends $pb.GeneratedMessage {
  factory Command({
    OpCode? opCode,
    InitCommand? init,
    ResetCommand? reset,
  }) {
    final result = create();
    if (opCode != null) result.opCode = opCode;
    if (init != null) result.init = init;
    if (reset != null) result.reset = reset;
    return result;
  }

  Command._();

  factory Command.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Command.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Command',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'dfu'),
      createEmptyInstance: create)
    ..aE<OpCode>(1, _omitFieldNames ? '' : 'opCode', enumValues: OpCode.values)
    ..aOM<InitCommand>(2, _omitFieldNames ? '' : 'init',
        subBuilder: InitCommand.create)
    ..aOM<ResetCommand>(3, _omitFieldNames ? '' : 'reset',
        subBuilder: ResetCommand.create);

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Command clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Command copyWith(void Function(Command) updates) =>
      super.copyWith((message) => updates(message as Command)) as Command;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Command create() => Command._();
  @$core.override
  Command createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Command getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Command>(create);
  static Command? _defaultInstance;

  @$pb.TagNumber(1)
  OpCode get opCode => $_getN(0);
  @$pb.TagNumber(1)
  set opCode(OpCode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasOpCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearOpCode() => $_clearField(1);

  @$pb.TagNumber(2)
  InitCommand get init => $_getN(1);
  @$pb.TagNumber(2)
  set init(InitCommand value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasInit() => $_has(1);
  @$pb.TagNumber(2)
  void clearInit() => $_clearField(2);
  @$pb.TagNumber(2)
  InitCommand ensureInit() => $_ensure(1);

  @$pb.TagNumber(3)
  ResetCommand get reset => $_getN(2);
  @$pb.TagNumber(3)
  set reset(ResetCommand value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasReset() => $_has(2);
  @$pb.TagNumber(3)
  void clearReset() => $_clearField(3);
  @$pb.TagNumber(3)
  ResetCommand ensureReset() => $_ensure(2);
}

class SignedCommand extends $pb.GeneratedMessage {
  factory SignedCommand({
    Command? command,
    SignatureType? signatureType,
    $core.List<$core.int>? signature,
  }) {
    final result = create();
    if (command != null) result.command = command;
    if (signatureType != null) result.signatureType = signatureType;
    if (signature != null) result.signature = signature;
    return result;
  }

  SignedCommand._();

  factory SignedCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SignedCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SignedCommand',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'dfu'),
      createEmptyInstance: create)
    ..aQM<Command>(1, _omitFieldNames ? '' : 'command',
        subBuilder: Command.create)
    ..aE<SignatureType>(2, _omitFieldNames ? '' : 'signatureType',
        fieldType: $pb.PbFieldType.QE, enumValues: SignatureType.values)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.QY);

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignedCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignedCommand copyWith(void Function(SignedCommand) updates) =>
      super.copyWith((message) => updates(message as SignedCommand))
          as SignedCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SignedCommand create() => SignedCommand._();
  @$core.override
  SignedCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SignedCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SignedCommand>(create);
  static SignedCommand? _defaultInstance;

  @$pb.TagNumber(1)
  Command get command => $_getN(0);
  @$pb.TagNumber(1)
  set command(Command value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCommand() => $_has(0);
  @$pb.TagNumber(1)
  void clearCommand() => $_clearField(1);
  @$pb.TagNumber(1)
  Command ensureCommand() => $_ensure(0);

  @$pb.TagNumber(2)
  SignatureType get signatureType => $_getN(1);
  @$pb.TagNumber(2)
  set signatureType(SignatureType value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasSignatureType() => $_has(1);
  @$pb.TagNumber(2)
  void clearSignatureType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get signature => $_getN(2);
  @$pb.TagNumber(3)
  set signature($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSignature() => $_has(2);
  @$pb.TagNumber(3)
  void clearSignature() => $_clearField(3);
}

/// Parent packet type
class Packet extends $pb.GeneratedMessage {
  factory Packet({
    Command? command,
    SignedCommand? signedCommand,
  }) {
    final result = create();
    if (command != null) result.command = command;
    if (signedCommand != null) result.signedCommand = signedCommand;
    return result;
  }

  Packet._();

  factory Packet.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Packet.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Packet',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'dfu'),
      createEmptyInstance: create)
    ..aOM<Command>(1, _omitFieldNames ? '' : 'command',
        subBuilder: Command.create)
    ..aOM<SignedCommand>(2, _omitFieldNames ? '' : 'signedCommand',
        subBuilder: SignedCommand.create);

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Packet clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Packet copyWith(void Function(Packet) updates) =>
      super.copyWith((message) => updates(message as Packet)) as Packet;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Packet create() => Packet._();
  @$core.override
  Packet createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Packet getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Packet>(create);
  static Packet? _defaultInstance;

  @$pb.TagNumber(1)
  Command get command => $_getN(0);
  @$pb.TagNumber(1)
  set command(Command value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCommand() => $_has(0);
  @$pb.TagNumber(1)
  void clearCommand() => $_clearField(1);
  @$pb.TagNumber(1)
  Command ensureCommand() => $_ensure(0);

  @$pb.TagNumber(2)
  SignedCommand get signedCommand => $_getN(1);
  @$pb.TagNumber(2)
  set signedCommand(SignedCommand value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasSignedCommand() => $_has(1);
  @$pb.TagNumber(2)
  void clearSignedCommand() => $_clearField(2);
  @$pb.TagNumber(2)
  SignedCommand ensureSignedCommand() => $_ensure(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
