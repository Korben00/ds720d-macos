// SPDX-License-Identifier: MIT
#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "ServiceClient.h"

@interface ScannerApp : NSObject <NSApplicationDelegate,NSWindowDelegate>
@property NSWindow *window;
@property NSTextField *status;
@property NSTextField *folderLabel;
@property NSButton *scanButton;
@property NSButton *folderButton;
@property NSButton *cleanButton;
@property NSButton *keepButton;
@property NSButton *resultsButton;
@property NSProgressIndicator *progress;
@property NSURL *folder;
@property NSArray<NSURL *> *results;
@property BOOL busy;
@end

static NSTextField *label(NSString *text,CGFloat size,BOOL bold) {
    NSTextField *field=[NSTextField wrappingLabelWithString:text];
    field.font=bold?[NSFont boldSystemFontOfSize:size]:[NSFont systemFontOfSize:size];
    return field;
}

@implementation ScannerApp
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSURL *pictures=[NSFileManager.defaultManager URLsForDirectory:NSPicturesDirectory inDomains:NSUserDomainMask].firstObject;
    self.folder=[pictures URLByAppendingPathComponent:@"DS720D Scans" isDirectory:YES];
    self.results=@[];
    NSMenu *menu=[NSMenu new];
    NSMenuItem *appItem=[NSMenuItem new];[menu addItem:appItem];
    NSMenu *appMenu=[NSMenu new];
    [appMenu addItemWithTitle:@"À propos de DS-720D Scanner" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"Quitter DS-720D Scanner" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu=appMenu;
    NSMenuItem *fileItem=[NSMenuItem new];[menu addItem:fileItem];
    NSMenu *fileMenu=[[NSMenu alloc] initWithTitle:@"Fichier"];
    NSMenuItem *import=[fileMenu addItemWithTitle:@"Retraiter une capture…" action:@selector(importCapture:) keyEquivalent:@"o"];
    import.target=self;fileItem.submenu=fileMenu;
    NSApp.mainMenu=menu;

    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,680,450)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"DS-720D Scanner";self.window.delegate=self;
    NSView *view=self.window.contentView;
    NSTextField *title=label(@"Brother DS-720D",25,YES);title.frame=NSMakeRect(32,382,610,36);[view addSubview:title];
    NSTextField *subtitle=label(@"Recto verso · Couleur · 300 dpi",14,NO);subtitle.textColor=NSColor.secondaryLabelColor;
    subtitle.frame=NSMakeRect(32,352,610,26);[view addSubview:subtitle];
    NSTextField *instructions=label(@"Installe le pilote, branche le scanner et insère une feuille. La numérisation ne demande aucune autorisation administrateur.",14,NO);
    instructions.frame=NSMakeRect(32,287,610,52);[view addSubview:instructions];

    self.folderLabel=label(@"",12,NO);self.folderLabel.frame=NSMakeRect(32,236,460,40);[view addSubview:self.folderLabel];
    self.folderButton=[NSButton buttonWithTitle:@"Choisir le dossier…" target:self action:@selector(chooseFolder:)];
    self.folderButton.frame=NSMakeRect(495,244,150,30);[view addSubview:self.folderButton];
    self.cleanButton=[NSButton checkboxWithTitle:@"Nettoyer le fond et retirer les bordures" target:nil action:NULL];
    self.cleanButton.state=NSControlStateValueOn;self.cleanButton.frame=NSMakeRect(32,203,610,26);[view addSubview:self.cleanButton];
    self.keepButton=[NSButton checkboxWithTitle:@"Conserver la capture pour retraitement (volumineux)" target:nil action:NULL];
    self.keepButton.frame=NSMakeRect(32,173,610,26);[view addSubview:self.keepButton];

    self.scanButton=[NSButton buttonWithTitle:@"Numériser les deux faces" target:self action:@selector(scan:)];
    self.scanButton.bezelStyle=NSBezelStyleRounded;self.scanButton.keyEquivalent=@"\r";
    self.scanButton.frame=NSMakeRect(32,111,250,42);[view addSubview:self.scanButton];
    self.resultsButton=[NSButton buttonWithTitle:@"Voir les images" target:self action:@selector(showResults:)];
    self.resultsButton.frame=NSMakeRect(300,116,160,32);self.resultsButton.enabled=NO;[view addSubview:self.resultsButton];
    self.progress=[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(614,122,20,20)];
    self.progress.style=NSProgressIndicatorStyleSpinning;self.progress.displayedWhenStopped=NO;[view addSubview:self.progress];
    self.status=label(@"Prêt. Les images seront enregistrées en PNG.",12,NO);
    self.status.frame=NSMakeRect(32,42,610,55);self.status.textColor=NSColor.secondaryLabelColor;[view addSubview:self.status];
    NSTextField *preview=label(@"Version expérimentale · Logiciel libre MIT",11,NO);
    preview.frame=NSMakeRect(32,14,610,20);preview.textColor=NSColor.tertiaryLabelColor;[view addSubview:preview];
    [self updateFolder];[self.window center];[self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)updateFolder { self.folderLabel.stringValue=[@"Destination : " stringByAppendingString:self.folder.path];self.folderLabel.toolTip=self.folder.path; }
