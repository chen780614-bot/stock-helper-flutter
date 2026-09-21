import 'securities_models.dart';

/// Pure validation for one market's staged securities payload.
class SecuritiesValidator {
  const SecuritiesValidator({
    this.minRetentionRatio = 0.70,
    this.maxDuplicateRatio = 0.05,
  });

  /// Cancel market update if count < this fraction of last successful count.
  final double minRetentionRatio;

  /// Fail when duplicate codes exceed this fraction of staged rows.
  final double maxDuplicateRatio;

  static final RegExp codePattern = RegExp(r'^\d{4,6}[A-Z]{0,2}$');

  ValidationResult validate({
    required TwMarket market,
    required bool httpOk,
    required List<Map<String, Object?>> staged,
    required int lastSuccessfulCount,
  }) {
    if (!httpOk) {
      return ValidationResult.fail('HTTP 失敗，已保留舊資料');
    }
    if (staged.isEmpty) {
      return ValidationResult.fail('資料為空，已取消更新');
    }

    final cleaned = <Map<String, Object?>>[];
    final seen = <String>{};
    var dupes = 0;
    var missingFields = 0;
    var badFormat = 0;

    for (final row in staged) {
      final code = '${row['code'] ?? ''}'.trim().toUpperCase();
      final name = '${row['name'] ?? ''}'.trim();
      final mkt = '${row['market'] ?? ''}'.trim().toUpperCase();
      if (code.isEmpty || name.isEmpty || mkt.isEmpty) {
        missingFields++;
        continue;
      }
      if (!codePattern.hasMatch(code)) {
        badFormat++;
        continue;
      }
      if (mkt != market.code) {
        badFormat++;
        continue;
      }
      if (!seen.add(code)) {
        dupes++;
        continue; // keep first; count as duplicate
      }
      cleaned.add({
        ...row,
        'code': code,
        'name': name,
        'market': market.code,
      });
    }

    if (cleaned.isEmpty) {
      return ValidationResult.fail(
        '無有效資料（缺欄位 $missingFields、格式錯誤 $badFormat）',
      );
    }

    final dupRatio = staged.isEmpty ? 0.0 : dupes / staged.length;
    if (dupRatio > maxDuplicateRatio && dupes >= 3) {
      return ValidationResult.fail(
        '重複代號過多（$dupes / ${staged.length}），已取消更新',
      );
    }

    // Required-fields / format: if more than 30% of raw rows are junk, abort.
    final junk = missingFields + badFormat;
    if (junk / staged.length > 0.30) {
      return ValidationResult.fail(
        '缺欄位或格式錯誤過多（$junk / ${staged.length}），已取消更新',
      );
    }

    if (lastSuccessfulCount > 0) {
      final floor = (lastSuccessfulCount * minRetentionRatio).floor();
      if (cleaned.length < floor) {
        return ValidationResult.fail(
          '筆數異常下降（${cleaned.length} < 70% of $lastSuccessfulCount），已取消更新',
        );
      }
    }

    return ValidationResult.ok(cleaned);
  }
}

class ValidationResult {
  const ValidationResult._({
    required this.ok,
    required this.rows,
    required this.errorMessage,
  });

  factory ValidationResult.ok(List<Map<String, Object?>> rows) =>
      ValidationResult._(ok: true, rows: rows, errorMessage: '');

  factory ValidationResult.fail(String message) =>
      ValidationResult._(ok: false, rows: const [], errorMessage: message);

  final bool ok;
  final List<Map<String, Object?>> rows;
  final String errorMessage;
}
