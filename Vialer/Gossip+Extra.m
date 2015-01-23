//
//  Gossip+Extra.m
//  Vialer
//
//  Created by Reinier Wieringa on 26/12/14.
//  Copyright (c) 2014 VoIPGRID. All rights reserved.
//

#import "Gossip+Extra.h"
#import "GSPJUtil.h"

#import "PJSIP.h"

@implementation GSCall (Gossip_Extra)

- (void)setPaused:(BOOL)paused {
    if (paused) {
        pjsua_call_set_hold(self.callId, NULL);
    } else {
        pjsua_call_reinvite(self.callId, PJ_TRUE, NULL);
    }
}

- (BOOL)paused {
    pjsua_call_info callInfo;
    pjsua_call_get_info(self.callId, &callInfo);
    return (callInfo.media_status == PJSUA_CALL_MEDIA_LOCAL_HOLD) || (callInfo.media_status == PJSUA_CALL_MEDIA_REMOTE_HOLD);
}

- (NSTimeInterval)callDuration {
    pjsua_call_info callInfo;
    pjsua_call_get_info(self.callId, &callInfo);

    return ((NSTimeInterval)PJ_TIME_VAL_MSEC(callInfo.total_duration)) / 1000.f;
}

- (NSString *)remoteInfo {
    pjsua_call_info callInfo;
    pjsua_call_get_info(self.callId, &callInfo);

    NSString *remoteInfo = [[GSPJUtil stringWithPJString:&callInfo.remote_info] copy];
    NSRange range = [remoteInfo rangeOfString:@"\"" options:NSBackwardsSearch];
    if (range.location != NSNotFound) {
        remoteInfo = [remoteInfo substringToIndex:range.location];
    }
    return [remoteInfo stringByReplacingOccurrencesOfString:@"\"" withString:@""];
}

+ (NSArray *)activeCalls {
    NSMutableArray *activeCalls = [NSMutableArray array];

    unsigned callCount = pjsua_call_get_count();
    if (callCount) {
        pjsua_call_id callIds[callCount];
        pjsua_enum_calls(callIds, &callCount);

        GSAccount *account = [GSUserAgent sharedAgent].account;
        for (unsigned i = 0; i < callCount; i++) {
            [activeCalls addObject:[GSCall incomingCallWithId:callIds[i] toAccount:account]];
        }
    }

    return activeCalls;
}

@end