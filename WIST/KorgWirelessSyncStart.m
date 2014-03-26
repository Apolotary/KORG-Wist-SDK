//
//  KorgWirelessSyncStart.m
//  WIST SDK Version 1.0.0
//
//  Portions contributed by Retronyms (www.retronyms.com).
//  Copyright 2011 KORG INC. All rights reserved.
//

#import <mach/mach_time.h>
#import "KorgWirelessSyncStart.h"

@interface KorgGKSession : GKSession
@end

@implementation KorgGKSession
- (void)denyConnectionFromPeer:(NSString *)peerID
{
    [super denyConnectionFromPeer:peerID];
    [self.delegate session:self connectionWithPeerFailed:peerID withError:nil];
}
@end


@interface KorgWirelessSyncStart()
- (void)resetTime;
- (void)forceDisconnect;
- (void)timerFired:(NSTimer*)timer;
@property (retain) GKSession* session;
@end

@implementation KorgWirelessSyncStart

@synthesize delegate;
@synthesize session;
@synthesize isConnected = isConnected_;
@synthesize isMaster = isMaster_;
@synthesize latency = latency_;

enum
{
    kGKCommand_Beacon               = 0,   //  master -> slave -> master
    kGKCommand_StartSlave           = 1,
    kGKCommand_StopSlave            = 2,

    kGKCommand_RequestLatency       = 3,
    kGKCommand_Latency              = 4,
    kGKCommand_PeersLatencyChanged  = 5,

    kGKCommand_RequestDelay         = 6,
    kGKCommand_Delay                = 7,
};

//  ---------------------------------------------------------------------------
//      init
//  ---------------------------------------------------------------------------
- (id)init
{
    self = [super init];
    if (self != nil)
    {
        isConnected_ = NO;
        isMaster_ = NO;
        doDisconnectByMyself_ = NO;

        [self resetTime];

        const NSTimeInterval    interval = 1.0 / 8.0;
        timer_ = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(timerFired:) userInfo:nil repeats:YES];
        [self release];
    }
    return self;
}

//  ---------------------------------------------------------------------------
//      dealloc
//  ---------------------------------------------------------------------------
- (void)dealloc
{
    [self retain];
    [timer_ invalidate];
    [self forceDisconnect];

    self.delegate = nil;
    [super dealloc];
}

//  ---------------------------------------------------------------------------
//      resetTime
//  ---------------------------------------------------------------------------
- (void)resetTime
{
    delay_ = 0;
    peerDelay_ = 0;
    gotPeerDelay_ = NO;
    gkWorstDelay_ = 0;
    beaconReceived_ = NO;
    latency_ = 0;
    peerLatency_ = 0;
    gotPeerLatency_ = NO;
    timeDiff_ = 0;
}

//  ---------------------------------------------------------------------------
//      forceDisconnect
//  ---------------------------------------------------------------------------
- (void)forceDisconnect
{
    const BOOL  prevStatus = isConnected_;
    doDisconnectByMyself_ = YES;

    [self.session disconnectFromAllPeers];
    self.session = nil;
    [self resetTime];

    isConnected_ = NO;

    if (prevStatus)
    {
        if (self.delegate && [self.delegate respondsToSelector:@selector(wistConnectionLost)])
        {
            [self.delegate performSelector:@selector(wistConnectionLost) withObject:nil];
        }
    }
}

//  ---------------------------------------------------------------------------
//      sendData:withDataMode
//  ---------------------------------------------------------------------------
- (void)sendData:(NSData *)data withDataMode:(GKSendDataMode)dataMode
{
    if (isConnected_)
    {
        NSError*    error = nil;
        const BOOL  sent = [self.session sendDataToAllPeers:data withDataMode:dataMode error:&error];
        if (!sent)
        {
#ifdef DEBUG
            NSLog(@"KorgWirelessSyncStart sendData failed: %@", [error localizedDescription]);
#endif
        }
    }
}

//  ---------------------------------------------------------------------------
//      setLatency
//  ---------------------------------------------------------------------------
- (void)setLatency:(uint64_t)latencyNano
{
    if (latency_ != latencyNano)
    {
        latency_ = latencyNano;

        if (isConnected_)
        {
            NSArray*    commands = [NSArray arrayWithObjects:[NSNumber numberWithInt:kGKCommand_PeersLatencyChanged], nil];
            [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:GKSendDataReliable];
        }
    }
}

//  ---------------------------------------------------------------------------
//      searchPeer
//  ---------------------------------------------------------------------------
- (void)searchPeer
{
    if (!isConnected_)
    {
        doDisconnectByMyself_ = NO;
        isMaster_ = NO;

        GKPeerPickerController* picker = [[GKPeerPickerController alloc] init];
        picker.delegate = self;
        picker.connectionTypesMask = GKPeerPickerConnectionTypeNearby;
        [picker show]; 
    }
}

