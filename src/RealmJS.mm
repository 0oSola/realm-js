/* Copyright 2015 Realm Inc - All Rights Reserved
 * Proprietary and Confidential
 */

#import "RealmJS.h"
#import "RJSRealm.hpp"
#import "RJSObject.hpp"
#import "RJSUtil.hpp"
#import "RJSSchema.hpp"

#include "shared_realm.hpp"

JSValueRef RJSTypeGet(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef* exception) {
    return RJSValueForString(ctx, RJSTypeGet(RJSStringForJSString(propertyName)));
}

JSClassRef RJSRealmTypeClass() {
    JSClassDefinition realmTypesDefinition = kJSClassDefinitionEmpty;
    realmTypesDefinition.className = "PropTypes";
    JSStaticValue types[] = {
        { "BOOL",   RJSTypeGet, NULL, kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete },
        { "INT",    RJSTypeGet, NULL, kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete },
        { "FLOAT",  RJSTypeGet, NULL, kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete },
        { "DOUBLE", RJSTypeGet, NULL, kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete },
        { "STRING", RJSTypeGet, NULL, kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete },
        { "DATE",   RJSTypeGet, NULL, kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete },
        { "DATA",   RJSTypeGet, NULL, kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete },
        { "OBJECT", RJSTypeGet, NULL, kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete },
        { "LIST",  RJSTypeGet, NULL, kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete },
        { NULL, NULL, NULL, 0 }
    };
    realmTypesDefinition.staticValues = types;
    return JSClassCreate(&realmTypesDefinition);
}

NSString *RealmFileDirectory() {
#if TARGET_OS_IPHONE
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
#else
    NSString *path = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES)[0];
    return [path stringByAppendingPathComponent:[[[NSBundle mainBundle] executablePath] lastPathComponent]];
#endif
}

static JSValueRef ClearTestState(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef *exception) {
    RJSClearTestState();
    return NULL;
}

JSObjectRef RJSConstructorCreate(JSContextRef ctx) {
    JSObjectRef realmObject = JSObjectMake(ctx, RJSRealmConstructorClass(), NULL);
    JSObjectRef typesObject = JSObjectMake(ctx, RJSRealmTypeClass(), NULL);

    JSValueRef exception = NULL;
    JSStringRef typeString = JSStringCreateWithUTF8CString("Types");
    JSPropertyAttributes attributes = kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontEnum | kJSPropertyAttributeDontDelete;
    JSObjectSetProperty(ctx, realmObject, typeString, typesObject, attributes, &exception);
    JSStringRelease(typeString);
    assert(!exception);

    JSStringRef clearTestStateString = JSStringCreateWithUTF8CString("clearTestState");
    JSObjectRef clearTestStateFunction = JSObjectMakeFunctionWithCallback(ctx, clearTestStateString, ClearTestState);
    JSObjectSetProperty(ctx, realmObject, clearTestStateString, clearTestStateFunction, attributes, &exception);
    JSStringRelease(clearTestStateString);
    assert(!exception);

    return realmObject;
}

void RJSInitializeInContext(JSContextRef ctx) {
    JSObjectRef globalObject = JSContextGetGlobalObject(ctx);
    JSObjectRef realmObject = RJSConstructorCreate(ctx);

    JSValueRef exception = NULL;
    JSStringRef nameString = JSStringCreateWithUTF8CString("Realm");
    JSPropertyAttributes attributes = kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontEnum | kJSPropertyAttributeDontDelete;

    JSObjectSetProperty(ctx, globalObject, nameString, realmObject, attributes, &exception);
    JSStringRelease(nameString);
    assert(!exception);
}

void RJSClearTestState() {
    realm::Realm::s_global_cache.close_all();
    realm::Realm::s_global_cache.clear();

    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *fileDir = RealmFileDirectory();
    for (NSString *path in [manager enumeratorAtPath:fileDir]) {
        if (![manager removeItemAtPath:[fileDir stringByAppendingPathComponent:path] error:nil]) {
            @throw [NSException exceptionWithName:@"removeItemAtPath error" reason:@"Failed to delete file" userInfo:nil];
        }
    }
}
