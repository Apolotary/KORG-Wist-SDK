//
//  WISTSampleAppDelegate.h
//  WISTSample
//
//  Created by Nobuhisa Okamura on 11/05/19.
//  Copyright 2011 KORG INC. All rights reserved.
//

#import <UIKit/UIKit.h>

@class WISTSampleViewController;

@interface WISTSampleAppDelegate : NSObject <UIApplicationDelegate>
{
    UIWindow*   window;
    WISTSampleViewController*   viewController;
}

@property (nonatomic, retain) IBOutlet UIWindow*    window;
@property (nonatomic, retain) IBOutlet WISTSampleViewController*    viewController;

@end

