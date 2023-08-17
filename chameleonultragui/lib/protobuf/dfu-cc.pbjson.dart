//
//  Generated code. Do not modify.
//  source: dfu-cc.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use opCodeDescriptor instead')
const OpCode$json = {
  '1': 'OpCode',
  '2': [
    {'1': 'RESET', '2': 0},
    {'1': 'INIT', '2': 1},
  ],
};

/// Descriptor for `OpCode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List opCodeDescriptor = $convert.base64Decode(
    'CgZPcENvZGUSCQoFUkVTRVQQABIICgRJTklUEAE=');

@$core.Deprecated('Use fwTypeDescriptor instead')
const FwType$json = {
  '1': 'FwType',
  '2': [
    {'1': 'APPLICATION', '2': 0},
    {'1': 'SOFTDEVICE', '2': 1},
    {'1': 'BOOTLOADER', '2': 2},
    {'1': 'SOFTDEVICE_BOOTLOADER', '2': 3},
    {'1': 'EXTERNAL_APPLICATION', '2': 4},
  ],
};

/// Descriptor for `FwType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List fwTypeDescriptor = $convert.base64Decode(
    'CgZGd1R5cGUSDwoLQVBQTElDQVRJT04QABIOCgpTT0ZUREVWSUNFEAESDgoKQk9PVExPQURFUh'
    'ACEhkKFVNPRlRERVZJQ0VfQk9PVExPQURFUhADEhgKFEVYVEVSTkFMX0FQUExJQ0FUSU9OEAQ=');

@$core.Deprecated('Use hashTypeDescriptor instead')
const HashType$json = {
  '1': 'HashType',
  '2': [
    {'1': 'NO_HASH', '2': 0},
    {'1': 'CRC', '2': 1},
    {'1': 'SHA128', '2': 2},
    {'1': 'SHA256', '2': 3},
    {'1': 'SHA512', '2': 4},
  ],
};

/// Descriptor for `HashType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List hashTypeDescriptor = $convert.base64Decode(
    'CghIYXNoVHlwZRILCgdOT19IQVNIEAASBwoDQ1JDEAESCgoGU0hBMTI4EAISCgoGU0hBMjU2EA'
    'MSCgoGU0hBNTEyEAQ=');

@$core.Deprecated('Use validationTypeDescriptor instead')
const ValidationType$json = {
  '1': 'ValidationType',
  '2': [
    {'1': 'NO_VALIDATION', '2': 0},
    {'1': 'VALIDATE_GENERATED_CRC', '2': 1},
    {'1': 'VALIDATE_SHA256', '2': 2},
    {'1': 'VALIDATE_ECDSA_P256_SHA256', '2': 3},
  ],
};

/// Descriptor for `ValidationType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List validationTypeDescriptor = $convert.base64Decode(
    'Cg5WYWxpZGF0aW9uVHlwZRIRCg1OT19WQUxJREFUSU9OEAASGgoWVkFMSURBVEVfR0VORVJBVE'
    'VEX0NSQxABEhMKD1ZBTElEQVRFX1NIQTI1NhACEh4KGlZBTElEQVRFX0VDRFNBX1AyNTZfU0hB'
    'MjU2EAM=');

@$core.Deprecated('Use signatureTypeDescriptor instead')
const SignatureType$json = {
  '1': 'SignatureType',
  '2': [
    {'1': 'ECDSA_P256_SHA256', '2': 0},
    {'1': 'ED25519', '2': 1},
  ],
};

/// Descriptor for `SignatureType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List signatureTypeDescriptor = $convert.base64Decode(
    'Cg1TaWduYXR1cmVUeXBlEhUKEUVDRFNBX1AyNTZfU0hBMjU2EAASCwoHRUQyNTUxORAB');

@$core.Deprecated('Use hashDescriptor instead')
const Hash$json = {
  '1': 'Hash',
  '2': [
    {'1': 'hash_type', '3': 1, '4': 2, '5': 14, '6': '.dfu.HashType', '10': 'hashType'},
    {'1': 'hash', '3': 2, '4': 2, '5': 12, '10': 'hash'},
  ],
};

/// Descriptor for `Hash`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hashDescriptor = $convert.base64Decode(
    'CgRIYXNoEioKCWhhc2hfdHlwZRgBIAIoDjINLmRmdS5IYXNoVHlwZVIIaGFzaFR5cGUSEgoEaG'
    'FzaBgCIAIoDFIEaGFzaA==');

@$core.Deprecated('Use bootValidationDescriptor instead')
const BootValidation$json = {
  '1': 'BootValidation',
  '2': [
    {'1': 'type', '3': 1, '4': 2, '5': 14, '6': '.dfu.ValidationType', '10': 'type'},
    {'1': 'bytes', '3': 2, '4': 2, '5': 12, '10': 'bytes'},
  ],
};

/// Descriptor for `BootValidation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bootValidationDescriptor = $convert.base64Decode(
    'Cg5Cb290VmFsaWRhdGlvbhInCgR0eXBlGAEgAigOMhMuZGZ1LlZhbGlkYXRpb25UeXBlUgR0eX'
    'BlEhQKBWJ5dGVzGAIgAigMUgVieXRlcw==');

