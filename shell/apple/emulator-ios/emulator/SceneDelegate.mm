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
#import "SceneDelegate.h"
#import "AppDelegate.h"

static AppDelegate *appDelegate()
{
	return (AppDelegate *)UIApplication.sharedApplication.delegate;
}

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
	// Files opened with the app while it wasn't running. Wait for the UI to be set up before starting the game.
	NSSet<UIOpenURLContext *> *urlContexts = connectionOptions.URLContexts;
	if (urlContexts.count > 0)
		dispatch_async(dispatch_get_main_queue(), ^{
			[self scene:scene openURLContexts:urlContexts];
		});
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts
{
	UIOpenURLContext *context = URLContexts.anyObject;
	if (context != nil)
		[appDelegate() application:UIApplication.sharedApplication openURL:context.URL options:@{}];
}

- (void)sceneWillResignActive:(UIScene *)scene
{
	[appDelegate() applicationWillResignActive:UIApplication.sharedApplication];
}

- (void)sceneDidEnterBackground:(UIScene *)scene
{
	[appDelegate() applicationDidEnterBackground:UIApplication.sharedApplication];
}

- (void)sceneWillEnterForeground:(UIScene *)scene
{
	[appDelegate() applicationWillEnterForeground:UIApplication.sharedApplication];
}

- (void)sceneDidBecomeActive:(UIScene *)scene
{
	[appDelegate() applicationDidBecomeActive:UIApplication.sharedApplication];
}

@end
