#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

__attribute__((weak_import)) extern "C" void MSHookFunction(void *symbol, void *hook, void **old);
extern "C" uintptr_t _dyld_get_image_header(uint32_t image_index);

// Core Unity string representation structure
typedef struct Il2CppString {
    int32_t length;
    uint16_t chars;
} Il2CppString;
__attribute__((weak_import)) extern "C" Il2CppString* il2cpp_string_new(const char* str);

// Function pointer signatures targeting scene management 
void (*UnityEngine_SceneManagement_SceneManager_LoadScene)(Il2CppString* sceneName);
void (*scnEditor_LoadLevel)(void* instance, Il2CppString* path);

// Global placeholder to store the level editor controller when it wakes up
void* activeEditorInstance = nullptr;
void (*orig_scnEditor_Awake)(void* instance);

void hook_scnEditor_Awake(void* instance) {
    orig_scnEditor_Awake(instance);
    activeEditorInstance = instance;
    NSLog(@"[ADOFAI_Port] Level editor instance securely captured: %p", instance);
}

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
    self.view.userInteractionEnabled = NO;
    
    // UI Layout Definition for PC Editor Activation
    self.editorLaunchBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.editorLaunchBtn.frame = CGRectMake(40, 40, 170, 44);
    self.editorLaunchBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.2 alpha:0.9];
    self.editorLaunchBtn.layer.cornerRadius = 10;
    [self.editorLaunchBtn setTitle:@"Launch PC Editor" forState:UIControlStateNormal];
    self.editorLaunchBtn.userInteractionEnabled = YES;
    [self.editorLaunchBtn addTarget:self action:@selector(handleLaunchRequest) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.editorLaunchBtn];

    // UI Layout Definition for File Importing
    self.fileBrowserBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.fileBrowserBtn.frame = CGRectMake(230, 40, 180, 44);
    self.fileBrowserBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.4 alpha:0.9];
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
            self.view.frame = keyWindow.bounds;
            [keyWindow addSubview:self.view];
            [keyWindow bringSubviewToFront:self.view];
        }
    });
}

- (void)handleLaunchRequest {
    if (UnityEngine_SceneManagement_SceneManager_LoadScene) {
        NSLog(@"[ADOFAI_Port] Forcing Unity to load the level editor scene asset container.");
        // Generate an internal string pointing to the editor setup scene
        Il2CppString* sceneToken = il2cpp_string_new("scnEditor");
        UnityEngine_SceneManagement_SceneManager_LoadScene(sceneToken);
    }
}

- (void)handleFileRequest {
    if (!activeEditorInstance) {
        NSLog(@"[ADOFAI_Port] Warning: Cannot import file because you aren't inside the Editor scene yet.");
        return;
    }
    UIDocumentPickerViewController *filePicker = [[UIDocumentPickerViewController alloc] 
        initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"adofai"] ?: [UTType item]] asCopy:YES];
    filePicker.delegate = self;
    [self presentViewController:filePicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *selectedFileURL = [urls firstObject];
    if (selectedFileURL && activeEditorInstance && scnEditor_LoadLevel) {
        [selectedFileURL startAccessingSecurityScopedResource];
        Il2CppString* unityStringPath = il2cpp_string_new([[selectedFileURL path] UTF8String]);
        scnEditor_LoadLevel(activeEditorInstance, unityStringPath);
        [selectedFileURL stopAccessingSecurityScopedResource];
    }
}
@end

@interface AppLaunchObserver : NSObject
@end
@implementation AppLaunchObserver
+ (void)load {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification 
                                                      object:nil 
                                                       queue:[NSOperationQueue mainQueue] 
                                                  usingBlock:^(NSNotification *note) {
        [[PersistentModOverlay sharedInstance] attachToActiveWindow];
    }];
}
@end

__attribute__((constructor))
static void initialize_runtime_injection() {
    uintptr_t runtime_slide = (uintptr_t)_dyld_get_image_header(0);
    
    // !!! STEP REQUIRED: CONFIRM THESE TWO OFFSETS IN YOUR DUMP.CS !!!
    uintptr_t loadScene_offset = 0x2A3B4C; // Find 'UnityEngine.SceneManagement.SceneManager$$LoadScene'
    uintptr_t editorAwake_offset = 0x15E430C; // scnEditor.Awake
    uintptr_t loadLevel_offset = 0x160792C; // scnEditor.OpenLevel

    UnityEngine_SceneManagement_SceneManager_LoadScene = (void (*)(Il2CppString*))(runtime_slide + loadScene_offset);
    scnEditor_LoadLevel = (void (*)(void*, Il2CppString*))(runtime_slide + loadLevel_offset);

    MSHookFunction((void *)(runtime_slide + editorAwake_offset), (void *)&hook_scnEditor_Awake, (void **)&orig_scnEditor_Awake);
}
