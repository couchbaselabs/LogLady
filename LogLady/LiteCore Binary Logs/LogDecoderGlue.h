//
// LogDecoderGlue.h
//
// Copyright © 2019 Couchbase. All rights reserved.
//

#pragma once
#include <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#define NOEXCEPT noexcept
#else
#define NOEXCEPT
#endif

    typedef struct {
        long secs;
        unsigned microsecs;
        int8_t level;
        uint64_t objectID;
    } BinaryLogEntry;

    bool DecodeLogData(NSData*) NOEXCEPT;
    bool DecodeLogFile(NSString*) NOEXCEPT;

    int NextLogEntry(BinaryLogEntry*) NOEXCEPT;

    NSString* _Nullable LogEntryDomain(void) NOEXCEPT;
    NSString* _Nullable LogEntryObjectDescription(void) NOEXCEPT;
    NSString* LogEntryMessage(void) NOEXCEPT;

    void EndLogDecoder(void) NOEXCEPT;


#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
