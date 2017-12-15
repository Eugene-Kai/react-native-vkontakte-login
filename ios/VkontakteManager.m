#import "VkontakteManager.h"

#if __has_include(<VKSdkFramework/VKSdkFramework.h>)
#import <VKSdkFramework/VKSdkFramework.h>
#else
#import "VKSdk.h"
#endif

#if __has_include(<React/RCTUtils.h>)
#import <React/RCTUtils.h>
#elif __has_include("RCTUtils.h")
#import "RCTUtils.h"
#else
#import "React/RCTUtils.h" // Required when used as a Pod in a Swift project
#endif

#ifdef DEBUG
#define DMLog(...) NSLog(@"[VKLogin] %s %@", __PRETTY_FUNCTION__, [NSString stringWithFormat:__VA_ARGS__])
#else
#define DMLog(...) do { } while (0)
#endif

@implementation VkontakteManager {
  VKSdk *sdk;
  RCTPromiseResolveBlock loginResolver;
  RCTPromiseRejectBlock loginRejector;
}

- (instancetype)init
{
  if (self = [super init]) {
    NSNumber *appId = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"VK_APP_ID"];
    if (appId){
      DMLog(@"Found appId %@ on startup", appId);
      [self initialize:appId];
    }
  }
  return self;
}

RCT_EXPORT_MODULE();

- (dispatch_queue_t)methodQueue {
  return dispatch_get_main_queue();
}

RCT_EXPORT_METHOD(initialize: (nonnull NSNumber *) appId) {
  DMLog(@"Initialize app id %@", appId);

  sdk = [VKSdk initializeWithAppId:[appId stringValue]];
  [sdk registerDelegate:self];
  [sdk setUiDelegate:self];
}

RCT_EXPORT_METHOD(login: (NSArray *) scope resolver: (RCTPromiseResolveBlock) resolve rejecter: (RCTPromiseRejectBlock) reject) {
  DMLog(@"Login with scope %@", scope);
  if (![VKSdk initialized]){
    reject(RCTErrorUnspecified, nil, RCTErrorWithMessage(@"VK SDK must be initialized first"));
    return;
  }

  self->loginResolver = resolve;
  self->loginRejector = reject;
  [VKSdk wakeUpSession:scope completeBlock:^(VKAuthorizationState state, NSError *error) {
    switch (state) {
      case VKAuthorizationAuthorized: {
        DMLog(@"User already authorized");
        NSDictionary *loginData = [self getResponse];
        self->loginResolver(loginData);
        break;
      }
      case VKAuthorizationInitialized: {
        DMLog(@"Authorization required");
        [VKSdk authorize:scope];
        break;
      }
      case VKAuthorizationError: {
        NSString *errMessage = [NSString stringWithFormat:@"VK Authorization error: %@", [error localizedDescription]];
        DMLog(errMessage);
        self->loginRejector(RCTErrorUnspecified, nil, RCTErrorWithMessage(errMessage));
      }
    }
  }];
};

RCT_EXPORT_METHOD(isLoggedIn: (RCTPromiseResolveBlock) resolve rejecter: (RCTPromiseRejectBlock) reject) {
  if ([VKSdk initialized]){
  resolve([NSNumber numberWithBool:[VKSdk isLoggedIn]]);
}
  else {
    reject(RCTErrorUnspecified, nil, RCTErrorWithMessage(@"VK SDK must be initialized first"));
  }
}

RCT_REMAP_METHOD(logout, resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject){
  DMLog(@"Logout");
  if (![VKSdk initialized]){
    reject(RCTErrorUnspecified, nil, RCTErrorWithMessage(@"VK SDK must be initialized first"));
    return;
  }
  [VKSdk forceLogout];
  resolve(nil);
};

- (void)vkSdkAccessAuthorizationFinishedWithResult:(VKAuthorizationResult *)result {
  DMLog(@"Authorization result is %@", result);
  if (result.error && self->loginRejector != nil) {
    self->loginRejector(RCTErrorUnspecified, nil, RCTErrorWithMessage(result.error.localizedDescription));
  } else if (result.token && self->loginResolver != nil) {
    NSDictionary *loginData = [self getResponse];
    self->loginResolver(loginData);
  }
}

- (void)vkSdkUserAuthorizationFailed:(VKError *)error {
  DMLog(@"Authrization failed with %@", error.errorMessage);
  self->loginRejector(RCTErrorUnspecified, nil, RCTErrorWithMessage(error.errorMessage));
}

- (void)vkSdkNeedCaptchaEnter:(VKError *)captchaError {
  DMLog(@"VK SDK UI Delegate needs captcha: %@", captchaError);
  VKCaptchaViewController *vc = [VKCaptchaViewController captchaControllerWithError:captchaError];

  UIViewController *root = [[[[UIApplication sharedApplication] delegate] window] rootViewController];

  [vc presentIn:root];
}

- (void)vkSdkShouldPresentViewController:(UIViewController *)controller {
  DMLog(@"Presenting view controller");
  UIViewController *root = [[[[UIApplication sharedApplication] delegate] window] rootViewController];

  [root presentViewController:controller animated:YES completion:nil];
}

- (NSDictionary *)getResponse {
  VKAccessToken *token = [VKSdk accessToken];

  if (token) {
    return @{
        @"access_token" : token.accessToken,
        @"user_id" : token.userId,
        @"expires_in" : [NSNumber numberWithInt:token.expiresIn],
        @"email" : token.email ?: [NSNull null],
        @"secret" : token.secret ?: [NSNull null]
    };
  }
  else {
    return [NSNull null];
  }
}

+ (BOOL)requiresMainQueueSetup {
  return YES;
}

@end
