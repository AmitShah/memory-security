//
//  IMSUtil.h
//  Memory Security Demo
//
//  Created by Hannah, Robert J on 7/11/14.
//  Copyright (c) 2014 Black, Gavin S. All rights reserved.
//

#include <sys/sysctl.h>
#include <mach/mach.h>

#if TARGET_IPHONE_SIMULATOR
bool is64bitSimulator();
#endif
BOOL is64bitHardware();

