//
//  DataController.m
//  Usage Prototype
//
//  Created by Stadelman, Stan on 3/7/14.
//  Copyright (c) 2014 Stan Stadelman. All rights reserved.
//


/*
 *
 *
 *  THIS CODE SHOULD BE BOILERPLATE
 *
 *
 *  MAKE ADDITIONS TO REQUEST INTERFACE THROUGH CATEGORIES
 *
 *
 *
 */


#import "DataController+FetchRequestsSample.h"

#import "OnlineStore.h"
#import "OfflineStore.h"
#import "LogonHandler.h"

#import "SODataRequestDelegate.h"
#import "SODataRequestExecution.h"
#import "SODataResponseSingle.h"
#import "SODataPayload.h"
#import "SODataEntity.h"
#import "SODataError.h"
#import "SODataRequestParamSingleDefault.h"
#import "SODataEntityDefault.h"
#import "SODataEntitySetDefault.h"
#import "SODataErrorDefault.h"


#import <FXNotifications/FXNotifications.h>

@interface DataController() <SODataRequestDelegate> {
}


@end

@implementation DataController

#pragma mark Singleton Init
+(instancetype)shared
{
    static id _shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        _shared= [[DataController alloc] init];
        
    });
    
    return _shared;
}



#pragma mark Initialize with BaseURL and HttpConversationManager

-(instancetype)init
{
    if (self == [super init]) {
        
        self.definingRequests = [[NSArray alloc] init];
        self.workingMode = WorkingModeMixed;
        
        return self;
    }
    
    return nil;
}

/* 

    Here is where we setup the Online and Offline stores.  
    
    By default, the DataController works in 'Mixed' mode, meaning that both an Online and Offline
    store are initialized and configured.  
    
    For the sake of slimming down the application, the developer can also set 'Online' or 'Offline'
    mode directly.

    1.  First, remove all listeners on self
    2.  Check if logon is already finished, (i.e. MAFLogonRegistrationData != nil)
    3.  If logon is already finished, simply initialize and open store
    3b.  If logon is not finished, then listen for kLogonFinished, then initialize and open store
*/


-(void)loadWorkingMode
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if ([LogonHandler shared].logonManager.logonState.isUserRegistered &&
        [LogonHandler shared].logonManager.logonState.isSecureStoreOpen) {
        
        [self setupStores];
        
    } else {
        
        [[NSNotificationCenter defaultCenter] addObserver:self forName:kLogonFinished object:nil queue:nil usingBlock:^(NSNotification *note, id observer) {
            
            [[NSNotificationCenter defaultCenter] removeObserver:observer name:kLogonFinished object:observer];
            
            [self setupStores];
        }];
    }
}


- (void)setupStores
{
    __block BOOL onlineStoreConfig = NO;
    __block BOOL offlineStoreConfig = NO;
    
    __block void (^setupNetworkStore)(void) = ^void() {
        
        self.networkStore = [[OnlineStore alloc] initWithURL:[[LogonHandler shared].baseURL applicationURL]
                                     httpConversationManager:[LogonHandler shared].httpConvManager];
        
        onlineStoreConfig = YES;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kOnlineStoreConfigured object:nil];
    };
    
    __block void (^setupLocalStore)(void) = ^void() {
        
        self.localStore = [[OfflineStore alloc] init];
        
        offlineStoreConfig = YES;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kOfflineStoreConfigured object:nil];
    };
    
    switch (self.workingMode) {
    
        case WorkingModeMixed:
            setupLocalStore();
            setupNetworkStore();
            
            NSAssert(onlineStoreConfig == YES && offlineStoreConfig == YES, @"both stores configured");
            break;
            
        case WorkingModeOnline:
            setupNetworkStore();
            
            NSAssert(onlineStoreConfig == YES, @"online store configured");
            break;
            
        case WorkingModeOffline:
            setupLocalStore();
            
            NSAssert(offlineStoreConfig == YES, @"offline store configured");
            break;
        default:
            break;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kStoreConfigured object:nil];
}

