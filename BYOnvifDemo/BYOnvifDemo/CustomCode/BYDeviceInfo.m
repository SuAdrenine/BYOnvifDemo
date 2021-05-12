//
//  BYDeviceInfo.c
//  BYOnvifDemo
//
//  Created by Kystar's Mac Book Pro on 2021/5/10.
//

#include "BYDeviceInfo.h"
#import <Foundation/Foundation.h>

void soap_perror(struct soap *soap, const char *str)
{
    if (NULL == str) {
        SOAP_DBGERR("[soap] error: %d, %s, %s\n", soap->error, *soap_faultcode(soap), *soap_faultstring(soap));
    } else {
        SOAP_DBGERR("[soap] %s error: %d, %s, %s\n", str, soap->error, *soap_faultcode(soap), *soap_faultstring(soap));
    }
    return;
}

void* ONVIF_soap_malloc(struct soap *soap, unsigned int n)
{
    void *p = NULL;
    
    if (n > 0) {
        p = soap_malloc(soap, n);
        SOAP_ASSERT(NULL != p);
        memset(p, 0x00 ,n);
    }
    return p;
}

struct soap *ONVIF_soap_new(int timeout)
{
    struct soap *soap = NULL;                                                   // soap环境变量
    
    SOAP_ASSERT(NULL != (soap = soap_new()));
    
    soap_set_namespaces(soap, namespaces);                                      // 设置soap的namespaces
    soap->recv_timeout    = timeout;                                            // 设置超时（超过指定时间没有数据就退出）
    soap->send_timeout    = timeout;
    soap->connect_timeout = timeout;
    
#if defined(__linux__) || defined(__linux)                                      // 参考https://www.genivia.com/dev.html#client-c的修改：
    soap->socket_flags = MSG_NOSIGNAL;                                          // To prevent connection reset errors
#endif
    
    soap_set_mode(soap, SOAP_C_UTFSTRING);                                      // 设置为UTF-8编码，否则叠加中文OSD会乱码
    
    return soap;
}

void ONVIF_soap_delete(struct soap *soap)
{
    soap_destroy(soap);                                                         // remove deserialized class instances (C++ only)
    soap_end(soap);                                                             // Clean up deserialized data (except class instances) and temporary data
    soap_done(soap);                                                            // Reset, close communications, and remove callbacks
    soap_free(soap);                                                            // Reset and deallocate the context created with soap_new or soap_copy
}

/************************************************************************
 **函数：ONVIF_init_header
 **功能：初始化soap描述消息头
 **参数：
 [in] soap - soap环境变量
 **返回：无
 **备注：
 1). 在本函数内部通过ONVIF_soap_malloc分配的内存，将在ONVIF_soap_delete中被释放
 ************************************************************************/
void ONVIF_init_header(struct soap *soap)
{
    struct SOAP_ENV__Header *header = NULL;
    
    SOAP_ASSERT(NULL != soap);
    
    header = (struct SOAP_ENV__Header *)ONVIF_soap_malloc(soap, sizeof(struct SOAP_ENV__Header));
    soap_default_SOAP_ENV__Header(soap, header);
    header->wsa__MessageID = (char*)soap_wsa_rand_uuid(soap);
    header->wsa__To        = (char*)ONVIF_soap_malloc(soap, strlen(SOAP_TO) + 1);
    header->wsa__Action    = (char*)ONVIF_soap_malloc(soap, strlen(SOAP_ACTION) + 1);
    strcpy(header->wsa__To, SOAP_TO);
    strcpy(header->wsa__Action, SOAP_ACTION);
    soap->header = header;
    
    return;
}

/************************************************************************
 **函数：ONVIF_init_ProbeType
 **功能：初始化探测设备的范围和类型
 **参数：
 [in]  soap  - soap环境变量
 [out] probe - 填充要探测的设备范围和类型
 **返回：
 0表明探测到，非0表明未探测到
 **备注：
 1). 在本函数内部通过ONVIF_soap_malloc分配的内存，将在ONVIF_soap_delete中被释放
 ************************************************************************/
void ONVIF_init_ProbeType(struct soap *soap, struct wsdd__ProbeType *probe)
{
    struct wsdd__ScopesType *scope = NULL;                                      // 用于描述查找哪类的Web服务
    
    SOAP_ASSERT(NULL != soap);
    SOAP_ASSERT(NULL != probe);
    
    scope = (struct wsdd__ScopesType *)ONVIF_soap_malloc(soap, sizeof(struct wsdd__ScopesType));
    soap_default_wsdd__ScopesType(soap, scope);                                 // 设置寻找设备的范围
    scope->__item = (char*)ONVIF_soap_malloc(soap, strlen(SOAP_ITEM) + 1);
    strcpy(scope->__item, SOAP_ITEM);
    
    memset(probe, 0x00, sizeof(struct wsdd__ProbeType));
    soap_default_wsdd__ProbeType(soap, probe);
    probe->Scopes = scope;
    probe->Types  = (char*)ONVIF_soap_malloc(soap, strlen(SOAP_TYPES) + 1);     // 设置寻找设备的类型
    strcpy(probe->Types, SOAP_TYPES);
    
    return;
}