//  ---------------------------------------------------------------------------
//      disconnect
//  ---------------------------------------------------------------------------
- (void)disconnect
{
    [self forceDisconnect];
}

//  ---------------------------------------------------------------------------
//      hostTime2NanoSec
//  ---------------------------------------------------------------------------
static inline uint64_t
hostTime2NanoSec(uint64_t hostTime)
{
    mach_timebase_info_data_t   timeInfo;
    mach_timebase_info(&timeInfo);
    return hostTime * timeInfo.numer / timeInfo.denom;
}

//  ---------------------------------------------------------------------------
//      nanoSec2HostTime
//  ---------------------------------------------------------------------------
static inline uint64_t
nanoSec2HostTime(uint64_t nanosec)
{
    mach_timebase_info_data_t   timeInfo;
    mach_timebase_info(&timeInfo);
    return nanosec * timeInfo.denom / timeInfo.numer;
}

//  ---------------------------------------------------------------------------
//      processLatencyCommand
//  ---------------------------------------------------------------------------
- (void)processLatencyCommand:(NSData *)data
{
    NSArray*    array = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    const int   command = [[array objectAtIndex:0] intValue];
    switch(command)
    {
        case kGKCommand_RequestLatency:
            {
                NSArray*    commands = [NSArray arrayWithObjects:
                                        [NSNumber numberWithInt:kGKCommand_Latency],
                                        [NSNumber numberWithUnsignedLongLong:self.latency],
                                        nil];
                [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:GKSendDataReliable];
            }
            break;
        case kGKCommand_Latency:
            {
                const uint64_t  latencyNano = [[array objectAtIndex:1] unsignedLongLongValue];
                peerLatency_ = latencyNano;
                gotPeerLatency_ = YES;
            }
            break;
        case kGKCommand_PeersLatencyChanged:
            peerLatency_ = 0;
            gotPeerLatency_ = NO;
            break;
        default:
            break;
    }
}

//  ---------------------------------------------------------------------------
//      receiveDataInMasterMode
//  ---------------------------------------------------------------------------
- (void)receiveDataInMasterMode:(NSData *)data
{
    @try
    {
        NSArray*    array = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        const int   command = [[array objectAtIndex:0] intValue];
        switch(command)
        {
            case kGKCommand_Delay:
                if (!gotPeerDelay_)
                {
                    peerDelay_ = [[array objectAtIndex:1] unsignedLongLongValue];
                    gotPeerDelay_= YES;
                }
                break;
            case kGKCommand_Beacon:
                {
                    const uint64_t  sentNano = [[array objectAtIndex:1] unsignedLongLongValue];
                    const uint64_t  remoteSentNano = [[array objectAtIndex:2] unsignedLongLongValue];
                    const uint64_t  receivedNano = hostTime2NanoSec(mach_absolute_time());
                    const uint64_t  elapseOnewayNano = (receivedNano - sentNano) / 2;
                    if (elapseOnewayNano < 4000000000ULL)   //  < 4 sec.
                    {
                        if (gkWorstDelay_ < elapseOnewayNano)
                        {
                            gkWorstDelay_ = elapseOnewayNano;
                        }

                        const double    diff = (double)remoteSentNano - elapseOnewayNano - sentNano;
                        if (beaconReceived_)
                        {
                            timeDiff_ = (timeDiff_ + diff) / 2;
                        }
                        else
                        {
                            timeDiff_ = diff;
                            beaconReceived_ = YES;
                        }
                    }
                }
                break;
            case kGKCommand_RequestLatency:
            case kGKCommand_Latency:
            case kGKCommand_PeersLatencyChanged:
                [self processLatencyCommand:data];
                break;
            default:
                break;
        }
    }
    @catch (NSException *exception) 
    {
#ifdef DEBUG
        NSLog(@"Exception caught %@:%@", [exception name], [exception reason]);
#endif
    }
    @finally
    {
    }
}

