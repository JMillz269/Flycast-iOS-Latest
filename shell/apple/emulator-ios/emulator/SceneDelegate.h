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

// UIScene lifecycle (required by UIKit for apps built with the iOS 27 SDK, including when running inside a host
// app such as LiveContainer). The window and root view controller come from FlycastStoryboard (scene manifest in
// the Info.plist); lifecycle events are forwarded to the AppDelegate, which keeps the app logic.
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>

@property (strong, nonatomic) UIWindow *window;

@end
