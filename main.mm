#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>

// Structural templates for hooking Unity's IL2CPP runtime mapping engine
typedef struct Il2CppClass Il2CppClass;
typedef struct MethodInfo MethodInfo;
typedef struct Il2CppDomain Il2CppDomain;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppImage Il2CppImage;

Il2CppDomain* (*il2cpp_domain_get)();
Il2CppAssembly** (*il2cpp_domain_get_assemblies)(const Il2CppDomain* domain, size_t* size);
Il2CppImage* (*il2cpp_assembly_get_image)(const Il2CppAssembly* assembly);
Il2CppClass* (*il2cpp_class_from_name)(const Il2CppImage* image, const char* namespaze, const char* name);
const MethodInfo* (*il2cpp_class_get_method_from_name)(Il2CppClass* klass, const char* name, int argsCount);
void* (*il2cpp_runtime_invoke)(const MethodInfo* method, void* obj, void** params, void** exc);

// Global constructor that fires directly as the app image slides into memory
__attribute__((constructor))
static void force_developer_mode() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        // Bind core runtime APIs
        il2cpp_domain_get = (Il2CppDomain* (*)())dlsym(RTLD_DEFAULT, "il2cpp_domain_get");
        il2cpp_domain_get_assemblies = (Il2CppAssembly** (*)(const Il2CppDomain*, size_t*))dlsym(RTLD_DEFAULT, "il2cpp_domain_get_assemblies");
        il2cpp_assembly_get_image = (Il2CppImage* (*)(const Il2CppAssembly*))dlsym(RTLD_DEFAULT, "il2cpp_assembly_get_image");
        il2cpp_class_from_name = (Il2CppClass* (*)(const Il2CppImage*, const char*, const char*))dlsym(RTLD_DEFAULT, "il2cpp_class_from_name");
        il2cpp_class_get_method_from_name = (const MethodInfo* (*)(Il2CppClass*, const char*, int))dlsym(RTLD_DEFAULT, "il2cpp_class_get_method_from_name");
        il2cpp_runtime_invoke = (void* (*)(const MethodInfo*, void*, void**, void**))dlsym(RTLD_DEFAULT, "il2cpp_runtime_invoke");

        if (!il2cpp_domain_get) {
            NSLog(@"[ADOFAI_Debug] Internal runtime interfaces unresolved.");
            return;
        }

        Il2CppDomain* domain = il2cpp_domain_get();
        size_t size = 0;
        Il2CppAssembly** assemblies = il2cpp_domain_get_assemblies(domain, &size);
        
        // Loop through assemblies to find the core game global configuration class
        for (size_t i = 0; i < size; ++i) {
            const Il2CppImage* image = il2cpp_assembly_get_image(assemblies[i]);
            
            // Checking common global data/debug managers in ADOFAI compilation matrices
            Il2CppClass* gdmClass = il2cpp_class_from_name(image, "", "GDM");
            if (!gdmClass) gdmClass = il2cpp_class_from_name(image, "", "GLog");
            
            if (gdmClass) {
                // Look for common debug mode setter properties (e.g., set_isDebug)
                const MethodInfo* setDebugMethod = il2cpp_class_get_method_from_name(gdmClass, "set_isDebug", 1);
                if (!setDebugMethod) setDebugMethod = il2cpp_class_get_method_from_name(gdmClass, "set_debugMode", 1);
                
                if (setDebugMethod) {
                    bool enabledState = true;
                    void* args[] = { &enabledState };
                    void* exception = nullptr;
                    
                    // Directly invoke the method to toggle internal debugger states
                    il2cpp_runtime_invoke(setDebugMethod, nullptr, args, &exception);
                    NSLog(@"[ADOFAI_Debug] Successfully flipped internal developer flag state to TRUE.");
                    break;
                }
            }
        }
    });
}
