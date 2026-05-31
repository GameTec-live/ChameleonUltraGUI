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

/// Definition of enums and types
class OpCode extends $pb.ProtobufEnum {
  static const OpCode RESET = OpCode._(0, _omitEnumNames ? '' : 'RESET');
  static const OpCode INIT = OpCode._(1, _omitEnumNames ? '' : 'INIT');

  static const $core.List<OpCode> values = <OpCode>[
    RESET,
    INIT,
  ];

  static final $core.List<OpCode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static OpCode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const OpCode._(super.value, super.name);
}

class FwType extends $pb.ProtobufEnum {
  static const FwType APPLICATION =
      FwType._(0, _omitEnumNames ? '' : 'APPLICATION');
  static const FwType SOFTDEVICE =
      FwType._(1, _omitEnumNames ? '' : 'SOFTDEVICE');
  static const FwType BOOTLOADER =
      FwType._(2, _omitEnumNames ? '' : 'BOOTLOADER');
  static const FwType SOFTDEVICE_BOOTLOADER =
      FwType._(3, _omitEnumNames ? '' : 'SOFTDEVICE_BOOTLOADER');
  static const FwType EXTERNAL_APPLICATION =
      FwType._(4, _omitEnumNames ? '' : 'EXTERNAL_APPLICATION');

  static const $core.List<FwType> values = <FwType>[
    APPLICATION,
    SOFTDEVICE,
    BOOTLOADER,
    SOFTDEVICE_BOOTLOADER,
    EXTERNAL_APPLICATION,
  ];

  static final $core.List<FwType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static FwType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const FwType._(super.value, super.name);
}

class HashType extends $pb.ProtobufEnum {
  static const HashType NO_HASH =
      HashType._(0, _omitEnumNames ? '' : 'NO_HASH');
  static const HashType CRC = HashType._(1, _omitEnumNames ? '' : 'CRC');
  static const HashType SHA128 = HashType._(2, _omitEnumNames ? '' : 'SHA128');
  static const HashType SHA256 = HashType._(3, _omitEnumNames ? '' : 'SHA256');
  static const HashType SHA512 = HashType._(4, _omitEnumNames ? '' : 'SHA512');

  static const $core.List<HashType> values = <HashType>[
    NO_HASH,
    CRC,
    SHA128,
    SHA256,
    SHA512,
  ];

  static final $core.List<HashType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static HashType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const HashType._(super.value, super.name);
}

class ValidationType extends $pb.ProtobufEnum {
  static const ValidationType NO_VALIDATION =
      ValidationType._(0, _omitEnumNames ? '' : 'NO_VALIDATION');
  static const ValidationType VALIDATE_GENERATED_CRC =
      ValidationType._(1, _omitEnumNames ? '' : 'VALIDATE_GENERATED_CRC');
  static const ValidationType VALIDATE_SHA256 =
      ValidationType._(2, _omitEnumNames ? '' : 'VALIDATE_SHA256');
  static const ValidationType VALIDATE_ECDSA_P256_SHA256 =
      ValidationType._(3, _omitEnumNames ? '' : 'VALIDATE_ECDSA_P256_SHA256');

  static const $core.List<ValidationType> values = <ValidationType>[
    NO_VALIDATION,
    VALIDATE_GENERATED_CRC,
    VALIDATE_SHA256,
    VALIDATE_ECDSA_P256_SHA256,
  ];

  static final $core.List<ValidationType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ValidationType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ValidationType._(super.value, super.name);
}

/// Signed command types
class SignatureType extends $pb.ProtobufEnum {
  static const SignatureType ECDSA_P256_SHA256 =
      SignatureType._(0, _omitEnumNames ? '' : 'ECDSA_P256_SHA256');
  static const SignatureType ED25519 =
      SignatureType._(1, _omitEnumNames ? '' : 'ED25519');

  static const $core.List<SignatureType> values = <SignatureType>[
    ECDSA_P256_SHA256,
    ED25519,
  ];

  static final $core.List<SignatureType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static SignatureType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SignatureType._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
