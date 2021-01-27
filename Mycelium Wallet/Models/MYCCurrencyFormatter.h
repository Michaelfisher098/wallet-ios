//
//  MYCCurrencyFormatter.h
//  Mycelium Wallet
//
//  Created by Pascal Edmond on 09/03/2015.
//  Copyright (c) 2015 Mycelium. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBitcoin/CoreBitcoin.h>

typedef NS_ENUM(NSInteger, MYCCurrencyFormatterStyle) {
    MYCCurrencyFormatterStyleNone = 0,
    MYCCurrencyFormatterStyleSymbol = 1,
    MYCCurrencyFormatterStyleCode = 2,
};

// App-specific currency formatter that can show both bitcoin denominations (BTC, bits) and
// fiat denominations (exchange rate converted and updated automatically).
// NSNumber returned and consumed is always BTCAmount.
@interface MYCCurrencyFormatter : NSNumberFormatter<NSCopying>

// Short currency code (BTC, bits, USD, EUR etc.)
// Setter is inactive.
@property(copy) NSString* currencyCode;

// Currency symbol (Ƀ, ƀ, $, € etc.)
// Setter is inactive.
@property(copy) NSString* currencySymbol;

// Complete name of this formatter including market/index name if needed.
// E.g. "BTC", "mBTC", "USD (Coindesk)", "EUR (Paymium)".
@property(nonatomic, readonly) NSString* name;

// Naked version of this formatter useful for parsing and re-formatting user input.
// Internal numbers are in satoshis (BTCAmount), displayed in selected currency, but without symbol.
@property(nonatomic, readonly) NSNumberFormatter* nakedFormatter;

// Does not perform any conversion, but simply re-formats the input.
@property(nonatomic, readonly) NSNumberFormatter* fiatReformatter;

@property(nonatomic, readonly) BOOL isBitcoinFormatter;
@property(nonatomic, readonly) BOOL isFiatFormatter;

@property(nonatomic, readonly) BTCNumberFormatter* btcFormatter;
@property(nonatomic, readonly) NSNumberFormatter* fiatFormatter;
@property(nonatomic, readonly) BTCCurrencyConverter* currencyConverter;

@property(nonatomic, readonly) NSString* placeholderText;

// Returns a formatter that shows one of BTC units (BTC, mBTC, bits, satoshis).
// Does not perform currency conversion.
- (id) initWithBTCFormatter:(BTCNumberFormatter*)btcFormatter;

// Returns a formatter that shows the fiat unit (USD, EUR, CNY).
// Does perform currency conversion fiat<->btc.
- (id) initWithCurrencyConverter:(BTCCurrencyConverter*)currencyConverter;

- (id) initWithDictionary:(NSDictionary*)dict;

- (NSDictionary*) dictionary;

// Formatted string from amount.
- (NSString *) stringFromAmount:(BTCAmount)amount;

// Parsed/converted amount from string.
- (BTCAmount) amountFromString:(NSString*)string;

@end
