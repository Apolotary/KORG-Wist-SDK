//
//  KorgWirelessSyncStart.m
//  WIST SDK Version 1.0.0
//
//  Portions contributed by Retronyms (www.retronyms.com).
//  Copyright 2011 KORG INC. All rights reserved.
//

#import <mach/mach_time.h>
#import "KorgWirelessSyncStart.h"

//@interface KorgGKSession : M
//@end
//
//@implementation KorgGKSession
//- (void)denyConnectionFromPeer:(NSString *)peerID
//{
//    [super denyConnectionFromPeer:peerID];
//    [self.delegate session:self connectionWithPeerFailed:peerID withError:nil];
//}
//@end


NSString * const kSessionType = @"wist-session";
NSString * const kMCFileReceivedNotification = @"FileReceivedNotification";
NSString * const kMCFileReceivedURL = @"FileReceivedURL";
NSString * const kServiceType = @"wist-service";

@interface KorgWirelessSyncStart()

@property (nonatomic, strong) NSMutableArray *mutableBlockedPeers;

- (void)resetTime;
- (void)forceDisconnect;
- (void)timerFired:(NSTimer*)timer;

@end

@implementation KorgWirelessSyncStart

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

#pragma mark - Init, dealloc and reset methods

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
        
        _peerID = nil;
        _session = nil;
        _browser = nil;
        _advertiser = nil;
        _mutableBlockedPeers = [NSMutableArray array];
    }
    return self;
}

//  ---------------------------------------------------------------------------
//      dealloc
//  ---------------------------------------------------------------------------
- (void)dealloc
{
    [timer_ invalidate];
    [self forceDisconnect];

    self.delegate = nil;
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

    [self.session disconnect];
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

#pragma mark - Public method implementation

-(void)setupPeerAndSessionWithDisplayName:(NSString *)displayName
{
    _peerID = [[MCPeerID alloc] initWithDisplayName:displayName];
    [_mutableBlockedPeers addObject:_peerID];
    
    _session = [[MCSession alloc] initWithPeer:_peerID];
    _session.delegate = self;
}


-(void)setupMCBrowser
{
    _browser = [[MCBrowserViewController alloc] initWithServiceType:kServiceType session:_session];
    [_browser setMinimumNumberOfPeers:0];
    _browser.delegate = self;
}


-(void)advertiseSelf:(BOOL)shouldAdvertise
{
    if (shouldAdvertise)
    {
        _advertiser = [[MCAdvertiserAssistant alloc] initWithServiceType:kServiceType discoveryInfo:nil session:_session];
        [_advertiser start];
    }
    else
    {
        [_advertiser stop];
        _advertiser = nil;
    }
}

#pragma mark - Connecting and sending data
//  ---------------------------------------------------------------------------
//      sendData:withDataMode
//  ---------------------------------------------------------------------------
- (void)sendData:(NSData *)data withDataMode:(MCSessionSendDataMode)dataMode
{
    if (isConnected_)
    {
        NSError*    error = nil;
        const BOOL  sent = [self.session sendData:data toPeers:self.session.connectedPeers withMode:dataMode error:&error];
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
            [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:MCSessionSendDataReliable];
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
                [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:MCSessionSendDataReliable];
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
                    [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:MCSessionSendDataUnreliable];
                }
                break;
            case kGKCommand_RequestDelay:
                {
                    NSArray*    commands = [NSArray arrayWithObjects:[NSNumber numberWithInt:kGKCommand_Delay],
                                            [NSNumber numberWithUnsignedLongLong:delay_],
                                            nil];
                    [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:MCSessionSendDataReliable];
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
        [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:MCSessionSendDataReliable];
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
        [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:MCSessionSendDataReliable];
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
            [self sendData:[NSKeyedArchiver archivedDataWithRootObject:request] withDataMode:MCSessionSendDataReliable];
        }
        if (isMaster_)
        {
            if (!gotPeerDelay_)
            {
                NSArray*    request = [NSArray arrayWithObjects: [NSNumber numberWithInt:kGKCommand_RequestDelay], nil];
                [self sendData:[NSKeyedArchiver archivedDataWithRootObject:request] withDataMode:MCSessionSendDataReliable];
            }

            NSArray*    commands = [NSArray arrayWithObjects:
                                    [NSNumber numberWithInt:kGKCommand_Beacon],
                                    [NSNumber numberWithUnsignedLongLong:hostTime2NanoSec(mach_absolute_time())],
                                    nil];
            [self sendData:[NSKeyedArchiver archivedDataWithRootObject:commands] withDataMode:MCSessionSendDataUnreliable];
        }
    }
}

#pragma mark - MCSessionDelegate

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID
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

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state;
{
    switch (state)
    {
        case MCSessionStateConnected:
            break;
        case MCSessionStateConnecting:
            break;
        case MCSessionStateNotConnected:
            if (!doDisconnectByMyself_)
            {
                NSString*   message = [NSString stringWithFormat:@"Lost connection with %@.", isMaster_ ? @"slave" : @"master"];
                UIAlertView*    alert = [[UIAlertView alloc] initWithTitle:nil message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
                [alert show];
            }
            [self forceDisconnect];
            break;
        default:
            break;
    }
}

// Received a byte stream from remote peer
- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)streamName fromPeer:(MCPeerID *)peerID
{
    
}

// Start receiving a resource from remote peer
- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID withProgress:(NSProgress *)progress
{
    NSLog(@"Receiving file: %@ from: %@", resourceName, peerID.displayName);
}

// Finished receiving a resource from remote peer and saved the content in a temporary location - the app is responsible for moving the file to a permanent location within its sandbox
- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID atURL:(NSURL *)localURL withError:(NSError *)error
{
    NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentPath = [searchPaths objectAtIndex:0];
    
    NSURL *destinationURL = [NSURL fileURLWithPath:documentPath];
    
    NSError *managerError;
    
    if (![[NSFileManager defaultManager] moveItemAtURL:localURL
                                                 toURL:destinationURL
                                                 error:&managerError]) {
        NSLog(@"[Error] %@", managerError);
    }
    
    NSURL *resultURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", destinationURL.absoluteString, resourceName]];
    NSLog(@"result url: %@", resultURL.absoluteString);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kMCFileReceivedNotification object:nil userInfo:@{kMCFileReceivedURL : resultURL}];
}

#pragma mark - Browser delegate

- (void)browserViewControllerDidFinish:(MCBrowserViewController *)browserViewController
{
    isMaster_ = YES;
    isConnected_ = YES;
    if (self.delegate && [self.delegate respondsToSelector:@selector(wistConnectionEstablished)])
    {
        [self.delegate performSelector:@selector(wistConnectionEstablished) withObject:nil];
    }
    [_browser dismissViewControllerAnimated:YES completion:nil];
}

- (void)browserViewControllerWasCancelled:(MCBrowserViewController *)browserViewController
{
    isMaster_ = NO;
    if (self.delegate && [self.delegate respondsToSelector:@selector(wistConnectionCancelled)])
    {
        [self.delegate performSelector:@selector(wistConnectionCancelled) withObject:nil];
    }

    [_browser dismissViewControllerAnimated:YES completion:nil];
}



@end
