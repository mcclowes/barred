#import "NativeMenuBarVisibility.h"
#import <dlfcn.h>
#import <objc/message.h>

@interface BarredVisibilityToken : NSObject
@property(nonatomic, strong) id assertion;
@end

@implementation BarredVisibilityToken
- (void)dealloc {
    id assertion = _assertion;
    if (assertion) {
        dispatch_async(dispatch_get_main_queue(), ^{ BarredInvalidateVisibility(assertion); });
    }
}
@end

static NSError *VisibilityError(NSString *message) {
    return [NSError errorWithDomain:@"BarredVisibility" code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

BOOL BarredNativeVisibilityAvailable(void) {
    static dispatch_once_t once;
    static BOOL available;
    dispatch_once(&once, ^{
        void *framework = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",
                                 RTLD_LAZY | RTLD_LOCAL);
        Class configuration = NSClassFromString(@"MBAssessmentModeConfiguration");
        Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
        available = framework
            && [configuration instancesRespondToSelector:NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:")]
            && [assertion instancesRespondToSelector:NSSelectorFromString(@"activateWithConfiguration:completionHandler:")]
            && [assertion instancesRespondToSelector:NSSelectorFromString(@"invalidate")];
    });
    return available;
}

void BarredActivateVisibility(NSArray<NSString *> *visibleApps,
                              void (^completion)(id, NSError *)) {
    __block BOOL completed = NO;
    __block id pendingHandle = nil;
    void (^deliver)(id, NSError *) = ^(id handle, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completed) {
                if (handle) BarredInvalidateVisibility(handle);
                return;
            }
            completed = YES;
            if (error && pendingHandle) BarredInvalidateVisibility(pendingHandle);
            pendingHandle = nil;
            BarredVisibilityToken *token = nil;
            if (handle && !error) {
                token = [BarredVisibilityToken new];
                token.assertion = handle;
            }
            completion(token, error);
        });
    };
    if (!BarredNativeVisibilityAvailable()) {
        deliver(nil, VisibilityError(@"Menu bar hiding is unavailable on this macOS version."));
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        deliver(nil, VisibilityError(@"Menu bar hiding timed out."));
    });
    @try {
        // Preserve all system controls; only third-party apps are sectioned.
        NSMutableArray<NSNumber *> *systemItems = [NSMutableArray array];
        for (NSInteger item = 0; item < 64; item++) {
            [systemItems addObject:@(item)];
        }
        typedef id (*Configure)(id, SEL, NSArray *, NSArray *);
        SEL initialize = NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:");
        id settings = ((Configure)objc_msgSend)([NSClassFromString(@"MBAssessmentModeConfiguration") alloc],
                                                initialize, systemItems, [visibleApps copy]);
        id handle = [[NSClassFromString(@"MBAssessmentModeAssertion") alloc] init];
        pendingHandle = handle;
        if (!settings || !handle) {
            deliver(nil, VisibilityError(@"Could not initialize menu bar hiding."));
            return;
        }
        typedef void (*Activate)(id, SEL, id, void (^)(NSError *));
        SEL activate = NSSelectorFromString(@"activateWithConfiguration:completionHandler:");
        ((Activate)objc_msgSend)(handle, activate, settings, ^(NSError *error) {
            deliver(error ? nil : handle, error);
        });
    } @catch (NSException *exception) {
        deliver(nil, VisibilityError(exception.reason ?: @"Menu bar hiding failed."));
    }
}

void BarredInvalidateVisibility(id handle) {
    if ([handle isKindOfClass:[BarredVisibilityToken class]]) {
        BarredVisibilityToken *token = handle;
        id assertion = token.assertion;
        token.assertion = nil;
        if (assertion) BarredInvalidateVisibility(assertion);
        return;
    }
    @try {
        SEL invalidate = NSSelectorFromString(@"invalidate");
        if ([handle respondsToSelector:invalidate]) {
            ((void (*)(id, SEL))objc_msgSend)(handle, invalidate);
        }
    } @catch (NSException *exception) {
        NSLog(@"Barred could not release menu bar hiding: %@", exception.reason);
    }
}
