import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ISO14443-4 is exposed as a high-frequency card type', () {
    expect(numberToChameleonTag(3000), TagType.hf14a4);
    expect(chameleonTagToFrequency(TagType.hf14a4), TagFrequency.hf);
    expect(
      getTagTypesByFrequency(TagFrequency.hf),
      contains(TagType.hf14a4),
    );
    expect(
      getTagTypesByFrequency(TagFrequency.lf),
      isNot(contains(TagType.hf14a4)),
    );
  });
}