void ONVIF_DetectDevice(void (*cb)(char *DeviceXAddr))
{
    int i;
    int result = 0;
    unsigned int count = 0;                                                     // 搜索到的设备个数
    struct soap *soap = NULL;                                                   // soap环境变量
    struct wsdd__ProbeType      req;                                            // 用于发送Probe消息
    struct __wsdd__ProbeMatches rep;                                            // 用于接收Probe应答
    struct wsdd__ProbeMatchType *probeMatch;
    
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    ONVIF_init_header(soap);                                                    // 设置消息头描述
    ONVIF_init_ProbeType(soap, &req);                                           // 设置寻找的设备的范围和类型
    result = soap_send___wsdd__Probe(soap, SOAP_MCAST_ADDR, NULL, &req);        // 向组播地址广播Probe消息
    while (SOAP_OK == result)                                                   // 开始循环接收设备发送过来的消息
    {
        memset(&rep, 0x00, sizeof(rep));
        result = soap_recv___wsdd__ProbeMatches(soap, &rep);
        if (SOAP_OK == result) {
            if (soap->error) {
                soap_perror(soap, "ProbeMatches");
            } else {                                                            // 成功接收到设备的应答消息
                if (NULL != rep.wsdd__ProbeMatches) {
                    SOAP_DBGLOG("===>\n%s\n<===\n",rep.wsdd__ProbeMatches->ProbeMatch->XAddrs);
                    
                    count += rep.wsdd__ProbeMatches->__sizeProbeMatch;
                    for(i = 0; i < rep.wsdd__ProbeMatches->__sizeProbeMatch; i++) {
                        probeMatch = rep.wsdd__ProbeMatches->ProbeMatch + i;
                        if (NULL != cb) {
                            cb(probeMatch->XAddrs);                             // 使用设备服务地址执行函数回调
                            
                            ONVIF_GetSystemDateAndTime(probeMatch->XAddrs);
                            
                            ONVIF_GetCapabilities(probeMatch->XAddrs);
                            
//                            ONVIF_PTZContinuousMove(probeMatch->XAddrs, "", PTZ_CMD_LEFTUP, 0.3);
                            ONVIF_PTZStopMove(probeMatch->XAddrs, "");
                            
                        }
                    }
                }
            }
        } else if (soap->error) {
            break;
        }
    }
    
    SOAP_DBGLOG("\ndetect end! It has detected %d devices!\n", count);
    
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    
    return ;
}

/************************************************************************
 **函数：ONVIF_SetAuthInfo
 **功能：设置认证信息
 **参数：
 [in] soap     - soap环境变量
 [in] username - 用户名
 [in] password - 密码
 **返回：
 0表明成功，非0表明失败
 **备注：
 ************************************************************************/
int ONVIF_SetAuthInfo(struct soap *soap, const char *username, const char *password)
{
    int result = 0;
    
    SOAP_ASSERT(NULL != username);
    SOAP_ASSERT(NULL != password);
    
    result = soap_wsse_add_UsernameTokenDigest(soap, NULL, username, password);
    SOAP_CHECK_ERROR(result, soap, "add_UsernameTokenDigest");
    
EXIT:
    
    return result;
}

/************************************************************************
 **函数：ONVIF_GetDeviceInformation
 **功能：获取设备基本信息
 **参数：
 [in] DeviceXAddr - 设备服务地址
 **返回：
 0表明成功，非0表明失败
 **备注：
 ************************************************************************/
int ONVIF_GetDeviceInformation(const char *DeviceXAddr)
{
    int result = 0;
    struct soap *soap = NULL;
    struct _tds__GetDeviceInformation           devinfo_req;
    struct _tds__GetDeviceInformationResponse   devinfo_resp;
    
    SOAP_ASSERT(NULL != DeviceXAddr);
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    
    memset(&devinfo_req, 0x00, sizeof(devinfo_req));
    memset(&devinfo_resp, 0x00, sizeof(devinfo_resp));
    result = soap_call___tds__GetDeviceInformation(soap, DeviceXAddr, NULL, &devinfo_req, &devinfo_resp);
    SOAP_CHECK_ERROR(result, soap, "GetDeviceInformation");
    
    SOAP_DBGLOG("===>\n%s\n<===\n",devinfo_resp.SerialNumber);
    
EXIT:
    
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    return result;
}

