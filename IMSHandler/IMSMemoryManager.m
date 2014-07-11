//
//  IMSMemoryManager.m
//  Memory Security Demo
//
//  Created by Black, Gavin S. on 8/8/13.
//  Copyright (c) 2013 Black, Gavin S. All rights reserved.
//

//#include <dlfcn.h>
#include <sys/sysctl.h>
#include <mach/mach.h>

#import "IMSMemoryManager.h"

// 32-bit
const int OFFSET32_SSTRING = 9;
const int OFFSET32_LSTRING = 12;
const int OFFSET32_NUMBER  = 8;
const int OFFSET32_ARRAY   = 8;
const int OFFSET32_DATA7   = 8;        // iOS >= 7.0
const int OFFSET32_DATA6   = 16;       // iOS <= 6.1

//64-bit
const int OFFSET64_SSTRING = 17;
const int OFFSET64_LSTRING = 24;
const int OFFSET64_NUMINT  = 1;
const int OFFSET64_NUMDEC  = 16;
const int OFFSET64_ARRAY   = 8;
const int OFFSET64_DATA7   = 16;

static NSMutableArray* functionPointers;
static NSPointerArray* trackedPointers;
static NSString* checksumStr;
static NSMutableDictionary *ivtable;

#if TARGET_IPHONE_SIMULATOR
bool is64bitSimulator()
{
    bool is64bitSimulator = false;
    
    /* Setting up the mib (Management Information Base) which is an array of integers where each
     * integer specifies how the data will be gathered.  Here we are setting the MIB
     * block to lookup the information on all the BSD processes on the system.  Also note that
     * every regular application has a recognized BSD process accociated with it.  We pass
     * CTL_KERN, KERN_PROC, KERN_PROC_ALL to sysctl as the MIB to get back a BSD structure with
     * all BSD process information for all processes in it (including BSD process names)
     */
    int mib[6] = {0,0,0,0,0,0};
    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_ALL;
    
    long numberOfRunningProcesses = 0;
    struct kinfo_proc* BSDProcessInformationStructure = NULL;
    size_t sizeOfBufferRequired = 0;
    
    /* Here we have a loop set up where we keep calling sysctl until we finally get an unrecoverable error
     * (and we return) or we finally get a succesful result.  Note with how dynamic the process list can
     * be you can expect to have a failure here and there since the process list can change between
     * getting the size of buffer required and the actually filling that buffer.
     */
    BOOL successfullyGotProcessInformation = NO;
    int error = 0;
    
    while (successfullyGotProcessInformation == NO)
    {
        /* Now that we have the MIB for looking up process information we will pass it to sysctl to get the
         * information we want on BSD processes.  However, before we do this we must know the size of the buffer to
         * allocate to accomidate the return value.  We can get the size of the data to allocate also using the
         * sysctl command.  In this case we call sysctl with the proper arguments but specify no return buffer
         * specified (null buffer).  This is a special case which causes sysctl to return the size of buffer required.
         *
         * First Argument: The MIB which is really just an array of integers.  Each integer is a constant
         *     representing what information to gather from the system.  Check out the man page to know what
         *     constants sysctl will work with.  Here of course we pass our MIB block which was passed to us.
         * Second Argument: The number of constants in the MIB (array of integers).  In this case there are three.
         * Third Argument: The output buffer where the return value from sysctl will be stored.  In this case
         *     we don't want anything return yet since we don't yet know the size of buffer needed.  Thus we will
         *     pass null for the buffer to begin with.
         * Forth Argument: The size of the output buffer required.  Since the buffer itself is null we can just
         *     get the buffer size needed back from this call.
         * Fifth Argument: The new value we want the system data to have.  Here we don't want to set any system
         *     information we only want to gather it.  Thus, we pass null as the buffer so sysctl knows that
         *     we have no desire to set the value.
         * Sixth Argument: The length of the buffer containing new information (argument five).  In this case
         *     argument five was null since we didn't want to set the system value.  Thus, the size of the buffer
         *     is zero or NULL.
         * Return Value: a return value indicating success or failure.  Actually, sysctl will either return
         *     zero on no error and -1 on error.  The errno UNIX variable will be set on error.
         */
        error = sysctl(mib, 3, NULL, &sizeOfBufferRequired, NULL, 0);
        if (error)
            return NULL;
        
        /* Now we successful obtained the size of the buffer required for the sysctl call.  This is stored in the
         * SizeOfBufferRequired variable.  We will malloc a buffer of that size to hold the sysctl result.
         */
        BSDProcessInformationStructure = (struct kinfo_proc*) malloc(sizeOfBufferRequired);
        if (BSDProcessInformationStructure == NULL)
            return NULL;
        
        /* Now we have the buffer of the correct size to hold the result we can now call sysctl
         * and get the process information.
         *
         * First Argument: The MIB for gathering information on running BSD processes.  The MIB is really
         *     just an array of integers.  Each integer is a constant representing what information to
         *     gather from the system.  Check out the man page to know what constants sysctl will work with.
         * Second Argument: The number of constants in the MIB (array of integers).  In this case there are three.
         * Third Argument: The output buffer where the return value from sysctl will be stored.  This is the buffer
         *     which we allocated specifically for this purpose.
         * Forth Argument: The size of the output buffer (argument three).  In this case its the size of the
         *     buffer we already allocated.
         * Fifth Argument: The buffer containing the value to set the system value to.  In this case we don't
         *     want to set any system information we only want to gather it.  Thus, we pass null as the buffer
         *     so sysctl knows that we have no desire to set the value.
         * Sixth Argument: The length of the buffer containing new information (argument five).  In this case
         *     argument five was null since we didn't want to set the system value.  Thus, the size of the buffer
         *     is zero or NULL.
         * Return Value: a return value indicating success or failure.  Actually, sysctl will either return
         *     zero on no error and -1 on error.  The errno UNIX variable will be set on error.
         */
        error = sysctl(mib, 3, BSDProcessInformationStructure, &sizeOfBufferRequired, NULL, 0);
        if (error == 0)
        {
            //Here we successfully got the process information.  Thus set the variable to end this sysctl calling loop
            successfullyGotProcessInformation = YES;
        }
        else
        {
            /* failed getting process information we will try again next time around the loop.  Note this is caused
             * by the fact the process list changed between getting the size of the buffer and actually filling
             * the buffer (something which will happen from time to time since the process list is dynamic).
             * Anyways, the attempted sysctl call failed.  We will now begin again by freeing up the allocated
             * buffer and starting again at the beginning of the loop.
             */
            free(BSDProcessInformationStructure);
        }
    } //end while loop
    
    
    /* Now that we have the BSD structure describing the running processes we will parse it for the desired
     * process name.  First we will the number of running processes.  We can determine
     * the number of processes running because there is a kinfo_proc structure for each process.
     */
    numberOfRunningProcesses = sizeOfBufferRequired / sizeof(struct kinfo_proc);
    for (int i = 0; i < numberOfRunningProcesses; i++)
    {
        //Getting name of process we are examining
        const char *name = BSDProcessInformationStructure[i].kp_proc.p_comm;
        
        if(strcmp(name, "SimulatorBridge") == 0)
        {
            int p_flag = BSDProcessInformationStructure[i].kp_proc.p_flag;
            is64bitSimulator = (p_flag & P_LP64) == P_LP64;
            break;
        }
    }
    
    free(BSDProcessInformationStructure);
    return is64bitSimulator;
}

