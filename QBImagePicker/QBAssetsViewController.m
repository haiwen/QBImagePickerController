//
//  QBAssetsViewController.m
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import "QBAssetsViewController.h"
#import <Photos/Photos.h>

// Views
#import "QBImagePickerController.h"
#import "QBAlbumsViewController.h"
#import "QBAssetCell.h"
#import "QBCheckmarkView.h"
#import "QBVideoIndicatorView.h"

static CGSize CGSizeScale(CGSize size, CGFloat scale) {
    return CGSizeMake(size.width * scale, size.height * scale);
}

static NSString * const QBAddPhotosCellIdentifier = @"QBAddPhotosCell";

#pragma mark - QBAddPhotosCell

@interface QBAddPhotosCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
- (void)applyTintColor:(UIColor *)tintColor;
- (void)applyIconImage:(UIImage *)image;
@end

@implementation QBAddPhotosCell

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        if (@available(iOS 13.0, *)) {
            self.contentView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        } else {
            self.contentView.backgroundColor = [UIColor colorWithWhite:0.93 alpha:1.0];
        }

        // Default fallback icon — picker hosts can override via
        // `addPhotosIconImage` on QBImagePickerController and the cell will
        // pick that up in `applyIconImage:` below.
        UIImage *icon = nil;
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:28.0 weight:UIImageSymbolWeightMedium];
            icon = [UIImage systemImageNamed:@"plus" withConfiguration:cfg];
        }
        _iconView = [[UIImageView alloc] initWithImage:icon];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:13.0];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.numberOfLines = 1;
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.75;
        [self.contentView addSubview:_titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:-12.0],
            [_iconView.widthAnchor constraintEqualToConstant:32.0],
            [_iconView.heightAnchor constraintEqualToConstant:32.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:6.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:4.0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4.0],
        ]];
    }
    return self;
}

- (void)applyTintColor:(UIColor *)tintColor
{
    UIColor *color = tintColor ?: [UIColor systemBlueColor];
    _iconView.tintColor = color;
    _titleLabel.textColor = color;
}

- (void)applyIconImage:(UIImage *)image
{
    if (!image) { return; }
    // Render as template so the host-provided icon respects the cell tint.
    _iconView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@end

@interface QBImagePickerController (Private)

@property (nonatomic, strong) NSBundle *assetBundle;

@end

@implementation NSIndexSet (Convenience)

- (NSArray *)qb_indexPathsFromIndexesWithSection:(NSUInteger)section
{
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:self.count];
    [self enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [indexPaths addObject:[NSIndexPath indexPathForItem:idx inSection:section]];
    }];
    return indexPaths;
}

@end

@implementation UICollectionView (Convenience)

- (NSArray *)qb_indexPathsForElementsInRect:(CGRect)rect
{
    NSArray *allLayoutAttributes = [self.collectionViewLayout layoutAttributesForElementsInRect:rect];
    if (allLayoutAttributes.count == 0) { return nil; }
    
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:allLayoutAttributes.count];
    for (UICollectionViewLayoutAttributes *layoutAttributes in allLayoutAttributes) {
        NSIndexPath *indexPath = layoutAttributes.indexPath;
        [indexPaths addObject:indexPath];
    }
    return indexPaths;
}

@end

@interface QBAssetsViewController () <PHPhotoLibraryChangeObserver, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) IBOutlet UIBarButtonItem *doneButton;

@property (nonatomic, strong) PHFetchResult *fetchResult;

@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, assign) CGRect previousPreheatRect;

@property (nonatomic, assign) BOOL disableScrollToBottom;
@property (nonatomic, strong) NSIndexPath *lastSelectedItemIndexPath;

@end

@implementation QBAssetsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self setUpToolbarItems];
    [self resetCachedAssets];

    // Register the trailing "Add Photos" cell so it can be dequeued when
    // `showsAddPhotosCell` is enabled on the picker controller.
    [self.collectionView registerClass:[QBAddPhotosCell class] forCellWithReuseIdentifier:QBAddPhotosCellIdentifier];

    // Register observer
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
}

#pragma mark - Add Photos cell helpers

- (BOOL)shouldShowAddCell
{
    return self.imagePickerController.showsAddPhotosCell;
}

// Number of trailing non-asset cells (currently 0 or 1). When 1, the
// "Add Photos" cell sits at the very end of the grid (i.e. immediately
// to the right of the newest photo) instead of the leading position.
- (NSInteger)trailingExtraCellCount
{
    return [self shouldShowAddCell] ? 1 : 0;
}

