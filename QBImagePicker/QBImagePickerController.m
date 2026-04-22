//
//  QBImagePickerController.m
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import "QBImagePickerController.h"
#import <Photos/Photos.h>

// ViewControllers
#import "QBAlbumsViewController.h"

@interface QBImagePickerController ()

@property (nonatomic, strong) UINavigationController *albumsNavigationController;

@property (nonatomic, strong) NSBundle *assetBundle;

@end

@implementation QBImagePickerController

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        // Set default values
        self.assetCollectionSubtypes = @[
                                         @(PHAssetCollectionSubtypeSmartAlbumUserLibrary),
                                         @(PHAssetCollectionSubtypeAlbumMyPhotoStream),
                                         @(PHAssetCollectionSubtypeSmartAlbumPanoramas),
                                         @(PHAssetCollectionSubtypeSmartAlbumVideos),
                                         @(PHAssetCollectionSubtypeSmartAlbumBursts)
                                         ];
        self.minimumNumberOfSelection = 1;
        self.numberOfColumnsInPortrait = 4;
        self.numberOfColumnsInLandscape = 7;

        // Default theme color is a neutral gray (#666666) so navigation bar
        // buttons (Cancel/Done), the selection checkmark and the trailing
        // "Add Photos" cell all render in a calm tone. Hosts may override
        // this before presenting the picker.
        self.tintColor = [UIColor colorWithRed:0x66/255.0 green:0x66/255.0 blue:0x66/255.0 alpha:1.0];

        _selectedAssets = [NSMutableOrderedSet orderedSet];
        
        // Get asset bundle
        self.assetBundle = [NSBundle bundleForClass:[self class]];
        NSString *bundlePath = [self.assetBundle pathForResource:@"QBImagePicker" ofType:@"bundle"];
        if (bundlePath) {
            self.assetBundle = [NSBundle bundleWithPath:bundlePath];
        }
        
        [self setUpAlbumsViewController];

        // Apply the theme tint to the embedded navigation bar so Cancel/Done
        // bar buttons render in the host app color instead of the system blue.
        self.albumsNavigationController.navigationBar.tintColor = self.tintColor;

        // Set instance
        QBAlbumsViewController *albumsViewController = (QBAlbumsViewController *)self.albumsNavigationController.topViewController;
        albumsViewController.imagePickerController = self;
    }
    
    return self;
}

- (void)setTintColor:(UIColor *)tintColor
{
    _tintColor = tintColor;
    // The navigation controller is created lazily in setUpAlbumsViewController;
    // when the host changes the tint after init, propagate it immediately.
    self.albumsNavigationController.navigationBar.tintColor = tintColor;
}

- (void)setBackIndicatorImage:(UIImage *)backIndicatorImage
{
    _backIndicatorImage = backIndicatorImage;
    // Apply to the picker's internal navigation bar so the chevron used on
    // push transitions matches the host app's back arrow. Use the original
    // rendering mode so the image renders as-is rather than being tinted.
    UIImage *img = [backIndicatorImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    self.albumsNavigationController.navigationBar.backIndicatorImage = img;
    self.albumsNavigationController.navigationBar.backIndicatorTransitionMaskImage = img;
}

- (void)setUpAlbumsViewController
{
    // Add QBAlbumsViewController as a child
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"QBImagePicker" bundle:self.assetBundle];
    UINavigationController *navigationController = [storyboard instantiateViewControllerWithIdentifier:@"QBAlbumsNavigationController"];
    
    [self addChildViewController:navigationController];
    
    navigationController.view.frame = self.view.bounds;
    [self.view addSubview:navigationController.view];
    
    [navigationController didMoveToParentViewController:self];
    
    self.albumsNavigationController = navigationController;
}

@end