#endif // TARGET_IPHONE_SIMULATOR

BOOL is64bitHardware(){
#if __LP64__
    // The app has been compiled for 64-bit intel and runs as 64-bit intel
    return YES;
#endif
    
    // Use some static variables to avoid performing the tasks several times.
    static BOOL sHardwareChecked = NO;
    static BOOL sIs64bitHardware = NO;
    
    if(!sHardwareChecked)
    {
        sHardwareChecked = YES;
        
#if TARGET_IPHONE_SIMULATOR
        // The app was compiled as 32-bit for the iOS Simulator.
        // We check if the Simulator is a 32-bit or 64-bit simulator using the function is64bitSimulator()
        // See http://blog.timac.org/?p=886
        sIs64bitHardware = is64bitSimulator();
#else
        // The app runs on a real iOS device: ask the kernel for the host info.
        struct host_basic_info host_basic_info;
        unsigned int count;
        kern_return_t returnValue = host_info(mach_host_self(), HOST_BASIC_INFO, (host_info_t)(&host_basic_info), &count);
        if(returnValue != KERN_SUCCESS)
        {
            sIs64bitHardware = NO;
        }
        
        sIs64bitHardware = (host_basic_info.cpu_type == CPU_TYPE_ARM64);
        
#endif // TARGET_IPHONE_SIMULATOR
    }
    
    return sIs64bitHardware;
}

