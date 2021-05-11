//
//  BYDeviceInfo.h
//  BYOnvifDemo
//
//  Created by Kystar's Mac Book Pro on 2021/5/10.
//

#ifndef BYDeviceInfo_h
#define BYDeviceInfo_h

#include "BYCommonDefine.h"

int ONVIF_GetProfiles(const char *DeviceXAddr);
int ONVIF_GetCapabilities(const char *DeviceXAddr);
int ONVIF_GetSystemDateAndTime(const char *DeviceXAddr);
void ONVIF_GetHostTimeZone(char *TZ, int sizeTZ);
int ONVIF_SetSystemDateAndTime(const char *DeviceXAddr);
int ONVIF_GetStreamUri(const char *MediaXAddr, char *ProfileToken, char *uri, unsigned int sizeuri);
void cb_discovery(char *DeviceXAddr);
int ONVIF_SetSystemDateAndTime(const char *DeviceXAddr);
void ONVIF_DetectDevice(void (*cb)(char *DeviceXAddr));
int ONVIF_GetDeviceInformation(const char *DeviceXAddr);

#endif /* BYDeviceInfo_h */
