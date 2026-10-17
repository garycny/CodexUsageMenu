#import <Cocoa/Cocoa.h>

static const CGFloat PanelWidth = 200.0;
static const CGFloat CollapsedPanelHeight = 230.0;
static const CGFloat PanelMargin = 8.0;

static NSRect RectFromTop(CGFloat containerHeight, CGFloat x, CGFloat top, CGFloat width, CGFloat height) {
    return NSMakeRect(x, containerHeight - top - height, width, height);
}

static BOOL UsesDarkAppearance(NSView *view) {
    NSAppearanceName match = [view.effectiveAppearance bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua,
        NSAppearanceNameDarkAqua
    ]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

static NSColor *PanelBackgroundColor(NSView *view) {
    return UsesDarkAppearance(view)
        ? [NSColor colorWithSRGBRed:0.145 green:0.145 blue:0.153 alpha:1.0]
        : [NSColor colorWithSRGBRed:0.949 green:0.949 blue:0.965 alpha:1.0];
}

static NSColor *CardBackgroundColor(NSView *view) {
    return UsesDarkAppearance(view)
        ? [NSColor colorWithSRGBRed:0.205 green:0.205 blue:0.218 alpha:1.0]
        : NSColor.whiteColor;
}

static NSColor *CardStrokeColor(NSView *view) {
    return UsesDarkAppearance(view)
        ? [NSColor colorWithWhite:1.0 alpha:0.14]
        : [NSColor colorWithSRGBRed:0.80 green:0.80 blue:0.83 alpha:1.0];
}

static NSDate *DateFromISO8601Value(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] == 0) {
        return nil;
    }
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSDate *date = [formatter dateFromString:value];
    if (!date) {
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        date = [formatter dateFromString:value];
    }
    return date;
}