void initMem(){
    if(!trackedPointers)
        trackedPointers = [[NSPointerArray alloc] init];
}

inline NSString* hexString(NSObject* obj){
    
    NSLog(@"%p %zu",obj, malloc_size((__bridge void*)obj));
    BOOL isNumInt64 = NO;
    unsigned char* rawObj = (__bridge void*)obj;
    NSMutableString *hex = [[NSMutableString alloc] init];

    
    if([obj isKindOfClass:[NSNumber class]]){
        char type = *[(NSNumber*)obj objCType];
        NSLog(@"%c",type);
        unsigned char msb = ((u_int64_t)rawObj >> (14*4)) & 0xf0;
        isNumInt64 = ((type == 'i' || type == 'q' || type == 'l') && msb == 0xb0);
    }
    
    if(isNumInt64){
        unsigned char* raw = (unsigned char*)&rawObj;
        for(int i=0;i<8;i++) [hex appendFormat:((i%4==0 && i>0)?@" %02X":@"%02X"),raw[i]];
    }
    else {
        int size = (int)malloc_size((__bridge void*) obj);
        for(int i = 0; i < size; i ++) {
            if(i%32==0 && i != 0) [hex appendString:@"\n"];
            else if(i%4==0 && i != 0) [hex appendString:@" "];
            [hex appendFormat:@"%02X", rawObj[i]];
        }
    }
    
    return [NSString stringWithString:hex];
}

inline void* getStart(NSObject* obj) {
    
    BOOL is64bit = is64bitHardware();
    float iosversion = [[[UIDevice currentDevice] systemVersion] floatValue];
    
    if([obj isKindOfClass:[NSString class]]) {
        if([(NSString*)obj length] < 256)
            return ((__bridge void*)obj + ((is64bit)?OFFSET64_SSTRING:OFFSET32_SSTRING));
        else
            return ((__bridge void*)obj + ((is64bit)?OFFSET64_LSTRING:OFFSET32_LSTRING));
    } else if([obj isKindOfClass:[NSData class]]) {
        return ((__bridge void*)obj + ((is64bit)?OFFSET64_DATA7:((iosversion < 7.0)?OFFSET32_DATA6:OFFSET32_DATA7)));
    } else if([obj isKindOfClass:[NSNumber class]]) {
        char type = *[(NSNumber*)obj objCType];
        if(!is64bit)
            return ((__bridge void*)obj + OFFSET32_NUMBER);
        else if(type == 'i' || type == 'l' || type == 'q'){
            unsigned char* raw = (__bridge void*)obj;
            return &raw;// + OFFSET64_NUMINT); THIS IS WRONG
        }
        else
            return ((__bridge void*)obj + OFFSET64_NUMDEC);
    } else if([obj isKindOfClass:[NSArray class]]) {
        return ((__bridge void*)obj + OFFSET32_ARRAY);
    } else {
        return 0;
    }
}

