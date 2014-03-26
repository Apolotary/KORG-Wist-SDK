//
//  KorgWirelessSyncStart.h
//  WIST SDK Version 1.0.0
//
//  Portions contributed by Retronyms (www.retronyms.com).
//  Copyright 2011 KORG INC. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MultipeerConnectivity/MultipeerConnectivity.h>
#import <stdint.h>

@protocol KorgWirelessSyncStartDelegate <NSObject>

@required
//  Indicates a command was received from master
- (void)wistStartCommandReceived:(uint64_t)hostTime withTempo:(float)tempo;
- (void)wistStopCommandReceived:(uint64_t)hostTime;

@optional
//  Indicates a state change
- (void)wistConnectionCancelled;
- (void)wistConnectionEstablished;
- (void)wistConnectionLost;

@end

// Custom constants

extern NSString * const kSessionType;
extern NSString * const kServiceType;
extern NSString * const kMCFileReceivedNotification;
extern NSString * const kMCFileReceivedURL;

@interface KorgWirelessSyncStart : NSObject <MCSessionDelegate, MCBrowserViewControllerDelegate, MCAdvertiserAssistantDelegate>
{
@private
    id<KorgWirelessSyncStartDelegate> delegate;
    BOOL        isConnected_;
    BOOL        isMaster_;
    BOOL        doDisconnectByMyself_;
    uint64_t    delay_;
    uint64_t    peerDelay_;
    BOOL        gotPeerDelay_;
    uint64_t    gkWorstDelay_;
    BOOL        beaconReceived_;
    double      timeDiff_;
    uint64_t    latency_;
    uint64_t    peerLatency_;
    BOOL        gotPeerLatency_;
    NSTimer*    timer_;
}

@property (nonatomic, strong) MCBrowserViewController *browser;
@property (nonatomic, strong) MCPeerID *peerID;
@property (nonatomic, strong) MCAdvertiserAssistant *advertiser;
@property (nonatomic, strong) MCSession *session;

@property (nonatomic, weak) id<KorgWirelessSyncStartDelegate> delegate;
@property (nonatomic) uint64_t latency;     //  unit:nanosec
@property (nonatomic, readonly) BOOL isConnected;   //  connection status
@property (nonatomic, readonly) BOOL isMaster;      //  YES:master, NO:slave


-(void)setupPeerAndSessionWithDisplayName:(NSString *)displayName;
-(void)setupMCBrowser;
-(void)advertiseSelf:(BOOL)shouldAdvertise;

- (id)init;

//  search / connect to peer
- (void)searchPeer;
//  disconnect
- (void)disconnect;

//  [master] send a command to slave
- (void)sendStartCommand:(uint64_t)hostTime withTempo:(float)tempo;
- (void)sendStopCommand:(uint64_t)hostTime;

//  [master] calculate host time for local sequencer
- (uint64_t)estimatedLocalHostTime:(uint64_t)hostTime;

@end
