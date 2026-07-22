import 'dart:typed_data';

import 'package:intl/intl.dart';

import 'package:dio/dio.dart';

import '../models/activity_model.dart';
import '../models/asset_model.dart';
import 'app_settings_service.dart';

class SnipeITException implements Exception {
  final String message;
  final int? statusCode;

  const SnipeITException(this.message, {this.statusCode});

  @override
  String toString() => 'SnipeITException($statusCode): $message';
}

class SnipeITService {
  late final Dio _dio;

  // Optional override, used only by the Settings screen's "Test
  // connection" button (see SnipeITService.withCredentials below). It lets
  // us try a URL/token pair *before* it's saved as the app's active
  // configuration. Everywhere else in the app these stay null and the
  // getters below fall back to the persisted AppSettingsService values —
  // that's what makes the server/token editable from inside the app
  // without a rebuild.
  final String? _overrideBaseUrl;
  final String? _overrideToken;

  String get _baseUrl => _overrideBaseUrl ?? AppSettingsService.baseUrl;
  String get _token => _overrideToken ?? AppSettingsService.token;

  SnipeITService()
      : _overrideBaseUrl = null,
        _overrideToken = null {
    _dio = _buildDio();
  }

  /// Constructs a service instance pointed at explicit, not-yet-saved
  /// credentials. Used by [SettingsScreen] to verify a URL/token pair
  /// works before the user commits it with "Save".
  SnipeITService.withCredentials({
    required String baseUrl,
    required String token,
  })  : _overrideBaseUrl = baseUrl,
        _overrideToken = token {
    _dio = _buildDio();
  }