inline int getSize(NSObject* obj) {
    
    BOOL is64bit = is64bitHardware();
    float iosversion = [[[UIDevice currentDevice] systemVersion] floatValue];
    
    if([obj isKindOfClass:[NSString class]]) {
        if ([(NSString *)obj length] < 256)
            return (int)(malloc_size((__bridge void*)obj) - ((is64bit)?OFFSET64_SSTRING:OFFSET32_SSTRING));
        else
            return (int)(malloc_size((__bridge void*)obj) - ((is64bit)?OFFSET64_LSTRING:OFFSET32_LSTRING));
    } else if([obj isKindOfClass:[NSData class]]) {
        return (int)(malloc_size((__bridge void*)obj) - ((is64bit)?OFFSET64_DATA7:((iosversion < 7.0)?OFFSET32_DATA6:OFFSET32_DATA7)));
    } else if([obj isKindOfClass:[NSNumber class]]) {
        char type = *[(NSNumber*)obj objCType];
        if(!is64bit)
            return (int)(malloc_size((__bridge void*)obj) - OFFSET32_NUMBER);
        else if(type == 'i' || type == 'l' || type == 'q')
            return (8 - OFFSET64_NUMINT);
        else
            return (int)(malloc_size((__bridge void*)obj) - OFFSET64_NUMDEC);
    } else if([obj isKindOfClass:[NSArray class]]) {
        return (int)(malloc_size((__bridge void*)obj) - OFFSET32_ARRAY);
    } else {
        return 0;
    }
}

inline NSString* getKey(void* obj) {
    return [NSString stringWithFormat:@"%p",obj];
}

// Return yes, if calling function should continue on
// no means caller should return immediately
inline BOOL handleType(NSObject* obj, NSString* pass, traversalFunc f) {
    BOOL ret = YES;
    BOOL enumerateObject = [obj isKindOfClass:[NSArray class]]
                        || [obj isKindOfClass:[NSSet class]];
    BOOL enumerateDict   = [obj isKindOfClass:[NSDictionary class]];
    
    if(enumerateObject){
        ret = NO;
        for(id newObj in (NSArray*)obj) {
            (*f)(newObj, pass);
        }
    }
    
    if(enumerateDict){
        ret = NO;
        for(id key in (NSDictionary*)obj){
            (*f)([(NSDictionary*)obj objectForKey:key],pass);
            (*f)(key,pass);
        }
    }
    
    NSLog(@"Done with type handler %@\n\n", ret?@"YES":@"NO");
    return ret;
}

// Wrapper for handling function ptr
extern inline BOOL wipeWrapper(NSObject* obj, NSString* ignore) {
    return wipe(obj);
}

// Return NO if wipe failed
extern inline BOOL wipe(NSObject* obj) {
    NSLog(@"Object pointer: %p", obj);
    if(handleType(obj, @"", &wipeWrapper) == YES) {
        NSLog(@"WIPE OBJ");
        memset( getStart(obj), 0, getSize(obj));
    }
    return YES;
}

extern inline void secureExit(){
    wipeAll();
    
    if (checksumStr)
        memset((__bridge void *)checksumStr, 0x00, malloc_size((__bridge void*)checksumStr));
    
    if (ivtable)
        memset((__bridge void *)ivtable, 0x00, malloc_size((__bridge void*)ivtable));
}

// Return NO if object already tracked
extern inline BOOL track(NSObject* obj) {
    initMem();
    [trackedPointers addPointer:(void *)obj];
    NSLog(@"TRACK %p -- %lu", obj, (unsigned long)[trackedPointers count]);
    return YES;
}

extern inline BOOL untrack(NSObject* obj) {
    initMem();
    [trackedPointers removePointerAtIndex:[[trackedPointers allObjects] indexOfObject:(__bridge id)(__bridge void*)obj]];
    return YES;
}


