#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DuoBarPowerAuthorization : NSObject

+ (instancetype)shared;
- (BOOL)setLowPowerModeEnabled:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NOTHROW;

@end

NS_ASSUME_NONNULL_END