static NSString *ExactDateText(id value) {
    NSDate *date = DateFromISO8601Value(value);
    if (!date) {
        return @"--";
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.timeZone = NSTimeZone.localTimeZone;
    formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    return [formatter stringFromDate:date];
}

static NSString *DaysUntilText(id value) {
    NSDate *date = DateFromISO8601Value(value);
    if (!date) {
        return @"未知";
    }
    NSTimeInterval remaining = [date timeIntervalSinceDate:NSDate.date];
    if (remaining <= 0) {
        return @"到期";
    }
    NSInteger days = (NSInteger)ceil(remaining / (24.0 * 60.0 * 60.0));
    if (days > 999) {
        return @"999+天";
    }
    return [NSString stringWithFormat:@"%ld天", (long)days];
}

static NSTextField *CreateLabel(NSView *parent, NSRect frame, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.bezeled = NO;
    label.bordered = NO;
    label.editable = NO;
    label.selectable = NO;
    label.drawsBackground = NO;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [parent addSubview:label];
    return label;
}

@interface UsageCreditListView : NSView
@property(nonatomic, copy) NSArray<NSValue *> *cardRects;
@property(nonatomic, copy) NSArray<NSValue *> *badgeRects;
@property(nonatomic, copy) NSArray<NSString *> *badgeTexts;
- (void)reloadWithCredits:(NSArray<NSDictionary *> *)credits width:(CGFloat)width;
@end

@implementation UsageCreditListView

- (BOOL)isFlipped {
    return YES;
}

- (void)reloadWithCredits:(NSArray<NSDictionary *> *)credits width:(CGFloat)width {
    for (NSView *subview in self.subviews.copy) {
        [subview removeFromSuperview];
    }

    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    NSMutableArray<NSValue *> *badges = [NSMutableArray array];
    NSMutableArray<NSString *> *badgeTexts = [NSMutableArray array];
    if (credits.count == 0) {
        self.frame = NSMakeRect(0, 0, width, 52);
        [rects addObject:[NSValue valueWithRect:NSMakeRect(0, 0, width, 48)]];

        NSTextField *title = CreateLabel(self, NSMakeRect(12, 8, width - 24, 16), 10.5, NSFontWeightSemibold, NSColor.labelColor);
        title.stringValue = @"暂无可用重置额度";
        NSTextField *detail = CreateLabel(self, NSMakeRect(12, 27, width - 24, 14), 9, NSFontWeightRegular, NSColor.secondaryLabelColor);
        detail.stringValue = @"获得后会显示在这里";
    } else {
        CGFloat cardHeight = 62.0;
        CGFloat gap = 8.0;
        self.frame = NSMakeRect(0, 0, width, credits.count * cardHeight + (credits.count - 1) * gap + 4);

        [credits enumerateObjectsUsingBlock:^(NSDictionary *credit, NSUInteger index, BOOL *stop) {
            (void)stop;
            CGFloat y = index * (cardHeight + gap);
            [rects addObject:[NSValue valueWithRect:NSMakeRect(0, y, width, cardHeight)]];

            NSString *countdownText = DaysUntilText(credit[@"expiresAt"]);
            NSDictionary *badgeAttributes = @{NSFontAttributeName: [NSFont systemFontOfSize:8.5 weight:NSFontWeightSemibold]};
            CGFloat badgeWidth = ceil([countdownText sizeWithAttributes:badgeAttributes].width) + 12;
            badgeWidth = MAX(30, MIN(48, badgeWidth));
            // The title and badge are drawn together in drawRect so their visual
            // centers use the same coordinate instead of NSTextField baselines.
            NSRect badgeRect = NSMakeRect(78, y + 6, badgeWidth, 18);
            [badges addObject:[NSValue valueWithRect:badgeRect]];
            [badgeTexts addObject:countdownText];

            NSTextField *status = CreateLabel(self, NSMakeRect(width - 52, y + 7, 40, 15), 9, NSFontWeightSemibold, NSColor.systemGreenColor);
            status.alignment = NSTextAlignmentRight;
            NSString *rawStatus = [credit[@"status"] isKindOfClass:NSString.class] ? credit[@"status"] : @"available";
            status.stringValue = [rawStatus isEqualToString:@"available"] ? @"可用" : rawStatus;

            NSString *granted = ExactDateText(credit[@"grantedAt"]);
            NSString *expires = ExactDateText(credit[@"expiresAt"]);
            if (![granted isEqualToString:@"--"]) {
                NSTextField *grantLabel = CreateLabel(self, NSMakeRect(12, y + 25, width - 24, 14), 9, NSFontWeightRegular, NSColor.secondaryLabelColor);
                grantLabel.stringValue = [NSString stringWithFormat:@"发放：%@", granted];
            }
            NSString *expiryText = [expires isEqualToString:@"--"]
                ? @"到期日期暂不可用"
                : [NSString stringWithFormat:@"到期：%@", expires];
            CGFloat expiryY = [granted isEqualToString:@"--"] ? y + 34 : y + 42;
            NSTextField *expiryLabel = CreateLabel(self, NSMakeRect(12, expiryY, width - 24, 14), 9, NSFontWeightRegular, NSColor.secondaryLabelColor);
            expiryLabel.stringValue = expiryText;
        }];
    }
    self.cardRects = rects;
    self.badgeRects = badges;
    self.badgeTexts = badgeTexts;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    for (NSValue *value in self.cardRects) {
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:value.rectValue xRadius:8 yRadius:8];
        [CardBackgroundColor(self) setFill];
        [path fill];
        [CardStrokeColor(self) setStroke];
        path.lineWidth = 0.75;
        [path stroke];
    }
    NSFont *badgeFont = [NSFont systemFontOfSize:8.5 weight:NSFontWeightSemibold];
    NSFont *titleFont = [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold];
    NSMutableParagraphStyle *centered = [[NSMutableParagraphStyle alloc] init];
    centered.alignment = NSTextAlignmentCenter;
    NSDictionary *badgeAttributes = @{
        NSFontAttributeName: badgeFont,
        NSForegroundColorAttributeName: NSColor.systemBlueColor,
        NSParagraphStyleAttributeName: centered,
    };
    [self.badgeRects enumerateObjectsUsingBlock:^(NSValue *value, NSUInteger index, BOOL *stop) {
        (void)stop;
        NSRect badgeRect = value.rectValue;
        NSRect cardRect = self.cardRects[index].rectValue;
        CGFloat headerCenterY = NSMinY(cardRect) + 15.0;

        NSString *title = [NSString stringWithFormat:@"第 %lu 次重置", (unsigned long)index + 1];
        NSDictionary *titleAttributes = @{
            NSFontAttributeName: titleFont,
            NSForegroundColorAttributeName: NSColor.labelColor,
        };
        CGFloat titleHeight = ceil([title sizeWithAttributes:titleAttributes].height);
        NSRect titleRect = NSMakeRect(NSMinX(cardRect) + 12,
                                      floor(headerCenterY - titleHeight / 2.0),
                                      62, titleHeight);
        [title drawInRect:titleRect withAttributes:titleAttributes];

        badgeRect.origin.y = headerCenterY - NSHeight(badgeRect) / 2.0;
        NSBezierPath *badge = [NSBezierPath bezierPathWithRoundedRect:badgeRect xRadius:9 yRadius:9];
        [[[NSColor systemBlueColor] colorWithAlphaComponent:0.12] setFill];
        [badge fill];
        if (index < self.badgeTexts.count) {
            NSString *text = self.badgeTexts[index];
            CGFloat textHeight = ceil([text sizeWithAttributes:badgeAttributes].height);
            NSRect textRect = NSMakeRect(NSMinX(badgeRect),
                                         floor(NSMidY(badgeRect) - textHeight / 2.0),
                                         NSWidth(badgeRect), textHeight);
            [text drawInRect:textRect withAttributes:badgeAttributes];
        }
    }];
}

