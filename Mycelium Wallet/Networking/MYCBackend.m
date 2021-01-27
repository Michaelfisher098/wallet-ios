//
//  MYCConnection.m
//  Mycelium Wallet
//
//  Created by Oleg Andreev on 01.10.2014.
//  Copyright (c) 2014 Mycelium. All rights reserved.
//

#import "MYCBackend.h"
#import "MYCWallet.h"
#import "MYCMinerFeeEstimations.h"
#import "MYCExchangeRate.h"

@interface MYCBackend () <NSURLSessionDelegate>

// List of NSURL endpoints to which this client may connect.
@property(atomic) NSArray* endpointURLs;

// SHA-1 fingerprints of the SSL certificates to prevent MITM attacks.
// E.g. B3:42:65:33:40:F5:B9:1B:DA:A2:C8:7A:F5:4C:7C:5D:A9:63:C4:C3.
@property(atomic) NSArray* SSLFingerprints;

@property(atomic) BTCNetwork* btcNetwork;

// Version of the API to be used.
@property(atomic) NSNumber* version;

// URL session used to issue requests
@property(atomic) NSURLSession* session;

// Currently used endpoint URL.
@property(readonly) NSURL* currentEndpointURL;
@property(readonly) NSData* currentSSLFingerprint;
@property(atomic) NSInteger currentEndpointIndex;

@property(atomic) int pendingTasksCount;

- (NSMutableURLRequest*) requestWithName:(NSString*)name;

@end

@implementation MYCBackend

// Returns an instance configured for mainnet.
+ (instancetype) mainnetBackend
{
    static MYCBackend* instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MYCBackend alloc] init];
        instance.version = @(1);
        instance.btcNetwork = [BTCNetwork mainnet];
        instance.endpointURLs = @[
                                  [NSURL URLWithString:@"https://mws20.mycelium.com/wapi"],
                                  [NSURL URLWithString:@"https://mws60.mycelium.com/wapi"],
                                  [NSURL URLWithString:@"https://mws80.mycelium.com/wapi"],
                                  ];
        instance.currentEndpointIndex = 0;
        instance.SSLFingerprints = @[
                                     BTCDataFromHex([@"65:1B:FF:6B:8C:7F:C8:1C:8E:14:77:1E:74:9C:F7:E5:46:42:BA:E0" stringByReplacingOccurrencesOfString:@":" withString:@""]),
                                     BTCDataFromHex([@"47:F1:F1:21:F3:90:39:05:D7:21:B6:1B:EB:79:B1:40:44:A1:6F:46" stringByReplacingOccurrencesOfString:@":" withString:@""]),
                                     BTCDataFromHex([@"9E:90:62:24:F7:71:83:FB:B6:B1:D6:4D:C2:78:4A:5D:29:3F:B5:BB" stringByReplacingOccurrencesOfString:@":" withString:@""]),
                                     BTCDataFromHex([@"EB:4C:27:A5:A3:8B:DF:E1:34:60:0A:97:57:3F:FA:FF:43:E0:EA:67" stringByReplacingOccurrencesOfString:@":" withString:@""])
                                     ];
    });
    return instance;
}


// Returns an instance configured for testnet.
+ (instancetype) testnetBackend
{
    static MYCBackend* instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MYCBackend alloc] init];
        instance.version = @(1);
        instance.btcNetwork = [BTCNetwork testnet];
        instance.endpointURLs = @[
                                [NSURL URLWithString:@"https://mws30.mycelium.com/wapitestnet"]
                                ];
        instance.currentEndpointIndex = 0;
        instance.SSLFingerprints = @[
                                     BTCDataFromHex([@"ed:c2:82:16:65:8c:4e:e1:c7:f6:a2:2b:15:ec:30:f9:cd:48:f8:db" stringByReplacingOccurrencesOfString:@":" withString:@""])
                                     ];
    });
    return instance;
}

- (id) init
{
    if (self = [super init])
    {
        NSURLSessionConfiguration* config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = 10.0;
        config.timeoutIntervalForResource = 120.0;
        config.HTTPMaximumConnectionsPerHost = 1;
        config.protocolClasses = @[];
        self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    }
    return self;
}

// Returns YES if currently loading something.
- (BOOL) isActive
{
    //MYCLog(@"isActive: tasks = %@", @(self.pendingTasksCount));
    return self.pendingTasksCount > 0;
}

- (NSURL *)currentEndpointURL {
    return self.endpointURLs[self.currentEndpointIndex];
}

- (NSData *)currentSSLFingerprint {
    return self.SSLFingerprints[self.currentEndpointIndex];
}

