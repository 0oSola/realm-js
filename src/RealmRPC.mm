////////////////////////////////////////////////////////////////////////////
//
// Copyright 2015 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

#import "RealmRPC.h"
#import <JavaScriptCore/JavaScriptCore.h>

#include <map>
#include <string>
#include "RealmJS.h"
#include "RJSObject.hpp"
#include "RJSResults.hpp"
#include "RJSArray.hpp"
#include "RJSRealm.hpp"
#include "RJSUtil.hpp"

#include "object_accessor.hpp"
#include "shared_realm.hpp"
#include "results.hpp"

using RPCObjectID = u_int64_t;
using RPCRequest = std::function<NSDictionary *(NSDictionary *dictionary)>;

@implementation RJSRPCServer {
    JSGlobalContextRef _context;
    std::map<std::string, RPCRequest> _requests;
    std::map<RPCObjectID, JSObjectRef> _objects;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _context = JSGlobalContextCreate(NULL);
        _requests["/create_realm"] = [=](NSDictionary *dict) {
            // We should have a method for serializing schema rather than relying on JSValue
            JSValueRef value = [[JSValue valueWithObject:dict
                                               inContext:[JSContext contextWithJSGlobalContextRef:_context]] JSValueRef];
            JSValueRef ex = NULL;
            RPCObjectID realmId = [self storeObject:RealmConstructor(_context, NULL, 1, &value, &ex)];
            if (ex) {
                return @{@"error": @(RJSStringForValue(_context, ex).c_str())};
            }
            return @{@"result": @(realmId)};
        };
        _requests["/begin_transaction"] = [=](NSDictionary *dict) {
            RPCObjectID realmId = [dict[@"realmId"] unsignedLongValue];
            RJSGetInternal<realm::SharedRealm *>(_objects[realmId])->get()->begin_transaction();
            return @{};
        };
        _requests["/cancel_transaction"] = [=](NSDictionary *dict) {
            RPCObjectID realmId = [dict[@"realmId"] unsignedLongValue];
            RJSGetInternal<realm::SharedRealm *>(_objects[realmId])->get()->cancel_transaction();
            return @{};
        };
        _requests["/commit_transaction"] = [=](NSDictionary *dict) {
            RPCObjectID realmId = [dict[@"realmId"] unsignedLongValue];
            RJSGetInternal<realm::SharedRealm *>(_objects[realmId])->get()->commit_transaction();
            return @{};
        };
        _requests["/call_realm_method"] = [=](NSDictionary *dict) {
            NSString *name = dict[@"name"];
            return [self performObjectMethod:name.UTF8String
                                classMethods:RJSRealmFuncs
                                        args:dict[@"arguments"]
                                    objectId:[dict[@"realmId"] unsignedLongValue]];
        };
        _requests["/get_property"] = [=](NSDictionary *dict) {
            JSValueRef exception = NULL;
            NSString *name = dict[@"name"];
            JSStringRef propString = RJSStringForString(name.UTF8String);
            RPCObjectID objectId = [dict[@"objectId"] unsignedLongValue];
            JSValueRef propertyValue = ObjectGetProperty(_context, _objects[objectId], propString, &exception);
            JSStringRelease(propString);

            if (exception) {
                return @{@"error": @(RJSStringForValue(_context, exception).c_str())};
            }
            return @{@"result": [self resultForJSValue:propertyValue]};
        };
        _requests["/set_property"] = [=](NSDictionary *dict) {
            JSStringRef propString = RJSStringForString([dict[@"name"] UTF8String]);
            RPCObjectID realmId = [dict[@"objectId"] unsignedLongValue];
            JSValueRef value = [self valueFromDictionary:dict[@"value"]];
            JSValueRef exception = NULL;

            ObjectSetProperty(_context, _objects[realmId], propString, value, &exception);
            JSStringRelease(propString);

            return exception ? @{@"error": @(RJSStringForValue(_context, exception).c_str())} : @{};
        };
        _requests["/dispose_object"] = [=](NSDictionary *dict) {
            RPCObjectID oid = [dict[@"id"] unsignedLongValue];
            JSValueUnprotect(_context, _objects[oid]);
            _objects.erase(oid);
            return @{};
        };
        _requests["/get_results_size"] = [=](NSDictionary *dict) {
            RPCObjectID resultsId = [dict[@"resultsId"] unsignedLongValue];

            JSValueRef exception = NULL;
            static JSStringRef lengthPropertyName = JSStringCreateWithUTF8CString("length");
            JSValueRef lengthValue = ResultsGetProperty(_context, _objects[resultsId], lengthPropertyName, &exception);
            
            return @{@"result": @(JSValueToNumber(_context, lengthValue, &exception))};
        };
        _requests["/get_results_item"] = [=](NSDictionary *dict) {
            RPCObjectID resultsId = [dict[@"resultsId"] unsignedLongValue];
            long index = [dict[@"index"] longValue];

            JSValueRef exception = NULL;
            JSStringRef indexPropertyName = JSStringCreateWithUTF8CString(std::to_string(index).c_str());
            JSValueRef objectValue = ResultsGetProperty(_context, _objects[resultsId], indexPropertyName, &exception);
            JSStringRelease(indexPropertyName);

            if (exception) {
                return @{@"error": @(RJSStringForValue(_context, exception).c_str())};
            }

            return @{@"result": [self resultForJSValue:objectValue]};
        };
        _requests["/get_list_size"] = [=](NSDictionary *dict) {
            RPCObjectID listId = [dict[@"listId"] unsignedLongValue];

            JSValueRef exception = NULL;
            static JSStringRef lengthPropertyName = JSStringCreateWithUTF8CString("length");
            JSValueRef lengthValue = ArrayGetProperty(_context, _objects[listId], lengthPropertyName, &exception);
            return @{@"result": @(JSValueToNumber(_context, lengthValue, &exception))};
        };
        _requests["/get_list_item"] = [=](NSDictionary *dict) {
            RPCObjectID listId = [dict[@"listId"] unsignedLongValue];
            long index = [dict[@"index"] longValue];

            JSValueRef exception = NULL;
            JSStringRef indexPropertyName = JSStringCreateWithUTF8CString(std::to_string(index).c_str());
            JSValueRef objectValue = ArrayGetProperty(_context, _objects[listId], indexPropertyName, &exception);
            JSStringRelease(indexPropertyName);

            if (exception) {
                return @{@"error": @(RJSStringForValue(_context, exception).c_str())};
            }
            
            return @{@"result": [self resultForJSValue:objectValue]};
        };
        _requests["/call_list_method"] = [=](NSDictionary *dict) {
            NSString *name = dict[@"name"];
            return [self performObjectMethod:name.UTF8String
                                classMethods:RJSArrayFuncs
                                        args:dict[@"arguments"]
                                    objectId:[dict[@"listId"] unsignedLongValue]];
        };
    }
    return self;
}