// Convert a collection view item index to an index into `self.fetchResult`.
// Returns NSNotFound when `item` points at a non-asset (e.g. the trailing +cell).
- (NSInteger)assetIndexForItem:(NSInteger)item
{
    if (item < (NSInteger)self.fetchResult.count) {
        return item;
    }
    return NSNotFound;
}

// Convert a fetch-result asset index back to the matching collection view
// index path. Asset indexes map 1:1 to item indexes because the only
// non-asset cell (the +cell) is appended at the end of the section.
- (NSIndexPath *)indexPathForAssetIndex:(NSInteger)assetIndex
{
    return [NSIndexPath indexPathForItem:assetIndex inSection:0];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    // Configure navigation item
    self.navigationItem.title = self.assetCollection.localizedTitle;
    self.navigationItem.prompt = self.imagePickerController.prompt;

    // Install a custom leading back button when the host provided a
    // back-arrow image. We pre-render the image at a fixed display size
    // and place it inside a UIImageView with an explicit frame so the
    // visible icon size is decoupled from the source asset's pixel
    // dimensions. The 12x20 icon centered in a 30x44 hit target matches
    // the main app's SeafNavLeftItem styling. The image is rendered as a
    // template and tinted with the picker's tintColor so its color stays
    // in sync with the rest of the host app's nav bar (e.g. Seafile's
    // #666666 gray) instead of falling back to the raw PNG black.
    UIImage *backImage = self.imagePickerController.backIndicatorImage;
    if (backImage) {
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 44)];
        container.clipsToBounds = YES;

        // Preserve the source aspect ratio while constraining the longest
        // edge to 20pt — gives a clean back chevron regardless of whether
        // the host supplied a tall (18x36) or square asset.
        CGSize source = backImage.size;
        CGFloat scale = MIN(20.0 / source.width, 20.0 / source.height);
        if (!isfinite(scale) || scale <= 0) { scale = 1.0; }
        CGSize iconSize = CGSizeMake(source.width * scale, source.height * scale);
        UIImage *rendered = [QBAlbumsViewController qb_renderImage:backImage
                                                            inSize:iconSize
                                                     renderingMode:UIImageRenderingModeAlwaysTemplate];
        UIImageView *icon = [[UIImageView alloc] initWithImage:rendered];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.frame = CGRectMake(0, (44 - iconSize.height) / 2.0, iconSize.width, iconSize.height);
        icon.tintColor = self.imagePickerController.tintColor;
        [container addSubview:icon];

        UIControl *tap = [[UIControl alloc] initWithFrame:container.bounds];
        [tap addTarget:self action:@selector(qb_popBack:) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:tap];

        UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithCustomView:container];
        [self.navigationItem setLeftBarButtonItem:backItem animated:NO];
    }

    // Configure collection view
    self.collectionView.allowsMultipleSelection = self.imagePickerController.allowsMultipleSelection;
    
    // Show/hide 'Done' button
    if (self.imagePickerController.allowsMultipleSelection) {
        [self.navigationItem setRightBarButtonItem:self.doneButton animated:NO];
    } else {
        [self.navigationItem setRightBarButtonItem:nil animated:NO];
    }
    
    [self updateDoneButtonState];
    [self updateSelectionInfo];
    [self.collectionView reloadData];
    
    // Scroll to bottom — show the very last item so the user lands on the
    // newest photo (and on the trailing +cell when shown in Limited mode).
    NSInteger lastItem = (NSInteger)self.fetchResult.count - 1 + [self trailingExtraCellCount];
    if (lastItem >= 0 && self.isMovingToParentViewController && !self.disableScrollToBottom) {
        // when presenting as a .FormSheet on iPad, the frame is not correct until just after viewWillAppear:
        // dispatching to the main thread waits one run loop until the frame is update and the layout is complete
        dispatch_async(dispatch_get_main_queue(), ^{
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:lastItem inSection:0];
            [self.collectionView scrollToItemAtIndexPath:indexPath atScrollPosition:UICollectionViewScrollPositionBottom animated:NO];
        });
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    self.disableScrollToBottom = YES;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.disableScrollToBottom = NO;
    
    [self updateCachedAssets];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    // Save indexPath for the last item
    NSIndexPath *indexPath = [[self.collectionView indexPathsForVisibleItems] lastObject];
    
    // Update layout
    [self.collectionViewLayout invalidateLayout];
    
    // Restore scroll position
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.collectionView scrollToItemAtIndexPath:indexPath atScrollPosition:UICollectionViewScrollPositionBottom animated:NO];
    }];
}

