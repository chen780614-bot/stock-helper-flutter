import 'package:flutter_test/flutter_test.dart';
import 'package:stock_helper/services/names.dart';
import 'package:stock_helper/services/quotes.dart';
import 'package:stock_helper/services/storage.dart';
import 'package:stock_helper/services/ticker.dart';

void main() {
  test('bare OTC/KY code becomes .TWO when marked OTC', () {
    final names = NamesService(AppStorage());
    names.debugReplaceMemory({'6907': '雅特力-KY', '2330': '台積電'},
        otcCodes: {'6907'});
    expect(names.normalizeTickerForMarket('6907'), '6907.TWO');
    expect(names.normalizeTickerForMarket('6907.TW'), '6907.TWO');
    expect(names.normalizeTickerForMarket('2330'), '2330.TW');
    expect(names.resolveName('6907.TWO'), '雅特力-KY');
  });

  test('bare 興櫃 code becomes .TWO when marked ESM', () {
    final names = NamesService(AppStorage());
    names.debugReplaceMemory({
      '1260': '富味鄉',
      '2330': '台積電',
      '6907': '雅特力-KY',
    }, otcCodes: {
      '6907'
    }, esmCodes: {
      '1260'
    });
    expect(names.normalizeTickerForMarket('1260'), '1260.TWO');
    expect(names.normalizeTickerForMarket('1260.TW'), '1260.TWO');
    expect(names.marketSuffixForCode('1260'), 'TWO');
    expect(names.isEsmCode('1260'), isTrue);
    expect(names.isOtcCode('6907'), isTrue);
    expect(names.normalizeTickerForMarket('6907'), '6907.TWO');
    expect(names.normalizeTickerForMarket('2330'), '2330.TW');
    expect(names.resolveName('1260.TWO'), '富味鄉');
  });

  test('normalizeTicker still defaults bare digits to .TW', () {
    expect(normalizeTicker('2330'), '2330.TW');
  });

  test('Taipei quote window is weekdays 08:30–14:30 inclusive', () {
    // Helper: DateTime.utc so conversion +8h is timezone-independent.
    DateTime taipei(int y, int m, int d, int h, int min) =>
        DateTime.utc(y, m, d, h - 8, min);

    // Monday 2026-09-14
    expect(QuotesService.isTwRegularSession(taipei(2026, 9, 14, 8, 29)), isFalse);
    expect(QuotesService.isTwRegularSession(taipei(2026, 9, 14, 8, 30)), isTrue);
    expect(QuotesService.isTwRegularSession(taipei(2026, 9, 14, 9, 0)), isTrue);
    expect(QuotesService.isTwRegularSession(taipei(2026, 9, 14, 13, 30)), isTrue);
    expect(QuotesService.isTwRegularSession(taipei(2026, 9, 14, 14, 30)), isTrue);
    expect(QuotesService.isTwRegularSession(taipei(2026, 9, 14, 14, 31)), isFalse);
    // Weekend
    expect(QuotesService.isTwRegularSession(taipei(2026, 9, 12, 10, 0)), isFalse);
    expect(QuotesService.isTwRegularSession(taipei(2026, 9, 13, 10, 0)), isFalse);
  });
}
