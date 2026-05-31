import 'dart:typed_data';

class DarksideItemDart {
  int nt1;
  int ks1;
  int par;
  int nr;
  int ar;

  DarksideItemDart(
      {required this.nt1,
      required this.ks1,
      required this.par,
      required this.nr,
      required this.ar});
}

class DarksideDart {
  int uid;
  List<DarksideItemDart> items;

  DarksideDart({required this.uid, required this.items});
}

class NestedDart {
  int uid;
  int distance;
  int nt0;
  int nt0Enc;
  int par0;
  int nt1;
  int nt1Enc;
  int par1;

  NestedDart(
      {required this.uid,
      required this.distance,
      required this.nt0,
      required this.nt0Enc,
      required this.par0,
      required this.nt1,
      required this.nt1Enc,
      required this.par1});
}

class StaticNestedDart {
  int uid;
  int keyType;
  int nt0;
  int nt0Enc;
  int nt1;
  int nt1Enc;

  StaticNestedDart(
      {required this.uid,
      required this.keyType,
      required this.nt0,
      required this.nt0Enc,
      required this.nt1,
      required this.nt1Enc});
}

class StaticEncryptedNestedDart {
  int uid;
  int nt;
  int ntEnc;
  int ntParEnc;

  StaticEncryptedNestedDart(
      {required this.uid,
      required this.nt,
      required this.ntEnc,
      required this.ntParEnc});
}

class HardNestedDart {
  Uint8List nonces;

  HardNestedDart({required this.nonces});
}

class Mfkey32Dart {
  int uid;
  int nt0;
  int nt1;
  int nr0Enc;
  int ar0Enc;
  int nr1Enc;
  int ar1Enc;

  Mfkey32Dart(
      {required this.uid,
      required this.nt0,
      required this.nt1,
      required this.nr0Enc,
      required this.ar0Enc,
      required this.nr1Enc,
      required this.ar1Enc});
}

class Mfkey64Dart {
  int uid;
  int nt;
  int nrEnc;
  int arEnc;
  int atEnc;

  Mfkey64Dart(
      {required this.uid,
      required this.nt,
      required this.nrEnc,
      required this.arEnc,
      required this.atEnc});
}
