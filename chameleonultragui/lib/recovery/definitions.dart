
class DarksideItemDart {
  int nt1;
  BigInt ks1;
  BigInt par;
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

class DarksideRequest {
  final int id;
  final DarksideDart darkside;

  const DarksideRequest(this.id, this.darkside);
}

class NestedRequest {
  final int id;
  final NestedDart nested;

  const NestedRequest(this.id, this.nested);
}

class Mfkey32Request {
  final int id;
  final Mfkey32Dart mfkey32;

  const Mfkey32Request(this.id, this.mfkey32);
}