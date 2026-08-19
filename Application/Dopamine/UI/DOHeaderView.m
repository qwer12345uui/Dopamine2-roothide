//
//  DOHeaderView.m
//  Dopamine
//
//  Created by tomt000 on 04/01/2024.
//

#import "DOHeaderView.h"
#import "DOThemeManager.h"

@interface DOHeaderView ()

@property (nonatomic) UIImageView *logoView;
@property (nonatomic) NSLayoutConstraint *logoAspectConstraint;

@end

@implementation DOHeaderView

-(id)initWithImage:(UIImage *)image subtitles:(NSArray<NSAttributedString *> *)subtitles {
    if (self = [super init]) {
        UIStackView *stackView = [[UIStackView alloc] init];
        stackView.axis = UILayoutConstraintAxisVertical;
        stackView.spacing = 2;
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.alignment = UIStackViewAlignmentLeading;

        [self addSubview:stackView];

        [NSLayoutConstraint activateConstraints:@[
            [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        //1 - Add the logo to our stack
        self.logoView = [[UIImageView alloc] init];
        self.logoView.translatesAutoresizingMaskIntoConstraints = NO;
        self.logoView.image = [image imageWithAlignmentRectInsets:UIEdgeInsetsMake(7, 0, -7, 0)];
        self.logoView.contentMode = UIViewContentModeScaleAspectFit;
        [stackView addArrangedSubview:self.logoView];

        self.logoAspectConstraint = [self.logoView.widthAnchor constraintEqualToAnchor:self.logoView.heightAnchor multiplier:[self logoAspectForImage:image]];
        [NSLayoutConstraint activateConstraints:@[
            [self.logoView.heightAnchor constraintEqualToConstant:40],
            self.logoAspectConstraint,
        ]];

        //3 - Add our subtitles to our stack
        [subtitles enumerateObjectsUsingBlock:^(NSAttributedString *formatedText, NSUInteger idx, BOOL *stop) {
            UILabel *label = [[UILabel alloc] init];
            label.attributedText = formatedText;
            label.translatesAutoresizingMaskIntoConstraints = NO;
            [stackView addArrangedSubview:label];
        }];

        self.translatesAutoresizingMaskIntoConstraints = NO;

        DOTheme *theme = [[DOThemeManager sharedInstance] enabledTheme];
        if (theme.titleShadow)
        {
            self.layer.shadowColor = [UIColor blackColor].CGColor;
            self.layer.shadowOffset = CGSizeZero;
            self.layer.shadowRadius = 30;
            self.layer.shadowOpacity = 0.3;
        }

    }
    return self;
}

- (CGFloat)logoAspectForImage:(UIImage *)image
{
    if (!image || image.size.width <= 0 || image.size.height <= 0) return 1.0;
    return MIN(MAX(image.size.width / image.size.height, 0.5), 4.0);
}

- (void)setLogoImage:(UIImage *)image
{
    if (!image) return;
    self.logoView.image = [image imageWithAlignmentRectInsets:UIEdgeInsetsMake(7, 0, -7, 0)];
    [NSLayoutConstraint deactivateConstraints:@[self.logoAspectConstraint]];
    self.logoAspectConstraint = [self.logoView.widthAnchor constraintEqualToAnchor:self.logoView.heightAnchor multiplier:[self logoAspectForImage:image]];
    self.logoAspectConstraint.active = YES;
}

- (void)setLogoHidden:(BOOL)hidden
{
    self.logoView.hidden = hidden;
}

@end