// Return count of how many wiped
extern inline int wipeAll() {
    initMem();
    for(id obj in trackedPointers) wipe(obj);
    
    return (int)[trackedPointers count];
}

// Return YES if the object was encrypted
extern inline BOOL cryptHelper(NSObject* obj, NSString* pass, CCOperation op) {
    BOOL success = NO;
    CCCryptorStatus cryptorStatus;
    
    NSLog(@"\nObject pointer: %p location: %p", obj, &obj);
    char *keyPtr = malloc(kCCKeySizeAES256+1);
    bzero(keyPtr, kCCKeySizeAES256+1);
    [pass getCString:keyPtr maxLength:kCCKeySizeAES256 encoding:NSUTF8StringEncoding];
    
    cryptorStatus = cryptwork(op, getStart(obj), getSize(obj), keyPtr, kCCKeySizeAES256);
    
    switch(cryptorStatus){
        case kCCSuccess:        NSLog(@"SUCCESS");              success = YES;      break;
        case kCCParamError:     NSLog(@"ERR: PARAMETER ERROR");                     break;
        case kCCBufferTooSmall: NSLog(@"ERR: BUFFER TOO SMALL");                    break;
        case kCCMemoryFailure:  NSLog(@"ERR: MEMORY FAILURE");                      break;
        case kCCAlignmentError: NSLog(@"ERR: ALIGNMENT ERROR");                     break;
        case kCCDecodeError:    NSLog(@"ERR: DECODE ERROR");                        break;
        case kCCUnimplemented:  NSLog(@"ERR: UNIMPLEMENTED");                       break;
        case kCCOverflow:       NSLog(@"ERR: OVERFLOW");                            break;
        case (-1):              NSLog(@"ERR: CANNOT UNLOCK, OBJECT NOT LOCKED");    break;
        case (-2):              NSLog(@"ERR: NULL IV");                             break;
        case (-3):              NSLog(@"ERR: CANNOT LOCK, OBJECT ALREADY LOCKED");  break;
        default:                NSLog(@"ERR: UNKNOWN ERROR(%d)",cryptorStatus);     break;
    }
    
    bzero(keyPtr, kCCKeySizeAES256+1);
    free(keyPtr);
    return success;
}