- (void) loadExchangeRatesForCurrencyCode:(NSString*)currencyCode
                               completion:(void(^)(NSArray * exchangeRates, NSError* error))completion
{
    MYC_ASSERT_MAIN_THREAD;
    NSParameterAssert(currencyCode);

//    curl  -k -X POST -H "Content-Type: application/json" -d '{"version":1,"currency":"USD"}' https://144.76.165.115/wapitestnet/wapi/queryExchangeRates
//    {
//        "errorCode": 0,
//        "r": {
//            "currency": "USD",
//            "exchangeRates": [{
//                "name": "Bitstamp",
//                "time": 1413196507900,
//                "price": 378.73,
//                "currency": "USD"
//            },
//            {
//                "name": "BTC-e",
//                "time": 1413196472250,
//                "price": 370.882,
//                "currency": "USD"
//            },

    [self makeJSONRequestWithName:@"queryExchangeRates"
                  payload:@{ @"version": self.version,
                             @"currency": currencyCode ?: @"USD" }
                 template:@{@"currency": @"USD",
                            @"exchangeRates": @[@{
                                @"name":     @"Bitstamp",
                                @"time":     @1413196507900,
                                @"price":    @378.12,
                                @"currency": @"USD"
                            }]}
               completion:^(NSDictionary* result, NSString* curlCommand, NSError* error){

                   if (!result)
                   {
                       if (completion) completion(nil, error);
                       return;
                   }

                   NSArray * exchangeRateDicts = result[@"exchangeRates"];
                   if (exchangeRateDicts.count < 1)
                   {
                       if (completion) completion(nil, [self dataError:@"No exchange rates returned"]);
                       return;
                   }

                   NSMutableArray * exchangeRates = [NSMutableArray arrayWithCapacity:exchangeRateDicts.count];
                   for (NSDictionary* dict in exchangeRateDicts) {
                       [exchangeRates addObject:[MYCExchangeRate exchangeRateFromDictionary:dict]];
                   }

                   if (completion) completion(exchangeRates, nil);
               }];
}


// Fetches unspent outputs (BTCTransactionOutput) for given addresses (BTCAddress instances).
- (void) loadUnspentOutputsForAddresses:(NSArray*)addresses completion:(void(^)(NSArray* outputs, NSInteger height, NSError* error))completion
{
    MYC_ASSERT_MAIN_THREAD;
    NSParameterAssert(addresses);

    if (addresses.count == 0)
    {
        if (completion) completion(@[], 0, nil);
        return;
    }

    //
    //curl  -k -X POST -H "Content-Type: application/json" -d '{"version":1,"addresses":["miWYetn5RRjatKmHgNm6VGYT2jivUjZv5y"]}' https://144.76.165.115/wapitestnet/wapi/queryUnspentOutputs
    //
    //{
    //    "errorCode": 0,
    //    "r": {
    //        "height": 300825,
    //        "unspent": [{
    //            "outPoint": "2c2cea628728ed8c6345a0d8bc172dd301104707ab1057a0309984b5a212dd98:0",
    //            "height": 300766,
    //            "value": 100000000,
    //            "script": "dqkUINSkoZDqj3qXkFlUtWwcl398DkaIrA==",
    //            "isCoinBase": false
    //        },
    //        {
    //            "outPoint": "5630d46ba9be82a4061931be11b7ba3126068aad93873ef0f742d8f419961e63:1",
    //            "height": 300825,
    //            "value": 90000000,
    //            "script": "dqkUINSkoZDqj3qXkFlUtWwcl398DkaIrA==",
    //            "isCoinBase": false
    //        },
    //    }
    //}

    [self makeJSONRequestWithName:@"queryUnspentOutputs"
                  payload:@{// @"version": self.version,
                             @"addresses": [addresses valueForKeyPath:@"publicAddress.base58String"] }
                 template:@{
                            @"height": @300825,
                            @"unspent": @[@{
                                              @"outPoint":   @"2c2cea628728ed8c6345a0d8bc172dd301104707ab1057a0309984b5a212dd98:0",
                                              @"height":     @300766,
                                              @"value":      @100000000,
                                              @"script":     @"dqkUINSkoZDqj3qXkFlUtWwcl398DkaIrA==",
                                              @"isCoinBase": @NO }]}
               completion:^(NSDictionary* result, NSString* curlCommand, NSError* error){

                   if (!result)
                   {
                       if (completion) completion(nil, 0, error);
                       return;
                   }

                   // Get the current block height.
                   NSInteger height = [result[@"height"] integerValue];

                   NSMutableArray* unspentOutputs = [NSMutableArray array];

                   for (NSDictionary* dict in result[@"unspent"])
                   {
                       // "outPoint": "92082fa94ae0e5b97b8f1b5a15c5f3f55648394f576755235bb2c2389d906f1d:0",
                       // "height": 300766,
                       // "value": 100000000,
                       // "script": "dqkUINSkoZDqj3qXkFlUtWwcl398DkaIrA==",
                       // "isCoinBase": false

                       NSArray* txHashAndIndex = [dict[@"outPoint"] componentsSeparatedByString:@":"];

                       if (txHashAndIndex.count != 2)
                       {
                           if (completion) completion(nil, 0, [self formatError:@"Malformed result: 'outPoint' is a string with a single ':' separator"]);
                           return;
                       }

                       NSData* scriptData = [[NSData alloc] initWithBase64EncodedString:dict[@"script"] options:0];

                       if (!scriptData)
                       {
                           if (completion) completion(nil, 0, [self formatError:@"Malformed result: 'script' is not a valid Base64 string"]);
                           return;
                       }

                       // tx hash is sent reversed, but we store the true hash
                       NSData* txhash = BTCReversedData(BTCDataFromHex(txHashAndIndex[0]));

                       if (!txhash || txhash.length != 32)
                       {
                           if (completion) completion(nil, 0, [self formatError:@"Malformed result: 'outPoint' does not contain a correct reversed hex 256-bit transaction hash."]);
                           return;
                       }

                       BTCTransactionOutput* txout = [[BTCTransactionOutput alloc] init];

                       txout.value = BTCAmountFromDecimalNumber(dict[@"value"]);
                       txout.script = [[BTCScript alloc] initWithData:scriptData];

                       txout.index = (uint32_t)[((NSString*)txHashAndIndex[1]) integerValue];
                       txout.transactionHash = txhash;
                       txout.blockHeight = [dict[@"height"] integerValue];

                       [unspentOutputs addObject:txout];
                   }

                   if (completion) completion(unspentOutputs, height, nil);
               }];
}


