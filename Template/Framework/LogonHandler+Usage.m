//
//  LogonHandler+Usage.m
//  TravelAgency_RKT
//
//  Created by Stadelman, Stan on 7/22/14.
//  Copyright (c) 2014 SAP. All rights reserved.
//

#import "LogonHandler+Usage.h"
#import "Usage.h"

@implementation LogonHandler (Usage)

-(void)startUsageCollection
{
    NSError * err;
    
        //Oggerschummer: Adjust for SP10PL01
    [[Usage sharedInstance] initializeUsageWithURL:[self.baseURL clientUsageURL] httpConversationManager:self.httpConvManager withError:&err];

}
@end