- (void)dealloc
{
    // Deregister observer
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}


#pragma mark - Accessors

- (void)setAssetCollection:(PHAssetCollection *)assetCollection
{
    _assetCollection = assetCollection;
    
    [self updateFetchRequest];
    [self.collectionView reloadData];
}

- (PHCachingImageManager *)imageManager
{
    if (_imageManager == nil) {
        _imageManager = [PHCachingImageManager new];
    }
    
    return _imageManager;
}

- (BOOL)isAutoDeselectEnabled
{
    return (self.imagePickerController.maximumNumberOfSelection == 1
            && self.imagePickerController.maximumNumberOfSelection >= self.imagePickerController.minimumNumberOfSelection);
}


#pragma mark - Actions

- (IBAction)done:(id)sender
{
    if ([self.imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:didFinishPickingAssets:)]) {
        [self.imagePickerController.delegate qb_imagePickerController:self.imagePickerController
                                               didFinishPickingAssets:self.imagePickerController.selectedAssets.array];
    }
}

- (void)qb_popBack:(id)sender
{
    [self.navigationController popViewControllerAnimated:YES];
}


#pragma mark - Toolbar

- (void)setUpToolbarItems
{
    // Space
    UIBarButtonItem *leftSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL];
    UIBarButtonItem *rightSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL];
    
    // Info label
    NSDictionary *attributes = @{ NSForegroundColorAttributeName: [UIColor blackColor] };
    UIBarButtonItem *infoButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:NULL];
    infoButtonItem.enabled = NO;
    [infoButtonItem setTitleTextAttributes:attributes forState:UIControlStateNormal];
    [infoButtonItem setTitleTextAttributes:attributes forState:UIControlStateDisabled];
    
    self.toolbarItems = @[leftSpace, infoButtonItem, rightSpace];
}

- (void)updateSelectionInfo
{
    NSMutableOrderedSet *selectedAssets = self.imagePickerController.selectedAssets;
    
    if (selectedAssets.count > 0) {
        NSBundle *bundle = self.imagePickerController.assetBundle;
        NSString *format;
        if (selectedAssets.count > 1) {
            format = NSLocalizedStringFromTableInBundle(@"assets.toolbar.items-selected", @"QBImagePicker", bundle, nil);
        } else {
            format = NSLocalizedStringFromTableInBundle(@"assets.toolbar.item-selected", @"QBImagePicker", bundle, nil);
        }
        
        NSString *title = [NSString stringWithFormat:format, selectedAssets.count];
        [(UIBarButtonItem *)self.toolbarItems[1] setTitle:title];
    } else {
        [(UIBarButtonItem *)self.toolbarItems[1] setTitle:@""];
    }
}


#pragma mark - Fetching Assets

- (void)updateFetchRequest
{
    if (self.assetCollection) {
        PHFetchOptions *options = [PHFetchOptions new];
        
        switch (self.imagePickerController.mediaType) {
            case QBImagePickerMediaTypeImage:
                options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %ld", PHAssetMediaTypeImage];
                break;
                
            case QBImagePickerMediaTypeVideo:
                options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %ld", PHAssetMediaTypeVideo];
                break;
                
            default:
                break;
        }
        
        self.fetchResult = [PHAsset fetchAssetsInAssetCollection:self.assetCollection options:options];
        
        if ([self isAutoDeselectEnabled] && self.imagePickerController.selectedAssets.count > 0) {
            // Get index of previous selected asset
            PHAsset *asset = [self.imagePickerController.selectedAssets firstObject];
            NSInteger assetIndex = [self.fetchResult indexOfObject:asset];
            self.lastSelectedItemIndexPath = [self indexPathForAssetIndex:assetIndex];
        }
    } else {
        self.fetchResult = nil;
    }
}


#pragma mark - Checking for Selection Limit

- (BOOL)isMinimumSelectionLimitFulfilled
{
   return (self.imagePickerController.minimumNumberOfSelection <= self.imagePickerController.selectedAssets.count);
}

