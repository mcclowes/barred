#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL BarredNativeVisibilityAvailable(void);
void BarredActivateVisibility(NSArray<NSString *> *visibleApps,
                              void (^completion)(id _Nullable handle, NSError * _Nullable error));
void BarredInvalidateVisibility(id handle);

NS_ASSUME_NONNULL_END
