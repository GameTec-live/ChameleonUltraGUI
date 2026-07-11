import 'dart:math' as math;

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

import 'package:chameleonultragui/gui/component/hex_viewer.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/hf_sniff.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

part 'hf_sniffing_controller.dart';
part 'hf_sniffing_view.dart';

class HfSniffingMenu extends StatefulWidget {
  const HfSniffingMenu({super.key});

  @override
  State<HfSniffingMenu> createState() => _HfSniffingMenuState();
}

class _HfSniffRecoveryState {
  final bool isLoading;
  final int? key;
  final String? method;
  final String? error;

  const _HfSniffRecoveryState({
    this.isLoading = false,
    this.key,
    this.method,
    this.error,
  });
}

class _HfSniffingMenuState extends State<HfSniffingMenu> {
  void updateSniffingState(VoidCallback update) => setState(update);

  static const int _kNoKey = 0xFFFFFFFFFFFFFFFF;

  final _formKey = GlobalKey<FormState>();
  final _timeoutController = TextEditingController(text: '5000');

  bool _isCapturing = false;
  bool _isRecoveringAll = false;
  bool? _capabilitySupported;
  String? _statusMessage;
  String? _errorMessage;

  HfSniffCapture? _capture;
  final Map<String, _HfSniffRecoveryState> _recoveryStates = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCapabilities();
    });
  }

  @override
  void dispose() {
    _timeoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final dialogWidth =
        math.min(MediaQuery.of(context).size.width * 0.92, 960.0).toDouble();
    final dialogHeight =
        math.min(MediaQuery.of(context).size.height * 0.84, 780.0).toDouble();

    return AlertDialog(
      title: Text(localizations.hf_sniffing),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: DefaultTabController(
          length: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCapabilityBanner(localizations),
              Form(
                key: _formKey,
                child: _buildHeaderControls(localizations),
              ),
              if (_statusMessage != null || _errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _buildStatusBlock(),
                ),
              const SizedBox(height: 12),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: localizations.hf_sniff_summary),
                  Tab(text: localizations.hf_sniff_frames),
                  Tab(text: localizations.hf_sniff_nonces),
                  Tab(text: localizations.hf_sniff_recovery),
                  Tab(text: localizations.hf_sniff_raw),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildSummaryTab(localizations),
                    _buildFramesTab(localizations),
                    _buildNoncesTab(localizations),
                    _buildRecoveryTab(localizations),
                    _buildRawTab(localizations),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.close),
        ),
      ],
    );
  }
}
