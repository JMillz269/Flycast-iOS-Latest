/*
	Copyright (c) 2014 Lounge Katt. All rights reserved.

	This file is part of Flycast.

	Flycast is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 2 of the License, or
	(at your option) any later version.

	Flycast is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with Flycast.  If not, see <https://www.gnu.org/licenses/>.
*/
//
//  Created by Lounge Katt on 2/6/14.
//
#import <UIKit/UIKit.h>

#import "AppDelegate.h"

int main(int argc, char * argv[])
{
    @autoreleasepool {
        setenv("MVK_CONFIG_LOG_LEVEL", "3", 1);
				setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "0", 1);
				setenv("MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE", "0", 1);
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        freopen([[docs stringByAppendingPathComponent:@"moltenvk.log"] fileSystemRepresentation], "a", stderr);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
