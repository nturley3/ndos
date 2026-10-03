#import "SceneDelegate.h"
#import "AppDelegate.h"

@implementation SceneDelegate

- (AppDelegate *)appDelegate
{
    return (AppDelegate *)[UIApplication sharedApplication].delegate;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
    if (![scene isKindOfClass:[UIWindowScene class]])
        return;
    self.window = [[self appDelegate] connectToWindowScene:(UIWindowScene *)scene
                                             URLContexts:connectionOptions.URLContexts];
}

- (void)sceneDidBecomeActive:(UIScene *)scene
{
    [[self appDelegate] emulatorDidBecomeActive];
}

- (void)sceneWillResignActive:(UIScene *)scene
{
    [[self appDelegate] emulatorWillResignActive];
}

- (void)sceneDidEnterBackground:(UIScene *)scene
{
    [[self appDelegate] saveHistory];
}

- (void)sceneDidDisconnect:(UIScene *)scene
{
    if (self.window.windowScene != scene)
        return;
    [[self appDelegate] emulatorWillResignActive];
    [[self appDelegate] saveHistory];
    self.window.hidden = YES;
    self.window.windowScene = nil;
    self.window = nil;
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts
{
    for (UIOpenURLContext *context in URLContexts)
    {
        if (context.URL.isFileURL)
        {
            [[self appDelegate] openPackageURL:context.URL];
            break;
        }
    }
}

@end
