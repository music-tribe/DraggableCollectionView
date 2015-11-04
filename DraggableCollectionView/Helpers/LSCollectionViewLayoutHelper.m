//
//  Copyright (c) 2013 Luke Scott
//  https://github.com/lukescott/DraggableCollectionView
//  Distributed under MIT license
//

#import "LSCollectionViewLayoutHelper.h"

@interface LSCollectionViewLayoutHelper ()

@end

@implementation LSCollectionViewLayoutHelper

- (id)initWithCollectionViewLayout:(UICollectionViewLayout<UICollectionViewLayout_Warpable>*)collectionViewLayout
{
    self = [super init];
    if (self) {
        _collectionViewLayout = collectionViewLayout;
    }
    return self;
}

- (NSArray *)modifiedLayoutAttributesForElements:(NSArray *)elements
{
    UICollectionView *collectionView = self.collectionViewLayout.collectionView;
    NSIndexPath *fromIndexPath = self.fromIndexPath;
    NSIndexPath *toIndexPath = self.toIndexPath;
    NSIndexPath *hideIndexPath = self.hideIndexPath;
    NSIndexPath *indexPathToRemove;
    
    const CGFloat heightInsetAmount = 4;
    
    // Default layout
    for(int i = 0; i < [elements count]; ++i) {
        UICollectionViewLayoutAttributes *currentLayoutAttributes = elements[i];
        
        NSInteger maximumSpacing = 10;

        CGRect frame = currentLayoutAttributes.frame;
        frame.size.height = _collectionViewLayout.collectionViewContentSize.height - (heightInsetAmount * 2);
        frame.origin.y = heightInsetAmount;
        if (i != 0) {
            UICollectionViewLayoutAttributes *prevLayoutAttributes = elements[i - 1];
        }
        
        currentLayoutAttributes.frame = frame;
    }
    
    if (toIndexPath == nil) {
        if (hideIndexPath == nil) {
            return elements;
        }
        for (UICollectionViewLayoutAttributes *layoutAttributes in elements) {
            if(layoutAttributes.representedElementCategory != UICollectionElementCategoryCell) {
                continue;
            }
        }
        
        [self rearrangeIndexPathOfLayoutAttributesForElements:elements];
        
        return elements;
    }
    
    [self rearrangeIndexPathOfLayoutAttributesForElements:elements];
    
    if (fromIndexPath.section != toIndexPath.section) {
        indexPathToRemove = [NSIndexPath indexPathForItem:[collectionView numberOfItemsInSection:fromIndexPath.section] - 1
                                                inSection:fromIndexPath.section];
    }
    
    for (UICollectionViewLayoutAttributes *layoutAttributes in elements) {
        if (layoutAttributes.representedElementCategory != UICollectionElementCategoryCell) {
            continue;
        }
        
        NSIndexPath *indexPath = layoutAttributes.indexPath;
       
        if([indexPath isEqual:toIndexPath]) {
            // Item's new location
            layoutAttributes.indexPath = fromIndexPath;
        }
        else {
            if (indexPath.item <= fromIndexPath.item && indexPath.item > toIndexPath.item) {
                // Item moved back
                layoutAttributes.indexPath = [NSIndexPath indexPathForItem:indexPath.item - 1 inSection:indexPath.section];
            }
            
            else if (indexPath.item >= fromIndexPath.item && indexPath.item < toIndexPath.item) {
                // Item moved forward
                layoutAttributes.indexPath = [NSIndexPath indexPathForItem:indexPath.item + 1 inSection:indexPath.section];
            }
        }
    }
    
    return elements;
}

/// Accounts for difference in iOS 9 where the order of elements can not be counted
- (void)rearrangeIndexPathOfLayoutAttributesForElements:(NSArray *)elements
{
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 9.0) {
            NSComparator comparator = ^(NSIndexPath *element1, NSIndexPath *element2){
        
                if (element1.section < element2.section) {
                            return (NSComparisonResult)NSOrderedAscending;
                }
        
                if (element1.row < element2.row) {
                        return (NSComparisonResult)NSOrderedAscending;
                }
    
                return (NSComparisonResult)NSOrderedDescending;
            };
    
            NSMutableArray *indexPathArray = [NSMutableArray array];
    
            for (UICollectionViewLayoutAttributes *layoutAttributes in elements) {
                    [indexPathArray addObject:layoutAttributes.indexPath];
            }
    
            NSArray *sortedArray = [[NSArray arrayWithArray:indexPathArray] sortedArrayUsingComparator:comparator];
        
            for (NSInteger index = 0; index < sortedArray.count; ++index) {
                        ((UICollectionViewLayoutAttributes*)[elements objectAtIndex:index]).indexPath = (NSIndexPath *)[sortedArray objectAtIndex:index];
            }
        }
}

@end