//  ---------------------------------------------------------------------------
//      receiveDataInSlaveMode
//  ---------------------------------------------------------------------------
- (void)receiveDataInSlaveMode:(NSData *)data
{
    @try
    {
        NSArray*    dataArray = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        const int   command = [[dataArray objectAtIndex:0] intValue];
        switch (command)
        {
            case kGKCommand_Beacon:
                {
                    NSArray*    commands = [NSArray arrayWithObjects:[NSNumber numberWithInt:kGKCommand_Beacon],
                                            [NSNumber numberWithUnsignedLongLong:[[dataArray objectAtIndex:1] unsignedLongLongValue]],
                                            [NSNumber numberWithUnsignedLongLong:hostTime2NanoSec(mach_absolute_time())],
                                            nil];
                    [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:GKSendDataUnreliable];
                }
                break;
            case kGKCommand_RequestDelay:
                {
                    NSArray*    commands = [NSArray arrayWithObjects:[NSNumber numberWithInt:kGKCommand_Delay],
                                            [NSNumber numberWithUnsignedLongLong:delay_],
                                            nil];
                    [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:GKSendDataReliable];
                }
                break;
            case kGKCommand_StartSlave:
                if (self.delegate)
                {
                    const uint64_t  nanoSec = [[dataArray objectAtIndex:1] unsignedLongLongValue];
                    const float     tempo = [[dataArray objectAtIndex:2] floatValue];
                    [self.delegate wistStartCommandReceived:nanoSec2HostTime(nanoSec) withTempo:tempo];
                }
                break;
            case kGKCommand_StopSlave:
                if (self.delegate)
                {
                    const uint64_t  nanoSec = [[dataArray objectAtIndex:1] unsignedLongLongValue];
                    [self.delegate wistStopCommandReceived:nanoSec2HostTime(nanoSec)];
                }
                break;
            case kGKCommand_RequestLatency:
            case kGKCommand_Latency:
            case kGKCommand_PeersLatencyChanged:
                [self processLatencyCommand:data];
                break;
            default:
                break;
        }        
    }
    @catch (NSException *exception)
    {
#ifdef DEBUG
        NSLog(@"Exception caught %@:%@", [exception name], [exception reason]);
#endif
    }
    @finally
    {
    }
}

//  ---------------------------------------------------------------------------
//      estimatedLocalHostTime
//  ---------------------------------------------------------------------------
- (uint64_t)estimatedLocalHostTime:(uint64_t)hostTime
{
    const uint64_t  delayMax = (delay_ < peerDelay_) ? peerDelay_ : delay_;
    const uint64_t  audioLatencyMax = (self.latency < peerLatency_) ? peerLatency_ : self.latency;
    const uint64_t  latencyNano = audioLatencyMax - self.latency;
    return hostTime + nanoSec2HostTime(gkWorstDelay_ + delayMax + latencyNano);
}

//  ---------------------------------------------------------------------------
//      estimatedRemoteHostTime
//  ---------------------------------------------------------------------------
- (uint64_t)estimatedRemoteHostTime:(uint64_t)hostTime
{
    const uint64_t  delayMax = (delay_ < peerDelay_) ? peerDelay_ : delay_;
    const uint64_t  audioLatencyMax = (self.latency < peerLatency_) ? peerLatency_ : self.latency;
    const uint64_t  latencyNano = audioLatencyMax - peerLatency_;
    return hostTime + nanoSec2HostTime(gkWorstDelay_ + delayMax + latencyNano);
}

//  ---------------------------------------------------------------------------
//      sendStartCommand
//  ---------------------------------------------------------------------------
- (void)sendStartCommand:(uint64_t)hostTime withTempo:(float)tempo
{
    if (isConnected_ && isMaster_)
    {
        const uint64_t  slaveNanoSec = beaconReceived_ ? (hostTime2NanoSec([self estimatedRemoteHostTime:hostTime]) + timeDiff_) : 0;
        NSArray*    commands = [NSArray arrayWithObjects:
                                [NSNumber numberWithInt:kGKCommand_StartSlave],
                                [NSNumber numberWithUnsignedLongLong:slaveNanoSec],
                                [NSNumber numberWithFloat:tempo],
                                nil];
        [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:GKSendDataReliable];
    }
}

//  ---------------------------------------------------------------------------
//      sendStopCommand
//  ---------------------------------------------------------------------------
- (void)sendStopCommand:(uint64_t)hostTime
{
    if (isConnected_ && isMaster_)
    {
        const uint64_t  slaveNanoSec = beaconReceived_ ? (hostTime2NanoSec([self estimatedRemoteHostTime:hostTime]) + timeDiff_) : 0;
        NSArray*    commands = [NSArray arrayWithObjects:
                                [NSNumber numberWithInt:kGKCommand_StopSlave],
                                [NSNumber numberWithUnsignedLongLong:slaveNanoSec],
                                nil];
        [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:GKSendDataReliable];
    }
}

