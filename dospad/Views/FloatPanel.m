/*
 *  Copyright (C) 2010  Chaoji Li
 *
 *  DOSPAD is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */

#import "FloatPanel.h"
#import "Common.h"

@interface SmoothBar : UIView
{
    
}
@end

@implementation SmoothBar

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        // Initialization code
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (void)drawRect:(CGRect)rect
{
    UIImage *image = ([UIDevice.currentDevice.model isEqual:@"iPad"] ? [UIImage imageNamed:@"landbarblank~iPad"] :
                      [UIImage imageNamed:@"landbarblank"]);
    
    [image drawInRect:rect];
    
    /*
    CGContextRef c = UIGraphicsGetCurrentContext();
    [[UIColor grayColor] set];
    CGContextMoveToPoint(c, 0, 0);
    CGContextAddLineToPoint(c, rect.size.width, 0);
    CGContextAddLineToPoint(c, rect.size.width-rect.size.height, rect.size.height);
    CGContextAddLineToPoint(c, rect.size.height, rect.size.height);
    CGContextFillPath(c);*/
}

@end

@implementation FloatPanel
@synthesize contentView;
@synthesize autoHide;
@synthesize autoHideInterval;

- (id)initWithFrame:(CGRect)frame 
{
    if ((self = [super initWithFrame:frame])) 
    {
        self.backgroundColor=[UIColor clearColor];
        self.clipsToBounds=YES;
        // Initialization code
        contentView = [[SmoothBar alloc] initWithFrame:self.bounds];
        [self addSubview:contentView];
        CGPoint pt = contentView.center;
        contentView.center = CGPointMake(pt.x, pt.y - contentView.frame.size.height);
        autoHide = YES;
        
        if ([UIDevice.currentDevice.model isEqual:@"iPad"])
        {
            btnAutoHide = [[UIButton alloc] initWithFrame:CGRectMake(0,0,48,24)];
            [btnAutoHide setImage:[UIImage imageNamed:@"unsticky~ipad"] forState:UIControlStateNormal];
            [btnAutoHide addTarget:self
                            action:@selector(toggleAutoHide) 
                  forControlEvents:UIControlEventTouchUpInside];
            btnAutoHide.center = CGPointMake(635, 18);
            [contentView addSubview:btnAutoHide];            
        }
        else
        {
            btnAutoHide = [[UIButton alloc] initWithFrame:CGRectMake(0,0,48,24)];
            [btnAutoHide setImage:[UIImage imageNamed:@"unsticky"] forState:UIControlStateNormal];
            [btnAutoHide addTarget:self
                            action:@selector(toggleAutoHide) 
                  forControlEvents:UIControlEventTouchUpInside];
            btnAutoHide.center = CGPointMake(432, 12);
            [contentView addSubview:btnAutoHide];
        }
        
        // Seconds before hiding the control bar
        autoHideInterval = 3;
    }
    return self;
}
             
- (void)toggleAutoHide
{
    [self setAutoHide:!autoHide];
}


- (void)resetAutoHideTimer
{
    if (autoHide)
    {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideContent) object:nil];
        [self performSelector:@selector(hideContent) withObject:nil afterDelay:autoHideInterval];
    }
}

- (void)setItems:(NSArray*)itemArray
{
    float marginx = ([UIDevice.currentDevice.model isEqual:@"iPad"] ? 95 : 66);
    float marginy_bot = ([UIDevice.currentDevice.model isEqual:@"iPad"] ? 10 : 7);
 
    if (!itemArray.count) return;
    float usableWidth = contentView.frame.size.width-marginx*2;
    float w = usableWidth / itemArray.count;
    float h = contentView.frame.size.height - marginy_bot;
    BOOL compact = NO;
    for (UIView *item in itemArray) {
        if (item.bounds.size.width > w) compact = YES;
    }
    // The first item is the CPU display; retain its internal label geometry.
    float indicatorWidth = ((UIView *)itemArray.firstObject).bounds.size.width;
    float buttonSlot = itemArray.count > 1
        ? (usableWidth - indicatorWidth) / (itemArray.count - 1) : usableWidth;
 
    if (items != nil)
    {
        for (UIView *v in items) 
            [v removeFromSuperview];
    }
    items = itemArray;
    
    for (int i = 0; i < [itemArray count]; i++)
    {
        UIView * v = [itemArray objectAtIndex:i];
        if (compact && i > 0) {
            CGRect bounds = v.bounds;
            bounds.size.width = MIN(bounds.size.width, buttonSlot);
            v.bounds = bounds;
            if ([v isKindOfClass:UIButton.class]) {
                UIButton *button = (UIButton *)v;
                for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateHighlighted)]) {
                    UIImage *image = [button imageForState:state.unsignedIntegerValue];
                    if (!image) continue;
                    CGFloat scale = MIN(1, MIN(bounds.size.width / image.size.width,
                                               bounds.size.height / image.size.height));
                    if (scale < 1) {
                        CGSize size = CGSizeMake(image.size.width * scale, image.size.height * scale);
                        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
                        UIImage *fitted = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                            [image drawInRect:(CGRect){CGPointZero, size}];
                        }];
                        [button setImage:fitted forState:state.unsignedIntegerValue];
                    }
                }
            }
        }
        CGFloat centerX = marginx+w*i+w/2;
        if (compact) {
            centerX = i == 0 ? marginx+indicatorWidth/2
                : marginx+indicatorWidth+buttonSlot*(i-1)+buttonSlot/2;
        }
        v.center = CGPointMake(centerX,h/2);
        [contentView addSubview:v];
        if ([v isKindOfClass:[UIControl class]])
        {
//            [(UIControl*)v addTarget:self action:@selector(resetAutoHideTimer)
//                    forControlEvents:UIControlEventTouchDown];
            [(UIControl*)v addTarget:self action:@selector(resetAutoHideTimer)
                    forControlEvents:UIControlEventTouchUpInside];
        }
    }
}

- (void)setAutoHide:(BOOL)b
{
    autoHide = b;
    if (b)
    {
        [btnAutoHide setImage:[UIImage imageNamed:[UIDevice.currentDevice.model isEqual:@"iPad"] ? @"unsticky~ipad.png" : @"unsticky.png"]
                     forState:UIControlStateNormal];
        [self performSelector:@selector(hideContent) withObject:nil afterDelay:autoHideInterval];
    }
    else
    {
        [btnAutoHide setImage:[UIImage imageNamed:[UIDevice.currentDevice.model isEqual:@"iPad"] ? @"sticky~ipad.png" : @"sticky.png"]
                     forState:UIControlStateNormal]; 
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideContent) object:nil];
    }
}

// Hide landbar content
- (void)hideContent
{
    if (!isContentShowing)
        return;
    isContentShowing = NO;
    
    CGPoint ptOrig = contentView.center;
    [UIView animateWithDuration:0.5 animations:^{
        self->contentView.center = CGPointMake(ptOrig.x, ptOrig.y - self->contentView.frame.size.height);
    }];
}

// Show landbar content
- (void)showContent
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideContent) object:nil];
    if (autoHide)
    {
        [self performSelector:@selector(hideContent) withObject:nil afterDelay:autoHideInterval];
    }
    if (!isContentShowing)
    {
        isContentShowing = YES;
        CGPoint ptOrig = contentView.center;
        [UIView animateWithDuration:0.5 animations:^{
            self->contentView.center = CGPointMake(ptOrig.x, ptOrig.y + self->contentView.frame.size.height);
        }];
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self showContent];
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

@end