void cb_discovery(char *DeviceXAddr)
{
    ONVIF_GetDeviceInformation(DeviceXAddr);
}

/************************************************************************
 **函数：ONVIF_GetSystemDateAndTime
 **功能：获取设备的系统时间
 **参数：
 [in] DeviceXAddr - 设备服务地址
 **返回：
 0表明成功，非0表明失败
 **备注：
 1). 对于IPC摄像头，OSD打印的时间是其LocalDateTime
 ************************************************************************/
int ONVIF_GetSystemDateAndTime(const char *DeviceXAddr)
{
    int result = 0;
    struct soap *soap = NULL;
    struct _tds__GetSystemDateAndTime         GetTm_req;
    struct _tds__GetSystemDateAndTimeResponse GetTm_resp;
    
    SOAP_ASSERT(NULL != DeviceXAddr);
    
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    
    memset(&GetTm_req, 0x00, sizeof(GetTm_req));
    memset(&GetTm_resp, 0x00, sizeof(GetTm_resp));
    result = soap_call___tds__GetSystemDateAndTime(soap, DeviceXAddr, NULL, &GetTm_req, &GetTm_resp);
    SOAP_CHECK_ERROR(result, soap, "GetSystemDateAndTime");
    struct tt__Date *Date = GetTm_resp.SystemDateAndTime->LocalDateTime->Date;
    struct tt__Time *Time = GetTm_resp.SystemDateAndTime->LocalDateTime->Time;
    SOAP_DBGLOG("===>\nLocal time :%d-%d-%d %d:%d:%d\n<===\n",Date->Year,Date->Month,Date->Day,Time->Hour, Time->Minute, Time->Second);
    
EXIT:
    
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    return result;
}

/************************************************************************
 **函数：ONVIF_GetHostTimeZone
 **功能：获取主机的时区信息
 **参数：
 [out] TZ    - 返回的时区信息
 [in] sizeTZ - TZ缓存大小
 **返回：无
 **备注：
 ************************************************************************/
void ONVIF_GetHostTimeZone(char *TZ, int sizeTZ)
{
    char timezone[20] = {0};
    
#ifdef WIN32
    
    TIME_ZONE_INFORMATION TZinfo;
    GetTimeZoneInformation(&TZinfo);
    sprintf(timezone, "GMT%c%02d:%02d",  (TZinfo.Bias <= 0) ? '+' : '-', labs(TZinfo.Bias) / 60, labs(TZinfo.Bias) % 60);
    
#else
    
    FILE *fp = NULL;
    char time_fmt[32] = {0};
    
    fp = popen("date +%z", "r");
    fread(time_fmt, sizeof(time_fmt), 1, fp);
    pclose(fp);
    
    if( ((time_fmt[0] == '+') || (time_fmt[0] == '-')) &&
       isdigit(time_fmt[1]) && isdigit(time_fmt[2]) && isdigit(time_fmt[3]) && isdigit(time_fmt[4]) ) {
        sprintf(timezone, "GMT%c%c%c:%c%c", time_fmt[0], time_fmt[1], time_fmt[2], time_fmt[3], time_fmt[4]);
    } else {
        strcpy(timezone, "GMT+08:00");
    }
    
#endif
    
    if (sizeTZ > strlen(timezone)) {
        strcpy(TZ, timezone);
    }
    return;
}

/************************************************************************
 **函数：ONVIF_SetSystemDateAndTime
 **功能：根据客户端主机当前时间，校时IPC的系统时间
 **参数：
 [in] DeviceXAddr - 设备服务地址
 **返回：
 0表明成功，非0表明失败
 **备注：
 1). 对于IPC摄像头，OSD打印的时间是其本地时间（本地时间跟时区息息相关），设置时间时一定要注意时区的正确性。
 ************************************************************************/
