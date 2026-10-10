#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import "DPSettingsViewController.h"
#import "DPEmulatorViewController.h"

extern BOOL dospad_settings_open(void);
extern int dospad_pause_flag;
extern void dospad_resume(void);

@interface DPEmulatorViewController (Testing)
- (void)showOption:(id)sender;
- (void)finishSettings;
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller;
@end

@interface SettingsTests : XCTestCase
@end
@implementation SettingsTests
- (void)settle
{
    XCTestExpectation *delay = [self expectationWithDescription:@"UI transition completes"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [delay fulfill]; });
    [self waitForExpectations:@[delay] timeout:3];
}
- (DPEmulatorViewController *)emulator
{
    for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in scene.windows) {
            if ([window.rootViewController isKindOfClass:DPEmulatorViewController.class])
                return (DPEmulatorViewController *)window.rootViewController;
        }
    }
    return nil;
}
- (void)testSettingsPresentationAndPause
{
    [self settle];
    DPEmulatorViewController *emulator = [self emulator];
    XCTAssertNotNil(emulator);
    [emulator showOption:nil];
    [self settle];
    UINavigationController *navigation = (id)emulator.presentedViewController;
    XCTAssertTrue([navigation isKindOfClass:UINavigationController.class]);
    XCTAssertEqual(navigation.presentationController.delegate, emulator);
    DPSettingsViewController *settings = (id)navigation.topViewController;
    XCTAssertTrue([settings isKindOfClass:DPSettingsViewController.class]);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:emulator.view.window.bounds];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [emulator.view.window drawViewHierarchyInRect:emulator.view.window.bounds afterScreenUpdates:YES];
    }];
    XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
    attachment.name = @"Settings modal";
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
    XCTAssertTrue(dospad_settings_open());
    XCTAssertEqual(dospad_pause_flag, 1);
    XCTAssertFalse(emulator.view.userInteractionEnabled);
    dospad_resume();
    [emulator willResignActive];
    [emulator didBecomeActive];
    XCTAssertEqual(dospad_pause_flag, 1);
    NSInteger rows = 0;
    for (NSInteger section = 0; section < [settings numberOfSectionsInTableView:settings.tableView]; section++)
        rows += [settings tableView:settings.tableView numberOfRowsInSection:section];
    XCTAssertEqual(rows, 18);
    NSIndexPath *path = [NSIndexPath indexPathForRow:0 inSection:0];
    UITableViewCell *cell = [settings tableView:settings.tableView cellForRowAtIndexPath:path];
    UISwitch *control = (id)cell.accessoryView;
    XCTAssertTrue([control isKindOfClass:UISwitch.class]);
    BOOL previous = control.on;
    control.on = !previous;
    [control sendActionsForControlEvents:UIControlEventValueChanged];
    XCTAssertEqual([DPSettings shared].autoOpenLastPackage, !previous);
    control.on = previous;
    [control sendActionsForControlEvents:UIControlEventValueChanged];
    // Slider edits save and convert transparency to overlay opacity.
    float previousTransparency = [[[DPSettings shared] valueForPreferenceKey:@"transparency"] floatValue];
    UITableViewCell *sliderCell = [settings tableView:settings.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3]];
    UIStackView *stack = nil;
    for (UIView *view in sliderCell.contentView.subviews)
        if ([view isKindOfClass:UIStackView.class]) stack = (id)view;
    UISlider *slider = (id)stack.arrangedSubviews.lastObject;
    XCTAssertTrue([slider isKindOfClass:UISlider.class]);
    slider.value = 0.6;
    [slider sendActionsForControlEvents:UIControlEventValueChanged];
    XCTAssertEqualWithAccuracy([DPSettings shared].floatAlpha, 0.4, 0.001);
    slider.value = previousTransparency;
    [slider sendActionsForControlEvents:UIControlEventValueChanged];
    // Select a scale, return to settings, and preserve the original value.
    id previousScale = [[DPSettings shared] valueForPreferenceKey:@"screen_scale_mode"];
    [settings tableView:settings.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
    [self settle];
    UITableViewController *choice = (id)navigation.topViewController;
    XCTAssertNotEqual(choice, settings);
    XCTAssertNotNil(choice.navigationItem.rightBarButtonItem);
    [choice tableView:choice.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
    [self settle];
    XCTAssertEqual([DPSettings shared].screenScaleMode, DPScreenScaleModeAspectFit16x9);
    [[DPSettings shared] setValue:previousScale forPreferenceKey:@"screen_scale_mode"];
    // Opening a second sheet is ignored.
    [emulator showOption:nil];
    XCTAssertEqual(emulator.presentedViewController, navigation);
    // Done uses an explicit completion; interactive dismissal uses the delegate.
    UIBarButtonItem *done = settings.navigationItem.rightBarButtonItem;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [done.target performSelector:done.action];
#pragma clang diagnostic pop
    [self settle];
    XCTAssertNil(emulator.presentedViewController);
    XCTAssertFalse(dospad_settings_open());
    XCTAssertEqual(dospad_pause_flag, 0);
    XCTAssertTrue(emulator.view.userInteractionEnabled);
    [emulator showOption:nil];
    [self settle];
    navigation = (id)emulator.presentedViewController;
    [navigation dismissViewControllerAnimated:NO completion:nil];
    [emulator presentationControllerDidDismiss:navigation.presentationController];
    XCTAssertFalse(dospad_settings_open());
    XCTAssertEqual(dospad_pause_flag, 0);
}
@end
