#import "Tweak.h"
#import <rootless.h>

// Adapted from 
// https://github.com/PoomSmart/YouPiP/blob/bd04bf37be3d01540db418061164ae17a8f0298e/Settings.x
// https://github.com/qnblackcat/uYouPlus/blob/265927b3900d886e2085d05bfad7cd4157be87d2/Settings.xm

#define LOCALIZED_STRING(s) [bundle localizedStringForKey:s value:nil table:nil]

static const NSInteger sectionId = 517; // DontEatMyContent's section ID (just a random number)
extern CGFloat constant;

static void DEMC_showSnackBar(NSString *text) {
	YTHUDMessage *message = [%c(YTHUDMessage) messageWithText:text];
	GOOHUDManagerInternal *manager = [%c(GOOHUDManagerInternal) sharedInstance];
	[manager showMessageMainThread:message];
}

%hook YTAppSettingsPresentationData
+ (NSArray *)settingsCategoryOrder {
	NSArray *order = %orig;
	NSMutableArray *mutableOrder = [order mutableCopy];
	NSUInteger insertIndex = [order indexOfObject:@(1)]; // Index of Settings > General
	if (insertIndex != NSNotFound)
		[mutableOrder insertObject:@(sectionId) atIndex:insertIndex + 1]; // Insert DontEatMyContent settings under General
	return mutableOrder;
}
%end

// Category for additional DEMC functions
@interface YTSettingsSectionItemManager (DEMC)
- (void)DEMC_updateSectionWithEntry:(id)entry;
@end

%hook YTSettingsSectionItemManager
%new
- (void)DEMC_updateSectionWithEntry:(id)entry {
	YTSettingsViewController *delegate = [self valueForKey:@"_dataDelegate"];
	NSMutableArray *sectionItems = [NSMutableArray array]; // Create autoreleased array

	// Get tweak bundle
	static NSBundle *bundle = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"DontEatMyContent" ofType:@"bundle"];
		if (bundlePath)
			bundle = [NSBundle bundleWithPath:bundlePath];
		else // Rootless
			bundle = [NSBundle bundleWithPath:ROOT_PATH_NS(@"/Library/Application Support/DontEatMyContent.bundle")];
	});

	// Enabled
	YTSettingsSectionItem *enabled = [%c(YTSettingsSectionItem) switchItemWithTitle:LOCALIZED_STRING(@"ENABLED")
		titleDescription:LOCALIZED_STRING(@"TWEAK_DESC")
		accessibilityIdentifier:nil
		switchOn:IS_TWEAK_ENABLED
		switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
			[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:ENABLED_KEY];
			
			YTAlertView *alert = [%c(YTAlertView) confirmationDialogWithAction:^ {
					// https://stackoverflow.com/a/17802404/19227228
					[[UIApplication sharedApplication] performSelector:@selector(suspend)];
					[NSThread sleepForTimeInterval:0.5];
					exit(0);
				}
				actionTitle:LOCALIZED_STRING(@"EXIT")
				cancelTitle:LOCALIZED_STRING(@"CANCEL")
			];
			alert.title = LOCALIZED_STRING(@"EXIT_YT");
			alert.subtitle = LOCALIZED_STRING(@"EXIT_YT_DESC");
			[alert show];

			return YES;
		}
		settingItemId:0
	];
	[sectionItems addObject:enabled];

	// Safe area constant
	YTSettingsSectionItem *constraintConstant = [%c(YTSettingsSectionItem) itemWithTitle:LOCALIZED_STRING(@"SAFE_AREA_CONST")
		titleDescription:LOCALIZED_STRING(@"SAFE_AREA_CONST_DESC")
		accessibilityIdentifier:nil
		detailTextBlock:^NSString *() {
			return [NSString stringWithFormat:@"%.1f", constant];
		}
		selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger sectionItemIndex) {
			__block YTSettingsViewController *settingsViewController = [self valueForKey:@"_settingsViewControllerDelegate"];
			NSMutableArray *rows = [NSMutableArray array];
			
			float currentConstant = 20.0;
			float storedConstant = [[NSUserDefaults standardUserDefaults] floatForKey:SAFE_AREA_CONSTANT_KEY];;
			UInt8 index = 0, selectedIndex = 0;
			while (currentConstant <= 25.0) {
				NSString *title = [NSString stringWithFormat:@"%.1f", currentConstant];
				if (currentConstant == DEFAULT_CONSTANT)
					title = [NSString stringWithFormat:@"%.1f (%@)", currentConstant, LOCALIZED_STRING(@"DEFAULT")];
				if (currentConstant == storedConstant)
					selectedIndex = index;
				[rows addObject:[%c(YTSettingsSectionItem) checkmarkItemWithTitle:title
					selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger sectionItemIndex) {
						[[NSUserDefaults standardUserDefaults] setFloat:currentConstant forKey:SAFE_AREA_CONSTANT_KEY];
						constant = currentConstant;
						[settingsViewController reloadData]; // Refresh section's detail text (constant)
						DEMC_showSnackBar(LOCALIZED_STRING(@"SAFE_AREA_CONST_MESSAGE"));
						return YES;
					}
				]];
				currentConstant += 0.5; index++;
			}

			YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOCALIZED_STRING(@"SAFE_AREA_CONST")
				pickerSectionTitle:nil
				rows:rows
				selectedItemIndex:selectedIndex
				parentResponder:[self parentResponder]
			];

        	[settingsViewController pushViewController:picker];
			return YES;
		}
	];
	[sectionItems addObject:constraintConstant];

	// Color views
	YTSettingsSectionItem *colorViews = [%c(YTSettingsSectionItem) switchItemWithTitle:LOCALIZED_STRING(@"COLOR_VIEWS")
		titleDescription:LOCALIZED_STRING(@"COLOR_VIEWS_DESC")
		accessibilityIdentifier:nil
		switchOn:IS_COLOR_VIEWS_ENABLED
		switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
			[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:COLOR_VIEWS_ENABLED_KEY];
			DEMC_showSnackBar(LOCALIZED_STRING(@"CHANGES_SAVED"));
			return YES;
		}
		settingItemId:0
	];
	[sectionItems addObject:colorViews];

	// Report an issue
	YTSettingsSectionItem *reportIssue = [%c(YTSettingsSectionItem) itemWithTitle:LOCALIZED_STRING(@"REPORT_ISSUE")
		titleDescription:nil
		accessibilityIdentifier:nil
		detailTextBlock:nil
		selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger sectionItemIndex) {
			return [%c(YTUIUtils) openURL:[NSURL URLWithString:@"https://github.com/therealFoxster/DontEatMyContent/issues/new"]];
		}
	];
	[sectionItems addObject:reportIssue];

	// View source code
	YTSettingsSectionItem *sourceCode = [%c(YTSettingsSectionItem) itemWithTitle:LOCALIZED_STRING(@"SOURCE_CODE")
		titleDescription:nil
		accessibilityIdentifier:nil
		detailTextBlock:nil
		selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger sectionItemIndex) {
			return [%c(YTUIUtils) openURL:[NSURL URLWithString:@"https://github.com/therealFoxster/DontEatMyContent"]];
		}
	];
	[sectionItems addObject:sourceCode];

	[delegate setSectionItems:sectionItems 
		forCategory:sectionId 
		title:@"DontEatMyContent" 
		titleDescription:nil 
		headerHidden:NO
	];
}
- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category == sectionId) {
        [self DEMC_updateSectionWithEntry:entry];
        return;
    }
    %orig;
}
%end