// Fetches the latest transaction ids for given addresses (BTCAddress instances).
// Results include both transactions spending and receiving to the given addresses.
- (void) loadTransactionIDsForAddresses:(NSArray*)addresses limit:(NSInteger)limit completion:(void(^)(NSArray* txids, NSInteger height, NSError* error))completion
{
    MYC_ASSERT_MAIN_THREAD;
    NSParameterAssert(addresses);

    if (addresses.count == 0)
    {
        if (completion) completion(@[], 0, nil);
        return;
    }

    // curl -k -X POST -H "Content-Type: application/json" -d '{"version":1,"addresses":["miWYetn5RRjatKmHgNm6VGYT2jivUjZv5y"],"limit":1000}' https://144.76.165.115/wapitestnet/wapi/queryTransactionInventory
    // {"errorCode":0,
    //     "r":{
    //         "height":301943,
    //         "txIds":[
    //                  "9857dc366848ffb8d4616631d6fa1bcb139ffd11834feb6e3520f9febd17ac79",
    //                  "3f7a173870c3c3b2914fc3228770863ae0aba7f3960774fb6ced88b915610262",
    //                  "3635eee25fb237c57090fda60d3a2f33707201a941d281bc663e540ef1eb1f0b",
    //                  "5630d46ba9be82a4061931be11b7ba3126068aad93873ef0f742d8f419961e63",
    //                  "6a73582d58fcbf6345ddb5d59daaf74776303e425237a7e5d9e683495187dc85",
    //                  "92082fa94ae0e5b97b8f1b5a15c5f3f55648394f576755235bb2c2389d906f1d",
    //                  "2c2cea628728ed8c6345a0d8bc172dd301104707ab1057a0309984b5a212dd98"
    //          ]
    //      }
    //  }

    [self makeJSONRequestWithName:@"queryTransactionInventory"
                  payload:@{// @"version": self.version,
                             @"addresses": [addresses valueForKeyPath:@"publicAddress.base58String"],
                             @"limit": @(limit)}
                 template:@{@"height": @301943,
                            @"txIds":@[
                               @"9857dc366848ffb8d4616631d6fa1bcb139ffd11834feb6e3520f9febd17ac79",
                               @"3f7a173870c3c3b2914fc3228770863ae0aba7f3960774fb6ced88b915610262",
                               @"3635eee25fb237c57090fda60d3a2f33707201a941d281bc663e540ef1eb1f0b",
                            ]}
               completion:^(NSDictionary* result, NSString* curlCommand, NSError* error){

                   if (!result)
                   {
                       if (completion) completion(nil, 0, error);
                       return;
                   }

                   // Get the current block height.
                   NSInteger height = [result[@"height"] integerValue];

                   NSArray* txids = result[@"txIds"] ?: @[];

                   if (completion) completion(txids, height, nil);
               }];
}

- (void) loadTransactionsForAddresses:(NSArray*)addresses limit:(NSInteger)limit completion:(void(^)(NSArray* txs, NSInteger height, NSError* error))completion
{
    MYC_ASSERT_MAIN_THREAD;
    NSParameterAssert(addresses);

    if (addresses.count == 0)
    {
        if (completion) completion(@[], 0, nil);
        return;
    }

    [self loadTransactionIDsForAddresses:addresses limit:limit completion:^(NSArray *txids, NSInteger height, NSError *error) {

        if (!txids)
        {
            if (completion) completion(nil, 0, error);
            return;
        }

        // Will return early if input is empty list.
        [self loadTransactions:txids completion:^(NSArray *transactions, NSError *error) {

            if (transactions)
            {
                if (transactions.count != txids.count)
                {
                    MYCError(@"MYCBackend: number of received transactions != number of requested txids! %d != %d (but we continue with what we have)",
                             (int)transactions.count, (int)txids.count);
                }
            }
            if (completion) completion(transactions, height, error);

        }];
    }];
}


