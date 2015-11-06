//
//  Copyright (c) 2013 Luke Scott
//  https://github.com/lukescott/DraggableCollectionView
//  Distributed under MIT license
//

#import "LSCollectionViewHelper.h"
#import "UICollectionViewLayout_Warpable.h"
#import "UICollectionViewDataSource_Draggable.h"
#import "LSCollectionViewLayoutHelper.h"
#import <QuartzCore/QuartzCore.h>

static int kObservingCollectionViewLayoutContext;

#ifndef CGGEOMETRY__SUPPORT_H_
CG_INLINE CGPoint
_CGPointAdd(CGPoint point1, CGPoint point2) {
    return CGPointMake(point1.x + point2.x, point1.y + point2.y);
}
#endif

typedef NS_ENUM(NSInteger, _ScrollingDirection) {
    _ScrollingDirectionUnknown = 0,
    _ScrollingDirectionUp,
    _ScrollingDirectionDown,
    _ScrollingDirectionLeft,
    _ScrollingDirectionRight
};

@interface LSCollectionViewHelper ()
{
    NSIndexPath *lastIndexPath;
    UICollectionViewCell *mockCell;
    CGPoint mockCenter;
    CGPoint fingerTranslation;
    CADisplayLink *timer;
    _ScrollingDirection scrollingDirection;
    BOOL canWarp;
    BOOL canScroll;
    NSArray<UIPanGestureRecognizer *> *_panGestures;
    UIPanGestureRecognizer *_currentPanPressGesture;
}
@property (readonly, nonatomic) LSCollectionViewLayoutHelper *layoutHelper;
@end

@implementation LSCollectionViewHelper

- (id)initWithCollectionView:(UICollectionView *)collectionView
{
    self = [super init];
    if (self) {
        _collectionView = collectionView;
        [_collectionView addObserver:self
                          forKeyPath:@"collectionViewLayout"
                             options:0
                             context:&kObservingCollectionViewLayoutContext];
        _scrollingEdgeInsets = UIEdgeInsetsMake(50.0f, 50.0f, 50.0f, 50.0f);
        _scrollingSpeed = 600.f;
        
        [self layoutChanged];
    }
    return self;
}

- (LSCollectionViewLayoutHelper *)layoutHelper
{
    return [(id <UICollectionViewLayout_Warpable>)self.collectionView.collectionViewLayout layoutHelper];
}

- (void)layoutChanged
{
    canWarp = [self.collectionView.collectionViewLayout conformsToProtocol:@protocol(UICollectionViewLayout_Warpable)];
    canScroll = [self.collectionView.collectionViewLayout respondsToSelector:@selector(scrollDirection)];
    
    for (UIPanGestureRecognizer *panPress in _panGestures) {
        panPress.enabled = canWarp && self.enabled;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == &kObservingCollectionViewLayoutContext) {
        [self layoutChanged];
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)setEnabled:(BOOL)enabled
{
    _enabled = enabled;
    
    for (UIPanGestureRecognizer *panPress in _panGestures) {
        panPress.enabled = canWarp && self.enabled;
    }
}

- (void)invalidatesScrollTimer {
    if (timer != nil) {
        [timer invalidate];
        timer = nil;
    }
    scrollingDirection = _ScrollingDirectionUnknown;
}

- (void)setupScrollTimerInDirection:(_ScrollingDirection)direction {
    scrollingDirection = direction;
    if (timer == nil) {
        timer = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleScroll:)];
        [timer addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    }
}

- (NSIndexPath *)indexPathForItemClosestToPoint:(CGPoint)point
{
    NSArray *layoutAttrsInRect;
    NSInteger closestDist = NSIntegerMax;
    NSIndexPath *indexPath;
    NSIndexPath *toIndexPath = self.layoutHelper.toIndexPath;
    
    // We need original positions of cells
    self.layoutHelper.toIndexPath = nil;
    layoutAttrsInRect = [self.collectionView.collectionViewLayout layoutAttributesForElementsInRect:self.collectionView.bounds];
    self.layoutHelper.toIndexPath = toIndexPath;
    
    // What cell are we closest to?
    for (UICollectionViewLayoutAttributes *layoutAttr in layoutAttrsInRect) {
        CGFloat xd = layoutAttr.center.x - point.x;
        NSInteger dist = sqrtf(xd*xd);
        if (dist < closestDist) {
            closestDist = dist;
            indexPath = layoutAttr.indexPath;
        }
    }
    
    return indexPath;
}

