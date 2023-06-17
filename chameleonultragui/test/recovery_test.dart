import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Test darkside', () async {
    var darkside = DarksideDart(uid: 2374329723, items: []);
    darkside.items.add(DarksideItemDart(
        nt1: 913032415, ks1: 216745674933338888, par: 0, nr: 0, ar: 0));
    darkside.items.add(DarksideItemDart(
        nt1: 913032415, ks1: 1010230244403446283, par: 0, nr: 1, ar: 0));
    var keys = await recovery.darkside(darkside);
    expect(keys.contains(0xFFFFFFFFFFFF), true);
  });

  test('Test nested', () async {
    var nested = NestedDart(
        uid: 2374329723,
        distance: 613,
        nt0: 1999585272,
        nt0Enc: 3173333529,
        par0: 3,
        nt1: 128306861,
        nt1Enc: 2363514210,
        par1: 7);
    var keys = await recovery.nested(nested);
    expect(keys.contains(0xFFFFFFFFFFFF), true);
  });
}
