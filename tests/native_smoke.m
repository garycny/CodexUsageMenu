// Exercise the actual native reader without opening the menu bar app or Codex.
#define main CodexUsageApplicationMain
#import "../apps/CodexUsageMenuBar/Sources/main.m"
#undef main

@interface SnapshotRecorder : NSObject
@property(nonatomic, strong) NSDictionary *snapshot;
@end

@implementation SnapshotRecorder
- (void)updateWithSnapshot:(NSDictionary *)snapshot error:(NSError *)error {
    (void)error;
    self.snapshot = snapshot;
}
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "%s\n", message.UTF8String);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSFileManager *files = NSFileManager.defaultManager;
        Check([files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil], @"temp directory");
        UsageMenuController *controller = [[UsageMenuController alloc] init];
        controller.snapshotPath = [directory stringByAppendingPathComponent:@"usage.json"];
        NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
        NSMutableDictionary *snapshot = [@{
            @"schemaVersion": @1,
            @"updatedAt": [formatter stringFromDate:NSDate.date],
            @"status": @"ok",
            @"rolling5h": @{@"remainingPercent": @82},
            @"weekly": @{@"remainingPercent": @75}
        } mutableCopy];
        void (^writeSnapshot)(void) = ^{
            NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
            Check([data writeToFile:controller.snapshotPath atomically:YES], @"write fixture");
        };
        writeSnapshot();
        Check([[controller loadSnapshot:nil][@"rolling5h"][@"remainingPercent"] isEqual:@82], @"read fresh values");
        SnapshotRecorder *recorder = [[SnapshotRecorder alloc] init];
        controller.panelView = (UsagePanelView *)recorder;
        controller.helperErrorCode = @"helper_failed";
        [controller loadCachedSnapshot];
        Check([recorder.snapshot[@"status"] isEqual:@"unavailable"] && !recorder.snapshot[@"rolling5h"], @"helper failure overrides valid cached values");
        controller.helperErrorCode = nil;
        [controller loadCachedSnapshot];
        Check([recorder.snapshot[@"rolling5h"][@"remainingPercent"] isEqual:@82], @"successful refresh restores cached values");
        snapshot[@"updatedAt"] = [formatter stringFromDate:[NSDate dateWithTimeIntervalSinceNow:-600]];
        writeSnapshot();
        Check([[controller loadSnapshot:nil][@"lastError"][@"code"] isEqual:@"stale_snapshot"], @"reject stale data");
        snapshot[@"updatedAt"] = @"invalid";
        writeSnapshot();
        Check([[controller loadSnapshot:nil][@"status"] isEqual:@"unavailable"], @"reject invalid timestamp");
        snapshot[@"schemaVersion"] = @99;
        writeSnapshot();
        Check([controller loadSnapshot:nil] == nil, @"reject unsupported schema");
        Check([[controller refreshSnapshotFile] isEqual:@"helper_missing"], @"report missing helper");

        NSString *helper = [directory stringByAppendingPathComponent:@"failing.py"];
        Check([@"raise SystemExit(1)\n" writeToFile:helper atomically:YES encoding:NSUTF8StringEncoding error:nil], @"write failing helper");
        controller.helperPath = helper;
        Check([[controller refreshSnapshotFile] isEqual:@"helper_failed"], @"report failing helper");

        // A successful helper clears the failure without launching a real Codex process.
        Check([@"pass\n" writeToFile:helper atomically:YES encoding:NSUTF8StringEncoding error:nil], @"write successful helper");
        Check([controller refreshSnapshotFile] == nil, @"recover from helper failure");
        [files removeItemAtPath:directory error:nil];
        puts("Native snapshot and helper checks passed.");
    }
    return 0;
}
