/// Taiwan securities master models.
library;

enum TwMarket { twse, tpex, emerging }

extension TwMarketX on TwMarket {
  String get code {
    switch (this) {
      case TwMarket.twse:
        return 'TWSE';
      case TwMarket.tpex:
        return 'TPEX';
      case TwMarket.emerging:
        return 'EMERGING';
    }
  }

  String get labelZh {
    switch (this) {
      case TwMarket.twse:
        return '上市';
      case TwMarket.tpex:
        return '上櫃';
      case TwMarket.emerging:
        return '興櫃';
    }
  }

  String? get yahooSuffix {
    switch (this) {
      case TwMarket.twse:
        return 'TW';
      case TwMarket.tpex:
        return 'TWO';
      case TwMarket.emerging:
        return null;
    }
  }

  static TwMarket? tryParse(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'TWSE':
      case 'TSE':
      case '上市':
        return TwMarket.twse;
      case 'TPEX':
      case 'OTC':
      case '上櫃':
        return TwMarket.tpex;
      case 'EMERGING':
      case 'ESM':
      case '興櫃':
        return TwMarket.emerging;
      default:
        return null;
    }
  }
}

enum SecurityType { stock, etf, etn, preferred, tdr, warrant, other }

extension SecurityTypeX on SecurityType {
  String get code {
    switch (this) {
      case SecurityType.stock:
        return 'STOCK';
      case SecurityType.etf:
        return 'ETF';
      case SecurityType.etn:
        return 'ETN';
      case SecurityType.preferred:
        return 'PREFERRED';
      case SecurityType.tdr:
        return 'TDR';
      case SecurityType.warrant:
        return 'WARRANT';
      case SecurityType.other:
        return 'OTHER';
    }
  }

  String get labelZh {
    switch (this) {
      case SecurityType.stock:
        return '普通股';
      case SecurityType.etf:
        return 'ETF';
      case SecurityType.etn:
        return 'ETN';
      case SecurityType.preferred:
        return '特別股';
      case SecurityType.tdr:
        return 'TDR';
      case SecurityType.warrant:
        return '權證';
      case SecurityType.other:
        return '其他';
    }
  }

  static SecurityType tryParse(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'STOCK':
        return SecurityType.stock;
      case 'ETF':
        return SecurityType.etf;
      case 'ETN':
        return SecurityType.etn;
      case 'PREFERRED':
        return SecurityType.preferred;
      case 'TDR':
        return SecurityType.tdr;
      case 'WARRANT':
        return SecurityType.warrant;
      default:
        return SecurityType.other;
    }
  }
}

class SecurityRow {
  const SecurityRow({
    required this.id,
    required this.code,
    required this.name,
    required this.market,
    required this.securityType,
    this.fullName = '',
    this.englishName = '',
    this.industry = '',
    this.isin = '',
    this.currency = 'TWD',
    this.yahooSymbol = '',
    this.isActive = true,
    this.listingDate = '',
    this.delistingDate = '',
    this.source = '',
    this.lastUpdated = '',
    this.normalizedName = '',
  });

  final int id;
  final String code;
  final String name;
  final String fullName;
  final String englishName;
  final TwMarket market;
  final SecurityType securityType;
  final String industry;
  final String isin;
  final String currency;
  final String yahooSymbol;
  final bool isActive;
  final String listingDate;
  final String delistingDate;
  final String source;
  final String lastUpdated;
  final String normalizedName;

  String get displayLine {
    final base =
        '$code｜$name｜${market.labelZh}｜${securityType.labelZh}';
    return isActive ? base : '$base｜非交易中';
  }
}

class SyncMeta {
  const SyncMeta({
    required this.lastSuccessAt,
    required this.lastAttemptAt,
    required this.rowCount,
    required this.source,
    required this.lastError,
  });

  final String lastSuccessAt;
  final String lastAttemptAt;
  final int rowCount;
  final String source;
  final String lastError;
}

String normalizeSearchKey(String raw) {
  final sb = StringBuffer();
  for (final rune in raw.trim().runes) {
    var c = rune;
    if (c >= 0xFF01 && c <= 0xFF5E) {
      c = c - 0xFEE0;
    } else if (c == 0x3000) {
      c = 0x20;
    }
    if (c >= 0x41 && c <= 0x5A) {
      c += 32;
    }
    if (c == 0x20) continue;
    sb.writeCharCode(c);
  }
  return sb.toString();
}

String yahooSymbolFor(String code, TwMarket market) {
  final suf = market.yahooSuffix;
  if (suf == null) return '';
  return '$code.$suf';
}
