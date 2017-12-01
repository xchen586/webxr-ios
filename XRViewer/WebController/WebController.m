#import <Foundation/Foundation.h>
#import "WebController.h"
#import "WebARKHeader.h"
#import "ARKHelper.h"
#import "OverlayHeader.h"
#import "BarView.h"

@interface WebController () <WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler>

@property (nonatomic, weak) UIView *rootView;
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, weak) WKUserContentController *contentController;
@property (nonatomic, copy) NSString *transferCallback;
@property (nonatomic, copy) NSString *lastURL;

@property (nonatomic, strong) NSLayoutConstraint *topWebViewConstraint;
@property (nonatomic, strong) NSLayoutConstraint *topBarViewConstraint;

@property (nonatomic, weak) BarView *barView;

@end

typedef void (^WebCompletion)(id _Nullable param, NSError * _Nullable error);

inline static WebCompletion debugCompletion(NSString *name)
{
    return ^(id  _Nullable param, NSError * _Nullable error)
    {
        DDLogDebug(@"%@ : %@", name, error ? @"error" : @"success");
    };
}

@implementation WebController

#pragma mark Interface

- (void)dealloc
{
    DDLogDebug(@"WebController dealloc");
}

- (instancetype)initWithRootView:(UIView *)rootView
{
    self = [super init];
    
    if (self)
    {
        [self setupWebViewWithRootView:rootView];
        [self setupWebContent];
        [self setupWebUI];
        [self setupBarView];
    }
    
    return self;
}
 
- (void)reload
{
    NSString *url = [[[self barView] urlFieldText] length] > 0 ? [[self barView] urlFieldText] : [self lastURL];
    [self loadURL:url];
}

- (void) goHome
{
    NSLog(@"going home");
    NSString* homeURL = [[NSUserDefaults standardUserDefaults] stringForKey:HOME_URL_KEY];
    if (homeURL && ![homeURL isEqualToString:@""]) {
        [self loadURL: homeURL];
    } else {
        [self loadURL:WEB_URL];
    }
}
   
- (void)loadURL:(NSString *)theUrl
{
    NSURL *url;
    if([theUrl hasPrefix:@"http://"] || [theUrl hasPrefix:@"https://"]) {
        url = [NSURL URLWithString:theUrl];
    } else {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@", theUrl]];
    }

    if (url)
    {
        NSString *scheme = [url scheme];
        
        if (scheme && [WKWebView handlesURLScheme:scheme])
        {
            NSURLRequest *r = [NSURLRequest requestWithURL:url
                                               cachePolicy:NSURLRequestReloadIgnoringCacheData
                                           timeoutInterval:60];
            
            [[NSURLCache sharedURLCache] removeAllCachedResponses];
            
            
            [[self webView] loadRequest:r];
            
            [self setLastURL:[url absoluteString]];
            
            return;
        }
    }
    
    if ([self onError])
    {
        [self onError](nil);
    }
}
    
- (void)showBar:(BOOL)showBar
{
    [_topBarViewConstraint setConstant:(showBar ? 0 : -URL_BAR_HEIGHT)];
    [UIView animateWithDuration:.35 animations:^
     {
         [[[self webView] superview] layoutSubviews];
     }];
}
    
