/* Copyright 2015 Realm Inc - All Rights Reserved
 * Proprietary and Confidential
 */

#import "RealmJSTests.h"
#import "Base/RCTJavaScriptExecutor.h"
#import "Base/RCTBridge.h"
#import "Modules/RCTDevMenu.h"

@import ObjectiveC;
@import RealmReact;

extern void JSGlobalContextSetIncludesNativeCallStackWhenReportingExceptions(JSGlobalContextRef ctx, bool includesNativeCallStack);

@interface RCTDevMenu () <RCTInvalidating>
@end

@interface RealmReactTests : RealmJSTests
@end

@interface RealmReactChromeTests : RealmReactTests
@end

@implementation RealmReactTests

+ (Class)executorClass {
    return NSClassFromString(@"RCTContextExecutor");
}

+ (NSString *)classNameSuffix {
    return @"";
}

+ (id<RCTJavaScriptExecutor>)currentExecutor {
    Class executorClass = [self executorClass];
    if (!executorClass) {
        NSLog(@"%@: Executor class not found", self);
        exit(1);
    }

    static RCTBridge *s_bridge;
    if (!s_bridge) {
        [[NSNotificationCenter defaultCenter] postNotificationName:RCTReloadNotification object:nil];
    }

    if (!s_bridge.valid) {
        NSNotification *notification = [self waitForNotification:RCTDidCreateNativeModules];
        s_bridge = notification.object;

        if (!s_bridge) {
            NSLog(@"No RCTBridge provided by RCTJavaScriptDidLoadNotification");
            exit(1);
        }

#ifdef DEBUG
        // We don't want the RCTDevMenu from switching the executor class from underneath us.
        [s_bridge.devMenu invalidate];
#endif

        [self waitForNotification:RCTJavaScriptDidLoadNotification];
    }

    if (s_bridge.executorClass != executorClass) {
        s_bridge.executorClass = executorClass;
        [s_bridge reload];

        // The [RCTBridge reload] method does a dispatch_async that we must run before trying again.
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

        return [self currentExecutor];
    }

    return [s_bridge valueForKey:@"javaScriptExecutor"];
}

+ (XCTestSuite *)defaultTestSuite {
    id<RCTJavaScriptExecutor> executor = [self currentExecutor];

    // FIXME: Remove this nonsense once the crashes go away when a test fails!
    JSGlobalContextRef ctx = RealmReactGetJSGlobalContextForExecutor(executor, false);
    if (ctx) {
        JSGlobalContextSetIncludesNativeCallStackWhenReportingExceptions(ctx, false);
    }

    NSError *error;
    NSDictionary *testCaseNames = [self invokeMethod:@"getTestNames" inModule:@"index" error:&error];

    if (error || !testCaseNames.count) {
        NSLog(@"Error from calling getTestNames() - %@", error ?: @"None returned");
        exit(1);
    }

    NSString *nameSuffix = [self classNameSuffix];
    if (nameSuffix.length) {
        NSMutableDictionary *renamedTestCaseNames = [[NSMutableDictionary alloc] init];
        for (NSString *name in testCaseNames) {
            renamedTestCaseNames[[name stringByAppendingString:nameSuffix]] = testCaseNames[name];
        }
        testCaseNames = renamedTestCaseNames;
    }

    XCTestSuite *suite = [super defaultTestSuite];
    for (XCTestSuite *testSuite in [self testSuitesFromDictionary:testCaseNames]) {
        [suite addTest:testSuite];
    }

    return suite;
}

+ (NSNotification *)waitForNotification:(NSString *)notificationName {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    __block BOOL condition = NO;
    __block NSNotification *notification;

    id token = [nc addObserverForName:notificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        condition = YES;
        notification = note;
    }];

    [self waitForCondition:&condition];
    [nc removeObserver:token];

    return notification;
}

+ (void)waitForCondition:(BOOL *)condition {
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];

    while (!*condition) {
        @autoreleasepool {
            [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    }
}

+ (id)invokeMethod:(NSString *)method inModule:(NSString *)module error:(NSError * __strong *)outError {
    id<RCTJavaScriptExecutor> executor = [self currentExecutor];
    module = [NSString stringWithFormat:@"realm-tests/%@.js", module];

    __block BOOL condition = NO;
    __block id result;

    [executor executeJSCall:module method:method arguments:@[] callback:^(id json, NSError *error) {
        // The React Native debuggerWorker.js very bizarrely returns an array five empty arrays to signify an error.
        if ([json isKindOfClass:[NSArray class]] && [json isEqualToArray:@[@[], @[], @[], @[], @[]]]) {
            json = nil;

            if (!error) {
                error = [NSError errorWithDomain:@"JS" code:1 userInfo:@{NSLocalizedDescriptionKey: @"unknown JS error"}];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            condition = YES;
            result = json;

            if (error && outError) {
                *outError = error;
            }
        });
    }];

    [self waitForCondition:&condition];

    return result;
}

- (void)invokeMethod:(NSString *)method {
    NSString *module = NSStringFromClass(self.class);
    NSString *suffix = [self.class classNameSuffix];

    if (suffix.length && [module hasSuffix:suffix]) {
        module = [module substringToIndex:(module.length - suffix.length)];
    }

    NSError *error;
    [self.class invokeMethod:method inModule:module error:&error];

    if (error) {
        // TODO: Parse and use localizedFailureReason info once we can source map the failure location in JS.
        [self recordFailureWithDescription:error.localizedDescription inFile:@(__FILE__) atLine:__LINE__ expected:YES];
    }
}

@end

/* TODO: Re-enable once this works in CI
@implementation RealmReactChromeTests

+ (Class)executorClass {
    return NSClassFromString(@"RCTWebSocketExecutor");
}

+ (NSString *)classNameSuffix {
    return @"_Chrome";
}

@end
 */
