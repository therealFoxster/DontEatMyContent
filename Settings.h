#import <YTHeaders/YTSettingsCell.h>
#import <YTHeaders/YTSettingsSectionItemManager.h>
#import <YTHeaders/YTSettingsPickerViewController.h>
#import <YTHeaders/YTSettingsSectionItem.h>
#import <YTHeaders/YTSettingsViewController.h>

#define DEMC @"DontEatMyContent"
#define VERSION @"1.1.4"
#define LOCALIZED_STRING(s) [bundle localizedStringForKey:s value:nil table:nil]

extern void DEMC_showSnackBar(NSString *text);
extern NSBundle *DEMC_getTweakBundle();
extern CGFloat constant;

// Category for additional functions
@interface YTSettingsSectionItemManager (DontEatMyContent)
- (void)updateDEMCSectionWithEntry:(id)entry;
@end