- (BOOL)isMaximumSelectionLimitReached
{
    NSUInteger minimumNumberOfSelection = MAX(1, self.imagePickerController.minimumNumberOfSelection);
   
    if (minimumNumberOfSelection <= self.imagePickerController.maximumNumberOfSelection) {
        return (self.imagePickerController.maximumNumberOfSelection <= self.imagePickerController.selectedAssets.count);
    }
   
    return NO;
}

- (void)updateDoneButtonState
{
    self.doneButton.enabled = [self isMinimumSelectionLimitFulfilled];
}


#pragma mark - Asset Caching

- (void)resetCachedAssets
{
    [self.imageManager stopCachingImagesForAllAssets];
    self.previousPreheatRect = CGRectZero;
}

- (void)updateCachedAssets
{
    BOOL isViewVisible = [self isViewLoaded] && self.view.window != nil;
    if (!isViewVisible) { return; }
    
    // The preheat window is twice the height of the visible rect
    CGRect preheatRect = self.collectionView.bounds;
    preheatRect = CGRectInset(preheatRect, 0.0, -0.5 * CGRectGetHeight(preheatRect));
    
    // If scrolled by a "reasonable" amount...
    CGFloat delta = ABS(CGRectGetMidY(preheatRect) - CGRectGetMidY(self.previousPreheatRect));
    
    if (delta > CGRectGetHeight(self.collectionView.bounds) / 3.0) {
        // Compute the assets to start caching and to stop caching
        NSMutableArray *addedIndexPaths = [NSMutableArray array];
        NSMutableArray *removedIndexPaths = [NSMutableArray array];
        
        [self computeDifferenceBetweenRect:self.previousPreheatRect andRect:preheatRect addedHandler:^(CGRect addedRect) {
            NSArray *indexPaths = [self.collectionView qb_indexPathsForElementsInRect:addedRect];
            [addedIndexPaths addObjectsFromArray:indexPaths];
        } removedHandler:^(CGRect removedRect) {
            NSArray *indexPaths = [self.collectionView qb_indexPathsForElementsInRect:removedRect];
            [removedIndexPaths addObjectsFromArray:indexPaths];
        }];
        
        NSArray *assetsToStartCaching = [self assetsAtIndexPaths:addedIndexPaths];
        NSArray *assetsToStopCaching = [self assetsAtIndexPaths:removedIndexPaths];
        
        CGSize itemSize = [(UICollectionViewFlowLayout *)self.collectionViewLayout itemSize];
        CGSize targetSize = CGSizeScale(itemSize, [[UIScreen mainScreen] scale]);
        
        [self.imageManager startCachingImagesForAssets:assetsToStartCaching
                                            targetSize:targetSize
                                           contentMode:PHImageContentModeAspectFill
                                               options:nil];
        [self.imageManager stopCachingImagesForAssets:assetsToStopCaching
                                           targetSize:targetSize
                                          contentMode:PHImageContentModeAspectFill
                                              options:nil];
        
        self.previousPreheatRect = preheatRect;
    }
}

- (void)computeDifferenceBetweenRect:(CGRect)oldRect andRect:(CGRect)newRect addedHandler:(void (^)(CGRect addedRect))addedHandler removedHandler:(void (^)(CGRect removedRect))removedHandler
{
    if (CGRectIntersectsRect(newRect, oldRect)) {
        CGFloat oldMaxY = CGRectGetMaxY(oldRect);
        CGFloat oldMinY = CGRectGetMinY(oldRect);
        CGFloat newMaxY = CGRectGetMaxY(newRect);
        CGFloat newMinY = CGRectGetMinY(newRect);
        
        if (newMaxY > oldMaxY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, oldMaxY, newRect.size.width, (newMaxY - oldMaxY));
            addedHandler(rectToAdd);
        }
        if (oldMinY > newMinY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, newMinY, newRect.size.width, (oldMinY - newMinY));
            addedHandler(rectToAdd);
        }
        if (newMaxY < oldMaxY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, newMaxY, newRect.size.width, (oldMaxY - newMaxY));
            removedHandler(rectToRemove);
        }
        if (oldMinY < newMinY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, oldMinY, newRect.size.width, (newMinY - oldMinY));
            removedHandler(rectToRemove);
        }
    } else {
        addedHandler(newRect);
        removedHandler(oldRect);
    }
}

