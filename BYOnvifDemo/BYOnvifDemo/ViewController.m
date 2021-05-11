//
//  ViewController.m
//  BYOnvifDemo
//
//  Created by Kystar's Mac Book Pro on 2021/5/10.
//

#import "ViewController.h"
#import "BYDeviceInfo.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    ONVIF_DetectDevice(cb_discovery);
    
    
}


@end