@end

@class UsageMenuController;

@interface UsagePanelView : NSView
@property(nonatomic, weak) UsageMenuController *controller;
@property(nonatomic, strong) NSImageView *accountIcon;
@property(nonatomic, strong) NSTextField *accountTitle;
@property(nonatomic, strong) NSTextField *accountSubtitle;
@property(nonatomic, strong) NSTextField *fiveHourTitle;
@property(nonatomic, strong) NSTextField *fiveHourPercent;
@property(nonatomic, strong) NSTextField *fiveHourReset;
@property(nonatomic, strong) NSTextField *weeklyTitle;
@property(nonatomic, strong) NSTextField *weeklyPercent;
@property(nonatomic, strong) NSTextField *weeklyReset;
@property(nonatomic, strong) NSTextField *resetCreditsTitle;
@property(nonatomic, strong) NSTextField *resetCreditsValue;
@property(nonatomic, strong) NSTextField *disclosureLabel;
@property(nonatomic, strong) NSButton *resetDisclosureButton;
@property(nonatomic, strong) NSButton *refreshButton;
@property(nonatomic, strong) NSButton *quitButton;
@property(nonatomic, strong) NSScrollView *creditsScrollView;
@property(nonatomic, strong) UsageCreditListView *creditsListView;
@property(nonatomic, copy) NSArray<NSDictionary *> *creditEntries;
@property(nonatomic) double fiveHourRemainingPercent;
@property(nonatomic) double weeklyRemainingPercent;
@property(nonatomic) BOOL resetDetailsExpanded;
@property(nonatomic) CGFloat currentPanelHeight;
@property(nonatomic) CGFloat currentDetailsHeight;
@property(nonatomic) CGFloat currentFooterTop;
- (void)updateWithSnapshot:(NSDictionary *)snapshot error:(NSError *)error;
- (void)toggleResetDetails;
- (void)collapseResetDetails;
@end

@interface UsageMenuController : NSObject <NSApplicationDelegate, NSPopoverDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSPopover *popover;
@property(nonatomic, strong) UsagePanelView *panelView;
@property(nonatomic, strong) NSView *panelContainer;
@property(nonatomic, strong) NSViewController *panelViewController;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSString *snapshotPath;
@property(nonatomic, copy) NSString *helperPath;
@property(nonatomic, strong) id localClickMonitor;
@property(nonatomic, strong) id globalClickMonitor;
@property(nonatomic) BOOL refreshInProgress;
@property(nonatomic, copy) NSString *helperErrorCode;
- (void)refresh:(id)sender;
- (void)toggleResetDetails:(id)sender;
- (void)updatePopoverHeight:(CGFloat)height;
- (void)quit:(id)sender;
@end

