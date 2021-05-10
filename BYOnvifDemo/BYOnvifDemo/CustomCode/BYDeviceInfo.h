//
//  BYDeviceInfo.h
//  BYOnvifDemo
//
//  Created by Kystar's Mac Book Pro on 2021/5/10.
//

#ifndef BYDeviceInfo_h
#define BYDeviceInfo_h

#include "BYCommonDefine.h"

void cb_discovery(char *DeviceXAddr);
void ONVIF_DetectDevice(void (*cb)(char *DeviceXAddr));
int ONVIF_GetDeviceInformation(const char *DeviceXAddr);

#endif /* BYDeviceInfo_h */