// Checks status of the given transaction IDs and returns an array of dictionaries.
// Each dictionary is of this format: {@"txid": @"...", @"found": @YES/@NO, @"height": @123, @"date": NSDate }.
// * `txid` key corresponds to the transaction ID in the array of `txids`.
// * `found` contains YES if transaction is found and NO otherwise.
// * `height` contains -1 for unconfirmed transaction and block height at which it is included.
// * `date` contains time when transaction is recorded or noticed.
// In case of error, `dicts` is nil and `error` contains NSError object.
- (void) loadStatusForTransactions:(NSArray*)txids completion:(void(^)(NSArray* dicts, NSError* error))completion
{
    MYC_ASSERT_MAIN_THREAD;
    NSParameterAssert(txids);

    if (txids.count == 0)
    {
        if (completion) completion(@[], nil);
        return;
    }

    // curl   -k -X POST -H "Content-Type: application/json" -d '{"txIds":["1513b9b160ef6b20bbb06b7bb6e7364e58e27e1df53f8f7e12e67f17d46ad198"]}' https://144.76.165.115/wapitestnet/wapi/checkTransactions
    // {"errorCode":0,
    //   "r":{
    //       "transactions":[
    //           {"txid":"1513b9b160ef6b20bbb06b7bb6e7364e58e27e1df53f8f7e12e67f17d46ad198",
    //            "found":true,
    //            "height":280489,
    //            "time":1410965947}
    //        ]
    //    }}

    [self makeJSONRequestWithName:@"checkTransactions"
                  payload:@{// @"version": self.version,
                             @"txIds": txids }
                 template:@{
                            @"transactions":@[
                                @{@"txid":   @"1513b9b160ef6b20bbb06b7bb6e7364e58e27e1df53f8f7e12e67f17d46ad198",
                                  @"found":  @YES,
                                  @"height": @280489,
                                  @"time":   @1410965947}
                            ]}
               completion:^(NSDictionary* result, NSString* curlCommand, NSError* error){

                   if (!result)
                   {
                       if (completion) completion(nil, error);
                       return;
                   }

                   NSMutableArray* resultDicts = [NSMutableArray array];

                   for (NSDictionary* dict in result[@"transactions"])
                   {
                       NSTimeInterval ts = [dict[@"time"] doubleValue];
                       NSDate* date = [NSDate dateWithTimeIntervalSince1970:ts];
                       [resultDicts addObject:@{
                                          @"txid":   dict[@"txid"] ?: @"",
                                          @"found":  dict[@"found"] ?: @NO,
                                          @"height": dict[@"height"] ?: @(-1),
                                          @"date":   date,
                                          @"time":   date, // just in case
                                          }];
                   }
                   
                   if (completion) completion(resultDicts, nil);
               }];
}



