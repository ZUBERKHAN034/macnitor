#import "DuoBarPowerAuthorization.h"

#import <Security/Security.h>
#import <stdio.h>

@interface DuoBarPowerAuthorization () {
    AuthorizationRef _authorization;
}
@end

@implementation DuoBarPowerAuthorization

+ (instancetype)shared {
    static DuoBarPowerAuthorization *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (BOOL)setLowPowerModeEnabled:(BOOL)enabled error:(NSError **)error {
    @synchronized (self) {
        if (_authorization == NULL) {
            OSStatus status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &_authorization);
            if (status != errAuthorizationSuccess) {
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
                }
                return NO;
            }

            AuthorizationItem executeItem = {
                .name = kAuthorizationRightExecute,
                .valueLength = 0,
                .value = NULL,
                .flags = 0
            };
            AuthorizationRights rights = {
                .count = 1,
                .items = &executeItem
            };
            AuthorizationFlags flags = kAuthorizationFlagInteractionAllowed
                | kAuthorizationFlagExtendRights
                | kAuthorizationFlagPreAuthorize;
            status = AuthorizationCopyRights(_authorization, &rights, kAuthorizationEmptyEnvironment, flags, NULL);
            if (status != errAuthorizationSuccess) {
                AuthorizationFree(_authorization, kAuthorizationFlagDefaults);
                _authorization = NULL;
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
                }
                return NO;
            }
        }

        // Keep both the executable and argument set fixed to this one power-mode operation.
        char *arguments[] = {"-a", "lowpowermode", enabled ? "1" : "0", NULL};
        FILE *communicationPipe = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        OSStatus status = AuthorizationExecuteWithPrivileges(
            _authorization,
            "/usr/bin/pmset",
            kAuthorizationFlagDefaults,
            arguments,
            &communicationPipe
        );
#pragma clang diagnostic pop

        if (communicationPipe != NULL) {
            char output[1024];
            size_t length = fread(output, 1, sizeof(output) - 1, communicationPipe);
            output[length] = '\0';
            fclose(communicationPipe);
            if (length > 0 && error != NULL) {
                NSString *message = [NSString stringWithUTF8String:output];
                *error = [NSError errorWithDomain:@"DuoBarPowerAuthorization" code:1 userInfo:@{
                    NSLocalizedDescriptionKey: message ?: @"The power setting could not be changed."
                }];
            }
        }

        if (status != errAuthorizationSuccess) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
            }
            return NO;
        }
        return YES;
    }
}

- (void)dealloc {
    if (_authorization != NULL) {
        AuthorizationFree(_authorization, kAuthorizationFlagDefaults);
    }
}

@end
