//
//  QBImagePickerController.h
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

@class QBImagePickerController;

@protocol QBImagePickerControllerDelegate <NSObject>

@optional
- (void)qb_imagePickerController:(QBImagePickerController *)imagePickerController didFinishPickingAssets:(NSArray *)assets;
- (void)qb_imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController;

- (BOOL)qb_imagePickerController:(QBImagePickerController *)imagePickerController shouldSelectAsset:(PHAsset *)asset;
- (void)qb_imagePickerController:(QBImagePickerController *)imagePickerController didSelectAsset:(PHAsset *)asset;
- (void)qb_imagePickerController:(QBImagePickerController *)imagePickerController didDeselectAsset:(PHAsset *)asset;

// Called when the user taps the leading "Add Photos" cell that is shown
// when `showsAddPhotosCell` is enabled (typically used in Limited photo
// access mode to let the user expand the limited photo selection).
- (void)qb_imagePickerControllerDidTapAddPhotos:(QBImagePickerController *)imagePickerController;

@end

typedef NS_ENUM(NSUInteger, QBImagePickerMediaType) {
    QBImagePickerMediaTypeAny = 0,
    QBImagePickerMediaTypeImage,
    QBImagePickerMediaTypeVideo
};

@interface QBImagePickerController : UIViewController

@property (nonatomic, weak) id<QBImagePickerControllerDelegate> delegate;

@property (nonatomic, strong, readonly) NSMutableOrderedSet *selectedAssets;

@property (nonatomic, copy) NSArray *assetCollectionSubtypes;
@property (nonatomic, assign) QBImagePickerMediaType mediaType;

@property (nonatomic, assign) BOOL allowsMultipleSelection;
@property (nonatomic, assign) NSUInteger minimumNumberOfSelection;
@property (nonatomic, assign) NSUInteger maximumNumberOfSelection;

@property (nonatomic, copy) NSString *prompt;
@property (nonatomic, assign) BOOL showsNumberOfSelectedAssets;

@property (nonatomic, assign) NSUInteger numberOfColumnsInPortrait;
@property (nonatomic, assign) NSUInteger numberOfColumnsInLandscape;

// When YES, an extra "Add Photos" cell is inserted as the first item in
// every album grid so the user can quickly expand the limited photo
// selection without leaving the picker. Defaults to NO.
@property (nonatomic, assign) BOOL showsAddPhotosCell;

// Base theme color applied to the navigation bar (Cancel/Done buttons).
// Defaults to a neutral gray (#666666). When the dedicated tints below
// are nil they fall back to this color, preserving previous behavior.
@property (nonatomic, strong) UIColor *tintColor;

// Color applied to the selection checkmark body. When nil, falls back to
// `tintColor`. Hosts typically set this to their accent color (e.g. the
// Seafile app uses its theme orange) while keeping `tintColor` neutral.
@property (nonatomic, strong) UIColor *checkmarkTintColor;

// Color applied to the trailing "Add Photos" cell (icon + label). When
// nil, falls back to `tintColor`.
@property (nonatomic, strong) UIColor *addPhotosTintColor;

// Image used inside the trailing "Add Photos" cell. When nil, the cell
// falls back to the SF Symbol "plus". Provide a template-rendered image
// so it is tinted by `addPhotosTintColor`.
@property (nonatomic, strong) UIImage *addPhotosIconImage;

// Custom back-chevron image for the picker's internal navigation bar.
// When set, replaces the system back indicator on push transitions and
// strips the "back title" so only the icon is shown — matching hosts
// (like Seafile) that ship their own back arrow asset.
@property (nonatomic, strong) UIImage *backIndicatorImage;

// Custom image used as the leading bar button on the root albums screen
// (replacing the default "Cancel" text item). Provide a template image
// so it is tinted by `tintColor`.
@property (nonatomic, strong) UIImage *cancelImage;

@end
