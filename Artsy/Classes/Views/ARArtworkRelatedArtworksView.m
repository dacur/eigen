#import "ARArtworkRelatedArtworksView.h"
#import "AREmbeddedModelsViewController.h"
#import "ORStackView+ArtsyViews.h"
#import "ARArtworkSetViewController.h"

@interface ARArtworkRelatedArtworksView() <AREmbeddedModelsDelegate>
@property (nonatomic, assign) BOOL hasRequested;
@property (nonatomic, strong) AFJSONRequestOperation *relatedArtworksRequest;
@property (nonatomic, strong) Artwork *artwork;
@property (nonatomic) SaleArtwork *saleArtwork;
@property (nonatomic) BOOL hasArtworks;
@property (nonatomic, strong) AREmbeddedModelsViewController *artworksVC;
@end

@implementation ARArtworkRelatedArtworksView

- (instancetype)init
{
    self = [super init];
    if (!self) { return nil; }
    _hasArtworks = NO;
    return self;
}
- (void)updateWithArtwork:(Artwork *)artwork
{
    [self updateWithArtwork:artwork withCompletion:nil];
}
- (void)updateWithArtwork:(Artwork *)artwork withCompletion:(void(^)())completion
{
    if (self.hasRequested) { return; }

    self.artwork = artwork;
    self.hasRequested = YES;

    @weakify(self);

    // TODO: refactor these callbacks to return so we can use
    // results from the values array in a `when`
    KSPromise *salePromise = [artwork onSaleArtworkUpdate:^(SaleArtwork *saleArtwork) {
        self.saleArtwork = saleArtwork;
    } failure:nil];

    KSPromise *fairPromise = [artwork onFairUpdate:nil failure:nil];

    [[KSPromise when:@[salePromise, fairPromise]] then:^id(id value) {
        @strongify(self);
        id returnable = nil;

        Fair *fairContext;

        if ([self.parentViewController respondsToSelector:@selector(fair)]) {
            fairContext = [self.parentViewController fair];
        }

        if (!fairContext) {
            fairContext = self.artwork.fair;
        }

        if (self.saleArtwork.auction) {
            returnable = self.saleArtwork.auction;
            [self fetchSaleArtworks];

        } else if (fairContext) {
            returnable = fairContext;
            [self fetchFairArtworksForFair:fairContext];

        } else {
            [self fetchRelatedArtworks];
        }
        return returnable;

    } error:^id(NSError *error) {
        @strongify(self);
        ARErrorLog(@"Error fetching sale/fair for %@. Error: %@", self.artwork.artworkID, error.localizedDescription);
        [self fetchRelatedArtworks];
        return error;
    }];
}

- (void)fetchRelatedArtworks
{
    @weakify(self);
    self.relatedArtworksRequest = [self.artwork getRelatedArtworks:^(NSArray *artworks) {
        @strongify(self);
        [self renderWithArtworks:artworks heading:@"Suggested Artworks"];
    }];
}

- (void)fetchSaleArtworks
{
    @weakify(self);
    Sale *sale = self.saleArtwork.auction;
    self.relatedArtworksRequest = [ArtsyAPI getArtworksForSale:sale.saleID success:^(NSArray *artworks) {
        @strongify(self);
        NSString *heading = [NSString stringWithFormat:@"Works from %@", sale.name];
        [self renderWithArtworks:artworks heading:heading];
    } failure:^(NSError *error) {
        ARErrorLog(@"Couldn't fetch artworks for sale %@. Error: %@", sale.saleID, error.localizedDescription);
    }];

}

- (void)fetchFairArtworksForFair:(Fair *)fair
{
    @weakify(self);
    self.relatedArtworksRequest = [self.artwork getRelatedFairArtworks:fair success:^(NSArray *artworks) {
        @strongify(self);
        NSString *heading = [NSString stringWithFormat:@"Suggested artworks from %@", fair.name];
        [self renderWithArtworks:artworks heading:heading];
    }];
}