- (NSArray *)assetsAtIndexPaths:(NSArray *)indexPaths
{
    if (indexPaths.count == 0) { return nil; }
    
    NSMutableArray *assets = [NSMutableArray arrayWithCapacity:indexPaths.count];
    for (NSIndexPath *indexPath in indexPaths) {
        NSInteger assetIndex = [self assetIndexForItem:indexPath.item];
        if (assetIndex != NSNotFound && assetIndex < (NSInteger)self.fetchResult.count) {
            PHAsset *asset = self.fetchResult[assetIndex];
            [assets addObject:asset];
        }
    }
    return assets;
}


#pragma mark - PHPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(PHChange *)changeInstance
{
    dispatch_async(dispatch_get_main_queue(), ^{
        PHFetchResultChangeDetails *collectionChanges = [changeInstance changeDetailsForFetchResult:self.fetchResult];
        
        if (collectionChanges) {
            // Get the new fetch result
            self.fetchResult = [collectionChanges fetchResultAfterChanges];
            
            if (![collectionChanges hasIncrementalChanges] || [collectionChanges hasMoves]) {
                // We need to reload all if the incremental diffs are not available
                [self.collectionView reloadData];
            } else {
                // If we have incremental diffs, tell the collection view to animate insertions and deletions.
                // The trailing +cell sits past the last asset, so asset-space
                // indexes from PHFetchResultChangeDetails map 1:1 to item indexes.
                [self.collectionView performBatchUpdates:^{
                    NSIndexSet *removedIndexes = [collectionChanges removedIndexes];
                    if ([removedIndexes count]) {
                        [self.collectionView deleteItemsAtIndexPaths:[removedIndexes qb_indexPathsFromIndexesWithSection:0]];
                    }

                    NSIndexSet *insertedIndexes = [collectionChanges insertedIndexes];
                    if ([insertedIndexes count]) {
                        [self.collectionView insertItemsAtIndexPaths:[insertedIndexes qb_indexPathsFromIndexesWithSection:0]];
                    }

                    NSIndexSet *changedIndexes = [collectionChanges changedIndexes];
                    if ([changedIndexes count]) {
                        [self.collectionView reloadItemsAtIndexPaths:[changedIndexes qb_indexPathsFromIndexesWithSection:0]];
                    }
                } completion:NULL];
            }
            
            [self resetCachedAssets];
        }
    });
}


#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self updateCachedAssets];
}