  Dio _buildDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_baseUrl.isEmpty || _token.isEmpty) {
          handler.reject(
            DioException(
              requestOptions: options,
              error: const SnipeITException(
                'ยังไม่ได้ตั้งค่า Server URL / API Token ของ Snipe-IT '
                'กรุณาไปที่หน้าตั้งค่าก่อนใช้งาน',
              ),
              type: DioExceptionType.unknown,
            ),
          );
          return;
        }
        options.baseUrl = '$_baseUrl/api/v1/';
        options.headers['Authorization'] = 'Bearer $_token';
        handler.next(options);
      },
      onError: (error, handler) {
        final statusCode = error.response?.statusCode;
        final message = _extractErrorMessage(error.response?.data) ??
            error.message ??
            'Unknown error';
        handler.reject(
          DioException(
            requestOptions: error.requestOptions,
            error: SnipeITException(message, statusCode: statusCode),
            response: error.response,
            type: error.type,
          ),
        );
      },
    ));

    return dio;
  }

  // ── Connection test ────────────────────────────────────────────────────────

  /// Lightweight, side-effect-free call used by the Settings screen to
  /// confirm the entered URL/token actually reach a working Snipe-IT API
  /// before the user saves them.
  Future<void> pingStatusLabels() async {
    await _dio.get('statuslabels', queryParameters: {'limit': 1});
  }

  // ── Assets ─────────────────────────────────────────────────────────────────

  Future<AssetModel?> getAssetByTag(String assetTag) async {
    try {
      final response = await _dio.get('hardware/bytag/$assetTag');
      final data = response.data as Map<String, dynamic>;

      print('=== getAssetByTag response ===');
      print(data);

      if (data['status'] == 'error') return null;
      if (data['id'] == null) return null;

      return AssetModel.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      if (e.response?.data?['status'] == 'error') return null;
      rethrow;
    }
  }

  Future<AssetModel> getAssetById(int id) async {
    final response = await _dio.get('hardware/$id');
    return AssetModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AssetModel> createAsset({
    required int modelId,
    required int statusId,
    required String assetTag,
    String? serial,
    String? name,
    String? notes,
  }) async {
    final body = {
      'model_id': modelId,
      'status_id': statusId,
      'asset_tag': assetTag,
      if (serial != null) 'serial': serial,
      if (name != null) 'name': name,
      if (notes != null) 'notes': notes,
    };
    final response = await _dio.post('hardware', data: body);
    final payload = response.data as Map<String, dynamic>;
    _assertSuccess(payload);
    return AssetModel.fromJson(payload['payload'] as Map<String, dynamic>);
  }

  Future<AssetModel> updateAsset(int id, Map<String, dynamic> fields) async {
    final response = await _dio.patch('hardware/$id', data: fields);
    final payload = response.data as Map<String, dynamic>;
    _assertSuccess(payload);
    return AssetModel.fromJson(payload['payload'] as Map<String, dynamic>);
  }

  // ── Check-Out ──────────────────────────────────────────────────────────────

  Future<void> checkOutAsset({
    required int assetId,
    required int userId,
    String? checkoutAt,
    String? note,
  }) async {
    final body = {
      'checkout_to_type': 'user',
      'assigned_user': userId,
      'checkout_at': checkoutAt ??
          DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
      if (note != null) 'note': note,
    };
    final response =
        await _dio.post('hardware/$assetId/checkout', data: body);
    _assertSuccess(response.data as Map<String, dynamic>);
  }

  Future<void> checkOutAssetByName({
    required int assetId,
    required String assigneeName,
    String? note,
  }) async {
    final body = {
      'checkout_to_type': 'user',
      'assigned_user': 1,
      'checkout_at': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
      'note': note ?? 'Checked out to: $assigneeName',
    };
    final response =
        await _dio.post('hardware/$assetId/checkout', data: body);
    _assertSuccess(response.data as Map<String, dynamic>);
  }

  // ── Check-In ───────────────────────────────────────────────────────────────

  Future<void> checkInAsset({
    required int assetId,
    String? note,
  }) async {
    final body = {
      if (note != null) 'note': note,
    };
    final response =
        await _dio.post('hardware/$assetId/checkin', data: body);
    _assertSuccess(response.data as Map<String, dynamic>);
  }

  // ── Activity / History ─────────────────────────────────────────────────────

  Future<List<ActivityModel>> getAssetHistory(int assetId) async {
    final response = await _dio.get(
      'reports/activity',
      queryParameters: {
        'item_type': 'asset',
        'item_id': assetId,
        'limit': 50,
        'offset': 0,
        'sort': 'created_at',
        'order': 'desc',
      },
    );
    final rows = (response.data['rows'] as List<dynamic>? ?? []);
    return rows
        .map((e) => ActivityModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Users ──────────────────────────────────────────────────────────────────

  Future<List<AssetUser>> searchUsers(String query) async {
    final response = await _dio.get(
      'users',
      queryParameters: {'search': query, 'limit': 20},
    );
    final rows = response.data['rows'] as List<dynamic>? ?? [];
    return rows
        .map((e) => AssetUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch user details by ID (รวม department)
  Future<AssetUser?> getUserById(int userId) async {
    try {
      final response = await _dio.get('users/$userId');
      return AssetUser.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ── Manufacturers ──────────────────────────────────────────────────────────

  Future<List<AssetManufacturer>> getManufacturers() async {
    final response =
        await _dio.get('manufacturers', queryParameters: {'limit': 100});
    final rows = response.data['rows'] as List<dynamic>? ?? [];
    return rows
        .map((e) => AssetManufacturer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Models ─────────────────────────────────────────────────────────────────

  Future<List<AssetModel2>> getModels({int? manufacturerId}) async {
    final response = await _dio.get(
      'models',
      queryParameters: {
        'limit': 100,
        if (manufacturerId != null) 'manufacturer_id': manufacturerId,
      },
    );
    final rows = response.data['rows'] as List<dynamic>? ?? [];
    return rows
        .map((e) => AssetModel2.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Status Labels ──────────────────────────────────────────────────────────

  Future<List<AssetStatus>> getStatusLabels() async {
    final response =
        await _dio.get('statuslabels', queryParameters: {'limit': 50});
    final rows = response.data['rows'] as List<dynamic>? ?? [];
    return rows
        .map((e) => AssetStatus.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── File Uploads / Signatures ──────────────────────────────────────────────

  Future<bool> uploadSignature({
    required int assetId,
    required Uint8List pngBytes,
    String filename = 'signature.png',
  }) async {
    print('=== [Upload] START assetId=$assetId bytes=${pngBytes.length} file=$filename');

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        pngBytes,
        filename: filename,
        contentType: DioMediaType('image', 'png'),
      ),
    });

    // ใช้ Dio ใหม่แยกต่างหาก เพื่อหลีกเลี่ยง interceptor ที่ set Content-Type เป็น json
    final uploadDio = Dio(BaseOptions(
      baseUrl: '$_baseUrl/api/v1/',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/json',
        // ไม่ set Content-Type — Dio จะ set multipart/form-data + boundary เอง
      },
    ));

    final response = await uploadDio.post(
      'hardware/$assetId/uploads',
      data: formData,
    );

    print('=== [Upload] status=${response.statusCode} data=${response.data}');

    final ok = response.data?['status'] == 'success';
    print('=== [Upload] success=$ok');
    return ok;
  }

  // ── Upload Signature to User ───────────────────────────────────────────────

  /// Upload signature PNG ไปยัง Files ของ User (tab 📎 ใน Snipe-IT)
  /// Endpoint: POST /api/v1/users/{id}/uploads
  Future<bool> uploadSignatureToUser({
    required int userId,
    required Uint8List pngBytes,
    String filename = 'signature.png',
  }) async {
    print('=== [Upload User] START userId=$userId bytes=${pngBytes.length}');

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        pngBytes,
        filename: filename,
        contentType: DioMediaType('image', 'png'),
      ),
    });

    final uploadDio = Dio(BaseOptions(
      baseUrl: '$_baseUrl/api/v1/',
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/json',
      },
    ));

    final response = await uploadDio.post(
      'users/$userId/uploads',
      data: formData,
    );

    print('=== [Upload User] status=${response.statusCode} data=${response.data}');
    final ok = response.data?['status'] == 'success';
    print('=== [Upload User] success=$ok');
    return ok;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _assertSuccess(Map<String, dynamic> payload) {
    final status = payload['status'] as String?;
    if (status != 'success') {
      final messages = payload['messages'];
      final msg = messages is String
          ? messages
          : (messages is Map ? messages.values.join(', ') : 'Request failed');
      throw SnipeITException(msg);
    }
  }

  String? _extractErrorMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data['messages']?.toString() ?? data['message']?.toString();
    }
    return null;
  }
}