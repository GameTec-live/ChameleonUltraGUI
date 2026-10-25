// EMV scan tool (Phreakbyte fork addition). The device-side work is a
// single firmware call (HF14A_4_EMV_SCAN, 6005) -- already wired in the
// bridge as hf14a4EmvScan(), just never consumed by any GUI screen. This
// adds the screen: runs the scan, then the same BER-TLV walk + PAN/expiry/
// cardholder decode as chameleon_cli_unit.py's `emv scan` (and this fork's
// web terminal port of it). Result layout (summary cards + labeled panel)
// follows hf_sniffing.dart's house style rather than a raw text dump.
import 'dart:typed_data';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Map<int, List<Uint8List>> _tlvFind(Uint8List data, List<int> wantTags) {
  Map<int, List<Uint8List>> found = {for (var t in wantTags) t: []};
  int i = 0;
  while (i < data.length) {
    if (i + 1 >= data.length) break;
    int b0 = data[i];
    int tl = (b0 & 0x1F) == 0x1F ? 2 : 1;
    if (i + tl > data.length) break;
    int tag = 0;
    for (int k = 0; k < tl; k++) {
      tag = (tag << 8) | data[i + k];
    }
    i += tl;
    if (i >= data.length) break;
    bool constructed = (b0 & 0x20) != 0;
    int vlen;
    if ((data[i] & 0x80) != 0) {
      int nb = data[i] & 0x7F;
      i++;
      if (i + nb > data.length) break;
      vlen = 0;
      for (int k = 0; k < nb; k++) {
        vlen = (vlen << 8) | data[i + k];
      }
      i += nb;
    } else {
      vlen = data[i];
      i++;
    }
    bool truncated = i + vlen > data.length;
    Uint8List val = truncated ? data.sublist(i) : data.sublist(i, i + vlen);
    i = truncated ? data.length : i + vlen;
    if (wantTags.contains(tag) && !truncated) found[tag]!.add(val);
    if (constructed) {
      var sub = _tlvFind(val, wantTags);
      for (var t in wantTags) {
        found[t]!.addAll(sub[t]!);
      }
    }
  }
  return found;
}

bool _panLuhn(String panHex) {
  var digits = panHex
      .split('')
      .where((c) => RegExp(r'[0-9]').hasMatch(c))
      .map(int.parse)
      .toList()
      .reversed
      .toList();
  int total = 0;
  for (int i = 0; i < digits.length; i++) {
    int d = digits[i];
    if (i % 2 == 0) {
      total += d;
    } else {
      int d2 = d * 2;
      total += d2 > 9 ? d2 - 9 : d2;
    }
  }
  return total % 10 == 0;
}

String _ascii(Uint8List b) {
  return String.fromCharCodes(b).trim();
}

bool _swOk(Uint8List resp) {
  return resp.length >= 2 &&
      resp[resp.length - 2] == 0x90 &&
      resp[resp.length - 1] == 0x00;
}

