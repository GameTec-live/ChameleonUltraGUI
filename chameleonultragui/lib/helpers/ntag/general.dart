import 'package:chameleonultragui/bridge/chameleon.dart';

bool isNTAG(TagType type) {
  return [TagType.ntag213, TagType.ntag215, TagType.ntag216].contains(type);
}