@implementation UsagePanelView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.creditEntries = @[];

        self.accountIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        NSImage *accountImage = [NSImage imageWithSystemSymbolName:@"person.crop.circle.fill" accessibilityDescription:@"账户"];
        NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration configurationWithPointSize:22 weight:NSFontWeightRegular];
        self.accountIcon.image = [accountImage imageWithSymbolConfiguration:configuration];
        self.accountIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
        self.accountIcon.contentTintColor = NSColor.systemBlueColor;
        [self addSubview:self.accountIcon];
        self.accountTitle = CreateLabel(self, NSMakeRect(48, 13, 134, 16), 10.5, NSFontWeightSemibold, NSColor.labelColor);
        self.accountTitle.stringValue = @"Codex 账户";
        self.accountSubtitle = CreateLabel(self, NSMakeRect(48, 29, 134, 14), 9, NSFontWeightRegular, NSColor.secondaryLabelColor);
        self.accountSubtitle.stringValue = @"账户信息暂不可用";

        self.fiveHourTitle = CreateLabel(self, NSMakeRect(20, 69, 58, 17), 11.5, NSFontWeightSemibold, NSColor.labelColor);
        self.fiveHourTitle.stringValue = @"5 hours";
        self.fiveHourPercent = CreateLabel(self, NSMakeRect(148, 69, 34, 17), 10.5, NSFontWeightSemibold, NSColor.labelColor);
        self.fiveHourPercent.alignment = NSTextAlignmentRight;
        self.fiveHourReset = CreateLabel(self, NSMakeRect(100, 70, 40, 16), 9, NSFontWeightRegular, NSColor.secondaryLabelColor);
        self.fiveHourReset.alignment = NSTextAlignmentRight;

        self.weeklyTitle = CreateLabel(self, NSMakeRect(20, 108, 58, 17), 11.5, NSFontWeightSemibold, NSColor.labelColor);
        self.weeklyTitle.stringValue = @"week";
        self.weeklyPercent = CreateLabel(self, NSMakeRect(148, 108, 34, 17), 10.5, NSFontWeightSemibold, NSColor.labelColor);
        self.weeklyPercent.alignment = NSTextAlignmentRight;
        self.weeklyReset = CreateLabel(self, NSMakeRect(100, 109, 40, 16), 9, NSFontWeightRegular, NSColor.secondaryLabelColor);
        self.weeklyReset.alignment = NSTextAlignmentRight;

        self.resetCreditsTitle = CreateLabel(self, NSMakeRect(20, 161, 90, 17), 11, NSFontWeightRegular, NSColor.labelColor);
        self.resetCreditsTitle.stringValue = @"重置次数";
        self.resetCreditsValue = CreateLabel(self, NSMakeRect(140, 161, 30, 17), 11, NSFontWeightSemibold, NSColor.labelColor);
        self.resetCreditsValue.alignment = NSTextAlignmentRight;
        self.resetCreditsValue.stringValue = @"--";
        self.disclosureLabel = CreateLabel(self, NSMakeRect(174, 163, 8, 14), 9, NSFontWeightMedium, NSColor.tertiaryLabelColor);
        self.disclosureLabel.alignment = NSTextAlignmentRight;
        self.disclosureLabel.stringValue = @"⌄";

        self.resetDisclosureButton = [[NSButton alloc] initWithFrame:NSMakeRect(PanelMargin, 154, PanelWidth - PanelMargin * 2, 30)];
        self.resetDisclosureButton.title = @"";
        self.resetDisclosureButton.bordered = NO;
        self.resetDisclosureButton.transparent = YES;
        self.resetDisclosureButton.toolTip = @"展开重置额度详情";
        [self addSubview:self.resetDisclosureButton positioned:NSWindowAbove relativeTo:nil];

        self.creditsListView = [[UsageCreditListView alloc] initWithFrame:NSMakeRect(0, 0, PanelWidth - PanelMargin * 2, 52)];
        [self.creditsListView reloadWithCredits:@[] width:PanelWidth - PanelMargin * 2];
        self.creditsScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        self.creditsScrollView.borderType = NSNoBorder;
        self.creditsScrollView.drawsBackground = NO;
        self.creditsScrollView.hasVerticalScroller = NO;
        self.creditsScrollView.scrollerStyle = NSScrollerStyleOverlay;
        self.creditsScrollView.documentView = self.creditsListView;
        self.creditsScrollView.hidden = YES;
        [self addSubview:self.creditsScrollView];

        self.refreshButton = [self actionButton:@"刷新" action:@selector(refresh:)];
        self.quitButton = [self actionButton:@"退出" action:@selector(quit:)];
        [self layoutPanel];
    }
    return self;
}

- (NSButton *)actionButton:(NSString *)title action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeRegular;
    button.title = title;
    button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    button.action = action;
    [self addSubview:button];
    return button;
}

- (void)setController:(UsageMenuController *)controller {
    _controller = controller;
    self.refreshButton.target = controller;
    self.quitButton.target = controller;
    self.resetDisclosureButton.target = controller;
    self.resetDisclosureButton.action = @selector(toggleResetDetails:);
}

- (void)layoutContentForHeight:(CGFloat)height detailsHeight:(CGFloat)detailsHeight footerTop:(CGFloat)footerTop {
    self.accountIcon.frame = RectFromTop(height, 18, 18, 22, 22);
    self.accountTitle.frame = RectFromTop(height, 48, 13, 134, 16);
    self.accountSubtitle.frame = RectFromTop(height, 48, 29, 134, 14);

    self.fiveHourTitle.frame = RectFromTop(height, 20, 69, 58, 17);
    self.fiveHourReset.frame = RectFromTop(height, 100, 70, 40, 16);
    self.fiveHourPercent.frame = RectFromTop(height, 148, 69, 34, 17);
    self.weeklyTitle.frame = RectFromTop(height, 20, 108, 58, 17);
    self.weeklyReset.frame = RectFromTop(height, 100, 109, 40, 16);
    self.weeklyPercent.frame = RectFromTop(height, 148, 108, 34, 17);

    self.resetCreditsTitle.frame = RectFromTop(height, 20, 161, 90, 17);
    self.resetCreditsValue.frame = RectFromTop(height, 140, 161, 30, 17);
    self.disclosureLabel.frame = RectFromTop(height, 174, 163, 8, 14);
    self.resetDisclosureButton.frame = RectFromTop(height, PanelMargin, 154, PanelWidth - PanelMargin * 2, 30);

    if (self.resetDetailsExpanded) {
        self.creditsScrollView.frame = RectFromTop(height, PanelMargin, 192, PanelWidth - PanelMargin * 2, detailsHeight);
    }
    self.refreshButton.frame = RectFromTop(height, 18, footerTop, 72, 26);
    self.quitButton.frame = RectFromTop(height, 110, footerTop, 72, 26);
}