int ONVIF_SetSystemDateAndTime(const char *DeviceXAddr)
{
    int result = 0;
    struct soap *soap = NULL;
    struct _tds__SetSystemDateAndTime           SetTm_req;
    struct _tds__SetSystemDateAndTimeResponse   SetTm_resp;
    
    char TZ[20];                                                                // 用于获取客户端主机的时区信息（如"GMT+08:00"）
    time_t t;                                                                   // 用于获取客户端主机的UTC时间
    struct tm tm;
    
    SOAP_ASSERT(NULL != DeviceXAddr);
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    NSDateFormatter *df = [NSDateFormatter new];
    //        df.dateFormat = @"yyyy.MM.dd HH:mm:ss 'GMT'ZZZZZ";
    df.dateFormat = @"'GMT'ZZZZZ";
    NSString *dateString = [df stringFromDate:[NSDate date]];
    memcpy(TZ, [dateString cStringUsingEncoding:NSASCIIStringEncoding], 2*[dateString length]);// 获取客户端主机的时区信息
    //    ONVIF_GetHostTimeZone(TZ, sizeof(TZ));                                         // 获取客户端主机的时区信息
    
    t = time(NULL);                                                             // 获取客户端主机的UTC时间
#ifdef WIN32
    gmtime_s(&tm, &t);
#else
    gmtime_r(&t, &tm);
#endif
    
    memset(&SetTm_req, 0x00, sizeof(SetTm_req));
    memset(&SetTm_resp, 0x00, sizeof(SetTm_resp));
    SetTm_req.DateTimeType      = tt__SetDateTimeType__Manual;
    SetTm_req.DaylightSavings   = xsd__boolean__false_;
    SetTm_req.TimeZone          = (struct tt__TimeZone *)ONVIF_soap_malloc(soap, sizeof(struct tt__TimeZone));
    SetTm_req.UTCDateTime       = (struct tt__DateTime *)ONVIF_soap_malloc(soap, sizeof(struct tt__DateTime));
    SetTm_req.UTCDateTime->Date = (struct tt__Date *)ONVIF_soap_malloc(soap, sizeof(struct tt__Date));
    SetTm_req.UTCDateTime->Time = (struct tt__Time *)ONVIF_soap_malloc(soap, sizeof(struct tt__Time));
    
    SetTm_req.TimeZone->TZ              = TZ;                                   // 设置本地时区（IPC的OSD显示的时间就是本地时间）
    SetTm_req.UTCDateTime->Date->Year   = tm.tm_year + 1900;                    // 设置UTC时间（注意不是本地时间）
    SetTm_req.UTCDateTime->Date->Month  = tm.tm_mon + 1;
    SetTm_req.UTCDateTime->Date->Day    = tm.tm_mday;
    SetTm_req.UTCDateTime->Time->Hour   = tm.tm_hour;
    SetTm_req.UTCDateTime->Time->Minute = tm.tm_min;
    SetTm_req.UTCDateTime->Time->Second = tm.tm_sec;
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    result = soap_call___tds__SetSystemDateAndTime(soap, DeviceXAddr, NULL, &SetTm_req, &SetTm_resp);
    SOAP_CHECK_ERROR(result, soap, "SetSystemDateAndTime");
    
EXIT:
    
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    return result;
}

/************************************************************************
 **函数：ONVIF_GetCapabilities
 **功能：获取设备能力信息
 **参数：
 [in] DeviceXAddr - 设备服务地址
 **返回：
 0表明成功，非0表明失败
 **备注：
 1). 其中最主要的参数之一是媒体服务地址
 ************************************************************************/
int ONVIF_GetCapabilities(const char *DeviceXAddr)
{
    int result = 0;
    struct soap *soap = NULL;
    struct _tds__GetCapabilities            req;
    struct _tds__GetCapabilitiesResponse    rep;
    
    SOAP_ASSERT(NULL != DeviceXAddr);
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    
    memset(&req, 0x00, sizeof(req));
    memset(&rep, 0x00, sizeof(rep));
    result = soap_call___tds__GetCapabilities(soap, DeviceXAddr, NULL, &req, &rep);
    SOAP_CHECK_ERROR(result, soap, "GetCapabilities");
    
    SOAP_DBGLOG("===>\nDevice address : %s\n<===\n",rep.Capabilities->Device->XAddr);
    SOAP_DBGLOG("===>\nPTZ address : %s\n<===\n",rep.Capabilities->PTZ->XAddr);
    SOAP_DBGLOG("===>\nPTZ address : %s\n<===\n",rep.Capabilities->Media->XAddr);
    ONVIF_GetProfiles(rep.Capabilities->Media->XAddr);
EXIT:
    
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    return result;
}


/************************************************************************
 **函数：ONVIF_GetStreamUri
 **功能：获取设备码流地址(RTSP)
 **参数：
 [in]  MediaXAddr    - 媒体服务地址
 [in]  ProfileToken  - the media profile token
 [out] uri           - 返回的地址
 [in]  sizeuri       - 地址缓存大小
 **返回：
 0表明成功，非0表明失败
 **备注：
 ************************************************************************/
