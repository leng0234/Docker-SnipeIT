import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'signature_history_entry.dart';

/// Local, on-device replacement for embedding checkout/checkin history as
/// JSON inside Snipe-IT's `notes` field.
///
/// Each asset gets ONE JSON file on disk, keyed by assetId. Every save
/// OVERWRITES that file completely — there is no append, no growing log,
/// and nothing is ever sent to or stored in Snipe-IT's `action_logs`
/// table. Snipe-IT only ever sees a short human-readable note like
/// "Checkout signed by Somchai Rukchart".
///
/// Swap this for SQLite (sqflite) or Firestore later if you need
/// multi-device sync — the read/write contract (`load` / `save` /
/// `appendEntry`) stays the same either way.
class SignatureHistoryStore {
  const SignatureHistoryStore();

  Future<Directory> _historyDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/signature_history');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _fileFor(int assetId) async {
    final dir = await _historyDir();
    return File('${dir.path}/asset_$assetId.json');
  }

  /// All history entries ever recorded for this asset, oldest first.
  /// Returns an empty list if nothing has been saved yet (new asset, or
  /// storage was cleared).
  Future<List<SignatureHistoryEntry>> load(int assetId) async {
    final file = await _fileFor(assetId);
    if (!await file.exists()) return [];

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final e in decoded)
          if (e is Map) SignatureHistoryEntry.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      // Corrupt or unreadable file — treat as empty rather than crashing
      // the checkout/checkin flow.
      return [];
    }
  }

  /// Overwrites the asset's entire history file with [entries]. Use this
  /// after appending the newest entry in memory, so the file on disk
  /// always reflects the full, current list — never partial appends.
  Future<void> save(int assetId, List<SignatureHistoryEntry> entries) async {
    final file = await _fileFor(assetId);
    final raw = jsonEncode([for (final e in entries) e.toJson()]);
    await file.writeAsString(raw, flush: true);
  }

  /// Convenience: load, append one new entry, save. Returns the full
  /// updated list so the caller can pass it straight into the PDF builder.
  Future<List<SignatureHistoryEntry>> appendEntry(
    int assetId,
    SignatureHistoryEntry newEntry,
  ) async {
    final entries = await load(assetId);
    entries.add(newEntry);
    await save(assetId, entries);
    return entries;
  }

  /// Loads this asset's history already paired into printable rows (one
  /// row per cycleId, checkout matched with its checkin). Oldest cycle
  /// first — replaces the pairing logic that used to live inside
  /// `SnipeItFileApi.fetchSignatureHistory()`.
  Future<List<SignatureHistoryRow>> loadRows(int assetId) async {
    final entries = await load(assetId);

    final rows = <String, SignatureHistoryRow>{};
    final order = <String>[];
    for (final entry in entries) {
      final existing = rows[entry.cycleId];
      if (existing == null) {
        rows[entry.cycleId] = SignatureHistoryRow(
          cycleId: entry.cycleId,
          checkoutEntry: entry.isCheckout ? entry : null,
          checkinEntry: entry.isCheckout ? null : entry,
        );
        order.add(entry.cycleId);
      } else {
        rows[entry.cycleId] = SignatureHistoryRow(
          cycleId: entry.cycleId,
          checkoutEntry: entry.isCheckout ? entry : existing.checkoutEntry,
          checkinEntry: entry.isCheckout ? existing.checkinEntry : entry,
        );
      }
    }

    order.sort();
    return [for (final id in order) rows[id]!];
  }

  /// The cycleId of a checkout that hasn't been matched with a checkin yet
  /// (i.e. the asset is currently checked out to someone). Returns null if
  /// there's no open cycle — meaning a fresh checkout should mint a brand
  /// new cycleId rather than reuse one.
  Future<String?> findOpenCycleId(int assetId) async {
    final rows = await loadRows(assetId);
    for (final row in rows.reversed) {
      if (row.checkoutEntry != null && row.checkinEntry == null) {
        return row.cycleId;
      }
    }
    return null;
  }

  /// Optional: call this once a cycle-group is "closed off" and archived,
  /// if you still want a cap similar to `maxHistoryCycles` — e.g. to keep
  /// the local file from growing forever on assets with thousands of
  /// cycles. Unlike the old Snipe-IT approach, this is purely a local
  /// housekeeping choice now — it has zero effect on Snipe-IT's database.
  Future<void> clear(int assetId) async {
    final file = await _fileFor(assetId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}