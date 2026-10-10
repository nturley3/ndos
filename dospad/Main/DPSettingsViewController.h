#import <UIKit/UIKit.h>

@interface DPSettingsViewController : UITableViewController
@property (nonatomic, copy) void (^didFinish)(void);
@end
