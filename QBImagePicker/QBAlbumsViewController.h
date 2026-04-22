//
//  QBAlbumsViewController.h
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import <UIKit/UIKit.h>

@class QBImagePickerController;

@interface QBAlbumsViewController : UITableViewController

@property (nonatomic, weak) QBImagePickerController *imagePickerController;

// Pod-internal helper: re-renders an arbitrary UIImage at a fixed point
// size with the requested rendering mode. Exposed so sibling controllers
// (e.g. QBAssetsViewController) can normalize host-supplied bar-button
// icons whose pixel dimensions would otherwise overflow the nav bar.
+ (UIImage *)qb_renderImage:(UIImage *)image
                     inSize:(CGSize)size
              renderingMode:(UIImageRenderingMode)mode;

@end