- (void)clean
{
    [self cleanWebContent];
    
    [[self webView] stopLoading];
    
    [[[self webView] configuration] setProcessPool:[WKProcessPool new]];
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

- (void)setupForApp:(UIStyle)app
{
    dispatch_async(dispatch_get_main_queue(), ^
       {
           CGFloat top = 0;
           
           UIColor *backColor;
           
           if (app == Web)
           {
               top = URL_BAR_HEIGHT;
               backColor = [UIColor whiteColor];
           }
           else
           {
               backColor = [UIColor clearColor];
           }
           
           [_topWebViewConstraint setConstant:top];
           
           [UIView animateWithDuration:.35 
                            animations:^
                            {
                                [[[self webView] superview] layoutSubviews];
                            } 
                            completion:^(BOOL finished) 
                            {
                                [self callTranslationToSizeWebMethodWithSize:[[self webView] bounds].size angle:0];
                            }];
           
           [[[self webView] superview] setBackgroundColor:backColor];
           
           [[self animator] animate:[[self webView] superview] toColor:backColor];
       });
}
    
// xr
- (void)showDebug:(BOOL)showDebug
{
    [self callWebMethod:WEB_AR_SHOW_DEBUG_MESSAGE paramJSON:@{WEB_AR_UI_DEBUG_OPTION : (showDebug ? @YES : @NO)} webCompletion:debugCompletion(WEB_AR_SHOW_DEBUG_MESSAGE)];
}
    
- (void)didBackgroundAction:(BOOL)background
{
    NSString *message = background ? WEB_AR_MOVE_BACKGROUND_MESSAGE : WEB_AR_ENTER_FOREGROUND_MESSAGE;
    
    [self callWebMethod:message param:@"" webCompletion:debugCompletion(message)];
}
    
- (void)didReceiveMemoryWarning
{
    [self callWebMethod:WEB_AR_MEMORY_WARNING_MESSAGE param:@"" webCompletion:debugCompletion(WEB_AR_TRACKING_CHANGED_MESSAGE)];
}
    
- (void)viewWillTransitionToSize:(CGSize)size rotation:(CGFloat)rotation
{
    [self layout];
    
    NSInteger angleInt = rotationWith(rotation);
    DDLogDebug(@"viewWillTransitionToSize rotation - %ld", angleInt);
    
    [self callTranslationToSizeWebMethodWithSize:size angle:angleInt];
}

- (void)didChangeOrientation:(UIInterfaceOrientation)orientation withSize:(CGSize)size
{
    [self layout];
    
    NSString *orientationString = orientationFrom(orientation);
    DDLogDebug(@"didChangeOrientation - %@", orientationString);
               
    [self callWebMethod:WEB_AR_CHANGE_ORIENTATION_MESSAGE
              paramJSON:@{WEB_IOS_ORIENTATIOIN_OPTION : orientationString,
                          WEB_IOS_SIZE_OPTION: @{WEB_IOS_WIDTH_OPTION: @(size.width), WEB_IOS_HEIGHT_OPTION: @(size.height)}}
          webCompletion:debugCompletion(WEB_AR_CHANGE_ORIENTATION_MESSAGE)];
}
    
- (void)didRegion:(NSDictionary *)param enter:(BOOL)enter;
{
    NSString *message = enter ? WEB_AR_ENTER_REGION_MESSAGE : WEB_AR_EXIT_REGION_MESSAGE;
    
    [self callWebMethod:message paramJSON:param webCompletion:debugCompletion(message)];
}
    
- (void)didUpdateHeading:(NSDictionary *)dict
{
    [self callWebMethod:WEB_AR_UPDATE_HEADING_MESSAGE paramJSON:dict webCompletion:debugCompletion(WEB_AR_UPDATE_HEADING_MESSAGE)];
}
    
- (void)didUpdateLocation:(NSDictionary *)dict
{
    [self callWebMethod:WEB_AR_UPDATE_LOCATION_MESSAGE paramJSON:dict webCompletion:debugCompletion(WEB_AR_UPDATE_LOCATION_MESSAGE)];
}
    
- (void)wasARInterruption:(BOOL)interruption
{
    NSString *message = interruption ? WEB_AR_INTERRUPTION_MESSAGE : WEB_AR_INTERRUPTION_ENDED_MESSAGE;
    
    [self callWebMethod:message param:@"" webCompletion:debugCompletion(message)];
}

- (void)didChangeARTrackingState:(NSString *)state
{
        [self callWebMethod:WEB_AR_TRACKING_CHANGED_MESSAGE paramJSON:@{WEB_AR_TRACKING_STATE_OPTION : state} webCompletion:debugCompletion(WEB_AR_TRACKING_CHANGED_MESSAGE)];
}
    
- (void)didSessionFails
{
    [self callWebMethod:WEB_AR_SESSION_FAILS_MESSAGE param:@"" webCompletion:debugCompletion(WEB_AR_SESSION_FAILS_MESSAGE)];
}
    
- (void)didUpdateAnchors:(NSDictionary *)dict
{
    [self callWebMethod:WEB_AR_UPDATED_ANCHORS_MESSAGE paramJSON:dict webCompletion:debugCompletion(WEB_AR_UPDATED_ANCHORS_MESSAGE)];
}
    
- (void)didAddPlanes:(NSDictionary *)dict
{
    [self callWebMethod:WEB_AR_ADD_PLANES_MESSAGE paramJSON:dict webCompletion:debugCompletion(WEB_AR_ADD_PLANES_MESSAGE)];
}
    
- (void)didRemovePlanes:(NSDictionary *)dict
{
    [self callWebMethod:WEB_AR_REMOVE_PLANES_MESSAGE paramJSON:dict webCompletion:debugCompletion(WEB_AR_REMOVE_PLANES_MESSAGE)];
}
    
- (void)startRecording:(BOOL)start
{
    NSString *message = start ? WEB_AR_START_RECORDING_MESSAGE : WEB_AR_STOP_RECORDING_MESSAGE;
    
    [self callWebMethod:message param:@"" webCompletion:debugCompletion(message)];
}
    
- (BOOL)sendARData:(NSDictionary *)data
{
#define CHECK_UPDATE_CALL NO
    if ([self transferCallback] && data)
    {
        [self callWebMethod:[self transferCallback] paramJSON:data webCompletion:CHECK_UPDATE_CALL ? debugCompletion(@"sendARData") : NULL];
        
        return YES;
    }
    
    return NO;
}

#pragma mark WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    DDLogDebug(@"Received message: %@ , body: %@", [message name], [message body]);
    
    __weak typeof (self) blockSelf = self;
    
    if ([[message name] isEqualToString:WEB_JS_INIT_MESSAGE])
    {
        CGSize screenSize = [[UIScreen mainScreen] bounds].size;
        CGSize viewportSize = self.webView.frame.size;
        NSDictionary *params = @{ WEB_IOS_DEVICE_UUID_OPTION : [[[UIDevice currentDevice] identifierForVendor] UUIDString],
                                  WEB_IOS_IS_IPAD_OPTION : @([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad),
                                  WEB_IOS_SYSTEM_VERSION_OPTION : [[UIDevice currentDevice] systemVersion],
                                  WEB_IOS_SCREEN_SCALE_OPTION : @([[UIScreen mainScreen] nativeScale]),
                                  WEB_IOS_VIEWPORT_SIZE_OPTION : @{ WEB_IOS_WIDTH_OPTION : @(viewportSize.width),
                                                                  WEB_IOS_HEIGHT_OPTION : @(viewportSize.height) },
                                  WEB_IOS_ORIENTATIOIN_OPTION : orientationFrom([[UIApplication sharedApplication] statusBarOrientation]),
                                  WEB_IOS_SCREEN_SIZE_OPTION : @{ WEB_IOS_WIDTH_OPTION : @(screenSize.width),
                                                                WEB_IOS_HEIGHT_OPTION : @(screenSize.height)}};
        
        DDLogDebug(@"Init AR send - %@", [params debugDescription]);
        
        [self callWebMethod:[[message body] objectForKey:WEB_AR_CALLBACK_OPTION]
                  paramJSON:params
              webCompletion:^(id  _Nullable param, NSError * _Nullable error)
         {
             DDLogDebug(@"Init AR %@", error ? @"error" : @"success");
             
             if (error == nil)
             {
                 [blockSelf onInit]([message body][WEB_AR_REQUEST_OPTION][WEB_AR_UI_OPTION]);
             }
             else
             {
                 [blockSelf onError](error);
             }
         }];
    }
    else if ([[message name] isEqualToString:WEB_JS_LOAD_URL_MESSAGE])
    {
        [self onLoadURL]([[message body] objectForKey:WEB_AR_URL_OPTION]);
    }
    else if ([[message name] isEqualToString:WEB_JS_START_WATCH_MESSAGE])
    {
        [self setTransferCallback:[[message body] objectForKey:WEB_AR_CALLBACK_OPTION]];
        
        [self onWatch]([[message body] objectForKey:WEB_AR_REQUEST_OPTION]);
    }
    else if ([[message name] isEqualToString:WEB_JS_STOP_WATCH_MESSAGE])
    {
        NSString *callback = [[message body] objectForKey:WEB_AR_CALLBACK_OPTION];
        
        [self setTransferCallback:nil];
        
        [self onWatch](nil);
                
        [self callWebMethod:callback param:@"" webCompletion:NULL];
    }
    else if ([[message name] isEqualToString:WEB_JS_SET_UI_MESSAGE])
    {
        [self onSetUI]([[message body] objectForKey:WEB_AR_REQUEST_OPTION]);
    }
    else if ([[message name] isEqualToString:WEB_JS_HIT_TEST_MESSAGE])
    {
        NSString *callback = [[message body] objectForKey:WEB_AR_CALLBACK_OPTION];
        [self onHitTest]([[message body] objectForKey:WEB_AR_REQUEST_OPTION], ^(NSDictionary *results)
                         {
                             [blockSelf callWebMethod:callback paramJSON:results webCompletion:debugCompletion(WEB_JS_HIT_TEST_MESSAGE)];
                         });
    }
    else if ([[message name] isEqualToString:WEB_JS_ADD_ANCHOR_MESSAGE])
    {
        NSString *callback = [[message body] objectForKey:WEB_AR_CALLBACK_OPTION];
        [self onAddAnchor]([[message body] objectForKey:WEB_AR_REQUEST_OPTION], ^(NSDictionary *results)
                         {
                             [blockSelf callWebMethod:callback paramJSON:results webCompletion:debugCompletion(WEB_JS_ADD_ANCHOR_MESSAGE)];
                         });
    }
    else if ([[message name] isEqualToString:WEB_JS_REMOVE_ANCHOR_MESSAGE])
    {
        NSString *callback = [[message body] objectForKey:WEB_AR_CALLBACK_OPTION];
        [self onRemoveAnchor]([[message body] objectForKey:WEB_AR_REQUEST_OPTION], ^(NSDictionary *results)
                           {
                               [blockSelf callWebMethod:callback paramJSON:results webCompletion:debugCompletion(WEB_JS_REMOVE_ANCHOR_MESSAGE)];
                           });
    }
    else if ([[message name] isEqualToString:WEB_JS_UPDATE_ANCHOR_MESSAGE])
    {
        NSString *callback = [[message body] objectForKey:WEB_AR_CALLBACK_OPTION];
        [self onUpdateAnchor]([[message body] objectForKey:WEB_AR_REQUEST_OPTION], ^(NSDictionary *results)
                              {
                                  [blockSelf callWebMethod:callback paramJSON:results webCompletion:debugCompletion(WEB_JS_UPDATE_ANCHOR_MESSAGE)];
                              });
    }
    else if ([[message name] isEqualToString:WEB_JS_START_HOLD_ANCHOR_MESSAGE])
    {
        NSString *callback = [[message body] objectForKey:WEB_AR_CALLBACK_OPTION];
        [self onStartHold]([[message body] objectForKey:WEB_AR_REQUEST_OPTION], ^(NSDictionary *results)
                              {
                                  [blockSelf callWebMethod:callback paramJSON:results webCompletion:debugCompletion(WEB_JS_START_HOLD_ANCHOR_MESSAGE)];
                              });
    }
    else if ([[message name] isEqualToString:WEB_JS_STOP_HOLD_ANCHOR_MESSAGE])
    {
        NSString *callback = [[message body] objectForKey:WEB_AR_CALLBACK_OPTION];
        [self onStopHold]([[message body] objectForKey:WEB_AR_REQUEST_OPTION], ^(NSDictionary *results)
                           {
                               [blockSelf callWebMethod:callback paramJSON:results webCompletion:debugCompletion(WEB_JS_STOP_HOLD_ANCHOR_MESSAGE)];
                           });
    }
    else if ([[message name] isEqualToString:WEB_JS_ADD_REGION_MESSAGE])
    {
        NSString *callback = [[message body] objectForKey:WEB_AR_CALLBACK_OPTION];
        [self onAddRegion]([[message body] objectForKey:WEB_AR_REQUEST_OPTION], ^(NSDictionary *results)
                          {
                              [blockSelf callWebMethod:callback paramJSON:results webCompletion:debugCompletion(WEB_JS_ADD_REGION_MESSAGE)];
                          });
    }
    else if ([[message name] isEqualToString:WEB_JS_REMOVE_REGION_MESSAGE])
    {
        NSString *callback = [[message body] objectForKey:WEB_AR_CALLBACK_OPTION];
        [self onRemoveRegion]([[message body] objectForKey:WEB_AR_REQUEST_OPTION], ^(NSDictionary *results)
                           {
                               [blockSelf callWebMethod:callback paramJSON:results webCompletion:debugCompletion(WEB_JS_REMOVE_REGION_MESSAGE)];
                           });
    }
    else if ([[message name] isEqualToString:WEB_JS_IN_REGION_MESSAGE])
    {
        NSString *callback = [[message body] objectForKey:WEB_AR_CALLBACK_OPTION];
        [self onInRegion]([[message body] objectForKey:WEB_AR_REQUEST_OPTION], ^(NSDictionary *results)
                              {
                                  [blockSelf callWebMethod:callback paramJSON:results webCompletion:debugCompletion(WEB_JS_IN_REGION_MESSAGE)];
                              });
    }
    else
    {
        DDLogError(@"Unknown message: %@ ,for name: %@", [message body], [message name]);
    }
}

- (void)callWebMethod:(NSString *)name param:(NSString *)param webCompletion:(WebCompletion)completion
{
    NSData *jsonData = param ? [NSJSONSerialization dataWithJSONObject:@[param] options:0 error:nil] : [NSData data];
    [self callWebMethod:name jsonData:jsonData  webCompletion:completion];
}

- (void)callWebMethod:(NSString *)name paramJSON:(id)paramJSON webCompletion:(WebCompletion)completion
{
    NSData *jsonData = paramJSON ? [NSJSONSerialization dataWithJSONObject:paramJSON options:0 error:nil] : [NSData data];
    [self callWebMethod:name jsonData:jsonData webCompletion:completion];
}

- (void)callWebMethod:(NSString *)name jsonData:(NSData *)jsonData webCompletion:(WebCompletion)completion
{
    NSAssert(name, @" Web Massage name is nil !");
    
    NSString *jsString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSString *jsScript = [NSString stringWithFormat:@"%@(%@)", name, jsString];
    
    [[self webView] evaluateJavaScript:jsScript completionHandler:completion];
}

#pragma mark WKUIDelegate, WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(null_unspecified WKNavigation *)navigation
{
    DDLogDebug(@"didStartProvisionalNavigation - %@", navigation);
    [self onStartLoad]();
    
    [[self barView] startLoading:[[[self webView] URL] absoluteString]];
    [[self barView] setBackEnabled:[[self webView] canGoBack]];
    [[self barView] setForwardEnabled:[[self webView] canGoForward]];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(null_unspecified WKNavigation *)navigation
{
    DDLogDebug(@"didFinishNavigation - %@", navigation);
    NSString* loadedURL = [[[self webView] URL] absoluteString];
    [self setLastURL:loadedURL];
    
    [[NSUserDefaults standardUserDefaults] setObject:loadedURL forKey:LAST_URL_KEY];
    
    [self onFinishLoad]();
    
    [[self barView] finishLoading:[[[self webView] URL] absoluteString]];
    [[self barView] setBackEnabled:[[self webView] canGoBack]];
    [[self barView] setForwardEnabled:[[self webView] canGoForward]];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error
{
    DDLogError(@"Web Error - %@", error);
    
    if ([self shouldShowError:error])
    {
        [self onError](error);
    }
    
    [[self barView] finishLoading:[[[self webView] URL] absoluteString]];
    [[self barView] setBackEnabled:[[self webView] canGoBack]];
    [[self barView] setForwardEnabled:[[self webView] canGoForward]];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error
{
    DDLogError(@"Web Error - %@", error);
    
    if ([self shouldShowError:error])
    {
        [self onError](error);
    }
    
    [[self barView] finishLoading:[[[self webView] URL] absoluteString]];
    [[self barView] setBackEnabled:[[self webView] canGoBack]];
    [[self barView] setForwardEnabled:[[self webView] canGoForward]];
}

- (BOOL)webView:(WKWebView *)webView shouldPreviewElement:(WKPreviewElementInfo *)elementInfo
{
    return NO;
}

#pragma mark Private

- (BOOL)shouldShowError:(NSError *)error
{
    return
    (([error code] > SERVER_STOP_CODE) || ([error code] < SERVER_START_CODE)) &&
    ([error code] != CANCELLED_CODE);
}

- (void)layout
{
    [[self webView] layoutIfNeeded];
    
    [[self barView] layout];
}

- (void)setupWebUI
{
    [[self webView] setTranslatesAutoresizingMaskIntoConstraints:NO];
    _topWebViewConstraint = [[[self webView] topAnchor] constraintEqualToAnchor:[[[self webView] superview] topAnchor] constant:0];
    [_topWebViewConstraint setActive:YES];
    [[[[self webView] bottomAnchor] constraintEqualToAnchor:[[[self webView] superview] bottomAnchor] constant:0] setActive:YES];
    [[[[self webView] leftAnchor] constraintEqualToAnchor:[[[self webView] superview] leftAnchor] constant:0] setActive:YES];
    [[[[self webView] rightAnchor] constraintEqualToAnchor:[[[self webView] superview] rightAnchor] constant:0] setActive:YES];
    
    [[self webView] setAllowsLinkPreview:NO];
    [[self webView] setOpaque:NO];
    [[self webView] setBackgroundColor:[UIColor clearColor]];
    [[self webView] setUserInteractionEnabled:YES];
    [[[self webView] scrollView] setBounces:NO];
    [[[self webView] scrollView] setBouncesZoom:NO];
}

- (void)setupBarView
{
    BarView *barView = [[[NSBundle mainBundle] loadNibNamed:@"BarView" owner:self options:nil] firstObject];
    [[[self webView] superview] addSubview:barView];
    [self setBarView:barView];
    
    [barView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [[[barView heightAnchor] constraintEqualToConstant:URL_BAR_HEIGHT] setActive:YES];
    _topBarViewConstraint = [[barView topAnchor] constraintEqualToAnchor:[[[self webView] superview] topAnchor] constant:0];
    [_topBarViewConstraint setActive:YES];
    [[[barView leftAnchor] constraintEqualToAnchor:[[[self webView] superview] leftAnchor] constant:0] setActive:YES];
    [[[barView rightAnchor] constraintEqualToAnchor:[[[self webView] superview] rightAnchor] constant:0] setActive:YES];
    
    __weak typeof (self) blockSelf = self;
    __weak typeof (BarView *) blockBar = barView;
    
    [barView setBackActionBlock:^(id sender)
     {
         if ([[blockSelf webView] canGoBack])
         {
             [[blockSelf webView] goBack];
         }
         else
         {
             [blockBar setBackEnabled:NO];
         }
     }];
    
    [barView setForwardActionBlock:^(id sender)
     {
         if ([[blockSelf webView] canGoForward])
         {
             [[blockSelf webView] goForward];
         }
         else
         {
             [blockBar setForwardEnabled:NO];
         }
     }];
    
    [barView setHomeActionBlock:^(id sender) {
        [self goHome];
    }];
    
    [barView setCancelActionBlock:^(id sender)
     {
         [[blockSelf webView] stopLoading];
     }];
    
    [barView setReloadActionBlock:^(id sender)
     {
         [blockSelf loadURL:[blockBar urlFieldText]];
     }];
    
    [barView setGoActionBlock:^(NSString *url)
     {
         [blockSelf loadURL:url];
     }];
}

- (void)setupWebContent
{
    for(NSString *message in jsMessages())
    {
        [[self contentController] addScriptMessageHandler:self name:message];
    }
}

- (void)cleanWebContent
{
    for(NSString *message in jsMessages())
    {
        [[self contentController] removeScriptMessageHandlerForName:message];
    }
}

- (void)setupWebViewWithRootView:(__autoreleasing UIView*)rootView
{
    WKWebViewConfiguration *conf = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *contentController = [WKUserContentController new];
    [conf setUserContentController:contentController];
    [self setContentController:contentController];
    
    WKPreferences *pref = [[WKPreferences alloc] init];
    [pref setJavaScriptEnabled:YES];
    [conf setPreferences:pref];
    
    [conf setProcessPool:[WKProcessPool new]];

    [conf setAllowsInlineMediaPlayback: YES];
    [conf setAllowsAirPlayForMediaPlayback: YES];
    [conf setAllowsPictureInPictureMediaPlayback: YES];
    [conf setMediaTypesRequiringUserActionForPlayback: WKAudiovisualMediaTypeNone];
    
    WKWebView *wv = [[WKWebView alloc] initWithFrame:[rootView bounds] configuration:conf];
    [rootView addSubview:wv];
    [wv setNavigationDelegate:self];
    [wv setUIDelegate:self];
    [self setWebView:wv];
}

- (void)callTranslationToSizeWebMethodWithSize:(CGSize)size angle:(NSInteger)angle 
{
    [self callWebMethod:WEB_AR_TRANSITION_TO_SIZE_MESSAGE
              paramJSON:@{WEB_IOS_SIZE_OPTION : @{WEB_IOS_WIDTH_OPTION: @(size.width), 
                                                  WEB_IOS_HEIGHT_OPTION: @(size.height)},
                          WEB_IOS_ANGLE_OPTION: @(angle)
                          }
          webCompletion:debugCompletion(WEB_AR_TRANSITION_TO_SIZE_MESSAGE)];
}

@end