-(id<ODataStore>)storeForRequestToResourcePath:(NSString *)resourcePath
{
    /*
    First, test if mode is online- or offline-only anyway.
    */
    if (self.workingMode == WorkingModeOnline) {
    
        NSLog(@"Store %@ picked for resourcePath:  %@", [self.networkStore description], resourcePath);
        return self.networkStore;
        
    } else if (self.workingMode == WorkingModeOffline) {
    
        NSLog(@"Store %@ picked for resourcePath:  %@", [self.localStore description], resourcePath);
        return self.localStore;
    }
    
    /*
    And if there are any defining requests to test anyway
    */
    if (self.definingRequests.count < 1) {
        NSLog(@"Store %@ picked for resourcePath:  %@", [self.networkStore description], resourcePath);
        return self.networkStore;
    }
    
    /*
    Second, do a compare to see if the collection of the request matches the collection
    of the defining requests.  The principle here is that you can offline a collection,
    or filter of a collection, and all requests will be executed against the db for that
    collection.  You should adjust the filters of your defining requests to support the
    expected scope of requests for the user.
    */
    __block NSString * (^collectionName)(NSString *) = ^NSString * (NSString *string){
        
        NSString *relativeString = string;
        
        /*
         If the string is a fully-qualified URL, parse out just the relative resource path
         */
        if ([[relativeString substringToIndex:4] isEqualToString:@"http"]) {
            
            NSURL *url = [NSURL URLWithString:relativeString];
            relativeString = [url lastPathComponent];
        }
        
        /*
         Trim parenthesis element from last path component
         */
        if ([relativeString rangeOfString:@"("].location != NSNotFound) {
            relativeString = [relativeString substringToIndex:[relativeString rangeOfString:@"("].location];
        }
    
        return [relativeString rangeOfString:@"?"].location != NSNotFound ? [relativeString substringToIndex:[relativeString rangeOfString:@"?"].location] : relativeString;
    };
    
    NSString *resourcePathCollectionName = collectionName(resourcePath);
    
    for (NSString *request in self.definingRequests) {
        
        NSString *definingRequestCollectionName = collectionName(request);
        
        if ((resourcePathCollectionName && definingRequestCollectionName) && [resourcePathCollectionName isEqualToString:definingRequestCollectionName]) {
            
            NSLog(@"Store %@ picked for resourcePath:  %@", [self.localStore description], resourcePath);

            return self.localStore;
        }
    }
    
    /*
    Last, the default will always be to fall back to the network store (online request).
    This should cover Function Imports, and any requests which are not within the scope
    of the defining request collections
    */
    
    NSLog(@"Store %@ picked for resourcePath:  %@", [self.networkStore description], resourcePath);
    return self.networkStore;
}

#pragma mark Block Interface for scheduleRequest()

/* 
 * The application should invoke this method, since it wraps the scheduleRequest: method to ensure that the store is open
 *
 */

-(void)scheduleRequestForResource:(NSString *)resourcePath withMode:(SODataRequestModes)mode withEntity:(id<SODataEntity>)entity withCompletion:(void(^)(NSArray *entities, id<SODataRequestExecution>requestExecution, NSError *error))completion
{
    SODataRequestParamSingleDefault *myRequest = [[SODataRequestParamSingleDefault alloc] initWithMode:mode resourcePath:resourcePath];
    myRequest.payload = entity ? entity : nil;
    
    __block void (^openStore)(id<ODataStore>) = ^void(id<ODataStore>store) {
    
        [store openStoreWithCompletion:^(BOOL success) {
            
            if (success) {
                
                [self scheduleRequest:myRequest onStore:(id<SODataStoreAsync>)store completionHandler:^(NSArray *entities, id<SODataRequestExecution> requestExecution, NSError *error) {
                    if (error){
                        NSLog(@"ERROR: %@",error.debugDescription);
                    }
                    completion(entities, requestExecution, error);
                }];
                
            } else {
                
                NSLog(@"Failed to open store, will not schedule request:  %@", [myRequest description]);
                
            }

        }];
    };
    
    id<ODataStore>storeForRequest = [self storeForRequestToResourcePath:resourcePath];
    
    if (storeForRequest != nil) {
    
        openStore(storeForRequest);
        
    } else {
        
        [[NSNotificationCenter defaultCenter] addObserver:self forName:kStoreConfigured object:nil queue:nil usingBlock:^(NSNotification *note, id observer) {
            
            [[NSNotificationCenter defaultCenter] removeObserver:observer name:kStoreConfigured object:observer];
            
            id<ODataStore>storeForRequest = [self storeForRequestToResourcePath:resourcePath];
            openStore(storeForRequest);

        }];
    }
}

/*
 *
 *  Do NOT invoke this method directly, since it does not ensure that the store is open
 *
 */