String _swHex(Uint8List resp) {
  if (resp.length < 2) return "??";
  return resp
      .sublist(resp.length - 2)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

class _EmvResult {
  final String uid;
  final String atqaSak;
  final String ats;
  final List<String> appLabels;
  final String? pan;
  final bool? panLuhnOk;
  final String? expiry;
  final bool expiryFromTrack2;
  final String? cardholder;
  final List<String> trace;

  const _EmvResult({
    required this.uid,
    required this.atqaSak,
    required this.ats,
    required this.appLabels,
    required this.pan,
    required this.panLuhnOk,
    required this.expiry,
    required this.expiryFromTrack2,
    required this.cardholder,
    required this.trace,
  });
}

class EmvScanMenu extends StatefulWidget {
  const EmvScanMenu({super.key});

  @override
  State<EmvScanMenu> createState() => _EmvScanMenuState();
}

class _EmvScanMenuState extends State<EmvScanMenu> {
  bool _busy = false;
  String? _errorMessage;
  _EmvResult? _result;

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      var appState = context.read<ChameleonGUIState>();
      var localizations = AppLocalizations.of(context)!;
      var d = await appState.communicator!.hf14a4EmvScan();
      if (d.isEmpty) {
        setState(() {
          _result = null;
          _errorMessage = localizations.emv_scan_no_card;
        });
        return;
      }
      int off = 0;
      int uidLen = d[off++];
      var uid = d.sublist(off, off + uidLen);
      off += uidLen;
      var atqa = d.sublist(off, off + 2);
      off += 2;
      int sak = d[off++];
      int atsLen = d[off++];
      var ats = d.sublist(off, off + atsLen);
      off += atsLen;

      List<String> trace = [];

      int numApdus = d[off++];
      List<List<Uint8List>> pairs = [];
      for (int n = 0; n < numApdus; n++) {
        int cl = d[off++];
        var c = d.sublist(off, off + cl);
        off += cl;
        int rl = d[off] | (d[off + 1] << 8);
        off += 2;
        var r = d.sublist(off, off + rl);
        off += rl;
        pairs.add([c, r]);
      }
      if (pairs.isEmpty) {
        setState(() {
          _result = _EmvResult(
            uid: bytesToHex(uid),
            atqaSak:
                "${bytesToHex(atqa)} / 0x${sak.toRadixString(16).padLeft(2, '0')}",
            ats: bytesToHex(ats),
            appLabels: const [],
            pan: null,
            panLuhnOk: null,
            expiry: null,
            expiryFromTrack2: false,
            cardholder: null,
            trace: [localizations.emv_scan_no_apdu],
          );
        });
        return;
      }

      List<int> allRecordData = [];
      List<int> extraData = [];
      var ppseResp = pairs[0][1];
      if (_swOk(ppseResp)) {
        trace.add(localizations.emv_scan_trace_ppse(ppseResp.length));
        extraData.addAll(ppseResp.sublist(0, ppseResp.length - 2));
      } else {
        trace.add(localizations.emv_scan_trace_ppse_failed(_swHex(ppseResp)));
      }

      if (pairs.length >= 2) {
        var selResp = pairs[1][1];
        if (_swOk(selResp)) {
          trace.add(localizations.emv_scan_trace_select(selResp.length));
          extraData.addAll(selResp.sublist(0, selResp.length - 2));
        } else {
          trace.add(
              localizations.emv_scan_trace_select_failed(_swHex(selResp)));
        }
      }
      if (pairs.length >= 3) {
        var gpoResp = pairs[2][1];
        if (_swOk(gpoResp)) {
          trace.add(localizations.emv_scan_trace_gpo(gpoResp.length));
          extraData.addAll(gpoResp.sublist(0, gpoResp.length - 2));
        } else {
          trace.add(localizations.emv_scan_trace_gpo_failed(_swHex(gpoResp)));
        }
        for (var pair in pairs.sublist(3)) {
          var cb = pair[0], rb = pair[1];
          int sfiN = cb.length >= 4 ? (cb[3] >> 3) & 0x1F : 0;
          int recN = cb.length >= 3 ? cb[2] : 0;
          if (_swOk(rb)) {
            trace.add(
                localizations.emv_scan_trace_record(sfiN, recN, rb.length));
            allRecordData.addAll(rb.sublist(0, rb.length - 2));
          } else {
            trace.add(localizations.emv_scan_trace_record_failed(
                sfiN, recN, _swHex(rb)));
          }
        }
      }

      // searchData also carries the PPSE/SELECT/GPO reply bodies, not just
      // READ RECORD -- some cards return Track2 (tag 0x57) in the GPO reply
      // directly without repeating it in a record.
      var searchData = Uint8List.fromList([...allRecordData, ...extraData]);
      var tags = _tlvFind(searchData, [0x5A, 0x57, 0x5F24, 0x5F20, 0x5F28]);
      var appTags = _tlvFind(searchData, [0x9F12, 0x50]);

      List<String> appLabels = [];
      var seenLabels = <String>{};
      for (var v in appTags[0x50]!) {
        var lbl = _ascii(v);
        if (lbl.isNotEmpty && !seenLabels.contains(lbl)) {
          seenLabels.add(lbl);
          appLabels.add(lbl);
        }
      }

      String? panHex;
      for (var v in tags[0x57]!) {
        var t2 = bytesToHex(v).toUpperCase();
        var sep = t2.indexOf("D");
        if (sep > 0) {
          panHex = t2.substring(0, sep);
          break;
        }
      }
      if (panHex == null && tags[0x5A]!.isNotEmpty) {
        var raw = bytesToHex(tags[0x5A]![0]).toUpperCase();
        panHex = raw.endsWith("F") ? raw.replaceAll(RegExp(r'F+$'), '') : raw;
      }
      String? panDisplay;
      bool? panLuhnOk;
      if (panHex != null) {
        var buf = StringBuffer();
        for (int i = 0; i < panHex.length; i += 4) {
          if (i > 0) buf.write(" ");
          buf.write(panHex.substring(
              i, i + 4 > panHex.length ? panHex.length : i + 4));
        }
        panDisplay = buf.toString();
        panLuhnOk = _panLuhn(panHex);
      }

      String? expiry;
      bool expiryFromTrack2 = false;
      for (var v in tags[0x5F24]!) {
        if (v.length == 3) {
          var exp = bytesToHex(v).toUpperCase();
          expiry = "20${exp.substring(0, 2)}/${exp.substring(2, 4)}";
        }
      }
      if (expiry == null && panHex != null) {
        for (var v in tags[0x57]!) {
          var t2 = bytesToHex(v).toUpperCase();
          var sep = t2.indexOf("D");
          if (sep > 0 && t2.length >= sep + 5) {
            var yymm = t2.substring(sep + 1, sep + 5);
            if (RegExp(r'^\d+$').hasMatch(yymm)) {
              expiry = "20${yymm.substring(0, 2)}/${yymm.substring(2, 4)}";
              expiryFromTrack2 = true;
              break;
            }
          }
        }
      }

      String? cardholder;
      for (var v in tags[0x5F20]!) {
        if (v.isNotEmpty && v.every((b) => b >= 0x20 && b <= 0x7E)) {
          var name = _ascii(v);
          if (name.isNotEmpty) {
            cardholder = name;
            break;
          }
        }
      }

      setState(() {
        _result = _EmvResult(
          uid: bytesToHex(uid),
          atqaSak:
              "${bytesToHex(atqa)} / 0x${sak.toRadixString(16).padLeft(2, '0')}",
          ats: bytesToHex(ats),
          appLabels: appLabels,
          pan: panDisplay,
          panLuhnOk: panLuhnOk,
          expiry: expiry,
          expiryFromTrack2: expiryFromTrack2,
          cardholder: cardholder,
          trace: trace,
        );
      });
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildPanel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, String subtitle) {
    return SizedBox(
      width: 220,
      child: _buildPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBlock(String message) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var result = _result;
    return AlertDialog(
      title: Text(localizations.emv_scan_title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localizations.emv_scan_intro),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _busy ? null : _scan,
                child: Text(localizations.emv_scan_button),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                _buildErrorBlock(_errorMessage!),
              ],
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (result != null) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _summaryCard(
                      localizations.emv_scan_pan,
                      result.pan ?? localizations.emv_scan_not_found,
                      result.panLuhnOk == null
                          ? ""
                          : result.panLuhnOk!
                              ? "${localizations.emv_scan_luhn_label}: ${localizations.emv_scan_luhn_ok}"
                              : "${localizations.emv_scan_luhn_label}: ${localizations.emv_scan_luhn_fail}",
                    ),
                    _summaryCard(
                      localizations.emv_scan_expiry,
                      result.expiry ?? localizations.emv_scan_not_found,
                      result.expiryFromTrack2
                          ? localizations.emv_scan_expiry_track2_note
                          : "",
                    ),
                    _summaryCard(
                      localizations.emv_scan_app_label,
                      result.appLabels.isEmpty
                          ? localizations.emv_scan_not_found
                          : result.appLabels.first,
                      "",
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(localizations.emv_scan_summary,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      _infoRow(localizations.emv_scan_uid, result.uid),
                      _infoRow(
                          localizations.emv_scan_atqa_sak, result.atqaSak),
                      _infoRow(localizations.emv_scan_ats, result.ats),
                      if (result.appLabels.isNotEmpty)
                        _infoRow(localizations.emv_scan_app_label,
                            result.appLabels.join(', ')),
                      _infoRow(
                        localizations.emv_scan_pan,
                        result.pan == null
                            ? localizations.emv_scan_not_found
                            : "${result.pan} (${localizations.emv_scan_luhn_label}: ${result.panLuhnOk! ? localizations.emv_scan_luhn_ok : localizations.emv_scan_luhn_fail})",
                      ),
                      _infoRow(
                        localizations.emv_scan_expiry,
                        result.expiry == null
                            ? localizations.emv_scan_not_found
                            : result.expiryFromTrack2
                                ? "${result.expiry} (${localizations.emv_scan_expiry_track2_note})"
                                : result.expiry!,
                      ),
                      if (result.cardholder != null)
                        _infoRow(localizations.emv_scan_cardholder,
                            result.cardholder!),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(localizations.emv_scan_trace_title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      for (var line in result.trace)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: SelectableText(
                            line,
                            style: const TextStyle(
                                fontFamily: "monospace", fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.close),
        ),
      ],
    );
  }
}