// Loads actual transactions (BTCTransaction instances) for given txids.
// Each transaction contains blockHeight property (-1 = unconfirmed) and blockDate property.
//
// See WapiResponse<GetTransactionsResponse> getTransactions(GetTransactionsRequest request);
- (void) loadTransactions:(NSArray*)txids completion:(void(^)(NSArray* dicts, NSError* error))completion
{
    MYC_ASSERT_MAIN_THREAD;
    NSParameterAssert(txids);

    if (txids.count == 0)
    {
        if (completion) completion(@[], nil);
        return;
    }

    // curl -k -X POST -H "Content-Type: application/json" -d '{"version":1,"txIds":["1513b9b160ef6b20bbb06b7bb6e7364e58e27e1df53f8f7e12e67f17d46ad198"]}' https://144.76.165.115/wapitestnet/wapi/getTransactions
    // {"errorCode":0,
    //  "r":{
    //       "transactions":[{
    //            "txid":"1513b9b160ef6b20bbb06b7bb6e7364e58e27e1df53f8f7e12e67f17d46ad198",
    //            "height":280489,
    //            "time":1410965947,
    //            "binary":"AQAAAAHqHGsQSIun5hjDDWm7iFMwm85xNLt+HBfI3LS3uQHnSQEAAABrSDBFAiEA6rlGk4wgIL3TvC2YHK4XiBW2vPYg82iCgnQi+YOUwqACIBpzVk756/07SRORT50iRZvEGUIn3Lh3bhaRE1aUMgZZASECDFl9wEYDCvB1cJY6MbsakfKQ9tbQhn0eH9C//RI2iE//////ApHwGgAAAAAAGXapFIzWtPXZR7lk8RtvE0FDMHaLtsLCiKyghgEAAAAAABl2qRSuzci59wapXUEzwDzqKV9nIaqwz4isAAAAAA=="
    //           }]
    // }}

    [self makeJSONRequestWithName:@"getTransactions"
                  payload:@{// @"version": self.version,
                             @"txIds": txids }
                 template:@{
                            @"transactions":@[
                                    @{@"txid":   @"1513b9b160ef6b20bbb06b7bb6e7364e58e27e1df53f8f7e12e67f17d46ad198",
                                      @"height": @280489,
                                      @"time":   @1410965947,
                                      @"binary": @"base64string"}
                                    ]}
               completion:^(NSDictionary* result, NSString* curlCommand, NSError* error){

                   if (!result)
                   {
                       if (completion) completion(nil, error);
                       return;
                   }

                   NSMutableArray* txs = [NSMutableArray array];

                   BOOL parseFailure = NO;
                   for (NSDictionary* dict in result[@"transactions"])
                   {
                       NSString* txid = dict[@"txid"];
                       NSInteger blockHeight = [dict[@"height"] intValue];
                       NSTimeInterval ts = [dict[@"time"] doubleValue];
                       NSDate* blockDate = ts > 0.0 ? [NSDate dateWithTimeIntervalSince1970:ts] : nil;

                       NSData* txdata = [[NSData alloc] initWithBase64EncodedString:dict[@"binary"] options:0];

                       if (!txdata)
                       {
                           MYCLog(@"MYCBackend loadTransactions: malformed Base64 encoding for tx data: %@", dict);
                           parseFailure = YES;
                       }
                       else
                       {
                           BTCTransaction* tx = [[BTCTransaction alloc] initWithData:txdata];

                           tx.blockHeight = blockHeight;
                           tx.blockDate = blockDate;

                           if (!tx)
                           {
                               MYCLog(@"MYCBackend loadTransactions: malformed transaction data (can't make BTCTransaction): %@", dict);
                               parseFailure = YES;
                           }
                           else if (![tx.transactionID isEqualToString:txid])
                           {
                               MYCLog(@"MYCBackend loadTransactions: transaction data does not match declared txid: %@", dict);
                               parseFailure = YES;
                           }
                           else if (![txids containsObject:tx.transactionID])
                           {
                               MYCLog(@"MYCBackend loadTransactions: transaction ID is not contained in the requested txids: %@ (txids: %@)", dict, txids);
                               parseFailure = YES;
                           }
                           else
                           {
                               [txs addObject:tx];
                           }
                       }
                   }

                   if (parseFailure && txs.count == 0)
                   {
                       if (completion) completion(nil, [self formatError:[NSString stringWithFormat:NSLocalizedString(@"Cannot parse any transaction returned for txids %@", @""), txids]]);
                       return;
                   }

                   if (completion) completion(txs, nil);
               }];
}



// Broadcasts the transaction and returns appropriate status.
// See comments on MYCBackendBroadcastStatus above.
// Result: {"errorCode":0,"r":{"success":true,"txid":"1513b9b160ef6b20bbb06b7bb6e7364e58e27e1df53f8f7e12e67f17d46ad198"}}
// Result: {"errorCode":99}
// WapiResponse<BroadcastTransactionResponse> broadcastTransaction(BroadcastTransactionRequest request);
- (void) broadcastTransaction:(BTCTransaction*)tx completion:(void(^)(MYCBroadcastStatus status, NSError* error))completion
{
    MYC_ASSERT_MAIN_THREAD;
    NSParameterAssert(tx);

    // curl  -k -X POST -H "Content-Type: application/json" -d '{"version":1,"rawTransaction":"AQAAAAHqHGsQSIun5hjDDWm7iFMwm85xNLt+HBfI3LS3uQHnSQEAAABrSDBFAiEA6rlGk4wgIL3TvC2YHK4XiBW2vPYg82iCgnQi+YOUwqACIBpzVk756/07SRORT50iRZvEGUIn3Lh3bhaRE1aUMgZZASECDFl9wEYDCvB1cJY6MbsakfKQ9tbQhn0eH9C//RI2iE//////ApHwGgAAAAAAGXapFIzWtPXZR7lk8RtvE0FDMHaLtsLCiKyghgEAAAAAABl2qRSuzci59wapXUEzwDzqKV9nIaqwz4isAAAAAA=="}' https://144.76.165.115/wapitestnet/wapi/broadcastTransaction
    // Result: {"errorCode":0,"r":{"success":true,"txid":"1513b9b160ef6b20bbb06b7bb6e7364e58e27e1df53f8f7e12e67f17d46ad198"}}
    // Result: {"errorCode":99}

    NSData* txdata = tx.data;

    NSAssert(txdata, @"sanity check");

    NSString* base64tx = [txdata base64EncodedStringWithOptions:0];

    NSAssert(base64tx, @"sanity check");

    if (!base64tx)
    {
        if (completion) completion(MYCBroadcastStatusBadTransaction, nil);
        return;
    }

    [self makeJSONRequestWithName:@"broadcastTransaction"
                  payload:@{// @"version": self.version,
                             @"rawTransaction": base64tx }
                 template:@{
                            @"success":@YES,
                            @"txid": @"1513b9b160ef6b20bbb06b7bb6e7364e58e27e1df53f8f7e12e67f17d46ad198"
                            }
               completion:^(NSDictionary* result, NSString* curlCommand, NSError* error){

                   if (!result)
                   {
                       // Special case: bad transaction yields 99 error.
                       if ([error.domain isEqual:MYCErrorDomain] && error.code == 99)
                       {
                           if (completion) completion(MYCBroadcastStatusBadTransaction, error);
                           return;
                       }
                       if (completion) completion(MYCBroadcastStatusNetworkFailure, error);
                       return;
                   }

                   BOOL success = [result[@"success"] boolValue];

                   if (!success)
                   {
                       // Unknown failure
                       if (completion) completion(MYCBroadcastStatusNetworkFailure, error);
                       return;
                   }

                   if (completion) completion(MYCBroadcastStatusSuccess, error);
               }];
}

