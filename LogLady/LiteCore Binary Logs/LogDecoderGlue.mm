//
// LogDecoderGlue.mm
//
// Copyright © 2019 Couchbase. All rights reserved.
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

#include "LogDecoderGlue.h"
#include "LogDecoder.hh"
#include <fstream>
#include <sstream>

using namespace std;
using namespace litecore;


static istream* input;
static LogDecoder* decoder;
static string message;


bool DecodeLogData(NSData* data) noexcept {
    try {
        input = new istringstream(string((const char*)data.bytes, data.length));
        decoder = new LogDecoder(*input);
        return true;
    } catch (const exception &x) {
        fprintf(stderr, "LogDecoder exception: %s", x.what());
        EndLogDecoder();
        return false;
    }
}


bool DecodeLogFile(NSString *path) noexcept {
    try {
        input = new ifstream(path.UTF8String);
        decoder = new LogDecoder(*input);
        return true;
    } catch (const exception &x) {
        return false;
    }
}


int NextLogEntry(BinaryLogEntry *e) noexcept {
    try {
        if (!decoder->next())
            return false;
        auto ts = decoder->timestamp();
        e->secs = ts.secs;
        e->microsecs = ts.microsecs;
        e->level = decoder->level();
        e->objectID = decoder->objectID();
        return true;
    } catch (const exception &x) {
        fprintf(stderr, "LogDecoder exception: %s", x.what());
        return -1;
    }
}


NSString* LogEntryDomain(void) noexcept {
    if (decoder->domain().empty())
        return nil;
    return @(decoder->domain().c_str());
}

NSString* LogEntryObjectDescription(void) noexcept {
    const string* desc = decoder->objectDescription();
    return desc ? @(desc->c_str()) : nil;
}

NSString* LogEntryMessage(void) noexcept {
    try {
        return @(decoder->readMessage().c_str());
    } catch (const exception &x) {
        fprintf(stderr, "LogDecoder exception: %s", x.what());
        return nil;
    }
}


void EndLogDecoder(void) noexcept {
    try {
        message.clear();
        delete decoder;
        delete input;
    } catch (const exception &x) {
        fprintf(stderr, "LogDecoder exception: %s", x.what());
    }
}
