//
//  BYCommonDefine.h
//  BYOnvifDemo
//
//  Created by Kystar's Mac Book Pro on 2021/5/10.
//

#ifndef BYCommonDefine_h
#define BYCommonDefine_h

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include "soapH.h"
#include "wsaapi.h"
#include "wsseapi.h"

#define BYUSERNAME "admin"
#define BYPASSWORD "ky123456"
#define ONVIF_ADDRESS_SIZE 100

#define SOAP_ASSERT     assert
#define SOAP_DBGLOG     printf
#define SOAP_DBGERR     printf

#define SOAP_TO         "urn:schemas-xmlsoap-org:ws:2005:04:discovery"
#define SOAP_ACTION     "http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe"

#define SOAP_MCAST_ADDR "soap.udp://239.255.255.250:3702"                       // onvif规定的组播地址

#define SOAP_ITEM       ""                                                      // 寻找的设备范围
#define SOAP_TYPES      "dn:NetworkVideoTransmitter"                            // 寻找的设备类型

#define SOAP_SOCK_TIMEOUT    (10)                                               // socket超时时间（单秒秒）

#define SOAP_CHECK_ERROR(result, soap, str) \
    do { \
        if (SOAP_OK != (result) || SOAP_OK != (soap)->error) { \
            soap_perror((soap), (str)); \
            if (SOAP_OK == (result)) { \
                (result) = (soap)->error; \
            } \
            goto EXIT; \
        } \
} while (0)

enum PTZCMD
{
    PTZ_CMD_LEFT,
    PTZ_CMD_RIGHT,
    PTZ_CMD_UP,
    PTZ_CMD_DOWN,
    PTZ_CMD_LEFTUP,
    PTZ_CMD_LEFTDOWN,
    PTZ_CMD_RIGHTUP,
    PTZ_CMD_RIGHTDOWN,
    PTZ_CMD_ZOOM_IN,
    PTZ_CMD_ZOOM_OUT,
};

#endif /* BYCommonDefine_h */
