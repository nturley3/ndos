#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "DPSettings.h"
#import "DPKeyboardManager.h"
#import <GameController/GameController.h>
#include "keys.h"

static void check(BOOL condition, NSString *message)
{
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static BOOL settingsOpen;
BOOL dospad_settings_open(void) { return settingsOpen; }

@interface DPKeyboardManager (Testing)
- (void)addKeyboardHandler:(GCKeyboard *)keyboard;
@end

@interface TestKeyboardInput : NSObject
@property (nonatomic, copy) void (^keyChangedHandler)(GCKeyboardInput *, GCControllerButtonInput *, GCKeyCode, BOOL);
@end
@implementation TestKeyboardInput
@end

@interface TestKeyboard : NSObject
@property (nonatomic, strong) TestKeyboardInput *keyboardInput;
@end
@implementation TestKeyboard
@end

@interface TestKeyboardDelegate : NSObject <DPKeyboardManagerDelegate>
@property (nonatomic, strong) NSMutableArray<NSArray *> *events;
@end
@implementation TestKeyboardDelegate
- (void)keyboardManager:(DPKeyboardManager *)manager scancode:(int)scancode pressed:(BOOL)pressed
{
    [self.events addObject:@[@(scancode), @(pressed)]];
}
@end

static void key(TestKeyboard *keyboard, GCKeyCode code, BOOL pressed)
{
    keyboard.keyboardInput.keyChangedHandler(nil, nil, code, pressed);
    __block BOOL processed = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ processed = YES; });
    while (!processed)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
}

static void testKeyboard(DPSettings *settings)
{
    DPKeyboardManager *manager = [[DPKeyboardManager alloc] init];
    TestKeyboardDelegate *delegate = [[TestKeyboardDelegate alloc] init];
    delegate.events = [NSMutableArray array];
    manager.delegate = delegate;
    TestKeyboard *keyboard = [[TestKeyboard alloc] init];
    keyboard.keyboardInput = [[TestKeyboardInput alloc] init];
    [manager addKeyboardHandler:(GCKeyboard *)(id)keyboard];
    [settings setValue:@YES forPreferenceKey:@"smart_keyboard_mappings"];
    key(keyboard, GCKeyCodeLeftGUI, YES);
    key(keyboard, GCKeyCodeOne, YES);
    key(keyboard, GCKeyCodeLeftGUI, NO);
    key(keyboard, GCKeyCodeOne, NO);
    check([delegate.events isEqual:@[@[@(SDL_SCANCODE_F1), @YES], @[@(SDL_SCANCODE_F1), @NO]]], @"Command release before number releases the mapped F-key");
    [delegate.events removeAllObjects];
    [settings setValue:@NO forPreferenceKey:@"smart_keyboard_mappings"];
    key(keyboard, GCKeyCodeLeftGUI, YES);
    key(keyboard, GCKeyCodeOne, YES);
    key(keyboard, GCKeyCodeOne, NO);
    key(keyboard, GCKeyCodeLeftGUI, NO);
    check([delegate.events isEqual:@[@[@(SDL_SCANCODE_1), @YES], @[@(SDL_SCANCODE_1), @NO]]], @"Disabling shortcuts restores ordinary keys");
    [delegate.events removeAllObjects];
    [settings setValue:@YES forPreferenceKey:@"smart_keyboard_mappings"];
    key(keyboard, GCKeyCodeLeftGUI, YES);
    key(keyboard, GCKeyCodeRightGUI, YES);
    key(keyboard, GCKeyCodeLeftGUI, NO);
    key(keyboard, GCKeyCodeGraveAccentAndTilde, YES);
    key(keyboard, GCKeyCodeRightGUI, NO);
    key(keyboard, GCKeyCodeGraveAccentAndTilde, NO);
    check([delegate.events isEqual:@[@[@(SDL_SCANCODE_ESCAPE), @YES], @[@(SDL_SCANCODE_ESCAPE), @NO]]], @"Either Command key enables shortcuts, with balanced releases");
    [delegate.events removeAllObjects];
    settingsOpen = YES;
    [manager willResignActive];
    key(keyboard, GCKeyCodeLeftGUI, YES);
    key(keyboard, GCKeyCodeTwo, YES);
    check(delegate.events.count == 0, @"Settings suppresses hardware keyboard delivery");
    settingsOpen = NO;
    key(keyboard, GCKeyCodeTwo, NO);
    check(delegate.events.count == 0, @"Keys pressed in settings cannot generate orphan releases");
    key(keyboard, GCKeyCodeTwo, YES);
    key(keyboard, GCKeyCodeTwo, NO);
    check([delegate.events isEqual:@[@[@(SDL_SCANCODE_2), @YES], @[@(SDL_SCANCODE_2), @NO]]], @"Keyboard returns to ordinary input after settings closes");
    [NSNotificationCenter.defaultCenter removeObserver:manager];
    NSLog(@"Hardware keyboard mapping and input isolation passed");
}