- (void) loadMinerFeeEstimatationsWithCompletion:(void (^)(MYCMinerFeeEstimations *, NSError *))completion
{
    MYC_ASSERT_MAIN_THREAD;
    
    //    curl  -k -X POST -H "Content-Type: application/json" -d '{"version":1,"currency":"USD"}' https://144.76.165.115/wapitestnet/wapi/getMinerFeeEstimations
    //    {
    //        "errorCode": 0,
    //        "r": {
    //            "feeEstimation": {
    //                "feeForNBlocks": {
    //                    "1": "58639",
    //                    "2": "39877",
    //                    "3": "29190",
    //                    "4": "23784",
    //                    "5": "21452",
    //                    "10": "19678",
    //                    "15": "17945",
    //                    "20": "16032"
    //                },
    //                "validFor": 1456935054018
    //            }
    //        }
    
    [self makeJSONRequestWithName:@"getMinerFeeEstimations"
                          payload:@{}
                         template:@{@"feeEstimation": @{
                                            @"feeForNBlocks": @{
                                                    @"1": @"58639",
                                                    @"2": @"39877",
                                                    @"3": @"29190",
                                                    @"4": @"23784",
                                                    @"5": @"21452",
                                                    @"10": @"19678",
                                                    @"15": @"17945",
                                                    @"20": @"16032"
                                            },
                                            @"validFor": @1456935054018
                                    }}
                       completion:^(NSDictionary* result, NSString* curlCommand, NSError* error){
                           
                           if (!result)
                           {
                               if (completion) completion(nil, error);
                               return;
                           }
                           
                           if (![result[@"feeEstimation"] isKindOfClass:[NSDictionary class]] || ![result[@"feeEstimation"][@"feeForNBlocks"] isKindOfClass:[NSDictionary class]])
                           {
                               if (completion) completion(nil, [self dataError:NSLocalizedString(@"No miner fee estimates returned", nil)]);
                               return;
                           }
                           
                           NSDictionary * estimations = result[@"feeEstimation"][@"feeForNBlocks"];
                           
                           if (completion) completion([MYCMinerFeeEstimations estimationsWithDictionary:estimations], nil);
                       }];
}

#pragma mark - Utils


- (void) makeJSONRequestWithName:(NSString*)name payload:(NSDictionary*)payload template:(id)template completion:(void(^)(NSDictionary* result, NSString* curlCommand, NSError* error))completion
{
    NSMutableURLRequest* req = [self requestWithName:name];
    [self makeJSONRequest:req payload:payload template:template completion:completion];
}


- (void) makeJSONRequest:(NSMutableURLRequest*)req payload:(NSDictionary*)payload template:(id)template completion:(void(^)(NSDictionary* result, NSString* curlCommand, NSError* error))completion
{
    MYC_ASSERT_MAIN_THREAD;
    //MYCLog(@">>> INCREASING COUNT: %@", name);
    self.pendingTasksCount++;

    // Do json encoding on background thread.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{

        NSString* curlCommand = nil;

        if (payload)
        {
            NSError* jsonerror;
            NSData* jsonPayload = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonerror];
            if (!jsonPayload)
            {
                //MYCLog(@"<<< DECREASING COUNT: %@ (json failure)", name);
                self.pendingTasksCount--;
                if (completion) completion(nil, nil, jsonerror);
                return;
            }

            [req setHTTPMethod:@"POST"];
            [req setHTTPBody:jsonPayload];

#if DEBUG
            curlCommand = [NSString stringWithFormat:@"curl -k -X POST -H \"Content-Type: application/json\" -d '%@' %@",
                           [[NSString alloc] initWithData:jsonPayload encoding:NSUTF8StringEncoding], req.URL.absoluteString];
#endif
        }
        else
        {
#if DEBUG
            curlCommand = [NSString stringWithFormat:@"curl -k -X GET %@", req.URL.absoluteString];
#endif
        }

        [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {

            NSDictionary* result = [self handleReceivedJSON:data response:response error:networkError failure:^(NSError* jsonError){
                dispatch_async(dispatch_get_main_queue(), ^{
                    //MYCLog(@"<<< DECREASING COUNT: %@ (format failure)", name);
                    self.pendingTasksCount--;
                    MYCLog(@"MYCBackend: REQUEST FAILED: %@ ERROR: %@", curlCommand, jsonError);
                    if (completion) completion(nil, nil, jsonError);
                });
            }];

            // Generic errors are already handled and reported above.
            if (!result) return;

            //MYCLog(@"API CALL: %@\nResult: %@", curlCommand, result);

            NSError* formatError = nil;
            BOOL valid = NO;

            // Validate the template provided
            valid = [self validatePlist:result matchingTemplate:template error:&formatError];
            if (!valid) result = nil;

            dispatch_async(dispatch_get_main_queue(), ^{

                //MYCLog(@"<<< DECREASING COUNT: %@ (load finished)", name);
                self.pendingTasksCount--;

                if (!result)
                {
                    MYCLog(@"MYCBackend: REQUEST FAILED: %@ ERROR: %@", curlCommand, formatError);
                }
                if (completion) completion(result, curlCommand, formatError);
            });

        }] resume];
    });
}