@$core.Deprecated('Use initCommandDescriptor instead')
const InitCommand$json = {
  '1': 'InitCommand',
  '2': [
    {'1': 'fw_version', '3': 1, '4': 1, '5': 13, '10': 'fwVersion'},
    {'1': 'hw_version', '3': 2, '4': 1, '5': 13, '10': 'hwVersion'},
    {
      '1': 'sd_req',
      '3': 3,
      '4': 3,
      '5': 13,
      '8': {'2': true},
      '10': 'sdReq',
    },
    {'1': 'type', '3': 4, '4': 1, '5': 14, '6': '.dfu.FwType', '10': 'type'},
    {'1': 'sd_size', '3': 5, '4': 1, '5': 13, '10': 'sdSize'},
    {'1': 'bl_size', '3': 6, '4': 1, '5': 13, '10': 'blSize'},
    {'1': 'app_size', '3': 7, '4': 1, '5': 13, '10': 'appSize'},
    {'1': 'hash', '3': 8, '4': 1, '5': 11, '6': '.dfu.Hash', '10': 'hash'},
    {'1': 'is_debug', '3': 9, '4': 1, '5': 8, '7': 'false', '10': 'isDebug'},
    {'1': 'boot_validation', '3': 10, '4': 3, '5': 11, '6': '.dfu.BootValidation', '10': 'bootValidation'},
  ],
};

/// Descriptor for `InitCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List initCommandDescriptor = $convert.base64Decode(
    'CgtJbml0Q29tbWFuZBIdCgpmd192ZXJzaW9uGAEgASgNUglmd1ZlcnNpb24SHQoKaHdfdmVyc2'
    'lvbhgCIAEoDVIJaHdWZXJzaW9uEhkKBnNkX3JlcRgDIAMoDUICEAFSBXNkUmVxEh8KBHR5cGUY'
    'BCABKA4yCy5kZnUuRndUeXBlUgR0eXBlEhcKB3NkX3NpemUYBSABKA1SBnNkU2l6ZRIXCgdibF'
    '9zaXplGAYgASgNUgZibFNpemUSGQoIYXBwX3NpemUYByABKA1SB2FwcFNpemUSHQoEaGFzaBgI'
    'IAEoCzIJLmRmdS5IYXNoUgRoYXNoEiAKCGlzX2RlYnVnGAkgASgIOgVmYWxzZVIHaXNEZWJ1Zx'
    'I8Cg9ib290X3ZhbGlkYXRpb24YCiADKAsyEy5kZnUuQm9vdFZhbGlkYXRpb25SDmJvb3RWYWxp'
    'ZGF0aW9u');

@$core.Deprecated('Use resetCommandDescriptor instead')
const ResetCommand$json = {
  '1': 'ResetCommand',
  '2': [
    {'1': 'timeout', '3': 1, '4': 2, '5': 13, '10': 'timeout'},
  ],
};

/// Descriptor for `ResetCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resetCommandDescriptor = $convert.base64Decode(
    'CgxSZXNldENvbW1hbmQSGAoHdGltZW91dBgBIAIoDVIHdGltZW91dA==');

@$core.Deprecated('Use commandDescriptor instead')
const Command$json = {
  '1': 'Command',
  '2': [
    {'1': 'op_code', '3': 1, '4': 1, '5': 14, '6': '.dfu.OpCode', '10': 'opCode'},
    {'1': 'init', '3': 2, '4': 1, '5': 11, '6': '.dfu.InitCommand', '10': 'init'},
    {'1': 'reset', '3': 3, '4': 1, '5': 11, '6': '.dfu.ResetCommand', '10': 'reset'},
  ],
};

/// Descriptor for `Command`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commandDescriptor = $convert.base64Decode(
    'CgdDb21tYW5kEiQKB29wX2NvZGUYASABKA4yCy5kZnUuT3BDb2RlUgZvcENvZGUSJAoEaW5pdB'
    'gCIAEoCzIQLmRmdS5Jbml0Q29tbWFuZFIEaW5pdBInCgVyZXNldBgDIAEoCzIRLmRmdS5SZXNl'
    'dENvbW1hbmRSBXJlc2V0');

@$core.Deprecated('Use signedCommandDescriptor instead')
const SignedCommand$json = {
  '1': 'SignedCommand',
  '2': [
    {'1': 'command', '3': 1, '4': 2, '5': 11, '6': '.dfu.Command', '10': 'command'},
    {'1': 'signature_type', '3': 2, '4': 2, '5': 14, '6': '.dfu.SignatureType', '10': 'signatureType'},
    {'1': 'signature', '3': 3, '4': 2, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `SignedCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List signedCommandDescriptor = $convert.base64Decode(
    'Cg1TaWduZWRDb21tYW5kEiYKB2NvbW1hbmQYASACKAsyDC5kZnUuQ29tbWFuZFIHY29tbWFuZB'
    'I5Cg5zaWduYXR1cmVfdHlwZRgCIAIoDjISLmRmdS5TaWduYXR1cmVUeXBlUg1zaWduYXR1cmVU'
    'eXBlEhwKCXNpZ25hdHVyZRgDIAIoDFIJc2lnbmF0dXJl');

@$core.Deprecated('Use packetDescriptor instead')
const Packet$json = {
  '1': 'Packet',
  '2': [
    {'1': 'command', '3': 1, '4': 1, '5': 11, '6': '.dfu.Command', '10': 'command'},
    {'1': 'signed_command', '3': 2, '4': 1, '5': 11, '6': '.dfu.SignedCommand', '10': 'signedCommand'},
  ],
};

/// Descriptor for `Packet`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List packetDescriptor = $convert.base64Decode(
    'CgZQYWNrZXQSJgoHY29tbWFuZBgBIAEoCzIMLmRmdS5Db21tYW5kUgdjb21tYW5kEjkKDnNpZ2'
    '5lZF9jb21tYW5kGAIgASgLMhIuZGZ1LlNpZ25lZENvbW1hbmRSDXNpZ25lZENvbW1hbmQ=');

