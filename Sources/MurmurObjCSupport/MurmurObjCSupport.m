#import "MurmurObjCSupport.h"

NSError * _Nullable MurmurTryCatch(void (NS_NOESCAPE ^ _Nonnull block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[NSLocalizedDescriptionKey] =
            exception.reason ?: exception.name ?: @"Objective-C exception";
        if (exception.name) {
            info[@"MurmurExceptionName"] = exception.name;
        }
        return [NSError errorWithDomain:@"MurmurObjCException" code:1 userInfo:info];
    }
}