- (void)layoutPanel {
    CGFloat detailsHeight = 0;
    CGFloat footerTop = 194.0;
    if (self.resetDetailsExpanded) {
        CGFloat contentHeight = self.creditsListView.frame.size.height;
        detailsHeight = MIN(MAX(contentHeight, 52.0), 206.0);
        self.creditsScrollView.hidden = NO;
        footerTop = 192 + detailsHeight + 10;
    } else {
        self.creditsScrollView.hidden = YES;
    }

    self.currentPanelHeight = self.resetDetailsExpanded ? footerTop + 26 + 10 : CollapsedPanelHeight;
    self.currentDetailsHeight = detailsHeight;
    self.currentFooterTop = footerTop;
    if (self.controller) {
        [self.controller updatePopoverHeight:self.currentPanelHeight];
    }
    [self layoutContentForHeight:self.currentPanelHeight detailsHeight:detailsHeight footerTop:footerTop];
    [self setNeedsDisplay:YES];
}

- (void)layout {
    [super layout];
    [self layoutContentForHeight:self.bounds.size.height detailsHeight:self.currentDetailsHeight footerTop:self.currentFooterTop];
}

- (void)toggleResetDetails {
    self.resetDetailsExpanded = !self.resetDetailsExpanded;
    self.disclosureLabel.stringValue = self.resetDetailsExpanded ? @"⌃" : @"⌄";
    self.resetDisclosureButton.toolTip = self.resetDetailsExpanded ? @"收起重置额度详情" : @"展开重置额度详情";
    [self layoutPanel];
}

- (void)collapseResetDetails {
    if (!self.resetDetailsExpanded) {
        return;
    }
    self.resetDetailsExpanded = NO;
    self.disclosureLabel.stringValue = @"⌄";
    self.resetDisclosureButton.toolTip = @"展开重置额度详情";
    [self layoutPanel];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [PanelBackgroundColor(self) setFill];
    NSRectFill(self.bounds);

    NSArray<NSValue *> *cards = @[
        [NSValue valueWithRect:RectFromTop(self.bounds.size.height, 8, 8, 184, 42)],
        [NSValue valueWithRect:RectFromTop(self.bounds.size.height, 8, 58, 184, 88)],
        [NSValue valueWithRect:RectFromTop(self.bounds.size.height, 8, 154, 184, 30)],
    ];
    for (NSValue *value in cards) {
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:value.rectValue xRadius:9 yRadius:9];
        [CardBackgroundColor(self) setFill];
        [path fill];
        [CardStrokeColor(self) setStroke];
        path.lineWidth = 0.75;
        [path stroke];
    }

    [self drawQuotaBar:RectFromTop(self.bounds.size.height, 18, 93, 164, 5) percent:self.fiveHourRemainingPercent];
    [self drawQuotaBar:RectFromTop(self.bounds.size.height, 18, 132, 164, 5) percent:self.weeklyRemainingPercent];
}

- (void)drawQuotaBar:(NSRect)rect percent:(double)percent {
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:2.5 yRadius:2.5];
    [[[NSColor secondaryLabelColor] colorWithAlphaComponent:0.20] setFill];
    [track fill];

    CGFloat fillWidth = rect.size.width * MAX(0.0, MIN(100.0, percent)) / 100.0;
    if (fillWidth <= 0) {
        return;
    }
    NSBezierPath *fill = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(rect.origin.x, rect.origin.y, fillWidth, rect.size.height) xRadius:2.5 yRadius:2.5];
    [[self barColorForPercent:percent] setFill];
    [fill fill];
}

- (NSColor *)barColorForPercent:(double)percent {
    if (percent <= 20) {
        return NSColor.systemRedColor;
    }
    if (percent <= 50) {
        return NSColor.systemOrangeColor;
    }
    return NSColor.systemGreenColor;
}