- (void)handleInitialGesture:(UIPanGestureRecognizer *)sender
{
    if (_currentPanPressGesture == nil ) {
        _currentPanPressGesture = sender;
    }
    
    else if (sender != _currentPanPressGesture) {
        return;
    }
    
    if (sender.state == UIGestureRecognizerStateChanged) {
        [self handlePanGesture:sender];
        return;
    }
    if (![self.collectionView.dataSource conformsToProtocol:@protocol(UICollectionViewDataSource_Draggable)]) {
        return;
    }
    
    NSIndexPath *indexPath = [self indexPathForItemClosestToPoint:[sender locationInView:self.collectionView]];
    
    switch (sender.state) {
        case UIGestureRecognizerStateBegan: {
            if (indexPath == nil) {
                return;
            }
            if (![(id<UICollectionViewDataSource_Draggable>)self.collectionView.dataSource
                  collectionView:self.collectionView
                  canMoveItemAtIndexPath:indexPath]) {
                return;
            }
            // Create mock cell to drag around
            UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
            cell.highlighted = NO;
            mockCell = cell;
            mockCenter = mockCell.center;
            
            // Start warping
            cell.selected = YES;
            lastIndexPath = indexPath;
            self.layoutHelper.fromIndexPath = indexPath;
            self.layoutHelper.hideIndexPath = indexPath;
            self.layoutHelper.toIndexPath = indexPath;
        } break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            if(self.layoutHelper.fromIndexPath == nil) {
                return;
            }
            // Need these for later, but need to nil out layoutHelper's references sooner
            NSIndexPath *fromIndexPath = self.layoutHelper.fromIndexPath;
            NSIndexPath *toIndexPath = self.layoutHelper.toIndexPath;
            // Tell the data source to move the item
            id<UICollectionViewDataSource_Draggable> dataSource = (id<UICollectionViewDataSource_Draggable>)self.collectionView.dataSource;
            [dataSource collectionView:self.collectionView moveItemAtIndexPath:fromIndexPath toIndexPath:toIndexPath];
           
            // Move the item
            [self.collectionView performBatchUpdates:^{
                [self.collectionView moveItemAtIndexPath:fromIndexPath toIndexPath:toIndexPath];
                self.layoutHelper.fromIndexPath = nil;
                self.layoutHelper.toIndexPath = nil;
            } completion:^(BOOL finished) {
                if (finished) {
                    if ([dataSource respondsToSelector:@selector(collectionView:didMoveItemAtIndexPath:toIndexPath:)]) {
                        [dataSource collectionView:self.collectionView didMoveItemAtIndexPath:fromIndexPath toIndexPath:toIndexPath];
                    }
                }
            }];
            
            // Switch mock for cell
            UICollectionViewLayoutAttributes *layoutAttributes = [self.collectionView layoutAttributesForItemAtIndexPath:self.layoutHelper.hideIndexPath];
            [UIView
             animateWithDuration:0.01
             animations:^{
                mockCell.center = layoutAttributes.center;
             }
             completion:^(BOOL finished) {
                // [mockCell removeFromSuperview];
                 mockCell.selected = NO;
                 mockCell = nil;
                 self.layoutHelper.hideIndexPath = nil;
                 [self.collectionView.collectionViewLayout invalidateLayout];
                 _currentPanPressGesture = nil;
             }];
            
            // Reset
            [self invalidatesScrollTimer];
            lastIndexPath = nil;
        } break;
        default: break;
    }
}

- (void)warpToIndexPath:(NSIndexPath *)indexPath
{
    if(indexPath == nil || [lastIndexPath isEqual:indexPath]) {
        return;
    }
    lastIndexPath = indexPath;
    
    if ([self.collectionView.dataSource respondsToSelector:@selector(collectionView:canMoveItemAtIndexPath:toIndexPath:)] == YES
        && [(id<UICollectionViewDataSource_Draggable>)self.collectionView.dataSource
            collectionView:self.collectionView
            canMoveItemAtIndexPath:self.layoutHelper.fromIndexPath
            toIndexPath:indexPath] == NO) {
        return;
    }
    
    // we don't won't the default animations here
    [UIView setAnimationsEnabled:NO];
    [self.collectionView performBatchUpdates:^{
        [_collectionView bringSubviewToFront:mockCell];
        self.layoutHelper.hideIndexPath = indexPath;
        self.layoutHelper.toIndexPath = indexPath;
    } completion:nil];
    [UIView setAnimationsEnabled:YES];
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)sender
{
    if(sender.state == UIGestureRecognizerStateChanged) {
        // Move mock to match finger
        fingerTranslation = [sender translationInView:self.collectionView];
        // Only translate in the x axis
        switch (_draggableAxis) {
            case DraggableAxisBoth:
                mockCell.center = _CGPointAdd(mockCenter, fingerTranslation);
                break;
                
            case DraggableAxisX:
                mockCell.center = CGPointMake(mockCenter.x + fingerTranslation.x, mockCenter.y);
                break;
                
            case DraggableAxisY:
                mockCell.center = CGPointMake(mockCenter.x , mockCenter.y + fingerTranslation.y);
                break;
                
            default:
                [NSException raise:NSInternalInconsistencyException format:@"unrecognised DraggableAxis enum"];
                break;
        }
        
        // Scroll when necessary
        if (canScroll) {
            UICollectionViewFlowLayout *scrollLayout = (UICollectionViewFlowLayout*)self.collectionView.collectionViewLayout;
            if([scrollLayout scrollDirection] == UICollectionViewScrollDirectionVertical) {
                if (mockCell.center.y < (CGRectGetMinY(self.collectionView.bounds) + self.scrollingEdgeInsets.top)) {
                    [self setupScrollTimerInDirection:_ScrollingDirectionUp];
                }
                else {
                    if (mockCell.center.y > (CGRectGetMaxY(self.collectionView.bounds) - self.scrollingEdgeInsets.bottom)) {
                        [self setupScrollTimerInDirection:_ScrollingDirectionDown];
                    }
                    else {
                        [self invalidatesScrollTimer];
                    }
                }
            }
            else {
                if (mockCell.center.x < (CGRectGetMinX(self.collectionView.bounds) + self.scrollingEdgeInsets.left)) {
                    [self setupScrollTimerInDirection:_ScrollingDirectionLeft];
                } else {
                    if (mockCell.center.x > (CGRectGetMaxX(self.collectionView.bounds) - self.scrollingEdgeInsets.right)) {
                        [self setupScrollTimerInDirection:_ScrollingDirectionRight];
                    } else {
                        [self invalidatesScrollTimer];
                    }
                }
            }
        }
        
        // Avoid warping a second time while scrolling
        if (scrollingDirection > _ScrollingDirectionUnknown) {
            return;
        }
        
        // Warp item to finger location
        CGPoint point = mockCell.center;
        NSIndexPath *indexPath = [self indexPathForItemClosestToPoint:point];
        [self warpToIndexPath:indexPath];
    }
}