- (NSMutableURLRequest*) requestWithName:(NSString*)name
{
    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/wapi/%@", self.currentEndpointURL.absoluteString, name]];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];

    // Set the content defaults
    [request setValue:@"gzip,deflate" forHTTPHeaderField:@"Accept-Encoding"];
    NSString* locale = [[[NSLocale currentLocale] localeIdentifier] stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    [request setValue:locale forHTTPHeaderField:@"Accept-Language"];

    // Set the JSON defaults.
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"utf-8" forHTTPHeaderField:@"Accept-Charset"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; // default, can be overriden later

    return request;
}

- (NSError*) formatError:(NSString*)errorString
{
    return [NSError errorWithDomain:MYCErrorDomain code:1001 userInfo: errorString ? @{NSLocalizedDescriptionKey: errorString} : nil];
}

- (NSError*) dataError:(NSString*)errorString
{
    return [NSError errorWithDomain:MYCErrorDomain code:1002 userInfo: errorString ? @{NSLocalizedDescriptionKey: errorString} : nil];
}

// Generic error handling. Either returns a non-nil value or calls a block with error.
- (NSDictionary*) handleReceivedJSON:(NSData*)data response:(NSURLResponse*)response error:(NSError*)error failure:(void(^)(NSError*))failureBlock
{
    if (!data)
    {
        NSInteger nextEndpoint = rand() % self.endpointURLs.count;
        if (nextEndpoint == self.currentEndpointIndex) {
            nextEndpoint = (nextEndpoint + 1) % self.endpointURLs.count;
        }
        self.currentEndpointIndex = nextEndpoint;
        failureBlock(error);
        return nil;
    }

    if (![response isKindOfClass:[NSHTTPURLResponse class]])
    {
        MYCLog(@"EXPECTED HTTP RESPONSE, GOT THIS: %@ Error: %@", response, error);
        failureBlock(error ?: [NSError errorWithDomain:MYCErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Non-HTTP response received.", @"MYC")}]);
        return nil;
    }

    NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;

    NSError* jsonerror = nil;
    NSDictionary* dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonerror];

    if (!dict)
    {
        // TODO: make this error more readable for user
        MYCDebug(NSString* string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];)
        MYCLog(@"EXPECTED JSON, GOT THIS: %@ (%@) [http status code: %d, url: %@] response headers: %@", string, data, (int)httpResponse.statusCode, httpResponse.URL, httpResponse.allHeaderFields);
        failureBlock(jsonerror);
        return nil;
    }

    // Handle various HTTP errors (non-2xx codes).
    if (httpResponse.statusCode < 200 || httpResponse.statusCode > 299) {
        MYCLog(@"MYCBackend: received HTTP code %ld: %@", (long)httpResponse.statusCode, dict[@"localizedError"] ?: dict[@"error"] ?: dict[@"message"] ?: @"Server Error");

        NSError* httpError = [NSError errorWithDomain:NSURLErrorDomain
                                                 code:httpResponse.statusCode
                                             userInfo:@{
                                                        NSLocalizedDescriptionKey: dict[@"localizedError"] ?: dict[@"error"] ?: dict[@"message"] ?: @"Server Error",
                                                        @"debugMessage": dict[@"error"] ?: dict[@"message"] ?: @"unknown error from backend",
                                                        }];

        failureBlock(httpError);
        return nil;
    }

    // Check if response is correctly formatted with "errorCode" and "r" slots present.
    NSError* formatError = nil;
    BOOL validFormat = [self validatePlist:dict matchingTemplate:@{@"errorCode": @0, @"r": @{ }, @"message": @""} error:&formatError];
    if (!validFormat) {
        failureBlock(formatError);
        return nil;
    }

    // Success code - return result dictionary.
    if ([dict[@"errorCode"] integerValue] == 0 && dict[@"r"]) {
        return dict[@"r"];
    }

    MYCLog(@"MYCBackend: received errorCode %@: %@ [%@]", dict[@"errorCode"], dict, httpResponse.URL);
    NSError* apiError = [NSError errorWithDomain:MYCErrorDomain
                                             code:[dict[@"errorCode"] integerValue]
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedString(@"Mycelium server responded with error %@", @""), dict[@"errorCode"]]
                                                    }];

    failureBlock(apiError);
    return nil;
}





