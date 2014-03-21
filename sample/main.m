//
//  main.m
//  WISTSample
//
//  Created by Nobuhisa Okamura on 11/05/19.
//  Copyright 2011 KORG INC. All rights reserved.
//

#import <UIKit/UIKit.h>

//  ---------------------------------------------------------------------------
//      main
//  ---------------------------------------------------------------------------
int
main(int argc, char *argv[])
{    
    NSAutoreleasePool*  pool = [[NSAutoreleasePool alloc] init];
    int retVal = UIApplicationMain(argc, argv, nil, nil);
    [pool release];
    return retVal;
}
