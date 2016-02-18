/* Copyright 2016 Realm Inc - All Rights Reserved
 * Proprietary and Confidential
 */

#import "RealmAnalytics.h"

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_MAC
#import <CommonCrypto/CommonDigest.h>
#import <sys/socket.h>
#import <sys/sysctl.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <array>

// This symbol is defined by the Apple Generic versioning system when building this project.
// It confusingly looks like this: @(#)PROGRAM:RealmReact  PROJECT:RealmJS-0.0.1
extern "C" const char RealmReactVersionString[];

// Wrapper for sysctl() that handles the memory management stuff
static auto RLMSysCtl(int *mib, u_int mibSize, size_t *bufferSize) {
    std::unique_ptr<void, decltype(&free)> buffer(nullptr, &free);

    int ret = sysctl(mib, mibSize, nullptr, bufferSize, nullptr, 0);
    if (ret != 0) {
        return buffer;
    }

    buffer.reset(malloc(*bufferSize));
    if (!buffer) {
        return buffer;
    }

    ret = sysctl(mib, mibSize, buffer.get(), bufferSize, nullptr, 0);
    if (ret != 0) {
        buffer.reset();
    }

    return buffer;
}

// Get the version of OS X we're running on (even in the simulator this gives
// the OS X version and not the simulated iOS version)
static NSString *RLMOSVersion() {
    std::array<int, 2> mib = {CTL_KERN, KERN_OSRELEASE};
    size_t bufferSize;
    auto buffer = RLMSysCtl(&mib[0], mib.size(), &bufferSize);
    if (!buffer) {
        return nil;
    }

    return [[NSString alloc] initWithBytesNoCopy:buffer.release()
                                          length:bufferSize - 1
                                        encoding:NSUTF8StringEncoding
                                    freeWhenDone:YES];
}

// Hash the data in the given buffer and convert it to a hex-format string
static NSString *RLMHashData(const void *bytes, size_t length) {
    unsigned char buffer[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes, static_cast<CC_LONG>(length), buffer);

    char formatted[CC_SHA256_DIGEST_LENGTH * 2 + 1];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i) {
        sprintf(formatted + i * 2, "%02x", buffer[i]);
    }

    return [[NSString alloc] initWithBytes:formatted
                                    length:CC_SHA256_DIGEST_LENGTH * 2
                                  encoding:NSUTF8StringEncoding];
}

// Returns the hash of the MAC address of the first network adaptor since the
// vendorIdentifier isn't constant between iOS simulators.
static NSString *RLMMACAddress() {
    int en0 = static_cast<int>(if_nametoindex("en0"));
    if (!en0) {
        return nil;
    }

    std::array<int, 6> mib = {CTL_NET, PF_ROUTE, 0, AF_LINK, NET_RT_IFLIST, en0};
    size_t bufferSize;
    auto buffer = RLMSysCtl(&mib[0], mib.size(), &bufferSize);
    if (!buffer) {
        return nil;
    }

    // sockaddr_dl struct is immediately after the if_msghdr struct in the buffer
    auto sockaddr = reinterpret_cast<sockaddr_dl *>(static_cast<if_msghdr *>(buffer.get()) + 1);
    auto mac = reinterpret_cast<const unsigned char *>(sockaddr->sdl_data + sockaddr->sdl_nlen);
    
    return RLMHashData(mac, 6);
}

static bool RLMIsDebuggerAttached() {
    int name[] = {
        CTL_KERN,
        KERN_PROC,
        KERN_PROC_PID,
        getpid()
    };

    struct kinfo_proc info;
    size_t info_size = sizeof(info);
    if (sysctl(name, sizeof(name) / sizeof(name[0]), &info, &info_size, NULL, 0) == -1) {
        NSLog(@"sysctl() failed: %s", strerror(errno));
        return false;
    }

    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

static NSDictionary *RLMAnalyticsPayload() {
    static NSString * const kUnknownString = @"unknown";
    NSBundle *appBundle = NSBundle.mainBundle;
    NSString *hashedBundleID = appBundle.bundleIdentifier;
    NSString *hashedMACAddress = RLMMACAddress();

    // Main bundle isn't always the one of interest (e.g. when running tests
    // it's xctest rather than the app's bundle), so look for one with a bundle ID
    if (!hashedBundleID) {
        for (NSBundle *bundle in NSBundle.allBundles) {
            if ((hashedBundleID = bundle.bundleIdentifier)) {
                appBundle = bundle;
                break;
            }
        }
    }

    // If we found a bundle ID anywhere, hash it as it could contain sensitive
    // information (e.g. the name of an unnanounced product)
    if (hashedBundleID) {
        NSData *data = [hashedBundleID dataUsingEncoding:NSUTF8StringEncoding];
        hashedBundleID = RLMHashData(data.bytes, data.length);
    }

    return @{
        @"event": @"Run",
        @"properties": @{
            // MixPanel properties
            @"token": @"ce0fac19508f6c8f20066d345d360fd0",

            // Anonymous identifiers to deduplicate events
            @"distinct_id": hashedMACAddress ?: kUnknownString,
            @"Anonymized MAC Address": hashedMACAddress ?: kUnknownString,
            @"Anonymized Bundle ID": hashedBundleID ?: kUnknownString,

            // Which version of Realm is being used
            @"Binding": @"js",
            @"Language": @"js",
            @"Framework": @"react-native",
            @"Realm Version": [[@(RealmReactVersionString) componentsSeparatedByString:@"-"] lastObject] ?: kUnknownString,
#if TARGET_OS_MAC
            @"Target OS Type": @"osx",
#else
            @"Target OS Type": @"ios",
#endif
            // Current OS version the app is targetting
            @"Target OS Version": [[NSProcessInfo processInfo] operatingSystemVersionString],
            // Minimum OS version the app is targetting
            @"Target OS Minimum Version": appBundle.infoDictionary[@"MinimumOSVersion"] ?: kUnknownString,

            // Host OS version being built on
            @"Host OS Type": @"osx",
            @"Host OS Version": RLMOSVersion() ?: kUnknownString,
        }
    };
}

void RLMSendAnalytics() {
    if (getenv("REALM_DISABLE_ANALYTICS") || !RLMIsDebuggerAttached()) {
        return;
    }

    NSData *payload = [NSJSONSerialization dataWithJSONObject:RLMAnalyticsPayload() options:0 error:nil];
    NSString *url = [NSString stringWithFormat:@"https://api.mixpanel.com/track/?data=%@&ip=1", [payload base64EncodedStringWithOptions:0]];

    // No error handling or anything because logging errors annoyed people for no
    // real benefit, and it's not clear what else we could do
    [[NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:url]] resume];
}

#else

void RLMSendAnalytics() {}

#endif
