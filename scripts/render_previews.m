// Render the real AppKit panel with fictional data; never access a user account.
// clang -fobjc-arc scripts/render_previews.m -framework Cocoa -o /tmp/codexusage-previews
// /tmp/codexusage-previews docs/assets
#define main CodexUsageApplicationMain
#import "../apps/CodexUsageMenuBar/Sources/main.m"
#undef main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 1;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneWithName:@"Asia/Shanghai"]];
        NSString *output = @(argv[1]);
        NSDictionary *sample = @{
            @"account": @{@"displayName": @"Demo", @"planType": @"pro"},
            @"rolling5h": @{@"remainingPercent": @82, @"resetAt": @"2026-10-18T06:00:00Z"},
            @"weekly": @{@"remainingPercent": @75, @"resetAt": @"2026-10-23T06:00:00Z"},
            @"resetGrant": @{@"availableCount": @2, @"credits": @[
                @{@"status": @"available", @"expiresAt": @"2026-11-01T00:00:00Z"},
                @{@"status": @"available", @"expiresAt": @"2026-11-08T00:00:00Z"}
            ]}
        };
        for (NSString *theme in @[@"light", @"dark"]) {
            NSAppearance *appearance = [NSAppearance appearanceNamed:
                [theme isEqualToString:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
            [appearance performAsCurrentDrawingAppearance:^{
                UsagePanelView *panel = [[UsagePanelView alloc] initWithFrame:NSMakeRect(0, 0, PanelWidth, CollapsedPanelHeight)];
                panel.appearance = appearance;
                [panel updateWithSnapshot:sample error:nil];
                [panel toggleResetDetails];
                [panel setFrameSize:NSMakeSize(PanelWidth, panel.currentPanelHeight)];
                NSWindow *window = [[NSWindow alloc] initWithContentRect:panel.bounds styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
                window.appearance = appearance;
                window.contentView = panel;
                [panel layoutSubtreeIfNeeded];
                NSBitmapImageRep *bitmap = [panel bitmapImageRepForCachingDisplayInRect:panel.bounds];
                [panel cacheDisplayInRect:panel.bounds toBitmapImageRep:bitmap];
                NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                NSString *file = [output stringByAppendingPathComponent:[NSString stringWithFormat:@"panel-%@.png", theme]];
                if (![png writeToFile:file atomically:YES]) exit(2);
            }];
        }
    }
    return 0;
}
