//
//  WISTSampleViewController.mm
//  WISTSample
//
//  Created by Nobuhisa Okamura on 11/06/22.
//  Copyright 2011 KORG INC. All rights reserved.
//

#import <mach/mach_time.h>
#import "WISTSampleViewController.h"
#import "KorgWirelessSyncStart.h"
#import "AudioIO.h"
#import "Synthesizer.h"
#import "AboutWISTViewController.h"

@interface WISTSampleViewController()
@property (nonatomic, assign) float tempo;
- (void)updateTempoUI:(BOOL)animated;
- (void)updateWistUI:(BOOL)animated;
@end

@implementation WISTSampleViewController

@synthesize wistSwitch;
@synthesize startButton;
@synthesize stopButton;
@synthesize aboutButton;
@synthesize tempoSlider;
@synthesize tempoText;
@synthesize statusLabel;
@synthesize tempo = tempo_;

//  ---------------------------------------------------------------------------
//      initWithNibName:bundle
//  ---------------------------------------------------------------------------
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self != nil)
    {
        self.tempo = 120.0f;

        wist_ = [[KorgWirelessSyncStart alloc] init];
        wist_.delegate = self;

        const float fs = 44100.0f;
        synth_ = new Synthesizer(fs);
        audioIo_ = new AudioIO(fs);
        audioIo_->SetListener(synth_);
        audioIo_->Open();
        audioIo_->Start();
    }
    return self;
}

//  ---------------------------------------------------------------------------
//      releaseOutlets
//  ---------------------------------------------------------------------------
- (void)releaseOutlets
{
    self.wistSwitch = nil;
    self.startButton = nil;
    self.stopButton = nil;
    self.aboutButton = nil;
    self.tempoSlider = nil;
    self.tempoText = nil;
    self.statusLabel = nil;
}

//  ---------------------------------------------------------------------------
//      dealloc
//  ---------------------------------------------------------------------------
- (void)dealloc
{
    delete audioIo_;
    audioIo_ = NULL;
    delete synth_;
    synth_ = NULL;

    [wist_ release];
    wist_ = nil;

    [self releaseOutlets];

    [super dealloc];
}

//  ---------------------------------------------------------------------------
//      viewDidLoad
//  ---------------------------------------------------------------------------
- (void)viewDidLoad
{
    [super viewDidLoad];
}

//  ---------------------------------------------------------------------------
//      viewWillAppear
//  ---------------------------------------------------------------------------
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self updateTempoUI:NO];
    [self updateWistUI:NO];
}

//  ---------------------------------------------------------------------------
//      viewDidUnload
//  ---------------------------------------------------------------------------
- (void)viewDidUnload
{
    [self releaseOutlets];
}

//  ---------------------------------------------------------------------------
//      shouldAutorotateToInterfaceOrientation
//  ---------------------------------------------------------------------------
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return UIInterfaceOrientationIsLandscape(interfaceOrientation);
}

//  ---------------------------------------------------------------------------
//      didReceiveMemoryWarning
//  ---------------------------------------------------------------------------
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

//  ---------------------------------------------------------------------------
//      updateTempoUI
//  ---------------------------------------------------------------------------
- (void)updateTempoUI:(BOOL)animated
{
    [tempoSlider setValue:self.tempo animated:animated];
    self.tempoText.text = [NSString stringWithFormat:@"%3.1f", self.tempo];
}

//  ---------------------------------------------------------------------------
//      updateWistUI
//  ---------------------------------------------------------------------------
- (void)updateWistUI:(BOOL)animated
{
    [self.wistSwitch setOn:wist_.isConnected animated:animated];
    self.statusLabel.text = wist_.isConnected ? (wist_.isMaster ? @"Master mode" : @"Slave mode") : @"";
}

#pragma mark -
//  ---------------------------------------------------------------------------
//      setTempo
//  ---------------------------------------------------------------------------
- (void)setTempo:(float)value
{
    tempo_ = static_cast<float>(static_cast<int>(value * 10)) / 10;
}

//  ---------------------------------------------------------------------------
//      disconnectWist
//  ---------------------------------------------------------------------------
- (void)disconnectWist
{
    [wist_ disconnect];
}

//  ---------------------------------------------------------------------------
//      latency
//  ---------------------------------------------------------------------------
- (uint64_t)latency
{
    uint64_t    result = 0;
    if (audioIo_ != NULL)
    {
        result += audioIo_->GetLatency();  //  audio i/o latency
    }
    return result;  //  nanosec
}

//  ---------------------------------------------------------------------------
//      startLocalSequence
//  ---------------------------------------------------------------------------
- (void)startLocalSequence:(uint64_t)hostTime
{
    if (synth_ != NULL)
    {
        synth_->StartSequence(hostTime, self.tempo);
    }
}