#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.fetchResult.count + [self trailingExtraCellCount];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    // Trailing "Add Photos" cell (only present when `showsAddPhotosCell` is
    // YES on the picker controller). It is placed after the newest photo so
    // it appears immediately to the right of the latest asset.
    NSInteger assetIndex = [self assetIndexForItem:indexPath.item];
    if (assetIndex == NSNotFound) {
        QBAddPhotosCell *addCell = [collectionView dequeueReusableCellWithReuseIdentifier:QBAddPhotosCellIdentifier forIndexPath:indexPath];
        NSBundle *bundle = self.imagePickerController.assetBundle;
        addCell.titleLabel.text = NSLocalizedStringFromTableInBundle(@"assets.add-photos", @"QBImagePicker", bundle, @"Add Photos");
        // Use the dedicated `addPhotosTintColor` (e.g. the Seafile app sets
        // it to #999999) when provided, otherwise fall back to the global
        // `tintColor` for backward compatibility.
        UIColor *addTint = self.imagePickerController.addPhotosTintColor ?: self.imagePickerController.tintColor;
        [addCell applyTintColor:addTint];
        [addCell applyIconImage:self.imagePickerController.addPhotosIconImage];
        return addCell;
    }

    QBAssetCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"AssetCell" forIndexPath:indexPath];
    cell.tag = indexPath.item;
    cell.showsOverlayViewWhenSelected = self.imagePickerController.allowsMultipleSelection;

    // Theme the selection checkmark to match the host app's accent color.
    // Hosts set `checkmarkTintColor` independently of the navigation bar
    // tint so e.g. Seafile keeps Cancel/Done in neutral gray while the
    // checkmark uses the app's theme orange. Falls back to `tintColor`.
    UIColor *tint = self.imagePickerController.checkmarkTintColor ?: self.imagePickerController.tintColor;
    if (tint) {
        for (UIView *sub in cell.contentView.subviews) {
            for (UIView *inner in sub.subviews) {
                if ([inner isKindOfClass:[QBCheckmarkView class]]) {
                    QBCheckmarkView *checkmark = (QBCheckmarkView *)inner;
                    if (![checkmark.bodyColor isEqual:tint]) {
                        checkmark.bodyColor = tint;
                        [checkmark setNeedsDisplay];
                    }
                }
            }
        }
    }

    // Image
    PHAsset *asset = self.fetchResult[assetIndex];
    CGSize itemSize = [(UICollectionViewFlowLayout *)collectionView.collectionViewLayout itemSize];
    CGSize targetSize = CGSizeScale(itemSize, [[UIScreen mainScreen] scale]);
    
    [self.imageManager requestImageForAsset:asset
                                 targetSize:targetSize
                                contentMode:PHImageContentModeAspectFill
                                    options:nil
                              resultHandler:^(UIImage *result, NSDictionary *info) {
                                  if (cell.tag == indexPath.item) {
                                      cell.imageView.image = result;
                                  }
                              }];
    
    // Video indicator
    if (asset.mediaType == PHAssetMediaTypeVideo) {
        cell.videoIndicatorView.hidden = NO;
        
        NSInteger minutes = (NSInteger)(asset.duration / 60.0);
        NSInteger seconds = (NSInteger)ceil(asset.duration - 60.0 * (double)minutes);
        cell.videoIndicatorView.timeLabel.text = [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
        
        if (asset.mediaSubtypes & PHAssetMediaSubtypeVideoHighFrameRate) {
            cell.videoIndicatorView.videoIcon.hidden = YES;
            cell.videoIndicatorView.slomoIcon.hidden = NO;
        }
        else {
            cell.videoIndicatorView.videoIcon.hidden = NO;
            cell.videoIndicatorView.slomoIcon.hidden = YES;
        }
    } else {
        cell.videoIndicatorView.hidden = YES;
    }
    
    // Selection state
    if ([self.imagePickerController.selectedAssets containsObject:asset]) {
        [cell setSelected:YES];
        [collectionView selectItemAtIndexPath:indexPath animated:NO scrollPosition:UICollectionViewScrollPositionNone];
    }
    
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    if (kind == UICollectionElementKindSectionFooter) {
        UICollectionReusableView *footerView = [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionFooter
                                                                                  withReuseIdentifier:@"FooterView"
                                                                                         forIndexPath:indexPath];
        
        // Number of assets
        UILabel *label = (UILabel *)[footerView viewWithTag:1];
        
        NSBundle *bundle = self.imagePickerController.assetBundle;
        NSUInteger numberOfPhotos = [self.fetchResult countOfAssetsWithMediaType:PHAssetMediaTypeImage];
        NSUInteger numberOfVideos = [self.fetchResult countOfAssetsWithMediaType:PHAssetMediaTypeVideo];
        
        switch (self.imagePickerController.mediaType) {
            case QBImagePickerMediaTypeAny:
            {
                NSString *format;
                if (numberOfPhotos == 1) {
                    if (numberOfVideos == 1) {
                        format = NSLocalizedStringFromTableInBundle(@"assets.footer.photo-and-video", @"QBImagePicker", bundle, nil);
                    } else {
                        format = NSLocalizedStringFromTableInBundle(@"assets.footer.photo-and-videos", @"QBImagePicker", bundle, nil);
                    }
                } else if (numberOfVideos == 1) {
                    format = NSLocalizedStringFromTableInBundle(@"assets.footer.photos-and-video", @"QBImagePicker", bundle, nil);
                } else {
                    format = NSLocalizedStringFromTableInBundle(@"assets.footer.photos-and-videos", @"QBImagePicker", bundle, nil);
                }
                
                label.text = [NSString stringWithFormat:format, numberOfPhotos, numberOfVideos];
            }
                break;
                
            case QBImagePickerMediaTypeImage:
            {
                NSString *key = (numberOfPhotos == 1) ? @"assets.footer.photo" : @"assets.footer.photos";
                NSString *format = NSLocalizedStringFromTableInBundle(key, @"QBImagePicker", bundle, nil);
                
                label.text = [NSString stringWithFormat:format, numberOfPhotos];
            }
                break;
                
            case QBImagePickerMediaTypeVideo:
            {
                NSString *key = (numberOfVideos == 1) ? @"assets.footer.video" : @"assets.footer.videos";
                NSString *format = NSLocalizedStringFromTableInBundle(key, @"QBImagePicker", bundle, nil);
                
                label.text = [NSString stringWithFormat:format, numberOfVideos];
            }
                break;
        }
        
        return footerView;
    }
    
    return nil;
}


