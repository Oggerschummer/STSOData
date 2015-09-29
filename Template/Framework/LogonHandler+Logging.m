//
//  LogonHandler+Logging.m
//  TravelAgency_RKT
//
//  Created by Stadelman, Stan on 8/12/14.
//  Copyright (c) 2014 SAP. All rights reserved.
//

#import "LogonHandler+Logging.h"
#import "HttpConversationManager.h"
#import "SupportabilityUploader.h"
#import "SAPSupportabilityFacade.h"


@implementation LogonHandler (Logging)


- (void) setupLogging
{
    /*
     Initialize the logging framework.  Set log level for different identifiers, and the log destination (default FILESYSTEM)
     Add SAPClientLogger.h, and SAPSupportabilityFacade.h to your *.pch file, so that the logger macros are available throughout your app.
     */
    self.logManager = [[SAPSupportabilityFacade sharedManager] getClientLogManager];
//    [self.logManager setLogLevel:InfoClientLogLevel forIdentifier:LOG_ODATAREQUEST];
//    [self.logManager setLogLevel:InfoClientLogLevel forIdentifier:LOG_ONLINESTORE];
//    [self.logManager setLogLevel:InfoClientLogLevel forIdentifier:LOG_OFFLINESTORE];
//    [self.logManager setLogLevel:InfoClientLogLevel forIdentifier:LOG_LOGUPLOAD];
    [self.logManager setLogLevel:ErrorClientLogLevel];
    [self.logManager setLogDestination:(CONSOLE | FILESYSTEM)];
}


- (void) uploadLogs {
        
    /*
     Log upload endpoint is constant for all applications on a host:port
     
     You MUST have logging enabled for a particular application connection through the Admin UI, 
     or uploaded logs will be rejected.
     
     You ALSO MUST have SAP Solution Manager propery integrated with SAP SMP Server, or uploaded
     logs will be rejected.
     */
//    NSString *logUploadURL = [NSString stringWithFormat:@"%@://%@:%i/clientlogs", self.data.isHttps ? @"https" : @"http", self.data.serverHost, self.data.serverPort];
//    
//    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:logUploadURL]];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self.baseURL clientLogsURL]];
    
    [request setValue:self.data.applicationConnectionId forHTTPHeaderField:@"X-SMP-APPCID"];
    
    SupportabilityUploader *uploader = [[SupportabilityUploader alloc] initWithHttpConversationManager:self.httpConvManager urlRequest:request];
    
    
        //Oggerschummer 20150929 BEGIN
        //Deprecation NSArray *logData0 = [self.logManager getLogEntries:AllClientLogLevel];
   
    NSArray *logData0;
    NSOutputStream * oStream;
    
    oStream = [[NSOutputStream alloc] initToMemory];
    NSError *oError = Nil;
    if ([self.logManager getLogEntries:AllClientLogLevel outputStream:&oStream error:&oError]){
        [oStream open];
        
            // fill the output stream somehow
        
        NSData *contents = [oStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
        [oStream close];
        logData0 = [NSKeyedUnarchiver unarchiveObjectWithData:contents];
    }
    else {
        NSLog(@"Error in getting log data: %@", [oError description]);
    }
    
    if (logData0){
        NSLog(@"Log Data \n%@", [logData0 description]);
    }
        //Oggerschummer 20150929 END
    

        //Oggerschummer 20150929 begin
        //Deprecation fix
    
        //NSData *rawLogData = [self.logManager getRawLogData];
    NSData *rawLogData =  Nil;
    
    oStream = [[NSOutputStream alloc] initToMemory];
    oError = Nil;
    if ([self.logManager getRawLogData:&oStream error:&oError]){
        [oStream open];
        
            // fill the output stream somehow
        
        rawLogData = [oStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
        [oStream close];
        NSString *stringFromData = [[NSString alloc]initWithData:rawLogData encoding:NSUTF8StringEncoding];
        NSLog(@"Raw Log Data\n%@", [stringFromData description]); // just to eliminate 'unused' warning in this sample

    }
    else {
        NSLog(@"Error in getting log data: %@", [oError description]);
    }

    
        //Oggerschummer 20150929 END
    

    
    
    [self.logManager uploadClientLogs:uploader completion:^(NSError *error) {
        
        if (!error) {
            
            UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"Upload succeeded" message:nil delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                [alertView show];
            });
        } else {
            UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"Upload failed" message:nil delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                [alertView show];
            });
        }
    }];
    
    
}
@end