int ONVIF_GetStreamUri(const char *MediaXAddr, char *ProfileToken, char *uri, unsigned int sizeuri)
{
    int result = 0;
    struct soap *soap = NULL;
    struct tt__StreamSetup              ttStreamSetup;
    struct tt__Transport                ttTransport;
    struct _trt__GetStreamUri           req;
    struct _trt__GetStreamUriResponse   rep;
    
    SOAP_ASSERT(NULL != MediaXAddr);
    SOAP_ASSERT(NULL != uri);
    memset(uri, 0x00, sizeuri);
    
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    memset(&req, 0x00, sizeof(req));
    memset(&rep, 0x00, sizeof(rep));
    memset(&ttStreamSetup, 0x00, sizeof(ttStreamSetup));
    memset(&ttTransport, 0x00, sizeof(ttTransport));
    ttStreamSetup.Stream                = tt__StreamType__RTP_Unicast;
    ttStreamSetup.Transport             = &ttTransport;
    ttStreamSetup.Transport->Protocol   = tt__TransportProtocol__RTSP;
    ttStreamSetup.Transport->Tunnel     = NULL;
    req.StreamSetup                     = &ttStreamSetup;
    req.ProfileToken                    = ProfileToken;
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    result = soap_call___trt__GetStreamUri(soap, MediaXAddr, NULL, &req, &rep);
    SOAP_CHECK_ERROR(result, soap, "GetServices");
    
    SOAP_DBGLOG("===>\nGetStreamUri : %s\n<===\n",rep.MediaUri->Uri);
    
    result = -1;
    if (NULL != rep.MediaUri) {
        if (NULL != rep.MediaUri->Uri) {
            if (sizeuri > strlen(rep.MediaUri->Uri)) {
                strcpy(uri, rep.MediaUri->Uri);
                result = 0;
            } else {
                SOAP_DBGERR("Not enough cache!\n");
            }
        }
    }
    
EXIT:
    
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    
    return result;
}

void insertcharatindex(char *str, const char *pch, int pos) {
    long len = strlen(str);
    long nlen = strlen(pch);
    for (long i = len - 1; i >= pos; --i) {
        *(str + i + nlen) = *(str + i);
    }
    for (int n = 0; n < nlen;n++)
        *(str + pos + n) = *pch++;
    *(str + len + nlen) = 0;
}

void append_uri_withauthInfo(const char *uri, int len, const char *username, const char *password, char *uriAuth) {
    memcpy(uriAuth, uri, len);
    //rtsp://10.10.9.15:554/Streaming/Channels/101?transportmode=unicast&profile=Profile_1
    insertcharatindex(uriAuth, "@", 7);
    insertcharatindex(uriAuth, password, 7);
    insertcharatindex(uriAuth, ":", 7);
    insertcharatindex(uriAuth, username, 7);
    SOAP_DBGLOG("===>\nAppend StreamUri : %s\n<===\n",uriAuth);
}

int ONVIF_GetProfiles(const char *DeviceXAddr) {
    int result = 0;
    struct soap *soap = NULL;
    struct _trt__GetProfiles            req;
    struct _trt__GetProfilesResponse    rep;
    
    SOAP_ASSERT(NULL != DeviceXAddr);
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    
    memset(&req, 0x00, sizeof(req));
    memset(&rep, 0x00, sizeof(rep));
    result = soap_call___trt__GetProfiles(soap, DeviceXAddr, NULL, &req, &rep);
    
    char uri[ONVIF_ADDRESS_SIZE] = {0};                                         // 不带认证信息的URI地址
    char uri_auth[ONVIF_ADDRESS_SIZE + 50] = {0};                               // 带有认证信息的URI地址
    
    SOAP_CHECK_ERROR(result, soap, "GetProfiles");
    
    SOAP_DBGLOG("===>\nProfiles name : %s\n<===\n",rep.Profiles->Name);
    SOAP_DBGLOG("===>\nProfiles token : %s\n<===\n",rep.Profiles->token);
    
    ONVIF_GetStreamUri(DeviceXAddr, rep.Profiles->token, uri, sizeof(uri)); // 获取RTSP地址
    append_uri_withauthInfo(uri, sizeof(uri),BYUSERNAME, BYPASSWORD, uri_auth);
    
EXIT:
    
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    return result;
}

/************************************************************************
 **函数：ONVIF_GetVideoEncoderConfigurationOptions
 **功能：获取指定视频编码器配置的参数选项集
 **参数：
 [in] MediaXAddr   - 媒体服务地址
 [in] ConfigurationToken - 视频编码器配置的令牌字符串，如果为NULL，则获取所有视频编码器配置的选项集（会杂在一起，无法区分选项集是归属哪个视频编码配置器的）
 **返回：
 0表明成功，非0表明失败
 **备注：
 1). 有两种方式可以获取指定视频编码器配置的参数选项集：一种是根据ConfigurationToken，另一种是根据ProfileToken
 ************************************************************************/
