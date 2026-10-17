// Promotional composites from the author's real screenshots.
// The blue wallpaper comes from the source screenshot; product UI stays in native pixels.
// Raw screenshots are deliberately ignored by Git. See docs/assets/promo/README.md.
// SPDX-License-Identifier: Apache-2.0
#import <Cocoa/Cocoa.h>

static CGContextRef ctx;
static CGColorSpaceRef space;
static NSBitmapImageRep *canvas;
static void Begin(NSInteger w, NSInteger h) {
    canvas = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:w*4 bitsPerPixel:32];
    space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    ctx = CGBitmapContextCreate(canvas.bitmapData, w, h, 8, w*4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextTranslateCTM(ctx, 0, h);
    CGContextScaleCTM(ctx, 1, -1);
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES]];
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
}
static void End(NSString *path) {
    CGImageRef result = CGBitmapContextCreateImage(ctx);
    NSBitmapImageRep *image = [[NSBitmapImageRep alloc] initWithCGImage:result];
    NSData *png = [image representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (![png writeToFile:path atomically:YES]) { fprintf(stderr,"write failed\n"); exit(2); }
    CGImageRelease(result);
    CGContextRelease(ctx); CGColorSpaceRelease(space);
    [NSGraphicsContext setCurrentContext:nil]; canvas = nil;
}
static NSColor *Color(CGFloat r, CGFloat g, CGFloat b) { return [NSColor colorWithSRGBRed:r/255 green:g/255 blue:b/255 alpha:1]; }
static void Fill(NSRect r, NSColor *color) { CGContextSetFillColorWithColor(ctx,color.CGColor); CGContextFillRect(ctx,r); }
static void Draw(CGImageRef image, NSRect r) {
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, r.origin.x, r.origin.y+r.size.height);
    CGContextScaleCTM(ctx,1,-1);
    CGContextDrawImage(ctx,CGRectMake(0,0,r.size.width,r.size.height),image);
    CGContextRestoreGState(ctx);
}
static void Copy(CGImageRef source, NSRect from, NSRect to) {
    CGImageRef crop = CGImageCreateWithImageInRect(source,from); Draw(crop,to); CGImageRelease(crop);
}
static void Text(NSString *text, CGFloat x, CGFloat y, CGFloat w, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init]; p.lineSpacing=8;
    [text drawInRect:NSMakeRect(x,y,w,400) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:size weight:weight], NSForegroundColorAttributeName:color, NSParagraphStyleAttributeName:p}];
}
static NSColor *CanvasColor(NSInteger x, NSInteger y) {
    unsigned char *pixel=canvas.bitmapData+y*canvas.bytesPerRow+x*4;
    return Color(pixel[0],pixel[1],pixel[2]);
}
static void Foreground(NSBitmapImageRep *source, NSRect from, NSRect to) {
    NSInteger w=from.size.width,h=from.size.height;
    NSMutableData *data=[NSMutableData dataWithLength:w*h*4];
    unsigned char *pixels=data.mutableBytes;
    for(NSInteger y=0;y<h;y++) for(NSInteger x=0;x<w;x++) {
        NSColor *color=[[source colorAtX:from.origin.x+x y:from.origin.y+y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        NSColor *base=[[source colorAtX:from.origin.x+x y:44] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        CGFloat delta=color.redComponent-base.redComponent;
        CGFloat alpha=delta<0.025?0:MAX(0,MIN(1,delta/(0.94-base.redComponent)));
        NSInteger i=(y*w+x)*4;
        pixels[i]=pixels[i+1]=pixels[i+2]=(unsigned char)round(240*alpha);
        pixels[i+3]=(unsigned char)round(255*alpha);
    }
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef rgb=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image=CGImageCreate(w,h,8,32,w*4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,provider,NULL,NO,kCGRenderingIntentDefault);
    Draw(image,to); CGImageRelease(image); CGColorSpaceRelease(rgb); CGDataProviderRelease(provider);
}
static NSBitmapImageRep *Load(NSString *path) { return [[NSBitmapImageRep alloc] initWithData:[NSData dataWithContentsOfFile:path]]; }
static NSString *Out(NSString *root, NSString *file) { return [root stringByAppendingPathComponent:file]; }

typedef struct { const char *input; const char *output; CGFloat panelX,panelY,panelH,arrowY,headerX,rhsX,emailX,emailY; BOOL dark; } Config;
static Config configs[] = {
    {"download.png","screenshot-light.png",68,72,461,50,198,528,164,98,NO},
    {"download-1.png","screenshot-light-expanded.png",65,74,889,52,196,526,162,100,NO},
    {"download-2.png","screenshot-dark.png",66,78,460,56,196,526,162,104,YES},
    {"download-3.png","screenshot-dark-expanded.png",124,78,889,56,254,584,220,104,YES},
};
static void Sanitize(NSString *input, NSString *output, Config c) {
    NSBitmapImageRep *source=Load(Out(input,@(c.input)));
    NSInteger w=source.pixelsWide,h=source.pixelsHigh;
    Begin(w,h); Draw(source.CGImage,NSMakeRect(0,0,w,h));
    // Remove the network widget (and the red annotation) from the whole top strip.
    // Each column uses adjacent untouched wallpaper. Isolate native foreground
    // glyphs, then move the right-hand status group exactly 176 px left.
    for(NSInteger x=0; x<w; x++) {
        NSInteger sampleX=x;
        CGFloat center=c.panelX+200;
        if(fabs(x-center)<48) sampleX=(NSInteger)(x<center?center-50:center+50);
        NSColor *base=CanvasColor(sampleX,64);
        Fill(NSMakeRect(x,0,1,56),base);
    }
    Foreground(source,NSMakeRect(c.headerX,0,140,56),NSMakeRect(c.headerX,0,140,56));
    Foreground(source,NSMakeRect(c.rhsX,0,w-c.rhsX,56),NSMakeRect(c.rhsX-176,0,w-c.rhsX,56));
    NSColor *accountBG=CanvasColor((NSInteger)c.emailX+270,(NSInteger)c.emailY+12);
    Fill(NSMakeRect(c.emailX,c.emailY,270,32),accountBG);
    Text(@"demo@example.com",c.emailX+2,c.emailY,266,21,NSFontWeightSemibold,c.dark?Color(231,231,234):Color(89,89,89));
    End(Out(output,@(c.output)));
}
static void Product(NSString *output, Config c, CGFloat x, CGFloat y, CGFloat scale) {
    NSBitmapImageRep *source=Load(Out(output,@(c.output)));
    // Panels float on the continuous blue wallpaper; retain the original UI pixels.
    CGContextSaveGState(ctx);
    CGFloat px=x+40*scale, py=y+82*scale;
    NSRect panel=NSMakeRect(px,py,400*scale,c.panelH*scale);
    // Soft editorial shadow stays outside the original UI.
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx,CGSizeMake(0,14*scale),24*scale,[[NSColor blackColor] colorWithAlphaComponent:0.18].CGColor);
    CGPathRef shadow=CGPathCreateWithRoundedRect(panel,42*scale,42*scale,NULL);
    CGContextAddPath(ctx,shadow); CGContextSetFillColorWithColor(ctx,(c.dark?Color(37,37,39):Color(242,242,247)).CGColor); CGContextFillPath(ctx); CGPathRelease(shadow);
    CGContextRestoreGState(ctx);
    // Native rounded silhouette and popover arrow. No UI redrawing or AI text.
    CGContextSaveGState(ctx);
    CGPathRef body=CGPathCreateWithRoundedRect(panel,42*scale,42*scale,NULL); CGContextAddPath(ctx,body); CGPathRelease(body);
    CGFloat center=px+200*scale;
    CGContextMoveToPoint(ctx,center-28*scale,py+2*scale);
    CGContextAddCurveToPoint(ctx,center-17*scale,py-3*scale,center-12*scale,py-23*scale,center,py-22*scale);
    CGContextAddCurveToPoint(ctx,center+12*scale,py-23*scale,center+17*scale,py-3*scale,center+28*scale,py+2*scale);
    CGContextClosePath(ctx); CGContextClip(ctx);
    Copy(source.CGImage,NSMakeRect(c.panelX,c.arrowY,400,c.panelH+c.panelY-c.arrowY),NSMakeRect(px,py-(c.panelY-c.arrowY)*scale,400*scale,(c.panelH+c.panelY-c.arrowY)*scale));
    CGContextRestoreGState(ctx);
    // Two original menu-bar crops: product title followed immediately by Spotlight.
    // 29 px gap at source scale (14.5 pt); popover arrow stays centered below Codex.
    Foreground(source,NSMakeRect(c.headerX,8,140,36),NSMakeRect(px+130*scale,y+20*scale,140*scale,36*scale));
    Foreground(source,NSMakeRect(c.rhsX-176+7,7,34,38),NSMakeRect(px+299*scale,y+19*scale,34*scale,38*scale));
    CGContextRestoreGState(ctx);
}
static void Brand(NSString *root) {
    NSBitmapImageRep *icon=Load(Out(root,@"apps/CodexUsageMenuBar/Assets/CodexUsageIconRounded.png"));
    Draw(icon.CGImage,NSMakeRect(150,100,66,66));
    Text(@"CODEX USAGE MENU",238,116,700,22,NSFontWeightSemibold,Color(247,251,255));
}
static void Background(NSString *background, CGFloat w, CGFloat h) {
    Fill(NSMakeRect(0,0,w,h),Color(246,247,249));
    if(background.length) { NSBitmapImageRep *plate=Load(background); Draw(plate.CGImage,NSMakeRect(0,0,w,h)); }
}
static void Promo(NSString *root,NSString *out,NSString *background,BOOL expanded) {
    CGFloat height=expanded?1800:1500;
    Begin(2400,height); Background(background,2400,height); Brand(root);
    NSColor *ink=Color(255,255,255),*secondary=Color(239,247,252);
    Text(@"原生 macOS 菜单栏工具",160,expanded?440:400,900,25,NSFontWeightMedium,secondary);
    if(!expanded) {
        Text(@"Codex Usage\nMenu",152,468,1000,100,NSFontWeightSemibold,ink);
        Text(@"额度与重置，一目了然。",160,742,960,43,NSFontWeightMedium,ink);
        Text(@"5 小时与每周额度，随时查看。\n浅色与深色，贴合你的桌面。",163,850,900,28,NSFontWeightRegular,secondary);
        Product(out,configs[0],1230,374,1.0);
        Product(out,configs[2],1780,374,1.0);
        Text(@"浅色模式",1236,1080,450,22,NSFontWeightMedium,secondary);
        Text(@"深色模式",1786,1080,450,22,NSFontWeightMedium,secondary);
    } else {
        Text(@"重置额度，\n展开即见。",152,515,860,91,NSFontWeightSemibold,ink);
        Text(@"发放时间、到期日期与可用状态，\n清楚呈现每一次重置权益。",163,800,760,29,NSFontWeightRegular,secondary);
        Text(@"点击「重置次数」展开详情",163,932,760,24,NSFontWeightMedium,secondary);
        Product(out,configs[1],1130,366,1.0);
        Product(out,configs[3],1720,366,1.0);
        Text(@"浅色模式 · 详情展开",1136,1475,520,22,NSFontWeightMedium,secondary);
        Text(@"深色模式 · 详情展开",1726,1475,520,22,NSFontWeightMedium,secondary);
    }
    Fill(NSMakeRect(160,height-157,2080,1),[[NSColor whiteColor] colorWithAlphaComponent:0.25]);
    Text(@"真实界面截图 · 账户已脱敏",160,height-115,1300,21,NSFontWeightRegular,secondary);
    Text(@"macOS 13+",2050,height-115,300,21,NSFontWeightRegular,secondary);
    End(Out(out,expanded?@"promo-reset-details.png":@"promo-overview.png"));
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if(argc<3) return 1;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSString *root=@(argv[1]),*output=@(argv[2]);
        [NSFileManager.defaultManager createDirectoryAtPath:output withIntermediateDirectories:YES attributes:nil error:nil];
        for(int i=0;i<4;i++) Sanitize(Out(root,@"参考图"),output,configs[i]);
        // Sample the same uninterrupted blue desktop area previously used behind
        // each widget, now filling the complete canvas without separate stages.
        NSString *background=Out(output,@"backdrop.png");
        NSBitmapImageRep *wallpaper=Load(Out(output,@"screenshot-light-expanded.png"));
        Begin(2400,1800);
        Copy(wallpaper.CGImage,NSMakeRect(600,100,450,850),NSMakeRect(0,0,2400,1800));
        End(background);
        Promo(root,output,background,NO); Promo(root,output,background,YES);
        puts("Rendered 4 sanitized screenshots and 2 promotional images.");
    }
    return 0;
}