- (NSString *)resetTimeText:(id)value {
    NSDate *date = DateFromISO8601Value(value);
    if (!date) {
        return @"--";
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = NSTimeZone.localTimeZone;
    formatter.dateFormat = [NSCalendar.currentCalendar isDate:date inSameDayAsDate:NSDate.date] ? @"HH:mm" : @"MM-dd";
    return [formatter stringFromDate:date];
}

- (void)updateAccountFromSnapshot:(NSDictionary *)snapshot {
    NSDictionary *account = [snapshot[@"account"] isKindOfClass:NSDictionary.class] ? snapshot[@"account"] : nil;
    NSString *email = [account[@"email"] isKindOfClass:NSString.class] ? account[@"email"] : nil;
    NSString *displayName = [account[@"displayName"] isKindOfClass:NSString.class] ? account[@"displayName"] : nil;
    NSString *planType = [account[@"planType"] isKindOfClass:NSString.class] ? account[@"planType"] : nil;
    NSString *accountType = [account[@"accountType"] isKindOfClass:NSString.class] ? account[@"accountType"] : nil;

    NSString *title = displayName.length > 0 ? displayName : (email.length > 0 ? email : @"Codex 账户");
    NSString *subtitle = @"账户信息暂不可用";
    if (displayName.length > 0 && email.length > 0) {
        subtitle = email;
    } else if (planType.length > 0) {
        subtitle = [NSString stringWithFormat:@"ChatGPT %@", planType.capitalizedString];
    } else if (accountType.length > 0) {
        subtitle = accountType.capitalizedString;
    }
    NSDictionary *lastError = [snapshot[@"lastError"] isKindOfClass:NSDictionary.class] ? snapshot[@"lastError"] : nil;
    NSString *code = [lastError[@"code"] isKindOfClass:NSString.class] ? lastError[@"code"] : @"";
    if ([code isEqualToString:@"timeout"]) {
        subtitle = @"读取超时，稍后自动重试";
    } else if ([code isEqualToString:@"signed_out"]) {
        subtitle = @"请先在 Codex 中登录";
    } else if ([code isEqualToString:@"executable_missing"]) {
        subtitle = @"未找到 Codex 程序";
    } else if ([code isEqualToString:@"python_missing"]) {
        subtitle = @"请先安装 Python 3";
    } else if ([code isEqualToString:@"stale_snapshot"]) {
        subtitle = @"数据已过期，正在刷新";
    } else if (code.length > 0) {
        subtitle = @"读取失败，稍后自动重试";
    }
    self.accountTitle.stringValue = title;
    self.accountSubtitle.stringValue = subtitle;
    self.accountSubtitle.toolTip = code.length > 0 ? [NSString stringWithFormat:@"%@: %@", lastError[@"stage"] ?: @"", code] : nil;

}

- (NSInteger)resetCreditsCount:(NSDictionary *)snapshot {
    NSDictionary *grant = [snapshot[@"resetGrant"] isKindOfClass:NSDictionary.class] ? snapshot[@"resetGrant"] : nil;
    id count = grant[@"availableCount"] ?: grant[@"available"];
    if ([count respondsToSelector:@selector(integerValue)]) {
        return MAX(0, [count integerValue]);
    }
    NSArray *credits = [grant[@"credits"] isKindOfClass:NSArray.class] ? grant[@"credits"] : nil;
    return credits ? credits.count : NSNotFound;
}

- (NSArray<NSDictionary *> *)creditEntriesFromSnapshot:(NSDictionary *)snapshot count:(NSInteger)count {
    NSDictionary *grant = [snapshot[@"resetGrant"] isKindOfClass:NSDictionary.class] ? snapshot[@"resetGrant"] : nil;
    NSArray *credits = [grant[@"credits"] isKindOfClass:NSArray.class] ? grant[@"credits"] : nil;
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (id credit in credits) {
        if ([credit isKindOfClass:NSDictionary.class]) {
            [entries addObject:credit];
        }
    }
    if (entries.count > 0) {
        return entries;
    }

    NSArray *dates = [grant[@"expirationDates"] isKindOfClass:NSArray.class] ? grant[@"expirationDates"] : nil;
    for (id date in dates) {
        if ([date isKindOfClass:NSString.class]) {
            [entries addObject:@{@"status": @"available", @"expiresAt": date}];
        }
    }
    if (entries.count == 0 && count != NSNotFound) {
        for (NSInteger index = 0; index < count; index++) {
            [entries addObject:@{@"status": @"available"}];
        }
    }
    return entries;
}

- (void)updateWithSnapshot:(NSDictionary *)snapshot error:(NSError *)error {
    (void)error;
    [self updateAccountFromSnapshot:snapshot ?: @{}];

    NSDictionary *fiveHour = [snapshot[@"rolling5h"] isKindOfClass:NSDictionary.class] ? snapshot[@"rolling5h"] : nil;
    NSDictionary *weekly = [snapshot[@"weekly"] isKindOfClass:NSDictionary.class] ? snapshot[@"weekly"] : nil;
    if (fiveHour && weekly) {
        self.fiveHourRemainingPercent = MAX(0, MIN(100, [fiveHour[@"remainingPercent"] doubleValue]));
        self.weeklyRemainingPercent = MAX(0, MIN(100, [weekly[@"remainingPercent"] doubleValue]));
        self.fiveHourPercent.stringValue = [NSString stringWithFormat:@"%.0f%%", self.fiveHourRemainingPercent];
        self.weeklyPercent.stringValue = [NSString stringWithFormat:@"%.0f%%", self.weeklyRemainingPercent];
        self.fiveHourReset.stringValue = [self resetTimeText:fiveHour[@"resetAt"]];
        self.weeklyReset.stringValue = [self resetTimeText:weekly[@"resetAt"]];

        NSInteger count = [self resetCreditsCount:snapshot];
        self.resetCreditsValue.stringValue = count == NSNotFound ? @"--" : [NSString stringWithFormat:@"%ld", (long)count];
        self.creditEntries = [self creditEntriesFromSnapshot:snapshot count:count];
    } else {
        self.fiveHourRemainingPercent = 0;
        self.weeklyRemainingPercent = 0;
        self.fiveHourPercent.stringValue = @"--";
        self.weeklyPercent.stringValue = @"--";
        self.fiveHourReset.stringValue = @"--";
        self.weeklyReset.stringValue = @"--";
        self.resetCreditsValue.stringValue = @"--";
        self.creditEntries = @[];
    }
    [self.creditsListView reloadWithCredits:self.creditEntries width:PanelWidth - PanelMargin * 2];
    [self layoutPanel];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self setNeedsDisplay:YES];
    [self.creditsListView setNeedsDisplay:YES];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        self.window.backgroundColor = PanelBackgroundColor(self);
    }
}

