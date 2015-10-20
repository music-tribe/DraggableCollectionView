//
//  Copyright (c) 2013 Luke Scott
//  https://github.com/lukescott/DraggableCollectionView
//  Distributed under MIT license
//

#import <UIKit/UIKit.h>
#import "UICollectionViewDataSource_Draggable.h"

typedef NS_ENUM(NSInteger, DraggableAxis) {
    DraggableAxisBoth,
    DraggableAxisX,
    DraggableAxisY
};

@interface UICollectionView (Draggable)

@property (nonatomic, assign) BOOL draggable;
@property DraggableAxis draggableAxis;
@property (nonatomic, assign) UIEdgeInsets scrollingEdgeInsets;
@property (nonatomic, assign) CGFloat scrollingSpeed;
- (void)addLongPressGesture:(UILongPressGestureRecognizer *)longPressGesture;
@end