extern inline CCCryptorStatus cryptwork(CCOperation op ,void* dataIn, size_t datalen, char* key, size_t keylen){
    
    NSLog(@"start: %p len %zu",dataIn,datalen);
    
    int saltlen = 8;
    int ivlen = kCCBlockSizeAES128;
    
    NSData *iv_salt;
    void *dataOut = malloc(datalen);
    bzero(dataOut, datalen);
    size_t dataOutMoved = 0;
    CCCryptorRef cryptorRef = NULL;
    CCCryptorStatus cryptorStatus;
    
    /* initialize ivtable if not already
     * table format (dictionary): { pointerAddress : < iv[16 bytes] salt[8 bytes] > }
     * e.g. { 0xcafebabe : <01234567 890abcdef 01234567 890abcdef 0124567 890abcdef> }
     */
    
    if (ivtable == nil)
        ivtable = [NSMutableDictionary dictionary];
    
    if (op == kCCEncrypt) {
        if ([ivtable objectForKey:getKey(dataIn)] != nil)
            return (cryptorStatus = -3); // object already encrypted
        
        iv_salt = IMSCryptoUtilsPseudoRandomData(ivlen + saltlen);
        [ivtable setObject:iv_salt forKey:getKey(dataIn)];
    }
    else {
        if ([ivtable objectForKey:getKey(dataIn)] == nil)
            return (cryptorStatus = -1); // object not encrypted
        
        iv_salt = [ivtable objectForKey:getKey(dataIn)];
        [ivtable removeObjectForKey:getKey(dataIn)];
    }
    
//    NSLog(@"%@",ivtable);
    
    if (iv_salt == nil || [iv_salt bytes] == NULL)
        return (cryptorStatus = -2); // error with iv_salt
    
    char *_iv = malloc(ivlen);
    char *_salt = malloc(saltlen);
    
    const char *_iv_salt = [iv_salt bytes];
    memcpy(_iv, _iv_salt, ivlen);
    memcpy(_salt, _iv_salt + ivlen, saltlen);

    /* key = key[padded to 32 bytes] XOR salt[8 bytes]
     * e.g.      P A S S  W O R D 00000000 00000000 00000000 00000000 00000000 00000000 00000000
     *     XOR  00000000 00000000 00000000 00000000 00000000 00000000 00000000  S A L T  H E R E
     */
    for(int i = (int)keylen - saltlen; i < keylen; i++)
        key[i] = key [i] ^ _salt[i - keylen + saltlen];
    
    unsigned char *keyhash = malloc(keylen);
    keyhash = CC_SHA256(key, (unsigned int)keylen, keyhash);
    
//    printf("_iv:\t");
//    for(int i = 0; i < ivlen; i++){ if(i%4==0) printf(" "); printf("%02x",(unsigned char)_iv[i]); }
//    printf("\n");
//    printf("_salt:\t");
//    for(int i = 0; i < saltlen; i++){ if(i%4==0) printf(" "); printf("%02x",(unsigned char)_salt[i]); }
//    printf("\n");
//    printf("key:\t");
//    for(int i = 0; i < keylen; i++){ if(i%4==0) printf(" "); printf("%02x",(unsigned char)key[i]); }
//    printf("\n");
//    printf("keyhash:");
//    for(int i = 0; i < keylen; i++){ if(i%4==0) printf(" "); printf("%02x",(unsigned char)keyhash[i]); }
//    printf("\n");

    cryptorStatus = CCCryptorCreateWithMode(op, kCCModeCTR, kCCAlgorithmAES128,
                                            ccNoPadding, _iv,
                                            keyhash, keylen, NULL, 0, 0,
                                            kCCModeOptionCTR_BE,
                                            &cryptorRef);
    
    if (cryptorStatus == kCCSuccess) {
        cryptorStatus = CCCryptorUpdate(cryptorRef,
                                        dataIn, datalen,
                                        dataOut, datalen,
                                        &dataOutMoved);
        if (cryptorStatus == kCCSuccess) {
            cryptorStatus = CCCryptorRelease(cryptorRef);
            memcpy(dataIn, dataOut, datalen);
        }
    }
    
    /* zero and free all the things */    
    bzero(dataOut, datalen);
    bzero(keyhash, keylen);
    bzero(_iv, kCCBlockSizeAES128);
    bzero(_salt, 8);
    free(dataOut);
    free(keyhash);
    free(_iv);
    free(_salt);
    return cryptorStatus;
}

extern inline BOOL lock(NSObject* obj, NSString* pass) {
    if(handleType(obj, pass, &lock)) {
      return cryptHelper(obj, pass, kCCEncrypt);
    } else
      return YES;
}

extern inline BOOL unlock(NSObject* obj, NSString* pass) {
   if(handleType(obj, pass, &unlock) == YES) {
     return cryptHelper(obj, pass, kCCDecrypt);
    } else
     return YES;
}

extern inline BOOL lockC(void *data, int len, char *pass) {
    BOOL success = YES;
    CCCryptorStatus cryptorStatus;
    
    char *key = malloc(kCCKeySizeAES256 + 1);
    bzero(key, kCCKeySizeAES256+1);
    memcpy(key, pass, strlen(pass));
    
    cryptorStatus = cryptwork(kCCEncrypt, data, len, key, kCCKeySizeAES256);
    
    if (cryptorStatus != kCCSuccess)
        success = NO;
    
    bzero(key, kCCKeySizeAES256+1);
    free(key);
    return success;
}