- (void)chooseFolder:(id)sender {
    (void)sender;
    NSOpenPanel *panel=[NSOpenPanel openPanel];panel.canChooseDirectories=YES;panel.canChooseFiles=NO;
    panel.canCreateDirectories=YES;panel.directoryURL=self.folder;panel.prompt=@"Choisir";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if(result==NSModalResponseOK){self.folder=panel.URL;[self updateFolder];}
    }];
}
- (void)setWorking:(BOOL)working message:(NSString *)message {
    self.busy=working;self.scanButton.enabled=!working;self.folderButton.enabled=!working;
    self.cleanButton.enabled=!working;self.keepButton.enabled=!working;
    self.resultsButton.enabled=!working && self.results.count>0;
    self.status.stringValue=message;
    if(working)[self.progress startAnimation:nil];else [self.progress stopAnimation:nil];
}
- (NSString *)helper:(NSArray<NSString *> *)arguments status:(int *)status {
    NSURL *binary=[NSBundle.mainBundle URLForAuxiliaryExecutable:@"ds720d"];
    if(!binary){*status=1;return @"Le moteur de numérisation manque dans l’application.";}
    NSTask *task=[NSTask new];task.executableURL=binary;task.arguments=arguments;
    NSPipe *pipe=[NSPipe pipe];task.standardOutput=pipe;task.standardError=pipe;
    NSError *error=nil;
    if(![task launchAndReturnError:&error]){*status=1;return error.localizedDescription;}
    NSMutableData *log=[NSMutableData data];
    for(;;) {
        NSData *part=[pipe.fileHandleForReading availableData];if(!part.length)break;
        // Drain the process even after the bounded diagnostic log is full.
        if(log.length+part.length<262144)[log appendData:part];
    }
    [task waitUntilExit];*status=task.terminationStatus;
    return [[NSString alloc] initWithData:log encoding:NSUTF8StringEncoding]?:@"Sortie du moteur illisible.";
}
- (void)finishCapture:(NSURL *)capture clean:(BOOL)clean created:(BOOL)created keep:(BOOL)keep {
    int status=0;
    NSArray *arguments=clean?@[@"decode",capture.path]:@[@"decode",capture.path,@"--raw"];
    NSString *log=[self helper:arguments status:&status];
    NSString *base=[capture.path stringByDeletingPathExtension];
    NSURL *front=[NSURL fileURLWithPath:[base stringByAppendingString:clean?@"-front.png":@"-raw-front.png"]];
    NSURL *back=[NSURL fileURLWithPath:[base stringByAppendingString:clean?@"-back.png":@"-raw-back.png"]];
    if(status==0 && [NSFileManager.defaultManager fileExistsAtPath:front.path] && [NSFileManager.defaultManager fileExistsAtPath:back.path]) {
        if(created && !keep)[NSFileManager.defaultManager removeItemAtURL:capture error:NULL];
        dispatch_async(dispatch_get_main_queue(),^{self.results=@[front,back];[self setWorking:NO message:@"Les deux faces sont enregistrées. Clique sur « Voir les images » pour les retrouver."];});
    } else [self fail:[@"Le traitement des images a échoué. La capture est conservée.\n" stringByAppendingString:log]];
}
- (void)fail:(NSString *)detail {
    NSString *last=detail.length>800?[detail substringFromIndex:detail.length-800]:detail;
    dispatch_async(dispatch_get_main_queue(),^{[self setWorking:NO message:last];});
}
- (void)scan:(id)sender {
    (void)sender;if(self.busy)return;
    BOOL clean=self.cleanButton.state==NSControlStateValueOn,keep=self.keepButton.state==NSControlStateValueOn;
    NSURL *folder=self.folder;
    [self setWorking:YES message:@"Numérisation en cours. La feuille doit ressortir entièrement."];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool {
        int status=0;
        NSString *devices=[self helper:@[@"list"] status:&status];
        id list=[NSJSONSerialization JSONObjectWithData:[devices dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        if(status || ![list isKindOfClass:NSArray.class] || [list count]!=1){[self fail:@"Branche exactement un DS-720D, ferme les autres logiciels de scan, puis réessaie."];return;}
        NSError *error=nil;
        NSURL *capture=ds_service_capture_file(folder,&error);
        if(!capture){[self fail:[@"La numérisation n’a pas abouti.\n" stringByAppendingString:error.localizedDescription?:@"Erreur du service USB."]];return;}
        dispatch_async(dispatch_get_main_queue(),^{self.status.stringValue=@"Numérisation terminée. Préparation des images…";});
        [self finishCapture:capture clean:clean created:YES keep:keep];
    }});
}
- (void)importCapture:(id)sender {
    (void)sender;if(self.busy)return;
    NSOpenPanel *panel=[NSOpenPanel openPanel];panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;
    panel.allowedContentTypes=@[[UTType typeWithFilenameExtension:@"jsonl" conformingToType:UTTypeData]];
    panel.message=@"Choisis une capture brute DS-720D pour préparer à nouveau ses images.";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if(result!=NSModalResponseOK)return;
        NSURL *file=panel.URL;BOOL clean=self.cleanButton.state==NSControlStateValueOn;
        [self setWorking:YES message:@"Préparation des images à partir de la capture…"];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{[self finishCapture:file clean:clean created:NO keep:YES];}});
    }];
}
- (void)showResults:(id)sender { (void)sender;if(self.results.count)[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:self.results]; }
- (BOOL)windowShouldClose:(NSWindow *)sender { (void)sender;if(self.busy){NSBeep();return NO;}return YES; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender { (void)sender;return self.busy?NSTerminateCancel:NSTerminateNow; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender;return YES; }
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app=NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        ScannerApp *delegate=[ScannerApp new];app.delegate=delegate;[app run];
    }
    return 0;
}