- (NSDictionary *)performRequest:(NSString *)name args:(NSDictionary *)args {
    // perform all realm ops on the main thread
    RPCRequest action = _requests[name.UTF8String];
    __block id response;
    dispatch_sync(dispatch_get_main_queue(), ^{
        try {
            response = action(args);
        } catch (std::exception &exception) {
            response = @{@"error": [@"exception thrown: " stringByAppendingString:@(exception.what())]};
        }
    });
    return response;
}

- (NSDictionary *)performObjectMethod:(const char *)name
                         classMethods:(const JSStaticFunction [])methods
                                 args:(NSArray *)args
                             objectId:(RPCObjectID)oid {
    NSUInteger count = args.count;
    JSValueRef argValues[count];
    for (NSUInteger i = 0; i < count; i++) {
        argValues[i] = [self valueFromDictionary:args[i]];
    }

    size_t index = 0;
    while (methods[index].name) {
        if (!strcmp(methods[index].name, name)) {
            JSValueRef ex = NULL;
            JSValueRef ret = methods[index].callAsFunction(_context, NULL, _objects[oid], count, argValues, &ex);
            if (ex) {
                return @{@"error": @(RJSStringForValue(_context, ex).c_str())};
            }
            return @{@"result": [self resultForJSValue:ret]};
        }
        index++;
    }

    return @{@"error": @"invalid method"};
}

- (RPCObjectID)storeObject:(JSObjectRef)object {
    static RPCObjectID s_next_id = 1;
    RPCObjectID next_id = s_next_id++;
    JSValueProtect(_context, object);
    _objects[next_id] = object;
    return next_id;
}

