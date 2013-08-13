//
//  IMSMemoryManager.m
//  Memory Security Demo
//
//  Created by Black, Gavin S. on 8/8/13.
//  Copyright (c) 2013 Black, Gavin S. All rights reserved.
//

#import "IMSMemoryManager.h"

static NSPointerArray* unlockedPointers;
static NSMutableArray* lockedPointers;
static NSString* checksumStr;

void initMem(){
    if(!unlockedPointers) {
        NSLog(@"Initializing");
        unlockedPointers =[[NSPointerArray alloc] init];
    }
}

NSString* hexString(NSObject* obj){
    NSMutableString *hex = [[NSMutableString alloc] init];
    unsigned char* rawObj = (__bridge void*) obj;
    int size = malloc_size((__bridge void*) obj);
    for(int i = 0; i < size; i ++) {
        if(i%15 == 0) [hex appendString:@"\n"];
        [hex appendFormat:@"%02x", rawObj[i]];
    }
    return [NSString stringWithString:hex];
}

void* getStart(NSObject* obj) {
    if([obj isKindOfClass:[NSString class]]) {
        return ((__bridge void*)obj + 9);
    } else if([obj isKindOfClass:[NSData class]]) {
        return ((__bridge void*)obj + 12);
    } else if([obj isKindOfClass:[NSNumber class]]) {
        return ((__bridge void*)obj + 8);
    } else if([obj isKindOfClass:[NSArray class]]) {
        return ((__bridge void*)obj + 4);
    } else {
        return 0;
    }
}

int getSize(NSObject* obj) {
    if([obj isKindOfClass:[NSString class]]) {
        return (malloc_size((__bridge void*)obj) - 9);
    } else if([obj isKindOfClass:[NSData class]]) {
        return (malloc_size((__bridge void*)obj) - 12);
    } else if([obj isKindOfClass:[NSNumber class]]) {
        return (malloc_size((__bridge void*)obj) - 8);
    } else if([obj isKindOfClass:[NSArray class]]) {
        return (malloc_size((__bridge void*)obj) - 4);
    } else {
        return 0;
    }
}


// Return yes, if calling function should continue on
// no means caller should return immediately
BOOL handleType(NSObject* obj, NSString* pass, traversalFunc f) {
    BOOL ret = YES;
    if([obj isKindOfClass:[NSArray class]]){
        ret = NO;
        for( id newObj in (NSArray*)obj) {
            (*f)(newObj, pass);
        }
    }
    NSLog(@"Done with type handler %d", ret);
    return ret;
}

// Wrapper for handling function ptr
BOOL wipeWrapper(NSObject* obj, NSString* ignore) {
    return wipe(obj);
}

// Return NO if wipe failed
BOOL wipe(NSObject* obj) {
    NSLog(@"Object pointer: %p", obj);
    if(handleType(obj, @"", &wipeWrapper) == YES) {
        NSLog(@"WIPE OBJ");
        memset( getStart(obj), 0, getSize(obj));
    }
    return YES;
}


// Return NO if object already tracked
BOOL track(NSObject* obj) {
    initMem();
    [unlockedPointers addPointer:(void *)obj];
    NSLog(@"TRACK %p -- %d", obj, [unlockedPointers count]);
    return YES;
}

BOOL untrack(NSObject* obj) {
    initMem();
    for(int i = 0; i < [unlockedPointers count]; i ++){
        if([unlockedPointers pointerAtIndex:i] == (__bridge void *)(obj)){
            [unlockedPointers removePointerAtIndex:i];
        }
    }
    
    return YES;
}


// Return count of how many wiped
int wipeAll() {
    initMem();
    for(id obj in unlockedPointers) wipe(obj);
    
    return [unlockedPointers count];
}

// Return YES is the object was encrypted
BOOL cryptHelper(NSObject* obj, NSString* pass, CCOperation op) {
    NSLog(@"Object pointer: %p", obj);
    char keyPtr[kCCKeySizeAES256+1];
    bzero(keyPtr, sizeof(keyPtr));
    [pass getCString:keyPtr maxLength:sizeof(keyPtr) encoding:NSUTF8StringEncoding];
    
    size_t bufferSize = getSize(obj) + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    NSUInteger dataLength = getSize(obj);
    
    
    size_t numBytesEncrypted = 0;
    CCCryptorStatus cryptStatus = CCCrypt(op,
                                          kCCAlgorithmAES128,
                                          kCCOptionPKCS7Padding,
                                          keyPtr, kCCKeySizeAES256,
                                          NULL,
                                          getStart(obj),
                                          dataLength,
                                          buffer, bufferSize,
                                          &numBytesEncrypted);
    memcpy(getStart(obj), buffer, dataLength);
    free(buffer);
    
    // TODO: Make sure key is wiped
    // TODO: Return based on cryptStatus  --  if (cryptStatus == kCCSuccess)
    return YES;
}

BOOL lock(NSObject* obj, NSString* pass) {
  //  if(handleType(obj, @"", &lock) == YES) {
        return cryptHelper(obj, pass, kCCEncrypt);
  //  } else return YES;
}

BOOL unlock(NSObject* obj, NSString* pass) {
   // if(handleType(obj, @"", &unlock) == YES) {
        return cryptHelper(obj, pass, kCCDecrypt);
   // } else return YES;
}

BOOL lockAll(NSObject* obj, NSString* pass) {
    NSLog(@"NOT IMPLEMENTED");
    
    return YES;
}

BOOL unlockAll(NSObject* obj, NSString* pass) {
    NSLog(@"NOT IMPLEMENTED");
    
    return YES;
}

BOOL checksumTest() {
    initMem();
    NSString* checksumTmp = [checksumStr copy];
    NSString* newSum = checksumMem();
    
    if([checksumTmp isEqualToString:newSum]) return YES;
    else return NO;
}

NSString* checksumObj(NSObject* obj) {
    NSLog(@"Object pointer: %p", obj);
    NSMutableString *hex = [[NSMutableString alloc] init];
    
    unsigned char* digest = malloc(CC_SHA1_DIGEST_LENGTH);
    if (CC_SHA1((__bridge void*)obj, malloc_size((__bridge void*)obj), digest)) {
        for (NSUInteger i=0; i<CC_SHA1_DIGEST_LENGTH; i++)
            [hex appendFormat:@"%02x", digest[i]];
    }
    free(digest);
    
    return [NSString stringWithString:hex];
}

NSString* checksumMem() {
    initMem();
    NSMutableString *hex = [[NSMutableString alloc] init];
    
    for(id obj in unlockedPointers) {
        [hex appendFormat:@"%p", obj];
        [hex appendString:checksumObj(obj)];
    }
    checksumStr = [NSString stringWithString:hex];
    return [checksumStr copy];
}