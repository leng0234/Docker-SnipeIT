import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';
import '../services/snipeit_service.dart';
import '../utils/app_constants.dart';
import '../widgets/common_widgets.dart';

/// Lets the user enter or update the Snipe-IT server URL/IP and API token
/// from inside the app, replacing the old build-time `.env` configuration.
///
/// Shown two ways:
/// - `isInitialSetup: true` — first run, no saved settings yet. There's no
///   back button; saving successfully takes the user straight into the
///   Scanner screen.
/// - `isInitialSetup: false` (default) — opened later from the Scanner
///   screen's settings icon to view/change the connection. Saving pops
///   back to whatever screen opened it.
class SettingsScreen extends StatefulWidget {
  final bool isInitialSetup;

  const SettingsScreen({super.key, this.isInitialSetup = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;

  bool _obscureToken = true;
  bool _isSaving = false;
  bool _isTesting = false;
  String? _error;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: AppSettingsService.baseUrl);
    _tokenController = TextEditingController(text: AppSettingsService.token);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  String? _validateUrl(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'กรุณากรอก URL หรือ IP ของ Snipe-IT';
    final uri = Uri.tryParse(value);
    final looksValid = uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!looksValid) {
      return 'กรุณาใส่ URL ให้ครบ เช่น http://192.168.1.10 '
          'หรือ https://snipeit.example.com';
    }
    return null;
  }

  String? _validateToken(String? v) {
    if ((v?.trim() ?? '').isEmpty) return 'กรุณากรอก API Token';
    return null;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _error = null;
      _successMessage = null;
    });

    // Tested against the entered values directly, without persisting them
    // first — a failed test should never clobber previously-saved, working
    // settings.
    final testService = SnipeITService.withCredentials(
      baseUrl: _urlController.text.trim(),
      token: _tokenController.text.trim(),
    );

    try {
      await testService.pingStatusLabels();
      if (!mounted) return;
      setState(() => _successMessage = 'เชื่อมต่อสำเร็จ ✓');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'เชื่อมต่อไม่สำเร็จ: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
      _successMessage = null;
    });

    try {
      await AppSettingsService.save(
        baseUrl: _urlController.text.trim(),
        token: _tokenController.text.trim(),
      );
      if (!mounted) return;

      if (widget.isInitialSetup) {
        Navigator.of(context).pushReplacementNamed('/scanner');
      } else {
        setState(() => _successMessage = 'บันทึกการตั้งค่าเรียบร้อย');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _error = 'บันทึกไม่สำเร็จ: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งค่าการเชื่อมต่อ Snipe-IT'),
        automaticallyImplyLeading: !widget.isInitialSetup,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.isInitialSetup)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppConstants.accentBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppConstants.accentBlue.withOpacity(0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppConstants.accentBlue, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'กรุณากรอก URL/IP และ API Token ของ Snipe-IT '
                        'ก่อนเริ่มใช้งาน',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppConstants.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),

            if (_error != null) ErrorBanner(message: _error!),

            if (_successMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppConstants.accentGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppConstants.accentGreen.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: AppConstants.accentGreen, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: const TextStyle(
                            color: AppConstants.accentGreen, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            const SectionHeader(title: 'การเชื่อมต่อ'),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Snipe-IT Server URL / IP',
                  hintText: 'เช่น http://192.168.1.10 หรือ https://snipeit.company.com',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                validator: _validateUrl,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextFormField(
                controller: _tokenController,
                decoration: InputDecoration(
                  labelText: 'API Token',
                  hintText: 'Personal Access Token จาก Snipe-IT',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureToken
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                  ),
                ),
                obscureText: _obscureToken,
                autocorrect: false,
                maxLines: 1,
                validator: _validateToken,
              ),
            ),

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                icon: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('ทดสอบการเชื่อมต่อ'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(
                    widget.isInitialSetup ? 'บันทึกและเริ่มใช้งาน' : 'บันทึก'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.accentGreen,
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}