- (NSDictionary *)resultForJSValue:(JSValueRef)value {
    switch (JSValueGetType(_context, value)) {
        case kJSTypeUndefined:
            return @{};
        case kJSTypeNull:
            return @{@"value": [NSNull null]};
        case kJSTypeBoolean:
            return @{@"value": @(JSValueToBoolean(_context, value))};
        case kJSTypeNumber:
            return @{@"value": @(JSValueToNumber(_context, value, NULL))};
        case kJSTypeString:
            return @{@"value": @(RJSStringForValue(_context, value).c_str())};
        case kJSTypeObject:
            break;
    }

    JSObjectRef jsObject = JSValueToObject(_context, value, NULL);
    RPCObjectID oid = [self storeObject:jsObject];

    if (JSValueIsObjectOfClass(_context, value, RJSObjectClass())) {
        realm::Object *object = RJSGetInternal<realm::Object *>(jsObject);
        return @{
             @"type": @(RJSTypeGet(realm::PropertyTypeObject).c_str()),
             @"id": @(oid),
             @"schema": [self objectSchemaToJSONObject:object->object_schema]
        };
    }
    else if (JSValueIsObjectOfClass(_context, value, RJSArrayClass())) {
        realm::ObjectArray *array = RJSGetInternal<realm::ObjectArray *>(jsObject);
        return @{
             @"type": @(RJSTypeGet(realm::PropertyTypeArray).c_str()),
             @"id": @(oid),
             @"size": @(array->link_view->size()),
             @"schema": [self objectSchemaToJSONObject:array->object_schema]
         };
    }
    else if (JSValueIsObjectOfClass(_context, value, RJSResultsClass())) {
        realm::Results *results = RJSGetInternal<realm::Results *>(jsObject);
        return @{
             @"type": @"ObjectTypesRESULTS",
             @"resultsId": @(oid),
             @"size": @(results->size()),
             @"schema": [self objectSchemaToJSONObject:results->object_schema]
        };
    }
    else if (RJSIsValueArray(_context, value)) {
        size_t length = RJSValidatedArrayLength(_context, jsObject);
        NSMutableArray *array = [NSMutableArray new];
        for (unsigned int i = 0; i < length; i++) {
            [array addObject:[self resultForJSValue:JSObjectGetPropertyAtIndex(_context, jsObject, i, NULL)]];
        }
        return @{@"value": array};
    }
    else {
        assert(0);
    }
}

- (NSDictionary *)objectSchemaToJSONObject:(realm::ObjectSchema &)objectSchema {
    NSMutableArray *properties = [[NSMutableArray alloc] init];

    for (realm::Property prop : objectSchema.properties) {
        NSDictionary *dict = @{
            @"name": @(prop.name.c_str()),
            @"type": @(RJSTypeGet(prop.type).c_str()),
        };

        [properties addObject:dict];
    }

    return @{
        @"name": @(objectSchema.name.c_str()),
        @"properties": properties,
    };
}

- (JSValueRef)valueFromDictionary:(NSDictionary *)dict {
    RPCObjectID oid = [dict[@"id"] longValue];
    if (oid) {
        return _objects[oid];
    }

    id value = dict[@"value"];
    if (!value) {
        return JSValueMakeUndefined(_context);
    }
    else if ([value isKindOfClass:[NSNull class]]) {
        return JSValueMakeNull(_context);
    }
    else if ([value isKindOfClass:[@YES class]]) {
        return JSValueMakeBoolean(_context, [value boolValue]);
    }
    else if ([value isKindOfClass:[NSNumber class]]) {
        return JSValueMakeNumber(_context, [value doubleValue]);
    }
    else if ([value isKindOfClass:[NSString class]]) {
        return RJSValueForString(_context, std::string([value UTF8String]));
    }
    else if ([value isKindOfClass:[NSArray class]]) {
        NSUInteger count = [value count];
        JSValueRef jsValues[count];

        for (NSUInteger i = 0; i < count; i++) {
            jsValues[i] = [self valueFromDictionary:value[i]];
        }

        return JSObjectMakeArray(_context, count, jsValues, NULL);
    }
    else if ([value isKindOfClass:[NSDictionary class]]) {
        JSObjectRef jsObject = JSObjectMake(_context, NULL, NULL);

        for (NSString *key in value) {
            JSValueRef jsValue = [self valueFromDictionary:value[key]];
            JSStringRef jsKey = JSStringCreateWithCFString((__bridge CFStringRef)key);

            JSObjectSetProperty(_context, jsObject, jsKey, jsValue, 0, NULL);
            JSStringRelease(jsKey);
        }

        return jsObject;
    }

    return JSValueMakeUndefined(_context);
}

@end