- (void)fetchRelatedArtworksForSale:(Sale *)sale
{
    @weakify(self);
    if (sale) {
        self.relatedArtworksRequest = [ArtsyAPI getArtworksForSale:sale.saleID success:^(NSArray *artworks) {
            @strongify(self);
            NSString *heading = [NSString stringWithFormat:@"Works from %@", sale.name];
            [self renderWithArtworks:artworks heading:heading];
        } failure:^(NSError *error) {
            ARErrorLog(@"Couldn't fetch artworks for sale %@. Error: %@", sale.saleID, error.localizedDescription);
        }];
    } else {
    }
}

- (void)renderWithArtworks:(NSArray *)artworks heading:(NSString *)heading
{
    if (self.relatedArtworksRequest.isCancelled) { return; }

    artworks = [artworks reject:^BOOL(Artwork *artwork) {
        return [artwork isEqual:self.artwork];
    }];

    BOOL hasArtworks = artworks && artworks.count > 0;
    self.hasArtworks = hasArtworks;
    if (!hasArtworks) {
        ARActionLog(@"No similar artworks for %@", self.artwork.artworkID);
    } else {
        [self addPageSubtitleWithString:heading.uppercaseString];

        ARArtworkMasonryLayout layout = [UIDevice isPad] ? [self masonryLayoutForPadWithOrientation:[[UIApplication sharedApplication] statusBarOrientation]] : ARArtworkMasonryLayout2Column;
        ARArtworkMasonryModule *module = [ARArtworkMasonryModule masonryModuleWithLayout:layout andStyle:AREmbeddedArtworkPresentationStyleArtworkMetadata];
        module.layoutProvider = self;

        self.artworksVC = [[AREmbeddedModelsViewController alloc] init];
        self.artworksVC.shouldAnimate = self.parentViewController.shouldAnimate;
        self.artworksVC.delegate = self;
        self.artworksVC.activeModule = module;
        self.artworksVC.constrainHeightAutomatically = YES;
        [self.artworksVC appendItems:artworks];

        [self addViewController:self.artworksVC toParent:self.parentViewController withTopMargin:@"0" sideMargin:@"0"];
        self.bottomMarginHeight = 20;
        [self invalidateIntrinsicContentSize];

        [self layoutIfNeeded];
        [self.parentViewController didUpdateRelatedArtworksView:self];
    }
}

- (ARArtworkMasonryLayout)masonryLayoutForPadWithOrientation:(UIInterfaceOrientation)orientation
{
    return UIInterfaceOrientationIsLandscape(orientation) ? ARArtworkMasonryLayout4Column : ARArtworkMasonryLayout3Column;
}

- (void)cancel
{
    [self.relatedArtworksRequest cancel];
}

- (CGSize)intrinsicContentSize
{
    return CGSizeMake(UIViewNoIntrinsicMetric, self.hasArtworks ? UIViewNoIntrinsicMetric : 0);
}

#pragma mark - AREmbeddedModelsDelegate

- (void)embeddedModelsViewController:(AREmbeddedModelsViewController *)controller shouldPresentViewController:(UIViewController *)viewController
{
    [self.parentViewController relatedArtworksView:self shouldShowViewController:viewController];
}

- (void)embeddedModelsViewController:(AREmbeddedModelsViewController *)controller didTapItemAtIndex:(NSUInteger)index
{
    ARArtworkSetViewController *viewController = [ARSwitchBoard.sharedInstance loadArtworkSet:self.artworksVC.items inFair:self.fair atIndex:index];
    [self.parentViewController relatedArtworksView:self shouldShowViewController:viewController];
}

- (Fair *)fair
{
    if ([self.parentViewController respondsToSelector:@selector(fair)]) {
        return [self.parentViewController fair];
    } else {
        return nil;
    }
}

@end
