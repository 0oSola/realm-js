/* Copyright 2015 Realm Inc - All Rights Reserved
 * Proprietary and Confidential
 */

#import "RJSUtil.hpp"

namespace realm {
    class Realm;
    typedef std::shared_ptr<Realm> SharedRealm;
}

JSClassRef RJSResultsClass();
JSObjectRef RJSResultsCreate(JSContextRef ctx, realm::SharedRealm realm, std::string className);
JSObjectRef RJSResultsCreate(JSContextRef ctx, realm::SharedRealm realm, std::string className, std::string query);