@end

@implementation UsageMenuController

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSString *envPath = NSProcessInfo.processInfo.environment[@"CODEX_USAGE_SNAPSHOT_PATH"];
    self.snapshotPath = envPath.length > 0 ? envPath : [@"~/.codex/usage-menu/usage.json" stringByExpandingTildeInPath];
    self.helperPath = [self usageHelperPath];

    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.toolTip = @"Codex usage";
    self.statusItem.button.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium];
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(togglePopover:);

    self.panelContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, PanelWidth, CollapsedPanelHeight)];
    self.panelView = [[UsagePanelView alloc] initWithFrame:self.panelContainer.bounds];
    self.panelView.translatesAutoresizingMaskIntoConstraints = NO;
    self.panelView.controller = self;
    [self.panelContainer addSubview:self.panelView];
    [NSLayoutConstraint activateConstraints:@[
        [self.panelView.leadingAnchor constraintEqualToAnchor:self.panelContainer.leadingAnchor],
        [self.panelView.trailingAnchor constraintEqualToAnchor:self.panelContainer.trailingAnchor],
        [self.panelView.topAnchor constraintEqualToAnchor:self.panelContainer.topAnchor],
        [self.panelView.bottomAnchor constraintEqualToAnchor:self.panelContainer.bottomAnchor],
    ]];
    self.panelViewController = [[NSViewController alloc] init];
    self.panelViewController.view = self.panelContainer;
    self.panelViewController.preferredContentSize = NSMakeSize(PanelWidth, CollapsedPanelHeight);
    self.popover = [[NSPopover alloc] init];
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.contentViewController = self.panelViewController;
    self.popover.contentSize = NSMakeSize(PanelWidth, CollapsedPanelHeight);
    self.popover.delegate = self;

    [self refresh:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
}

- (NSDictionary *)loadSnapshot:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:self.snapshotPath options:0 error:error];
    if (!data) {
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:NSDictionary.class] || ![json[@"schemaVersion"] isEqual:@1]) {
        return nil;
    }
    NSDate *updatedAt = DateFromISO8601Value(json[@"updatedAt"]);
    NSTimeInterval age = updatedAt ? -updatedAt.timeIntervalSinceNow : INFINITY;
    if (age > 180 || age < -60) {
        return @{@"status": @"unavailable", @"lastError": @{@"code": @"stale_snapshot", @"stage": @"snapshot"}};
    }
    return json;
}

- (NSString *)usageHelperPath {
    NSString *configuredPath = NSProcessInfo.processInfo.environment[@"CODEX_USAGE_HELPER_PATH"];
    if (configuredPath.length > 0) {
        return configuredPath.stringByExpandingTildeInPath;
    }
    NSString *bundledPath = [NSBundle.mainBundle pathForResource:@"codex_usage" ofType:@"py" inDirectory:@"scripts"];
    if (bundledPath.length > 0 && [NSFileManager.defaultManager isReadableFileAtPath:bundledPath]) {
        return bundledPath;
    }
    NSString *workingDirectory = NSFileManager.defaultManager.currentDirectoryPath;
    for (NSString *candidate in @[
        [workingDirectory stringByAppendingPathComponent:@"../../scripts/codex_usage.py"],
        [workingDirectory stringByAppendingPathComponent:@"scripts/codex_usage.py"],
    ]) {
        NSString *path = candidate.stringByStandardizingPath;
        if ([NSFileManager.defaultManager isReadableFileAtPath:path]) {
            return path;
        }
    }
    return nil;
}