int main(void)
{
    @autoreleasepool {
        // Use a disposable defaults suite; do not touch app or developer preferences.
        NSString *suite = [@"ndos.settings-test." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        Method method = class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults));
        IMP original = method_setImplementation(method, imp_implementationWithBlock(^id(id receiver) { return defaults; }));
        [defaults setBool:YES forKey:@"auto_open_last"]; // Existing user's preference.
        DPSettings *settings = [[DPSettings alloc] init];
        check(settings.preferenceSpecifiers.count > 0, @"Bundled settings definition loads");
        check(settings.autoOpenLastPackage, @"Registering defaults preserves existing selections");
        check(settings.tapAsClick && settings.keyPressSound && settings.gamepadSound, @"Boolean defaults are preserved");
        check(settings.screenScaleMode == DPScreenScaleModeFill, @"Scale default is preserved");
        check(fabsf(settings.mouseSpeed - 0.5f) < 0.001f && fabsf(settings.floatAlpha - 0.8f) < 0.001f, @"Slider defaults are preserved");
        check(![[settings valueForPreferenceKey:@"smart_keyboard_mappings"] boolValue], @"Keyboard mapping default is false");

        __block NSUInteger notifications = 0;
        __block NSSet *changedKeys;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:DPFSettingsChangedNotification object:settings queue:nil usingBlock:^(NSNotification *note) {
            check(NSThread.isMainThread, @"Change notifications use main thread");
            notifications++;
            changedKeys = note.userInfo[@"keys"];
            check(settings.screenScaleMode == [[settings valueForPreferenceKey:@"screen_scale_mode"] integerValue], @"Cache refreshes before notification");
        }];
        [settings setValue:@4 forPreferenceKey:@"screen_scale_mode"];
        check(settings.screenScaleMode == DPScreenScaleModeAspectFit16x9, @"Scale edit applies synchronously");
        check(notifications == 1 && [changedKeys isEqual:[NSSet setWithObject:@"screen_scale_mode"]], @"One edit reports only its changed key");
        [settings setValue:@4 forPreferenceKey:@"screen_scale_mode"];
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:defaults];
        check(notifications == 1, @"Repeated writes and defaults notifications do not duplicate changes");
        [defaults setBool:YES forKey:@"unrelated_preference"];
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:defaults];
        check(notifications == 1, @"Unrelated preferences do not refresh settings");
        [settings setValue:@0.65 forPreferenceKey:@"transparency"];
        check(fabsf(settings.floatAlpha - 0.35f) < 0.001f, @"Transparency preserves opacity conversion");

        NSUInteger controls = 0;
        for (NSDictionary *item in settings.preferenceSpecifiers) {
            NSString *key = item[@"Key"];
            if (!key) continue;
            controls++;
            check([settings valueForPreferenceKey:key] != nil, @"Every control has a registered default");
            id value = item[@"DefaultValue"];
            if ([item[@"Type"] isEqual:@"PSToggleSwitchSpecifier"]) value = @(![value boolValue]);
            else if ([item[@"Type"] isEqual:@"PSSliderSpecifier"]) value = item[@"MaximumValue"];
            else if ([item[@"Type"] isEqual:@"PSMultiValueSpecifier"]) value = [item[@"Values"] lastObject];
            [settings setValue:value forPreferenceKey:key];
            check([[settings valueForPreferenceKey:key] isEqual:value], @"Every control can be saved");
            check([[defaults persistentDomainForName:suite][key] isEqual:value], @"Edits reach persistent defaults");
        }
        check(controls == 18, @"All 18 existing preferences are represented");

        // A defaults change coming from outside the controller must refresh on main.
        [defaults setFloat:0.25 forKey:@"mouse_speed"];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:defaults];
        });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (fabsf(settings.mouseSpeed - 0.25f) > 0.001f && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        check(fabsf(settings.mouseSpeed - 0.25f) < 0.001f, @"External changes refresh cached preferences");

        testKeyboard(settings);
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        [defaults removePersistentDomainForName:suite];
        method_setImplementation(method, original);
        NSLog(@"Settings persistence and notifications passed");
    }
    return 0;
}
