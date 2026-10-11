//
//  DPSettings.m
//  dospad
//
//  Created by Chaoji Li on 2020/11/19.
//

#import "DPSettings.h"

#define kTapAsClick @"tap_as_click"
#define kScreenScaleMode @"screen_scale_mode"
#define kDoubleTapAsRightClick @"double_tap_as_right_click"
#define kMouseSpeed            @"mouse_speed"
#define kTransparency          @"transparency"
#define kShowMouseHold         @"show_mouse_hold"
#define kKeySoundEnabled       @"key_sound_enabled"
#define kGamePadSoundEnabled   @"gamepad_sound_enabled"
#define kAutoOpenLast          @"auto_open_last"
#define kKeepScreenAwake       @"keep_screen_awake"
#define kToolbarAutoHideDelay  @"toolbar_auto_hide_delay"
#define kToolbarLastAutoHideDelay @"toolbar_last_auto_hide_delay"
#define kPixelatedScaling      @"screen_pixelated"
#define kMouseAbsEnable        @"mouse_abs_enable"
#define kMouseNumpadMultiToggle  @"mouse_numpad_multi_toggle"
#define kLandbarToggleBottonScreen @"landbar_toggle_bottom_screen"
#define kAutoShrinkScreenKeyboardEnabled @"auto_shrink_screen_keyboard_enabled"

static DPSettings *s_settings;

static BOOL isTimedToolbarDelay(id value)
{
    return [@[@1, @3, @5, @10] containsObject:value];
}

@implementation DPSettings {
    NSDictionary *_lastValues;
}

+ (DPSettings*)shared
{
	if (!s_settings) {
		s_settings = [[DPSettings alloc] init];
	}
	return s_settings;
}


- (id)init
{
	if (self = [super init]) {
		[self registerDefaultSettings];

		[[NSNotificationCenter defaultCenter]
			addObserver:self
    		selector:@selector(defaultsDidChange:)
    		name:NSUserDefaultsDidChangeNotification
    		object:nil];
        
		[self defaultsDidChange:nil];
	}
	return self;
}

- (void)registerDefaultSettings
{
	NSString *path = [[NSBundle mainBundle] pathForResource:@"Settings" ofType:@"plist"];
	NSDictionary *settingsDict = [NSDictionary dictionaryWithContentsOfFile:path];
	_preferenceSpecifiers = settingsDict[@"PreferenceSpecifiers"];
	NSArray *prefs = _preferenceSpecifiers;
	NSMutableDictionary *defs = [NSMutableDictionary dictionary];
    defs[kToolbarLastAutoHideDelay] = @3;
	for (NSDictionary *item in prefs) {
		NSString *key = item[@"Key"];
		NSObject *obj = item[@"DefaultValue"];
		if (key && obj) {
			defs[key] = obj;
		}
	}
	if (defs.count > 0) {
		[[NSUserDefaults standardUserDefaults] registerDefaults:defs];
	}
}

- (id)valueForPreferenceKey:(NSString *)key
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:key];
}

- (void)setValue:(id)value forPreferenceKey:(NSString *)key
{
    NSAssert([NSThread isMainThread], @"Settings must be edited on the main thread");
    if ([[self valueForPreferenceKey:key] isEqual:value]) return;
    if ([key isEqual:kToolbarAutoHideDelay] && isTimedToolbarDelay(value))
        [[NSUserDefaults standardUserDefaults] setObject:value forKey:kToolbarLastAutoHideDelay];
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
    [self defaultsDidChange:nil];
}

- (void)toggleToolbarAutoHide
{
    id delay = @0;
    if (self.toolbarAutoHideDelay == 0) {
        delay = [[NSUserDefaults standardUserDefaults] objectForKey:kToolbarLastAutoHideDelay];
        if (!isTimedToolbarDelay(delay)) delay = @3;
    }
    [self setValue:delay forPreferenceKey:kToolbarAutoHideDelay];
}

- (void)defaultsDidChange:(NSNotification *)notification
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self defaultsDidChange:notification]; });
        return;
    }
    // Defaults notifications also arrive for unrelated app preferences. Avoid
    // redundant refreshes, including the notification following our own write.
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSDictionary *item in self.preferenceSpecifiers) {
        NSString *key = item[@"Key"];
        if (key) values[key] = [self valueForPreferenceKey:key];
    }
    if ([_lastValues isEqual:values]) return;
    NSMutableSet *changedKeys = [NSMutableSet set];
    for (NSString *key in values) {
        if (![_lastValues[key] isEqual:values[key]]) [changedKeys addObject:key];
    }
    _lastValues = [values copy];
    [self loadDefaults];
    [[NSNotificationCenter defaultCenter] postNotificationName:DPFSettingsChangedNotification object:self userInfo:@{@"keys":changedKeys}];
}

- (void)loadDefaults
{
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    _tapAsClick = [defs boolForKey:kTapAsClick];
	_screenScaleMode = [defs integerForKey:kScreenScaleMode];
	_doubleTapAsRightClick = [defs integerForKey:kDoubleTapAsRightClick];
	_mouseSpeed = [defs floatForKey:kMouseSpeed];
	_floatAlpha = 1-[defs floatForKey:kTransparency];
	_showMouseHold = [defs boolForKey:kShowMouseHold];
	_keyPressSound = [defs boolForKey:kKeySoundEnabled];
	_gamepadSound = [defs boolForKey:kGamePadSoundEnabled];
	_autoOpenLastPackage = [defs boolForKey:kAutoOpenLast];
	_keepScreenAwake = [defs boolForKey:kKeepScreenAwake];
    id toolbarDelay = [defs objectForKey:kToolbarAutoHideDelay];
    _toolbarAutoHideDelay = [toolbarDelay isEqual:@0] || isTimedToolbarDelay(toolbarDelay)
        ? [toolbarDelay doubleValue] : 3;
    // Remember timed choices made through external defaults edits as well.
    if (isTimedToolbarDelay(toolbarDelay) &&
        ![[defs objectForKey:kToolbarLastAutoHideDelay] isEqual:toolbarDelay]) {
        [defs setObject:toolbarDelay forKey:kToolbarLastAutoHideDelay];
    }
	_pixelatedScaling = [defs boolForKey:kPixelatedScaling];
    _mouseAbsEnable = [defs boolForKey:kMouseAbsEnable];
    _mouseNumpadMultiToggle = [defs boolForKey:kMouseNumpadMultiToggle];
    _landbarToggleBottomScreen = [defs boolForKey:kLandbarToggleBottonScreen];
    _autoShrinkScreenKeyboardEnabled = [defs boolForKey:kAutoShrinkScreenKeyboardEnabled];
}

@end
