//
//  AboutWISTViewController.h
//  WIST SDK Version 1.0.0
//
//  Portions contributed by Retronyms (www.retronyms.com).
//  Copyright 2011 KORG INC. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AboutWISTViewController : UIViewController <UIWebViewDelegate>
{
@private
    NSString*   pageUrl_;
    UIWebView*  webview_;
    UIActivityIndicatorView*    indicatorView_;
}

@end