int ONVIF_GetVideoEncoderConfigurationOptions(const char *MediaXAddr, char *ConfigurationToken)
{
    int result = 0;
    struct soap *soap = NULL;
    struct _trt__GetVideoEncoderConfigurationOptions          req;
    struct _trt__GetVideoEncoderConfigurationOptionsResponse  rep;
    
    SOAP_ASSERT(NULL != MediaXAddr);
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    memset(&req, 0x00, sizeof(req));
    memset(&rep, 0x00, sizeof(rep));
    req.ConfigurationToken = ConfigurationToken;
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    result = soap_call___trt__GetVideoEncoderConfigurationOptions(soap, MediaXAddr, NULL, &req, &rep);
    SOAP_CHECK_ERROR(result, soap, "GetVideoEncoderConfigurationOptions");
    
    SOAP_DBGLOG("===>\nMedia quality range : %d - %d\n<===\n",rep.Options->QualityRange->Min, rep.Options->QualityRange->Max);
    
EXIT:
    
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    
    return result;
}

/************************************************************************
 **函数：ONVIF_GetVideoEncoderConfiguration
 **功能：获取设备上指定的视频编码器配置信息
 **参数：
 [in] MediaXAddr - 媒体服务地址
 [in] ConfigurationToken - 视频编码器配置的令牌字符串
 **返回：
 0表明成功，非0表明失败
 **备注：
 ************************************************************************/
int ONVIF_GetVideoEncoderConfiguration(const char *MediaXAddr, char *ConfigurationToken)
{
    int result = 0;
    struct soap *soap = NULL;
    struct _trt__GetVideoEncoderConfiguration          req;
    struct _trt__GetVideoEncoderConfigurationResponse  rep;
    
    SOAP_ASSERT(NULL != MediaXAddr);
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    
    memset(&req, 0x00, sizeof(req));
    memset(&rep, 0x00, sizeof(rep));
    req.ConfigurationToken = ConfigurationToken;
    result = soap_call___trt__GetVideoEncoderConfiguration(soap, MediaXAddr, NULL, &req, &rep);
    SOAP_CHECK_ERROR(result, soap, "GetVideoEncoderConfiguration");
    
    SOAP_DBGLOG("===>\nVideoEncoder name : %s token : %s\n<===\n",rep.Configuration->Name, rep.Configuration->token);
    
EXIT:
    
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    
    return result;
}

struct tagVideoEncoderConfiguration {
    char *token;
    int Width;
    int Height;
};

/************************************************************************
 **函数：ONVIF_SetVideoEncoderConfiguration
 **功能：修改指定的视频编码器配置信息
 **参数：
 [in] MediaXAddr - 媒体服务地址
 [in] venc - 视频编码器配置信息
 **返回：
 0表明成功，非0表明失败
 **备注：
 1). 所设置的分辨率必须是GetVideoEncoderConfigurationOptions返回的“分辨率选项集”中的一种，否则调用SetVideoEncoderConfiguration会失败。
 ************************************************************************/
int ONVIF_SetVideoEncoderConfiguration(const char *MediaXAddr, struct tagVideoEncoderConfiguration *venc)
{
    int result = 0;
    struct soap *soap = NULL;
    
    struct _trt__GetVideoEncoderConfiguration           gVECfg_req;
    struct _trt__GetVideoEncoderConfigurationResponse   gVECfg_rep;
    
    struct _trt__SetVideoEncoderConfiguration           sVECfg_req;
    struct _trt__SetVideoEncoderConfigurationResponse   sVECfg_rep;
    
    SOAP_ASSERT(NULL != MediaXAddr);
    SOAP_ASSERT(NULL != venc);
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    memset(&gVECfg_req, 0x00, sizeof(gVECfg_req));
    memset(&gVECfg_rep, 0x00, sizeof(gVECfg_rep));
    gVECfg_req.ConfigurationToken = venc->token;
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    result = soap_call___trt__GetVideoEncoderConfiguration(soap, MediaXAddr, NULL, &gVECfg_req, &gVECfg_rep);
    SOAP_CHECK_ERROR(result, soap, "GetVideoEncoderConfiguration");
    
    if (NULL == gVECfg_rep.Configuration) {
        SOAP_DBGERR("video encoder configuration is NULL.\n");
        goto EXIT;
    }
    
    memset(&sVECfg_req, 0x00, sizeof(sVECfg_req));
    memset(&sVECfg_rep, 0x00, sizeof(sVECfg_rep));
    
    sVECfg_req.ForcePersistence = xsd__boolean__true_;
    sVECfg_req.Configuration    = gVECfg_rep.Configuration;
    
    if (NULL != sVECfg_req.Configuration->Resolution) {
        sVECfg_req.Configuration->Resolution->Width  = venc->Width;
        sVECfg_req.Configuration->Resolution->Height = venc->Height;
    }
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    result = soap_call___trt__SetVideoEncoderConfiguration(soap, MediaXAddr, NULL, &sVECfg_req, &sVECfg_rep);
    SOAP_CHECK_ERROR(result, soap, "SetVideoEncoderConfiguration");
    
EXIT:
    
    if (SOAP_OK == result) {
        SOAP_DBGLOG("\nSetVideoEncoderConfiguration success!!!\n");
    }
    
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    
    return result;
}