#pragma mark - Validation Utils





- (BOOL) validatePlist:(id)plist matchingTemplate:(id)template error:(NSError**)errorOut
{
    return [self validatePlist:plist matchingTemplate:template error:errorOut path:@""];
}

- (BOOL) validatePlist:(id)plist matchingTemplate:(id)template error:(NSError**)errorOut path:(NSString*)path
{
    // No template - all values are okay. This is used e.g. by empty array (arbitrary data is okay)
    if (!template) return YES;

    if (!plist)
    {
        if (errorOut) *errorOut = [self dataError:NSLocalizedString(@"Missing data", @"")];
        return NO;
    }

    if (![self plist:plist compatibleWithTypeOfPlist:template])
    {
        if (errorOut)
        {
            NSString* msg = [NSString stringWithFormat:NSLocalizedString(@"JSON entity (%@) is not type-compatible with expected template (%@): %@ <=> %@ (json%@)",@""),
                             [plist class], [template class], plist, template, path];
            *errorOut = [self formatError:msg];
        }
        return NO;
    }

    if ([plist isKindOfClass:[NSDictionary class]])
    {
        // Do not drill down the items if template does not specify any item value.
        if ([template count] == 0) return YES;

        // If we compare with dict, we accept any keys not mentioned in the template
        // and validate types of keys mentioned in the template
        for (id key in plist)
        {
            id templateItem = [template objectForKey:key];
            id item = [plist objectForKey:key];
            BOOL result = [self validatePlist:item matchingTemplate:templateItem error:errorOut path:[path stringByAppendingFormat:@"[@\"%@\"]", key]];
            if (!result) return NO;
        }
        return YES;
    }
    else if ([plist isKindOfClass:[NSArray class]])
    {
        // Do not drill down the items if template does not specify any item value.
        if ([template count] == 0) return YES;

        // Every item must be type compatible with the first item in the template.
        // If template is empty, no checking is required.
        id firstItemTemplate = [template firstObject]; // can be nil, then any item is accepted.
        int i = 0;
        for (id item in plist)
        {
            BOOL result = [self validatePlist:item matchingTemplate:firstItemTemplate error:errorOut path:[path stringByAppendingFormat:@"[%d]", i]];
            if (!result) return NO;
            i++;
        }
        return YES;
    }
    else
    {
        // Type-compatible scalar values (strings, numbers, dates, data objects).
        return YES;
    }
}

// This allows to compare immutable classes with mutable counterparts and handle unexpected private subclasses.
- (BOOL) plist:(id)a compatibleWithTypeOfPlist:(id)b
{
    if (!a || !b) return NO;
    if ([a class] == [b class]) return YES;
    if ([a isKindOfClass:[NSNumber class]]     && [b isKindOfClass:[NSNumber class]])     return YES;
    if ([a isKindOfClass:[NSString class]]     && [b isKindOfClass:[NSString class]])     return YES;
    if ([a isKindOfClass:[NSDictionary class]] && [b isKindOfClass:[NSDictionary class]]) return YES;
    if ([a isKindOfClass:[NSArray class]]      && [b isKindOfClass:[NSArray class]])      return YES;
    if ([a isKindOfClass:[NSDate class]]       && [b isKindOfClass:[NSDate class]])       return YES;
    if ([a isKindOfClass:[NSData class]]       && [b isKindOfClass:[NSData class]])       return YES;
    return NO;
}







#pragma mark - NSURLSessionDelegate


- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    NSURLCredential *credential = nil;

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust] &&
        self.currentSSLFingerprint)
    {
        // Certificate is invalid unless proven valid.
        disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;

        // Check that the hostname matches.
        if ([challenge.protectionSpace.host isEqualToString:self.currentEndpointURL.host])
        {
            // Check the sha1 fingerprint of the certificate here.
            // We may have several certificates, only one is enough to match.
            SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
            CFIndex crtCount = SecTrustGetCertificateCount(serverTrust);
            for (CFIndex i = 0; i < crtCount; i++)
            {
                SecCertificateRef cert = SecTrustGetCertificateAtIndex(serverTrust, i);
                NSData* certData = CFBridgingRelease(SecCertificateCopyData(cert));
                if ([BTCSHA1(certData) isEqual:self.currentSSLFingerprint])
                {
                    disposition = NSURLSessionAuthChallengeUseCredential;
                    credential = [NSURLCredential credentialForTrust:serverTrust];
                    break;
                }
            }
        }
    }
    if (completionHandler) completionHandler(disposition, credential);
}

@end
