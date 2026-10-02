#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

__attribute__((weak_import)) extern "C" void MSHookFunction(void *symbol, void *hook, void **old);
extern "C" uintptr_t _dyld_get_image_header(uint32_t image_index);

// Core Unity/IL2CPP String Allocation Export
typedef struct Il2CppString {
    int32_t length;
    uint16_t chars[0];
} Il2CppString;
__attribute__((weak_import)) extern "C" Il2CppString* il2cpp_string_new(const char* str);

void (*orig_scrController_Awake)(void* instance);
void (*scnEditor_OpenEditor)(void* instance);
void (*scnEditor_LoadLevel)(void* instance, Il2CppString* path);

void* activeEngineToken = nullptr;

void hook_scrController_Awake(void* instance) {
    orig_scrController_Awake(instance);
    activeEngineToken = instance;
    NSLog(@"[ADOFAI_Port] Hooked active gameplay controller: %p", instance);
}

// Persistent Native Controller Layer to protect buttons from being swept out of memory
@interface PersistentModOverlay : UIViewController <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIButton *editorLaunchBtn;
@property (nonatomic, strong) UIButton *fileBrowserBtn;
+ (instancetype)sharedInstance;
- (void)attachToActiveWindow;
@end

@implementation PersistentModOverlay

+ (instancetype)sharedInstance {
    static PersistentModOverlay *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PersistentModOverlay alloc] init];
    });
    return shared;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.userInteractionEnabled = NO; // Pass touches through to Unity backgrounds
    
    // 1. Permanent Button Definition: Open PC Editor Scene
    self.editorLaunchBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.editorLaunchBtn.frame = CGRectMake(40, 40, 160, 44);
    self.editorLaunchBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.2 alpha:0.85];
    self.editorLaunchBtn.layer.cornerRadius = 10;
    [self.editorLaunchBtn setTitle:@"Open PC Editor" forState:UIControlStateNormal];
    self.editorLaunchBtn.userInteractionEnabled = YES;
    [self.editorLaunchBtn addTarget:self action:@selector(handleLaunchRequest) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.editorLaunchBtn];

    // 2. Permanent Button Definition: Import Level File (.adofai)
    self.fileBrowserBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.fileBrowserBtn.frame = CGRectMake(220, 40, 180, 44);
    self.fileBrowserBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.4 alpha:0.85];
    self.fileBrowserBtn.layer.cornerRadius = 10;
    [self.fileBrowserBtn setTitle:@"Import Custom File" forState:UIControlStateNormal];
    self.fileBrowserBtn.userInteractionEnabled = YES;
    [self.fileBrowserBtn addTarget:self action:@selector(handleFileRequest) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.fileBrowserBtn];
}

- (void)attachToActiveWindow {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (keyWindow) {
            // Anchor our persistent layout directly into the hardware display stack
            self.view.frame = keyWindow.bounds;
            [keyWindow addSubview:self.view];
            [keyWindow bringSubviewToFront:self.view];
            NSLog(@"[ADOFAI_Port] Persistent controller attached to primary layout stack.");
        }
    });
}

- (void)handleLaunchRequest {
    if (activeEngineToken && scnEditor_OpenEditor) {
        NSLog(@"[ADOFAI_Port] Shifting context state to PC Level Editor scene.");
        scnEditor_OpenEditor(activeEngineToken);
    }
}

- (void)handleFileRequest {
    UIDocumentPickerViewController *filePicker = [[UIDocumentPickerViewController alloc] 
        initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"adofai"] ?: [UTType item]] asCopy:YES];
    filePicker.delegate = self;
    [self presentViewController:filePicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *selectedFileURL = [urls firstObject];
    if (selectedFileURL && activeEngineToken && scnEditor_LoadLevel) {
        [selectedFileURL startAccessingSecurityScopedResource];
        
        // Fix string parsing mismatch: Convert C++ text pointers to C# IL2CPP structures safely
        Il2CppString* unityStringPath = il2cpp_string_new([[selectedFileURL path] UTF8String]);
        NSLog(@"[ADOFAI_Port] Parsing level data stream from path: %@", [selectedFileURL path]);
        
        scnEditor_LoadLevel(activeEngineToken, unityStringPath);
        [selectedFileURL stopAccessingSecurityScopedResource];
    }
}
@end

// Secondary hardware monitor initialization hook to handle application launching cycles cleanly
@interface AppLaunchObserver : NSObject
@end
@implementation AppLaunchObserver
+ (void)load {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification 
                                                      object:nil 
                                                       queue:[NSOperationQueue mainQueue] 
                                                  usingBlock:^(NSNotification *note) {
        // Enforce the persistent bridge layer insertion right as the system boots up
        [[PersistentModOverlay sharedInstance] attachToActiveWindow];
    }];
}
@end

__attribute__((constructor))
static void initialize_runtime_injection() {
    uintptr_t runtime_slide = (uintptr_t)_dyld_get_image_header(0);
    
    uintptr_t awake_offset = 0x15934C8;  
    uintptr_t editor_offset = 0x15E430C; 
    uintptr_t load_offset = 0x160792C;   

    MSHookFunction((void *)(runtime_slide + awake_offset), (void *)&hook_scrController_Awake, (void **)&orig_scrController_Awake);
    scnEditor_OpenEditor = (void (*)(void*))(runtime_slide + editor_offset);
    scnEditor_LoadLevel = (void (*)(void*, Il2CppString*))(runtime_slide + load_offset);
}