// 获取当前ptz的位置以及状态
int ONVIF_PTZ_GetStatus(const char * ptzXAddr, const char * ProfileToken){
    int result = 0;
    struct soap *soap = NULL;
    struct _tptz__GetStatus           getStatus;
    struct _tptz__GetStatusResponse   getStatusResponse;
    
    SOAP_ASSERT(NULL != ptzXAddr);
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    struct _trt__GetProfiles            req;
    struct _trt__GetProfilesResponse    rep;
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    
    memset(&req, 0x00, sizeof(req));
    memset(&rep, 0x00, sizeof(rep));
    result = soap_call___trt__GetProfiles(soap, ptzXAddr, NULL, &req, &rep);
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    
    getStatus.ProfileToken = rep.Profiles->token;
    result = soap_call___tptz__GetStatus(soap, ptzXAddr, NULL, &getStatus, &getStatusResponse);
    SOAP_CHECK_ERROR(result, soap, "ONVIF_PTZ_GetStatus");
    
    if(*getStatusResponse.PTZStatus->MoveStatus->PanTilt == tt__MoveStatus__IDLE){
        SOAP_DBGLOG("===>\n空闲 ...\n<===\n ");
    }else if(*getStatusResponse.PTZStatus->MoveStatus->PanTilt == tt__MoveStatus__MOVING){
        SOAP_DBGLOG("===>\n移动中 ...\n<===\n ");
    }else if(*getStatusResponse.PTZStatus->MoveStatus->PanTilt == tt__MoveStatus__UNKNOWN){
        SOAP_DBGLOG("===>\n未知 ...\n<===\n ");
    }
    
    SOAP_DBGLOG("===>\n当前p: %f<===\n ", getStatusResponse.PTZStatus->Position->PanTilt->x);
    SOAP_DBGLOG("===>\n当前t: %f<===\n ", getStatusResponse.PTZStatus->Position->PanTilt->y);
    SOAP_DBGLOG("===>\n当前z: %f<===\n ", getStatusResponse.PTZStatus->Position->Zoom->x);
EXIT:
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    
    return 0;
}

// 以指定速度移动到指定位置的ptz
// p :  -1  ~ 1   []
// t :  -1  ~ 1
// z :   0  ~ 1
int ONVIF_PTZAbsoluteMove(const char * ptzXAddr, const char * ProfileToken){
    int result = 0;
    struct soap *soap = NULL;
    struct _tptz__AbsoluteMove           absoluteMove;
    struct _tptz__AbsoluteMoveResponse   absoluteMoveResponse;
    
    SOAP_ASSERT(NULL != ptzXAddr);
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    struct _trt__GetProfiles            req;
    struct _trt__GetProfilesResponse    rep;
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    
    memset(&req, 0x00, sizeof(req));
    memset(&rep, 0x00, sizeof(rep));
    result = soap_call___trt__GetProfiles(soap, ptzXAddr, NULL, &req, &rep);
    
    
    absoluteMove.ProfileToken = rep.Profiles->token;
    
    absoluteMove.Position = soap_new_tt__PTZVector(soap, 1);
    absoluteMove.Position->PanTilt = soap_new_tt__Vector2D(soap, 1);
    absoluteMove.Position->Zoom = soap_new_tt__Vector1D(soap, 1);
    absoluteMove.Speed = soap_new_tt__PTZSpeed(soap, 1);
    absoluteMove.Speed->PanTilt = soap_new_tt__Vector2D(soap, 1);
    absoluteMove.Speed->Zoom = soap_new_tt__Vector1D(soap, 1);
    
    
    absoluteMove.Position->PanTilt->x = 0.440833;  // p
    absoluteMove.Position->PanTilt->y = 0.583455;   // t
    absoluteMove.Position->Zoom->x = 0.0333333;   // z
    
    // x 和y的绝对值越接近1，表示云台的速度越快
    absoluteMove.Speed->PanTilt->x = 0.5;
    absoluteMove.Speed->PanTilt->y = 0.5;
    absoluteMove.Speed->Zoom->x = 0.5;
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    result = soap_call___tptz__AbsoluteMove(soap,ptzXAddr, NULL,&absoluteMove,&absoluteMoveResponse);
    SOAP_CHECK_ERROR(result, soap, "ONVIF_PTZAbsoluteMove");
    
    
EXIT:
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    return 0;
}