- (NSString *)refreshSnapshotFile {
    if (self.helperPath.length == 0) {
        return @"helper_missing";
    }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"];
    task.arguments = @[@"python3", self.helperPath, @"snapshot", @"--snapshot", self.snapshotPath];
    // Finder launches do not inherit the user's shell PATH.
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"PATH"] = [NSString stringWithFormat:@"%@:/opt/homebrew/bin:/usr/local/bin:%@/.local/bin:/usr/bin:/bin",
                            environment[@"PATH"] ?: @"", NSHomeDirectory()];
    task.environment = environment;
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *error = nil;
    if ([task launchAndReturnError:&error]) {
        [task waitUntilExit];
        return task.terminationStatus == 0 ? nil
            : (task.terminationStatus == 127 ? @"python_missing" : @"helper_failed");
    }
    return @"helper_failed";
}

- (void)loadCachedSnapshot {
    NSError *error = nil;
    NSDictionary *snapshot = [self loadSnapshot:&error];
    if (self.helperErrorCode.length > 0) {
        snapshot = @{@"status": @"unavailable", @"lastError": @{@"code": self.helperErrorCode, @"stage": @"helper"}};
    }
    NSDictionary *fiveHour = [snapshot[@"rolling5h"] isKindOfClass:NSDictionary.class] ? snapshot[@"rolling5h"] : nil;
    if (fiveHour) {
        NSInteger percent = lround([fiveHour[@"remainingPercent"] doubleValue]);
        self.statusItem.button.title = [NSString stringWithFormat:@"Codex %ld%%", (long)percent];
    } else {
        self.statusItem.button.title = @"Codex --";
    }
    [self.panelView updateWithSnapshot:snapshot error:error];
}

- (void)refresh:(id)sender {
    (void)sender;
    [self loadCachedSnapshot];
    if (self.refreshInProgress) {
        return;
    }
    self.refreshInProgress = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *helperErrorCode = [self refreshSnapshotFile];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.helperErrorCode = helperErrorCode;
            self.refreshInProgress = NO;
            [self loadCachedSnapshot];
        });
    });
}

- (void)togglePopover:(id)sender {
    (void)sender;
    if (self.popover.shown) {
        [self.popover performClose:nil];
        return;
    }
    [self loadCachedSnapshot];
    [self updatePopoverHeight:self.panelView.currentPanelHeight];
    [self.popover showRelativeToRect:self.statusItem.button.bounds ofView:self.statusItem.button preferredEdge:NSRectEdgeMinY];
    [self startClickOutsideMonitoring];
}

- (void)toggleResetDetails:(id)sender {
    (void)sender;
    [self.panelView toggleResetDetails];
}

- (void)updatePopoverHeight:(CGFloat)height {
    NSSize size = NSMakeSize(PanelWidth, height);
    self.panelViewController.preferredContentSize = size;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0;
        self.popover.contentSize = size;
    } completionHandler:nil];
    [self.panelContainer layoutSubtreeIfNeeded];
}

- (BOOL)eventIsInsidePopoverOrStatusItem:(NSEvent *)event {
    if (event.window == self.popover.contentViewController.view.window) {
        return YES;
    }
    NSButton *button = self.statusItem.button;
    if (button && event.window == button.window) {
        NSPoint point = [button convertPoint:event.locationInWindow fromView:nil];
        return NSPointInRect(point, button.bounds);
    }
    return NO;
}

- (void)startClickOutsideMonitoring {
    [self stopClickOutsideMonitoring];
    __weak UsageMenuController *weakSelf = self;
    NSEventMask mask = NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown;
    self.localClickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event) {
        UsageMenuController *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.popover.shown || [strongSelf eventIsInsidePopoverOrStatusItem:event]) {
            return event;
        }
        [strongSelf.popover performClose:nil];
        return event;
    }];
    self.globalClickMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:mask handler:^(NSEvent *event) {
        (void)event;
        UsageMenuController *strongSelf = weakSelf;
        if (strongSelf.popover.shown) {
            [strongSelf.popover performClose:nil];
        }
    }];
}

- (void)stopClickOutsideMonitoring {
    if (self.localClickMonitor) {
        [NSEvent removeMonitor:self.localClickMonitor];
        self.localClickMonitor = nil;
    }
    if (self.globalClickMonitor) {
        [NSEvent removeMonitor:self.globalClickMonitor];
        self.globalClickMonitor = nil;
    }
}

- (void)popoverDidClose:(NSNotification *)notification {
    (void)notification;
    [self stopClickOutsideMonitoring];
    [self.panelView collapseResetDetails];
}

- (void)quit:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}

@end


int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        UsageMenuController *delegate = [[UsageMenuController alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
