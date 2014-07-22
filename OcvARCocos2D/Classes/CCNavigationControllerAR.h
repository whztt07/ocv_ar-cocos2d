#import <Foundation/Foundation.h>

#import "CCDirector.h"
#import "CCAppDelegate.h"

@interface CCNavigationControllerAR : CCNavigationController {
    CCAppDelegate* __weak _appDelegateAR;
    NSString* _screenOrientationAR;
}

@property (nonatomic, weak) CCAppDelegate* appDelegateAR;
@property (nonatomic, strong) NSString* screenOrientationAR;

@end

