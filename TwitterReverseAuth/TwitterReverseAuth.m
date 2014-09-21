// TwitterHelper.m
//
// Copyright (c) 2013/2014 Kyle Begeman (www.kylebegeman.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "TwitterReverseAuth.h"

#import <Twitter/Twitter.h>
#import <Social/Social.h>
#import <STLOAuth/STLOAuthClient.h>
#import <AFNetworking/AFNetworking.h>
#import <Accounts/Accounts.h>

#import "TwitterReverseAuth.h"

const NSString *TRATwitterReverseAuthCredentialOAuthToken = @"oauth_token";
const NSString *TRATwitterReverseAuthCredentialOAuthTokenSecret = @"oauth_token_secret";
const NSString *TRATwitterReverseAuthCredentialUserID = @"user_id";
const NSString *TRATwitterReverseAuthCredentialScreenName = @"screen_name";


@interface TRATwitterReverseAuth () {
    ACAccountStore *_accountStore;
}

@property(nonatomic,readonly) ACAccountStore *accountStore;

@end


@implementation TRATwitterReverseAuth

- (instancetype)initWithDelegate:(id<TRATwitterReverseAuthDelegate>)delegate {
    self = [self init];
    if (self != nil) {
        self.delegate = delegate;
    }
    return self;
}

- (ACAccountStore *)accountStore {
    if ([self.delegate respondsToSelector:@selector(accountStoreForTwitterReverseAuth:)]) {
        return [self.delegate accountStoreForTwitterReverseAuth:self];
    } else {
        if (self->_accountStore == nil) {
            self->_accountStore = [[ACAccountStore alloc] init];
        }
        return self->_accountStore;
    }
}

- (void)requestCredentialsForAccount:(ACAccount *)account completion:(void (^)(NSDictionary *, NSError *))completion {
    NSParameterAssert(completion);
    // Configure the URL
    NSURL *url = [NSURL URLWithString:@"https://api.twitter.com/"];

    // Create a client
    NSString *APIKey = [self.delegate APIKeyForTwitterReverseAuth:self];
    NSString *APISecret = [self.delegate APISecretForTwitterReverseAuth:self];
    STLOAuthClient *client = [[STLOAuthClient alloc] initWithBaseURL:url consumerKey:APIKey secret:APISecret];

    // Create other parameters
    NSDictionary *params = @{@"x_auth_mode": @"reverse_auth"};

    //This get request is for the request_tokens.
    [client getPath:@"oauth/request_token" parameters:params success:^(AFHTTPRequestOperation *operation, id responseObject) {
        // Get the oauth response
        NSString *oauth = operation.responseString;

        NSDictionary *step2Params = [[NSMutableDictionary alloc] init];
        [step2Params setValue:APIKey forKey:@"x_reverse_auth_target"];
        [step2Params setValue:oauth forKey:@"x_reverse_auth_parameters"];

        NSURL *url2 = [NSURL URLWithString:@"https://api.twitter.com/oauth/access_token"];
        // Following two lines perform the access token request directly with iOS 6 Social Framework SLRequest
        SLRequest *stepTwoRequest = [SLRequest requestForServiceType:SLServiceTypeTwitter requestMethod:SLRequestMethodPOST URL:url2 parameters:step2Params];
        // Create a request  - following is some suggested iOS 5 code to accomplish the request thought it's really calling mapped SLRequest calls.
        //TWRequest *stepTwoRequest = [[TWRequest alloc] initWithURL:url2 parameters:step2Params requestMethod:TWRequestMethodPOST];

        // Set the account
        stepTwoRequest.account = account;

        // Perform the request
        [stepTwoRequest performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
            //  You *MUST* keep the ACAccountStore alive for as long as you need an ACAccount instance
            //  See WWDC 2011 Session 124 for more info.

            //  We only want to receive Twitter accounts
            ACAccountStore *store = self.accountStore;
            ACAccountType *twitterType = [store accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];

            //  Obtain the user's permission to access the store
            [store requestAccessToAccountsWithType:twitterType options:nil completion:^(BOOL granted, NSError *error) {
                if (!granted) {
                    completion(nil, error);
                } else {
                    // for simplicity, we will choose the first account returned - in your app,
                    // you should ensure that the user chooses the correct Twitter account
                    // to use with your application.  DO NOT FORGET THIS STEP.
                    [stepTwoRequest setAccount:account];

                    // execute the request
                    [stepTwoRequest performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
                        NSString *responseStr = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];

                        // see below for an example response
                        // NSLog(@"The user's info for your server:\n%@", responseStr);
                        // Check for errors
                        if (responseData && !error) {
                            completion(_TRATwitterReverseAuthCredentialsFromTwitterOAuthResponse(responseStr), nil);
                        } else {
                            completion(nil, error);
                        }
                    }];
                }
            }];
        }];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        completion(nil, error);
    }];
}

NSDictionary *_TRATwitterReverseAuthCredentialsFromTwitterOAuthResponse(NSString *response) {
    // Divide the string by ampersands
    NSArray *components = [response componentsSeparatedByString:@"&"];

    NSMutableDictionary *credentials = [NSMutableDictionary dictionaryWithCapacity:4];

    // Iterate through the components
    for (NSString *component in components) {
        // Split by = sign
        NSRange divider = [component rangeOfString:@"="];
        NSString *key = [component substringToIndex:divider.location];
        NSString *val = [component substringFromIndex:divider.location+1];
        [credentials setObject:val forKey:key];
    }
    return credentials;
}

@end
