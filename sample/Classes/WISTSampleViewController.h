//
//  WISTSampleViewController.h
//  WISTSample
//
//  Created by Nobuhisa Okamura on 11/06/22.
//  Copyright 2011 KORG INC. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "KorgWirelessSyncStart.h"

@class KorgWirelessSyncStart;

@interface WISTSampleViewController : UIViewController <KorgWirelessSyncStartDelegate>
{
    IBOutlet UISwitch*  wistSwitch;
    IBOutlet UIButton*  startButton;
    IBOutlet UIButton*  stopButton;
    IBOutlet UIButton*  aboutButton;
    IBOutlet UISlider*  tempoSlider;
    IBOutlet UITextField*   tempoText;
    IBOutlet UILabel*   statusLabel;

    float   tempo_;

    KorgWirelessSyncStart*  wist_;
    class Synthesizer*      synth_;
    class AudioIO*          audioIo_;
}

@property (nonatomic, retain) UISwitch* wistSwitch;
@property (nonatomic, retain) UIButton* startButton;
@property (nonatomic, retain) UIButton* stopButton;
@property (nonatomic, retain) UIButton* aboutButton;
@property (nonatomic, retain) UISlider* tempoSlider;
@property (nonatomic, retain) UITextField* tempoText;
@property (nonatomic, retain) UILabel* statusLabel;

- (IBAction)wistSwitchPushed:(id)sender;
- (IBAction)startButtonPushed:(id)sender;
- (IBAction)stopButtonPushed:(id)sender;
- (IBAction)aboutButtonPushed:(id)sender;
- (IBAction)tempoSliderChanged:(id)sender;

- (void)disconnectWist;

@end
