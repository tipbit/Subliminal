//
//  SubliminalInstrument.m
//  subliminal-instrument
//
//  For details and documentation:
//  http://github.com/inkling/Subliminal
//
//  Copyright 2014 Inkling Systems, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "SubliminalInstrument.h"

#import "NSTask+Utilities.h"
#import "SIOptions.h"
#import "NSFileHandle+StringWriting.h"

@implementation SubliminalInstrument

+ (NSString *)traceTemplatePath {
    static NSString *__traceTemplatePath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __traceTemplatePath = [@"~/Library/Application Support/Instruments/Templates/Subliminal/Subliminal.tracetemplate" stringByExpandingTildeInPath];
        NSAssert([[NSFileManager defaultManager] fileExistsAtPath:__traceTemplatePath],
                 @"Subliminal has not yet been installed on this machine. From Subliminal's root directory, execute `rake install DOCS=no`.");
    });
    return __traceTemplatePath;
}

+ (NSString *)instrumentsPath {
    static NSString *__instrumentsPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSTask *instrumentsTaskPath = [[NSTask alloc] init];
        instrumentsTaskPath.launchPath = @"/usr/bin/xcrun";
        instrumentsTaskPath.arguments = @[ @"-f", @"instruments" ];
        __instrumentsPath = [[instrumentsTaskPath output] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    });
    return __instrumentsPath;
}

- (id)init {
    self = [super init];
    if (self) {
        _standardOutput = [NSFileHandle fileHandleWithStandardOutput];
        _standardError = [NSFileHandle fileHandleWithStandardError];
    }
    return self;
}

#pragma mark -

- (void)printUsage {
    [self.standardError printString:@"usage: subliminal-instrument %@\n\n", [SIOptions usagePattern]];
    [self.standardError printString:@"`subliminal-instrument` is a wrapper around `instruments`\nwhich runs an application with the Subliminal instrument attached\nand formats the output of that instrument.\n\n"];
    [self.standardError printString:@"Options:\n"];
    [self.standardError printString:@"%@\n", [SIOptions optionDescriptions]];
}

- (void)run {
    SIOptions *options = [[SIOptions alloc] init];

    NSError *optionsError = nil;
    if (![options parseArguments:self.arguments error:&optionsError]) {
        [self.standardError printString:@"%@\n", [optionsError localizedDescription]];
        _terminationStatus = 1;
        return;
    }

    if (options.showHelp) {
        [self printUsage];
        _terminationStatus = 1;
        return;
    }

    NSTask *instrumentsTask = [[NSTask alloc] init];
    instrumentsTask.launchPath = [[self class] instrumentsPath];

    NSString *traceTemplatePath = [[self class] traceTemplatePath];
    NSMutableArray *instrumentsArguments = [[NSMutableArray alloc] initWithArray:options.instrumentsArguments];
    [instrumentsArguments insertObject:@"-t" atIndex:0];
    [instrumentsArguments insertObject:traceTemplatePath atIndex:1];
    instrumentsTask.arguments = instrumentsArguments;

    // We want to process the output of `instruments` in realtime. However,
    // `instruments` buffers its output if it determines that it is being piped to
    // another process. We can get around this by routing the output through a
    // pseudoterminal (as suggested by https://github.com/jonathanpenn/AutomationExample/blob/master/unix_instruments ).
    [instrumentsTask launchUsingPseudoTerminal:YES outputHandler:^(NSString *line) {
        [_standardOutput printString:@"%@\n", line];
    } errorHandler:^(NSString *line) {
        [_standardError printString:@"%@\n", line];
    }];

    _terminationStatus = instrumentsTask.terminationStatus;
}

@end