//  ---------------------------------------------------------------------------
//      stopLocalSequence
//  ---------------------------------------------------------------------------
- (void)stopLocalSequence:(uint64_t)hostTime
{
    if (synth_ != NULL)
    {
        synth_->StopSequence(hostTime);
    }
}

//  ---------------------------------------------------------------------------
//      wistOn
//  ---------------------------------------------------------------------------
- (void)wistOn
{
    if (!wist_.isConnected)
    {
        wist_.latency = [self latency];
        [wist_ searchPeer];
    }
}

//  ---------------------------------------------------------------------------
//      wistOff
//  ---------------------------------------------------------------------------
- (void)wistOff
{
    if (wist_.isConnected)
    {
        [wist_ disconnect];
    }
}

#pragma mark action
//  ---------------------------------------------------------------------------
//      wistSwitchPushed
//  ---------------------------------------------------------------------------
- (IBAction)wistSwitchPushed:(id)sender
{
    if (((UISwitch*)sender).on)
    {
        [self wistOn];
    }
    else 
    {
        [self wistOff];
    }
}

//  ---------------------------------------------------------------------------
//      now
//  ---------------------------------------------------------------------------
- (uint64_t)now
{
    return mach_absolute_time();
}

//  ---------------------------------------------------------------------------
//      startButtonPushed
//  ---------------------------------------------------------------------------
- (IBAction)startButtonPushed:(id)sender
{
    if (wist_.isConnected && wist_.isMaster)  //  In MASTER mode, send command to SLAVE
    {
        //  sync start
        const uint64_t  hostTime = [self now];
        [self startLocalSequence:[wist_ estimatedLocalHostTime:hostTime]];  //  local
        [wist_ sendStartCommand:hostTime withTempo:self.tempo];             //  remote
    }
    else
    {
        [self startLocalSequence:[self now]];
    }
}

//  ---------------------------------------------------------------------------
//      stopButtonPushed
//  ---------------------------------------------------------------------------
- (IBAction)stopButtonPushed:(id)sender
{
    if (wist_.isConnected && wist_.isMaster)  //  In MASTER mode, send command to SLAVE
    {
        //  sync stop
        const uint64_t  hostTime = [self now];
        [self stopLocalSequence:[wist_ estimatedLocalHostTime:hostTime]];   //  local
        [wist_ sendStopCommand:hostTime];                                   //  remote
    }
    else
    {
        [self stopLocalSequence:[self now]];
    }
}

//  ---------------------------------------------------------------------------
//      closeAboutButtonPushed
//  ---------------------------------------------------------------------------
- (void)closeAboutButtonPushed:(id)sender
{
    [self dismissModalViewControllerAnimated:YES];
}

//  ---------------------------------------------------------------------------
//      aboutButtonPushed
//  ---------------------------------------------------------------------------
- (IBAction)aboutButtonPushed:(id)sender
{
    AboutWISTViewController*    aboutController = [[[AboutWISTViewController alloc] init] autorelease];
    aboutController.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone 
                                                                                                       target:self
                                                                                                       action:@selector(closeAboutButtonPushed:)] autorelease];
    UINavigationController* nav = [[[UINavigationController alloc] initWithRootViewController:aboutController] autorelease];
    [self presentModalViewController:nav animated:YES];
}

//  ---------------------------------------------------------------------------
//      tempoSliderChanged
//  ---------------------------------------------------------------------------
- (IBAction)tempoSliderChanged:(id)sender
{
    self.tempo = ((UISlider*)sender).value;
    [self updateTempoUI:NO];
}

#pragma mark -
#pragma mark @protocol KorgWirelessSyncStartDelegate
//  ---------------------------------------------------------------------------
//      wistStartCommandReceived:withTempo
//  ---------------------------------------------------------------------------
- (void)wistStartCommandReceived:(uint64_t)hostTime withTempo:(float)tempo
{
    //  (In SLAVE mode) received start command from MASTER
    self.tempo = tempo;
    [self startLocalSequence:hostTime];

    [self updateTempoUI:YES];
}

//  ---------------------------------------------------------------------------
//      wistStopCommandReceived
//  ---------------------------------------------------------------------------
- (void)wistStopCommandReceived:(uint64_t)hostTime
{
    //  (In SLAVE mode) received stop command from MASTER
    [self stopLocalSequence:hostTime];
}

//  ---------------------------------------------------------------------------
//      wistConnectionCancelled (@optional)
//  ---------------------------------------------------------------------------
- (void)wistConnectionCancelled
{
    [self updateWistUI:YES];
}

//  ---------------------------------------------------------------------------
//      wistConnectionEstablished (@optional)
//  ---------------------------------------------------------------------------
- (void)wistConnectionEstablished
{
    [self updateWistUI:YES];
}

//  ---------------------------------------------------------------------------
//      wistConnectionLost (@optional)
//  ---------------------------------------------------------------------------
- (void)wistConnectionLost
{
    [self updateWistUI:YES];
}

@end