#pragma mark - UICollectionViewDelegate

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger assetIndex = [self assetIndexForItem:indexPath.item];
    // The trailing "Add Photos" cell must always be tappable: returning YES
    // here is required so UICollectionView still routes the tap to
    // didSelectItemAtIndexPath:. The visible "selected" state is cleared right
    // after we forward the tap to the delegate.
    if (assetIndex == NSNotFound) {
        return YES;
    }

    if ([self.imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:shouldSelectAsset:)]) {
        PHAsset *asset = self.fetchResult[assetIndex];
        return [self.imagePickerController.delegate qb_imagePickerController:self.imagePickerController shouldSelectAsset:asset];
    }

    if ([self isAutoDeselectEnabled]) {
        return YES;
    }

    return ![self isMaximumSelectionLimitReached];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    QBImagePickerController *imagePickerController = self.imagePickerController;

    // Tap on the "Add Photos" cell -> immediately drop the selection state so
    // it behaves like a button, then forward the tap to the delegate.
    NSInteger assetIndex = [self assetIndexForItem:indexPath.item];
    if (assetIndex == NSNotFound) {
        [collectionView deselectItemAtIndexPath:indexPath animated:NO];
        if ([imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerControllerDidTapAddPhotos:)]) {
            [imagePickerController.delegate qb_imagePickerControllerDidTapAddPhotos:imagePickerController];
        }
        return;
    }

    NSMutableOrderedSet *selectedAssets = imagePickerController.selectedAssets;
    PHAsset *asset = self.fetchResult[assetIndex];

    if (imagePickerController.allowsMultipleSelection) {
        if ([self isAutoDeselectEnabled] && selectedAssets.count > 0) {
            // Remove previous selected asset from set
            [selectedAssets removeObjectAtIndex:0];
            
            // Deselect previous selected asset
            if (self.lastSelectedItemIndexPath) {
                [collectionView deselectItemAtIndexPath:self.lastSelectedItemIndexPath animated:NO];
            }
        }
        
        // Add asset to set
        [selectedAssets addObject:asset];
        
        self.lastSelectedItemIndexPath = indexPath;
        
        [self updateDoneButtonState];
        
        if (imagePickerController.showsNumberOfSelectedAssets) {
            [self updateSelectionInfo];
            
            if (selectedAssets.count == 1) {
                // Show toolbar
                [self.navigationController setToolbarHidden:NO animated:YES];
            }
        }
    } else {
        if ([imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:didFinishPickingAssets:)]) {
            [imagePickerController.delegate qb_imagePickerController:imagePickerController didFinishPickingAssets:@[asset]];
        }
    }
    
    if ([imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:didSelectAsset:)]) {
        [imagePickerController.delegate qb_imagePickerController:imagePickerController didSelectAsset:asset];
    }
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (!self.imagePickerController.allowsMultipleSelection) {
        return;
    }

    NSInteger assetIndex = [self assetIndexForItem:indexPath.item];
    if (assetIndex == NSNotFound) {
        return;
    }

    QBImagePickerController *imagePickerController = self.imagePickerController;
    NSMutableOrderedSet *selectedAssets = imagePickerController.selectedAssets;

    PHAsset *asset = self.fetchResult[assetIndex];
    
    // Remove asset from set
    [selectedAssets removeObject:asset];
    
    self.lastSelectedItemIndexPath = nil;
    
    [self updateDoneButtonState];
    
    if (imagePickerController.showsNumberOfSelectedAssets) {
        [self updateSelectionInfo];
        
        if (selectedAssets.count == 0) {
            // Hide toolbar
            [self.navigationController setToolbarHidden:YES animated:YES];
        }
    }
    
    if ([imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:didDeselectAsset:)]) {
        [imagePickerController.delegate qb_imagePickerController:imagePickerController didDeselectAsset:asset];
    }
}


#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSUInteger numberOfColumns;
    if (UIInterfaceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation])) {
        numberOfColumns = self.imagePickerController.numberOfColumnsInPortrait;
    } else {
        numberOfColumns = self.imagePickerController.numberOfColumnsInLandscape;
    }
    
    CGFloat width = (CGRectGetWidth(self.view.frame) - 2.0 * (numberOfColumns - 1)) / numberOfColumns;
    
    return CGSizeMake(width, width);
}

@end
