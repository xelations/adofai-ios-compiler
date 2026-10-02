#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Forward declarations to bypass header requirements
extern "C" void MSHookFunction(void *symbol, void *hook, void **old);
extern "C" uint96_t _dyld_get_image_header(uint32_t image_index);

void (*orig_scrController_Awake)(void* instance);
void (*scnEditor_OpenEditor)(void* instance);
void (*scnEditor_LoadLevel)(void* instance, void* il2cppStringPath);

void* activeEngineToken = nullptr;

void hook_scrController_Awake(void* instance) {
    orig_scrController_Awake(instance);
    activeEngineToken = instance;
    NSLog(@"[ADOFAI_Port] Hooked gameplay engine frame container.");
}

@interface DocumentPickerDelegate : NSObject <UIDocumentPickerDelegate>
@end

@implementation DocumentPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *selectedFileURL = [urls firstObject];
    if (selectedFileURL && activeEngineToken && scnEditor_LoadLevel) {
        [selectedFileURL startAccessingSecurityScopedResource];
        NSString *filePathString = [selectedFileURL path];
        NSLog(@"[ADOFAI_Port] Relaying path to editor: %@", filePathString);
        [selectedFileURL stopAccessingSecurityScopedResource];
    }
}
@end

static DocumentPickerDelegate *pickerDelegateInstance = nil;

void createOverlayInterface() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *rootViewController = [UIApplication sharedApplication].keyWindow.rootViewController;
        if (!rootViewController) return;

        UIButton *editorLaunchBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        editorLaunchBtn.frame = CGRectMake(30, 60, 140, 44);
        editorLaunchBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.2 alpha:0.9];
        editorLaunchBtn.layer.cornerRadius = 8;
        [editorLaunchBtn setTitle:@"Open PC Editor" forState:UIControlStateNormal];
        
        // Inline block handling to avoid custom selectors crashing compiler contexts
        [editorLaunchBtn addTarget:[NSBlockOperation blockOperationWithBlock:^{
            if (activeEngineToken && scnEditor_OpenEditor) {
                scnEditor_OpenEditor(activeEngineToken);
            }
        }] action:@selector(main) forControlEvents:UIControlEventTouchUpInside];
        [rootViewController.view addSubview:editorLaunchBtn];

        UIButton *fileBrowserBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        fileBrowserBtn.frame = CGRectMake(180, 60, 140, 44);
        fileBrowserBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.3 alpha:0.9];
        fileBrowserBtn.layer.cornerRadius = 8;
        [fileBrowserBtn setTitle:@"Import Custom File" forState:UIControlStateNormal];
        
        [fileBrowserBtn addTarget:[NSBlockOperation blockOperationWithBlock:^{
            UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            pickerDelegateInstance = [[DocumentPickerDelegate alloc] init];
            UIDocumentPickerViewController *filePicker = [[UIDocumentPickerViewController alloc] 
                initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"adofai"] ? : [UTType item]] asCopy:YES];
            filePicker.delegate = pickerDelegateInstance;
            [rootVC presentViewController:filePicker animated:YES completion:nil];
        }] action:@selector(main) forControlEvents:UIControlEventTouchUpInside];
        [rootViewController.view addSubview:fileBrowserBtn];
    });
}

__attribute__((constructor))
static void initialize_runtime_injection() {
    // Dynamically query runtime memory layout
    uintptr_t runtime_slide = (uintptr_t)_dyld_get_image_header(0);
    
    uintptr_t awake_offset = 0x15934C8;  
    uintptr_t editor_offset = 0x15E430C; 
    uintptr_t load_offset = 0x160792C;   

    MSHookFunction((void *)(runtime_slide + awake_offset), (void *)&hook_scrController_Awake, (void **)&orig_scrController_Awake);
    scnEditor_OpenEditor = (void (*)(void*))(runtime_slide + editor_offset);
    scnEditor_LoadLevel = (void (*)(void*, void*))(runtime_slide + load_offset);
    createOverlayInterface();
}