- (void) scheduleRequest:(id<SODataRequestParam>)request onStore:(id<SODataStoreAsync>)store completionHandler:(void(^)(NSArray *entities, id<SODataRequestExecution>requestExecution, NSError *error))completion
{
    
    __block NSString *finishedSubscription = [NSString stringWithFormat:@"%@.%@", kRequestDelegateFinished, request];

    [[NSNotificationCenter defaultCenter] addObserver:self forName:finishedSubscription object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note, id observer) {
        
        [[NSNotificationCenter defaultCenter] removeObserver:observer name:finishedSubscription object:observer];
        
        // this code will handle the <requestExecution> response, and call the completion block.
        id<SODataRequestExecution>requestExecution = note.object;
        
        id<SODataResponse> response = requestExecution.response;
        
        if (response.isBatch)
        {
            // not yet implemented
            NSLog(@"Batch Reuqest not implemented yet !");
        }
        else // not a batch response, only one response to handle
        {
            id<SODataResponseSingle> respSingle = (id<SODataResponseSingle>) response;
            // extract the payload
            id<SODataPayload> p = respSingle.payload;
            
            // response is an entity set, return EntitiesSet
            if ([respSingle payloadType] == SODataTypeEntitySet)
            {
                // copy and cast the entities from the response payload
                id<SODataEntitySet>entities = (id<SODataEntitySet>)p;
                
                // call completion block, with entities, requestExecution, and no error
                completion(entities.entities, requestExecution, nil);
            }
            
            // if payload is an error, return Error
            else if ([respSingle payloadType] == SODataTypeError)
            {
                id<SODataError>e = (id<SODataError>)respSingle.payload;
                
                NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
                [errorDetail setValue:e.message forKey:NSLocalizedDescriptionKey];
                NSError *error = [NSError errorWithDomain:@"myDomain" code:[e.code integerValue] userInfo:errorDetail];
                
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                                message:[NSString stringWithFormat:@"Code: %@\nMessage: %@", e.code, e.message]
                                                               delegate:self
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil, nil];
                [alert show];
                // call the completion block with error and requestExecution
                completion(nil, requestExecution, error);
            }
            
            // response type == SODataTypeNone for CUD operations
            else if ([respSingle payloadType] == SODataTypeNone) {
                
                /*
                 handle for bug where count = 0, when there are still entities
                 */
                if ([(id<SODataEntitySet>)p entities].count > 0) {
                    completion([(id<SODataEntitySet>)p entities], requestExecution, nil);
                } else {
                    completion(nil, requestExecution, nil);
                }
            }
            
            else if ([respSingle payloadType] == SODataTypeEntity) {
                
                id<SODataPayload> p = respSingle.payload;
                completion(@[(id<SODataEntity>)p], requestExecution, nil);
            }
            
            // if payload is unhandled type, construct error
            else
            {
                NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
                [errorDetail setValue:@"Unexpected payload type" forKey:NSLocalizedDescriptionKey];
                NSError *error = [NSError errorWithDomain:@"myDomain" code:100 userInfo:errorDetail];
                
                // call the completion block with error and requestExecution
                completion(nil, requestExecution, error);
                return;
            }
        }

    }];

    // then, the original SODataAsynch API is called
    
    [store scheduleRequest:request delegate:self];
    
    
}

#pragma mark - SODataRequestDelegate methods

- (void) requestFailed:(id<SODataRequestExecution>)requestExecution error:(NSError *)error
{
    
   //NSLog (@"REQUEST FAILED !!!, %@",error.debugDescription);

}

- (void) requestServerResponse:(id<SODataRequestExecution>)requestExecution
{
    
    /*
     You may handle the server response from this callback, or the requestFinished
     callback.  The same content should be available in both, when requesting over
     network.
     */
   // NSLog (@"REQUEST SERVER RESPONSE");

}

- (void) requestStarted:(id<SODataRequestExecution>)requestExecution
{
    //NSLog (@"REQUEST started: Tag: %@",requestExecution.request.customTag );
    
}

- (void) requestFinished:(id<SODataRequestExecution>)requestExecution
{
    //NSLog (@"REQUEST finished:\n   Tag:%@\n   %u",requestExecution.request.customTag , requestExecution.status);
    
    

    // build notification tag for this request
    NSString *finishedSubscription = [NSString stringWithFormat:@"%@.%@", kRequestDelegateFinished, requestExecution.request];
    
    // send notification for the finished request
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:finishedSubscription object:requestExecution];
        

    });
   }


@end