//  ---------------------------------------------------------------------------
//      timerFired
//  ---------------------------------------------------------------------------
- (void)timerFired:(NSTimer*)timer
{
    //  send beacon
    if (isConnected_)
    {
        if (!gotPeerLatency_)
        {
            NSArray*    request = [NSArray arrayWithObjects: [NSNumber numberWithInt:kGKCommand_RequestLatency], nil];
            [self sendData:[NSKeyedArchiver archivedDataWithRootObject:request] withDataMode:GKSendDataReliable];
        }
        if (isMaster_)
        {
            if (!gotPeerDelay_)
            {
                NSArray*    request = [NSArray arrayWithObjects: [NSNumber numberWithInt:kGKCommand_RequestDelay], nil];
                [self sendData:[NSKeyedArchiver archivedDataWithRootObject:request] withDataMode:GKSendDataReliable];
            }

            NSArray*    commands = [NSArray arrayWithObjects:
                                    [NSNumber numberWithInt:kGKCommand_Beacon],
                                    [NSNumber numberWithUnsignedLongLong:hostTime2NanoSec(mach_absolute_time())],
                                    nil];
            [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:GKSendDataUnreliable];
        }
    }
}

#pragma mark GKSessionDelegate
//  ---------------------------------------------------------------------------
//      receiveData:fromPeer:inSession:context
//  ---------------------------------------------------------------------------
- (void)receiveData:(NSData *)data fromPeer:(NSString *)peer inSession:(GKSession *)session context:(void *)context
{
    if (isMaster_)
    {
        [self receiveDataInMasterMode:data];
    }
    else
    {
        [self receiveDataInSlaveMode:data];
    }
}

//  ---------------------------------------------------------------------------
//      session:peer:didChangeState
//  ---------------------------------------------------------------------------
- (void)session:(GKSession *)session peer:(NSString *)peerID didChangeState:(GKPeerConnectionState)state
{
    switch (state)
    {
        case GKPeerStateAvailable:
            break;
        case GKPeerStateUnavailable:
            break;
        case GKPeerStateConnected:
            break;
        case GKPeerStateConnecting:
            break;
        case GKPeerStateDisconnected:
            if (!doDisconnectByMyself_)
            {
                NSString*   message = [NSString stringWithFormat:@"Lost connection with %@.", isMaster_ ? @"slave" : @"master"];
                UIAlertView*    alert = [[[UIAlertView alloc] initWithTitle:nil message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease];
                [alert show];
            }
            [self forceDisconnect];
            break;
        default:
            break;
    }
}

//  ---------------------------------------------------------------------------
//      session:didReceiveConnectionRequestFromPeer
//  ---------------------------------------------------------------------------
- (void)session:(GKSession *)session didReceiveConnectionRequestFromPeer:(NSString *)peerID
{
    isMaster_ = YES;
}

//  ---------------------------------------------------------------------------
//      session:connectionWithPeerFailed:withError
//  ---------------------------------------------------------------------------
- (void)session:(GKSession *)session connectionWithPeerFailed:(NSString *)peerID withError:(NSError *)error
{
    isMaster_ = NO;
}

//  ---------------------------------------------------------------------------
//      session:didFailWithError
//  ---------------------------------------------------------------------------
- (void)session:(GKSession *)session didFailWithError:(NSError *)error
{
    isMaster_ = NO;
}

#pragma mark GKPeerPickerControllerDelegate
//  ---------------------------------------------------------------------------
//      peerPickerControllerDidCancel
//  ---------------------------------------------------------------------------
- (void)peerPickerControllerDidCancel:(GKPeerPickerController *)picker
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(wistConnectionCancelled)])
    {
        [self.delegate performSelector:@selector(wistConnectionCancelled) withObject:nil];
    }
    [picker release];
    self.session = nil;
}

//  ---------------------------------------------------------------------------
//      peerPickerController:didConnectPeer:toSession
//  ---------------------------------------------------------------------------
- (void)peerPickerController:(GKPeerPickerController *)picker didConnectPeer:(NSString *)peerID toSession:(GKSession *)session
{
    [picker dismiss];
    [picker release];
    [self.session setDataReceiveHandler:self withContext:nil];
    isConnected_ = YES;

    if (self.delegate && [self.delegate respondsToSelector:@selector(wistConnectionEstablished)])
    {
        [self.delegate performSelector:@selector(wistConnectionEstablished) withObject:nil];
    }
}

//  ---------------------------------------------------------------------------
//      peerPickerController:sessionForConnectionType
//  ---------------------------------------------------------------------------
- (GKSession *)peerPickerController:(GKPeerPickerController *)picker sessionForConnectionType:(GKPeerPickerConnectionType)type 
{
    NSString*   sessionId = @"jp.co.korg.wireless-sync-1";  //  don't change this session id
    GKSession*  gk = [[[KorgGKSession alloc] initWithSessionID:sessionId displayName:nil sessionMode:GKSessionModePeer] autorelease];
    gk.delegate = self;
    self.session = gk;
    return self.session;
}

@end