int ONVIF_PTZStopMove(const char * ptzXAddr, const char * ProfileToken){
    int result = 0;
    struct soap *soap = NULL;
    struct _tptz__Stop tptzStop;
    struct _tptz__StopResponse tptzStopResponse;
    
    SOAP_ASSERT(NULL != ptzXAddr);
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    struct _trt__GetProfiles            req;
    struct _trt__GetProfilesResponse    rep;
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    
    memset(&req, 0x00, sizeof(req));
    memset(&rep, 0x00, sizeof(rep));
    result = soap_call___trt__GetProfiles(soap, ptzXAddr, NULL, &req, &rep);
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    tptzStop.ProfileToken = rep.Profiles->token;
    result = soap_call___tptz__Stop(soap, ptzXAddr, NULL, &tptzStop, &tptzStopResponse);
    SOAP_CHECK_ERROR(result, soap, "ONVIF_PTZStopMove");
    
EXIT:
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    return result;
}

// speed --> (0, 1]
int ONVIF_PTZContinuousMove(const char * ptzXAddr, const char * ProfileToken, enum PTZCMD cmd, float speed){
    int result = 0;
    struct soap *soap = NULL;
    struct _tptz__ContinuousMove continuousMove;
    struct _tptz__ContinuousMoveResponse continuousMoveResponse;
    
    SOAP_ASSERT(NULL != ptzXAddr);
    SOAP_ASSERT(NULL != (soap = ONVIF_soap_new(SOAP_SOCK_TIMEOUT)));
    
    struct _trt__GetProfiles            req;
    struct _trt__GetProfilesResponse    rep;
    
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    
    memset(&req, 0x00, sizeof(req));
    memset(&rep, 0x00, sizeof(rep));
    result = soap_call___trt__GetProfiles(soap, ptzXAddr, NULL, &req, &rep);
    
    continuousMove.ProfileToken = rep.Profiles->token;
    continuousMove.Velocity = soap_new_tt__PTZSpeed(soap, 1);
    continuousMove.Velocity->PanTilt = soap_new_tt__Vector2D(soap, 1);
    continuousMove.Velocity->Zoom = soap_new_tt__Vector1D(soap, 1);
    
    switch (cmd)
    {
        case  PTZ_CMD_LEFT:
            continuousMove.Velocity->PanTilt->x = -speed;
            continuousMove.Velocity->PanTilt->y = 0;
            break;
        case  PTZ_CMD_RIGHT:
            continuousMove.Velocity->PanTilt->x = speed;
            continuousMove.Velocity->PanTilt->y = 0;
            break;
        case  PTZ_CMD_UP:
            continuousMove.Velocity->PanTilt->x = 0;
            continuousMove.Velocity->PanTilt->y = speed;
            break;
        case  PTZ_CMD_DOWN:
            continuousMove.Velocity->PanTilt->x = 0;
            continuousMove.Velocity->PanTilt->y = -speed;
            break;
        case  PTZ_CMD_LEFTUP:
            continuousMove.Velocity->PanTilt->x = -speed;
            continuousMove.Velocity->PanTilt->y = speed;
            break;
        case PTZ_CMD_LEFTDOWN:
            continuousMove.Velocity->PanTilt->x = -speed;
            continuousMove.Velocity->PanTilt->y = -speed;
            break;
        case  PTZ_CMD_RIGHTUP:
            continuousMove.Velocity->PanTilt->x = speed;
            continuousMove.Velocity->PanTilt->y = speed;
            break;
        case PTZ_CMD_RIGHTDOWN:
            continuousMove.Velocity->PanTilt->x = speed;
            continuousMove.Velocity->PanTilt->y = -speed;
            break;
        case  PTZ_CMD_ZOOM_IN:
            continuousMove.Velocity->PanTilt->x = 0;
            continuousMove.Velocity->PanTilt->y = 0;
            continuousMove.Velocity->Zoom->x = speed;
            break;
        case  PTZ_CMD_ZOOM_OUT:
            continuousMove.Velocity->PanTilt->x = 0;
            continuousMove.Velocity->PanTilt->y = 0;
            continuousMove.Velocity->Zoom->x = -speed;
            break;
        default:
            break;
    }
    ONVIF_SetAuthInfo(soap, BYUSERNAME, BYPASSWORD);
    // 也可以使用soap_call___tptz__RelativeMove实现
    result = soap_call___tptz__ContinuousMove(soap,ptzXAddr, NULL,&continuousMove,&continuousMoveResponse);
    SOAP_CHECK_ERROR(result, soap, "ONVIF_PTZAbsoluteMove");
    /*    sleep(1); //如果当前soap被删除（或者发送stop指令），就会停止移动
     ONVIF_PTZStopMove(ptzXAddr, ProfileToken);*/
EXIT:
    if (NULL != soap) {
        ONVIF_soap_delete(soap);
    }
    return result;
}