extern inline BOOL unlockC(void *data, int len, char *pass) {
    BOOL success = YES;
    CCCryptorStatus cryptorStatus;
    
    char *key = malloc(kCCKeySizeAES256 + 1);
    bzero(key, kCCKeySizeAES256+1);
    memcpy(key, pass, strlen(pass));
    
    cryptorStatus = cryptwork(kCCDecrypt, data, len, key, kCCKeySizeAES256);
    
    if (cryptorStatus != kCCSuccess)
        success = NO;
    
    bzero(key, kCCKeySizeAES256+1);
    free(key);
    return success;
}

extern inline BOOL lockAll(NSString* pass) {
    initMem();
    for(id obj in trackedPointers)
        lock(obj, pass);
    
    return YES;
}

extern inline BOOL unlockAll(NSString* pass) {
    initMem();
    for(id obj in trackedPointers) {
        unlock(obj, pass);
    }
    return YES;
}

extern inline BOOL checksumTest() {
    initMem();
    NSString* checksumTmp = [checksumStr copy];
    NSString* newSum = checksumMemHelper(NO);
    
    if([checksumTmp isEqualToString:newSum]) return YES;
    else return NO;
}

extern inline NSString* checksumObj(NSObject* obj) {
    NSLog(@"Object pointer: %p", obj);
    NSMutableString *hex = [[NSMutableString alloc] init];
    
    unsigned char* digest = malloc(CC_SHA1_DIGEST_LENGTH);
    if (CC_SHA1((__bridge void*)obj, (unsigned int)malloc_size((__bridge void*)obj), digest)) {
        for (NSUInteger i=0; i<CC_SHA1_DIGEST_LENGTH; i++)
            [hex appendFormat:@"%02x", digest[i]];
    }
    free(digest);
    return [NSString stringWithString:hex];
}

extern inline NSString* checksumMemHelper(BOOL saveStr) {
    initMem();
    NSMutableString *hex = [[NSMutableString alloc] init];
    
    for(id obj in trackedPointers) {
        [hex appendFormat:@"%p", obj];
        [hex appendString:checksumObj(obj)];
    }
    if(saveStr) {
        checksumStr = [NSString stringWithString:hex];
        return [checksumStr copy];
    } else {
        return [NSString stringWithString:hex];
    }
}

extern inline NSString* checksumMem() {
    return checksumMemHelper(YES);
}

extern inline BOOL validate(){
    
    functionPointers = [NSMutableArray arrayWithObjects:
                        [NSValue valueWithPointer:&track],
                        [NSValue valueWithPointer:&untrack],
                        [NSValue valueWithPointer:&wipe],
                        [NSValue valueWithPointer:&wipeAll],
                        [NSValue valueWithPointer:&secureExit],
                        [NSValue valueWithPointer:&lock],
                        [NSValue valueWithPointer:&unlock],
                        [NSValue valueWithPointer:&lockAll],
                        [NSValue valueWithPointer:&unlockAll],
                        [NSValue valueWithPointer:&lockC],
                        [NSValue valueWithPointer:&unlockC],
                        [NSValue valueWithPointer:&checksumTest],
                        [NSValue valueWithPointer:&checksumMemHelper],
                        [NSValue valueWithPointer:&checksumObj],
                        [NSValue valueWithPointer:&checksumMem],
                        [NSValue valueWithPointer:&hexString],
                        [NSValue valueWithPointer:&getSize],
                        [NSValue valueWithPointer:&getStart],
                        [NSValue valueWithPointer:&getKey],
                        [NSValue valueWithPointer:&handleType],
                        [NSValue valueWithPointer:&cryptHelper],
                        [NSValue valueWithPointer:&cryptwork],
                        nil];
    
    Dl_info * info = malloc(sizeof(Dl_info));
    
    
    return YES;
}





















