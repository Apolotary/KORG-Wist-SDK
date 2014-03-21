//
//  AboutWISTViewController.m
//  WIST SDK Version 1.0.0
//
//  Portions contributed by Retronyms (www.retronyms.com).
//  Copyright 2011 KORG INC. All rights reserved.
//

#import "AboutWISTViewController.h"

@implementation AboutWISTViewController

//  ---------------------------------------------------------------------------
//      dealloc
//  ---------------------------------------------------------------------------
- (void)dealloc
{
    self.view = nil;
    [super dealloc];
}

//  ---------------------------------------------------------------------------
//      reloadRequest
//  ---------------------------------------------------------------------------
-(void)reloadRequest
{
    NSURLRequest*   req = [NSURLRequest requestWithURL:[NSURL URLWithString:pageUrl_]];
    [webview_ loadRequest:req];
}

//  ---------------------------------------------------------------------------
//      loadView
//  ---------------------------------------------------------------------------
- (void)loadView
{
    pageUrl_ = @"http://www.korguser.net/wist/";
    
    webview_ = [[[UIWebView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease];
    webview_.delegate = self;
    webview_.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    webview_.scalesPageToFit = NO;
    self.view = webview_;

    indicatorView_ = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray] autorelease];
    indicatorView_.hidesWhenStopped = YES;
    indicatorView_.center = CGPointMake((int)self.view.bounds.size.width / 2, (int)self.view.bounds.size.height / 2);
    indicatorView_.autoresizingMask = (UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
                                       UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin);
    [self.view addSubview:indicatorView_];
}

//  ---------------------------------------------------------------------------
//      viewDidLoad
//  ---------------------------------------------------------------------------å
- (void)viewDidLoad
{
    [super viewDidLoad];
    [self reloadRequest];
}

//  ---------------------------------------------------------------------------
//      shouldAutorotateToInterfaceOrientation
//  ---------------------------------------------------------------------------
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return UIDeviceOrientationIsValidInterfaceOrientation(interfaceOrientation);
}

//  ---------------------------------------------------------------------------
//      didReceiveMemoryWarning
//  ---------------------------------------------------------------------------
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

//  ---------------------------------------------------------------------------
//      viewDidUnload
//  ---------------------------------------------------------------------------
- (void)viewDidUnload
{
}

#pragma mark UIWebViewDelegate
//  ---------------------------------------------------------------------------
//      webView:shouldStartLoadWithRequest:navigationType
//  ---------------------------------------------------------------------------
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    BOOL    result = YES;
    NSURL*  url = [request URL];
    if ([[url scheme] isEqualToString:@"file"])
    {
    }
    else
    {
        if ([[url absoluteString] hasPrefix:pageUrl_])
        {
        }
        else
        {
            UIApplication*  app = [UIApplication sharedApplication];
            if ([app canOpenURL:url])
            {
                [app openURL:url];
                result = NO;
            }
        }
    }
    return result;
}

//  ---------------------------------------------------------------------------
//      webViewDidStartLoad
//  ---------------------------------------------------------------------------
- (void)webViewDidStartLoad:(UIWebView *)webView
{
    [indicatorView_ startAnimating];
    indicatorView_.hidden = NO;
}

//  ---------------------------------------------------------------------------
//      webViewDidFinishLoad
//  ---------------------------------------------------------------------------
- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [indicatorView_ stopAnimating];
}

//  ---------------------------------------------------------------------------
//      webView:didFailLoadWithError
//  ---------------------------------------------------------------------------
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    NSString*   errorHtmlStr = @"<html>"
        "<head>"
        "<title>Network Error</title>"
        ""
        "<style>"
        "body {"
        "background: white;"
        "margin: 0;"
        "padding: 0;"
        "font-family: Helvetica, sans-serif;"
        "}"
        "div#wrapper {"
        "text-align: center;"
        "width: 75%;"
        "margin: 20px auto 20px auto;"
        "padding: 20px;"
        "background: #eeeeee;"
        "color: #333333;"
        "text-shadow: white 0 1px 0;"
        "-moz-border-radius: 8px;"
        "border-radius: 8px;"
        "border: 1px #cccccc solid;"
        "}"
        "</style>"
        ""
        "</head>"
        "<body>"
        "<div id=\"wrapper\">"
        "<h2>What is WIST?</h2>"
        "<p><strong>Korg’s WIST</strong> allows for wireless sync-start between compatible apps on nearby iPads and iPhones."
        "You can now sync with your friend’s device to create a dynamic live performance using two WIST-compatible apps.</p>"
        "<p style=\"color:#cc0000\">Connect to the internet to find out what apps are compatible.</p>"
        "</div>"
        "</body>"
        "</html>";

    [indicatorView_ stopAnimating];

    BOOL    ignoreErr = NO;
    if ([[error domain] isEqualToString:NSURLErrorDomain])
    {
        if ([error code] == NSURLErrorCancelled)
        {
            ignoreErr = YES;
        }
    }
    if (!ignoreErr)
    {
        [webview_ loadHTMLString:errorHtmlStr baseURL:[[NSBundle mainBundle] resourceURL]];
    }
}

@end
