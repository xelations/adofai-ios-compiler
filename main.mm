#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <sys/mman.h>
#include <mach/mach.h>

extern "C" uintptr_t _dyld_get_image_header(uint32_t image_index);

typedef struct Il2CppString {
    int32_t length;
    uint16_t chars;
} Il2CppString;
__attribute__((weak_import)) extern "C" Il2CppString* il2cpp_string_new(const char* str);

void (*UnityEngine_SceneManagement_SceneManager_LoadScene)(Il2CppString* sceneName);
void (*scnEditor_LoadLevel)(void* instance, Il2CppString* path);

// Global static pointer placeholder
void* globalEditorInstance = nil;

// Safe memory page patching utility to overwrite code natively
void patch_memory(uintptr_t address, void* custom_func) {
    vm_address_t page_start = address & ~PAGE_MASK;
    vm_size_t page_size = PAGE_SIZE;
    
    // Unlock the memory segment to allow writing instructions
    kern_return_t kr = vm_protect(mach_task_self(), page_start, page_size, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) return;
    
    // Generate an absolute branch instruction jump structure (ARM64 Trampoline)
    uint32_t jump_instructions[] = {
        0x58000050, // LDR X16, #8
        0xd61f0200, // BR X16
        (uint32_t)(uintptr_t)custom_func,
        (uint32_t)((uintptr_t)custom_func >> 32)
    };
    
    memcpy((void*)address, jump_instructions, sizeof(jump_instructions));
    
    // Re-lock the memory address for device execution safety
    vm_protect(mach_task_self(), page_start, page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    sys_icache_invalidate((void*)address, sizeof(jump_instructions));
}

// Our custom intercept handler that replaces the native scnEditor.Awake
void custom_scnEditor_Awake(void* instance) {
    globalEditorInstance = instance;
    NSLog(@"[ADOFAI_Port] Hook triggered. Captured scnEditor instance: %p", instance);
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
    
    self.editorLaunchBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.editorLaunchBtn.frame = CGRectMake(40, 40, 170, 44);
    self.editorLaunchBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.2 alpha:0.9];
    self.editorLaunchBtn.layer.cornerRadius = 10;
    [self.editorLaunchBtn setTitle:@"Launch PC Editor" forState:UIControlStateNormal];
    self.editorLaunchBtn.userInteractionEnabled = YES;
    [self.editorLaunchBtn addTarget:self action:@selector(handleLaunchRequest) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.editorLaunchBtn];

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
        NSLog(@"[ADOFAI_Port] Calling Native Unity Scene Switcher.");
        Il2CppString* sceneToken = il2cpp_string_new("scnEditor");
        UnityEngine_SceneManagement_SceneManager_LoadScene(sceneToken);
    }
}

- (void)handleFileRequest {
    if (!globalEditorInstance) {
        NSLog(@"[ADOFAI_Port] Cannot load: Enter the Editor scene first so the token updates.");
        return;
    }
    UIDocumentPickerViewController *filePicker = [[UIDocumentPickerViewController alloc] 
        initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"adofai"] ?: [UTType item]] asCopy:YES];
    filePicker.delegate = self;
    [self presentViewController:filePicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *selectedFileURL = [urls firstObject];
    if (selectedFileURL && globalEditorInstance && scnEditor_LoadLevel) {
        [selectedFileURL startAccessingSecurityScopedResource];
        Il2CppString* unityStringPath = il2cpp_string_new([[selectedFileURL path] UTF8String]);
        scnEditor_LoadLevel(globalEditorInstance, unityStringPath);
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
    
    uintptr_t loadScene_offset = 0x289D8B4;   
    uintptr_t editorAwake_offset = 0x15E430C; 
    uintptr_t loadLevel_offset = 0x160792C;   

    UnityEngine_SceneManagement_SceneManager_LoadScene = (void (*)(Il2CppString*))(runtime_slide + loadScene_offset);
    scnEditor_LoadLevel = (void (*)(void*, Il2CppString*))(runtime_slide + loadLevel_offset);

    // Apply the pure memory patch, completely bypassing MSHookFunction dependency limitations
    patch_memory(runtime_slide + editorAwake_offset, (void*)&custom_scnEditor_Awake);
}