- (void)addPanGesture:(UIPanGestureRecognizer *)panGesture
{
    [panGesture addTarget:self action:@selector(handleInitialGesture:)];
    
    NSMutableArray<UIPanGestureRecognizer *> *newPanGestures = [[NSMutableArray alloc] initWithArray:_panGestures];
    [newPanGestures addObject:panGesture];
    
    _panGestures = newPanGestures.copy;
}

- (void)handleScroll:(NSTimer *)timer {
    if (scrollingDirection == _ScrollingDirectionUnknown) {
        return;
    }
    
    CGSize frameSize = self.collectionView.bounds.size;
    CGSize contentSize = self.collectionView.contentSize;
    CGPoint contentOffset = self.collectionView.contentOffset;
    CGFloat distance = self.scrollingSpeed / 60.f;
    CGPoint translation = CGPointZero;
    
    switch(scrollingDirection) {
        case _ScrollingDirectionUp: {
            distance = -distance;
            if ((contentOffset.y + distance) <= 0.f) {
                distance = -contentOffset.y;
            }
            translation = CGPointMake(0.f, distance);
        } break;
        case _ScrollingDirectionDown: {
            CGFloat maxY = MAX(contentSize.height, frameSize.height) - frameSize.height;
            if ((contentOffset.y + distance) >= maxY) {
                distance = maxY - contentOffset.y;
            }
            translation = CGPointMake(0.f, distance);
        } break;
        case _ScrollingDirectionLeft: {
            distance = -distance;
            if ((contentOffset.x + distance) <= 0.f) {
                distance = -contentOffset.x;
            }
            translation = CGPointMake(distance, 0.f);
        } break;
        case _ScrollingDirectionRight: {
            CGFloat maxX = MAX(contentSize.width, frameSize.width) - frameSize.width;
            if ((contentOffset.x + distance) >= maxX) {
                distance = maxX - contentOffset.x;
            }
            translation = CGPointMake(distance, 0.f);
        } break;
        default: break;
    }
    
    switch (_draggableAxis) {
        case DraggableAxisBoth:
            mockCenter  = _CGPointAdd(mockCenter, translation);
            mockCell.center = _CGPointAdd(mockCenter, fingerTranslation);
            self.collectionView.contentOffset = _CGPointAdd(contentOffset, translation);
            break;
            
        case DraggableAxisX:
            mockCenter.x  += translation.x;
            mockCell.center = CGPointMake(mockCenter.x + fingerTranslation.x, mockCenter.y);
            self.collectionView.contentOffset = CGPointMake(contentOffset.x + translation.x, contentOffset.y);
            break;
            
        case DraggableAxisY:
            mockCenter.y  += translation.y;
            mockCell.center = CGPointMake(mockCenter.x, mockCenter.y  + fingerTranslation.y);
            self.collectionView.contentOffset = CGPointMake(contentOffset.x, contentOffset.y + translation.x);
            break;
            
        default:
            [NSException raise:NSInternalInconsistencyException format:@"unrecognised DraggableAxis enum"];
            break;
    }
    
    // Warp items while scrolling
    NSIndexPath *indexPath = [self indexPathForItemClosestToPoint:mockCell.center];
    [self warpToIndexPath:indexPath];
}

@end
