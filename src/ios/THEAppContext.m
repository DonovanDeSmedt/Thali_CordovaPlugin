//
//  The MIT License (MIT)
//
//  Copyright (c) 2015 Microsoft
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//
//  Thali CordovaPlugin
//  THEAppContext.m
//

#import <pthread.h>
#include "jx.h"
#import "JXcore.h"
#import "THEAtomicFlag.h"
#import "THEThreading.h"
#import "NPReachability.h"
#import "THEPeerBluetooth.h"
#import "THEMultipeerSession.h"
#import "THEAppContext.h"
#import "THEPeer.h"

// JavaScript callbacks.
NSString * const kPeerAvailabilityChanged   = @"peerAvailabilityChanged";
NSString * const kConnectingToPeerServer    = @"connectingToPeerServer";
NSString * const kConnectedToPeerServer     = @"connectedToPeerServer";
NSString * const kNotConnectedToPeerServer  = @"notConnectedToPeerServer";
NSString * const kPeerClientConnecting      = @"peerClientConnecting";
NSString * const kPeerClientConnected       = @"peerClientConnected";
NSString * const kPeerClientNotConnected    = @"peerClientNotConnected";

// THEAppContext (THEPeerBluetoothDelegate) interface.
@interface THEAppContext (THEPeerBluetoothDelegate)
@end

// THEAppContext (Internal) interface.
@interface THEAppContext (Internal)

// Class initializer.
- (instancetype)init;

// Fires the network changed event.
- (void)fireNetworkChangedEvent;

// UIApplicationWillResignActiveNotification callback.
- (void)applicationWillResignActiveNotification:(NSNotification *)notification;

// UIApplicationDidBecomeActiveNotification callback.
- (void)applicationDidBecomeActiveNotification:(NSNotification *)notification;

@end

// THEAppContext implementation.
@implementation THEAppContext
{
@private
  // The communications enabled atomic flag.
  THEAtomicFlag * _atomicFlagCommunicationsEnabled;
    
  // The reachability handler reference.
  id reachabilityHandlerReference;
    
  // Peer Bluetooth.
  THEPeerBluetooth * _peerBluetooth;
    
  // Peer Networking.
  THEMultipeerSession * _multipeerSession;
    
  // The mutex used to protect access to things below.
  pthread_mutex_t _mutex;
    
  // The peers dictionary.
  NSMutableDictionary * _peers;
}

// Singleton.
+ (instancetype)singleton
{
  // Singleton instance.
  static THEAppContext * appContext = nil;
    
  // If unallocated, allocate.
  if (!appContext)
  {
    // Allocator.
    void (^allocator)() = ^
    {
      appContext = [[THEAppContext alloc] init];
    };
        
    // Dispatch allocator once.
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, allocator);
  }
    
  // Done.
  return appContext;
}


// Starts communications.
- (BOOL)startBroadcasting:(NSString *)peerIdentifier serverPort:(NSNumber *)serverPort
{
  if ([_atomicFlagCommunicationsEnabled trySet])
  {
    // Allocate and initialize the service type.
    //NSUUID * serviceType = [[NSUUID alloc] initWithUUIDString:@"72D83A8B-9BE7-474B-8D2E-556653063A5B"];

    // Allocate and initialize the peer Bluetooth context.
    //_peerBluetooth = [[THEPeerBluetooth alloc] initWithServiceType:serviceType
    //                                                peerIdentifier:peerIdentifier
    //                                                      peerName:[serverPort stringValue]];
    //[_peerBluetooth setDelegate:(id<THEPeerBluetoothDelegate>)self];
       
    _peers = [[NSMutableDictionary alloc] init];

    // Allocate and initialize peer networking.
    _multipeerSession = [[THEMultipeerSession alloc] initWithServiceType:@"Thali"
                                                          peerIdentifier:peerIdentifier
                                                              peerName:[serverPort stringValue]];
    [_multipeerSession setDelegate:self];

    // Start peer Bluetooth and peer networking.
    //[_peerBluetooth start];
    [_multipeerSession start];
       
    // Once started, fire the network changed event.

    // TBD(tobe) - This arbitrary delay bothers me and also appears to change the
    // handler reference outside of the mutex
    OnMainThreadAfterTimeInterval(1.0, ^{
        [self fireNetworkChangedEvent];
        reachabilityHandlerReference = [[NPReachability sharedInstance] addHandler:^(NPReachability *reachability) {
            [self fireNetworkChangedEvent];
        }];
    });

    return true;
  }

  return false;
}

// Stops communications.
- (BOOL)stopBroadcasting
{
  if ([_atomicFlagCommunicationsEnabled tryClear])
  {
    NSLog(@"app: stop broadcasting");

    //[_peerBluetooth stop];
    [_multipeerSession stop];
    //[_peerBluetooth setDelegate:nil];
    [_multipeerSession setDelegate:nil];
    _peerBluetooth = nil;
    _multipeerSession = nil;

    if (reachabilityHandlerReference != nil) // network changed event may not have fired yet
    {
      [[NPReachability sharedInstance] removeHandler:reachabilityHandlerReference];
      reachabilityHandlerReference = nil;
    }

    _peers = nil;
    return YES;
  }
    
  NSLog(@"app: didn't stop broadcasting");
  return NO;
}

// SocketServerDelegate
////////////////////////////

// Connects to the peer server with the specified peer idetifier.
- (BOOL)connectToPeer:(NSString *)peerIdentifier 
      connectCallback:(void(^)(NSString *, uint))connectCallback
{
  if ([_atomicFlagCommunicationsEnabled isClear])
  {
      NSLog(@"Communications not enabled");
      connectCallback(@"app: Not initialised", 0);
      return NO;
  }
    
  // Lock.
  /*pthread_mutex_lock(&_mutex);
   
  // Find the peer.
  THEPeer * peer = _peers[peerIdentifier];
    
  // Unlock.
  pthread_mutex_unlock(&_mutex);
    
  // If we didn't find the peer, return NO.
  if (!peer)
  {
    return NO;
  }
  */

  return [_multipeerSession connectToPeerServerWithPeerIdentifier:peerIdentifier 
                                              withConnectCallback:connectCallback];
}

// Disconnects from the peer server with the specified peer idetifier.
- (BOOL)disconnectFromPeer:(NSString *)peerIdentifier
{
  // If communications are not enabled, return NO.
  if ([_atomicFlagCommunicationsEnabled isClear])
  {
    NSLog(@"Communications not enabled");
    return NO;
  }
    
  // Lock.
  /*pthread_mutex_lock(&_mutex);
    
  // Find the peer. If we didn't find it, return NO.
  THEPeer * peer = _peers[peerIdentifier];

  // Unlock.
  pthread_mutex_unlock(&_mutex);

  // If we didn't find the peer, return NO.
  if (!peer)
  {
    return NO;
  }*/

  return [_multipeerSession disconnectFromPeerServerWithPeerIdentifier:peerIdentifier];
}

////////////////////////////////////////////////////////////
// THEAppContext <THEMultipeerSessionDelegate> implementation.
////////////////////////////////////////////////////////////

- (void) didFindPeerIdentifier:(NSString *)peerIdentifier peerName:(NSString *)peerName
{
  NSLog(@"app: didFindPeerIdentifier %@", peerIdentifier);

  // Lock.
  pthread_mutex_lock(&_mutex);
  
  // Find the peer.
  THEPeer * peer = _peers[peerIdentifier];
  
  // If this is a new peer, add it.
  if (!peer)
  {
    // Allocate and initialize the peer, add it to the peers dictionary.
    peer = [[THEPeer alloc] initWithIdentifier:peerIdentifier
                                          name:peerName];
    [_peers setObject:peer
               forKey:peerIdentifier];
  }
    
  // Update the peer state.
  [peer setAvailable:YES];
    
  // Unlock.
  pthread_mutex_unlock(&_mutex);

  // Fire the peerAvailabilityChanged event.
  OnMainThread(^{
    [JXcore callEventCallback:kPeerAvailabilityChanged
                     withJSON:[peer JSON]];
  });
}

- (void) didLosePeerIdentifier:(NSString *)peerIdentifier
{
  NSLog(@"app: didLosePeerIdentifier %@", peerIdentifier);

  // Lock.
  pthread_mutex_lock(&_mutex);
    
  // Find the peer.
  THEPeer * peer = _peers[peerIdentifier];
  if (peer)
  {
    [peer setAvailable:NO];
  }

  // Unlock.
  pthread_mutex_unlock(&_mutex);
    
  // Fire the peerAvailabilityChanged event.
  if (peer)
  {
    OnMainThread(^{
        [JXcore callEventCallback:kPeerAvailabilityChanged
                         withJSON:[peer JSON]];
    });
  }
}

@end

///////////////////////////////////////////////////////////
// THEAppContext (THEPeerBluetoothDelegate) implementation.
///////////////////////////////////////////////////////////

@implementation THEAppContext (THEPeerBluetoothDelegate)

// Notifies the delegate that a peer was connected.
- (void)peerBluetooth:(THEPeerBluetooth *)peerBluetooth
didConnectPeerIdentifier:(NSString *)peerIdentifier
                peerName:(NSString *)peerName
{
  // Lock.
  pthread_mutex_lock(&_mutex);

  // Find the peer. If we found it, simply return.
  THEPeer * peer = [_peers objectForKey:peerIdentifier];
  if (peer)
  {
      pthread_mutex_unlock(&_mutex);
      return;
  }
    
  // Allocate and initialize the peer.
  peer = [[THEPeer alloc] initWithIdentifier:peerIdentifier
                                          name:peerName];
  [_peers setObject:peer
             forKey:peerIdentifier];

  // Unlock.
  pthread_mutex_unlock(&_mutex);

  // Fire the peerAvailabilityChanged event.
  OnMainThread(^{
      [JXcore callEventCallback:kPeerAvailabilityChanged
                       withJSON:[peer JSON]];
  });
}

// Notifies the delegate that a peer was disconnected.
- (void)peerBluetooth:(THEPeerBluetooth *)peerBluetooth
didDisconnectPeerIdentifier:(NSString *)peerIdentifier
{
}

@end


// THEAppContext (Internal) implementation.
@implementation THEAppContext (Internal)

// Class initializer.
- (instancetype)init
{
  // Initialize superclass.
  self = [super init];
    
  // Handle errors.
  if (!self)
  {
    return nil;
  }
    
  // Intialize.
  _atomicFlagCommunicationsEnabled = [[THEAtomicFlag alloc] init];
    
  // Allocate and initialize the service type
  //NSUUID * serviceType = [[NSUUID alloc] initWithUUIDString:@"72D83A8B-9BE7-474B-8D2E-556653063A5B"];
    
  // Static declarations.
  static NSString * const PEER_IDENTIFIER_KEY = @"PeerIdentifierKey";
    
  // Retrieve or create a persistent peerIdentifier
  NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
  NSString * peerIdentifier = [userDefaults stringForKey:PEER_IDENTIFIER_KEY];
  if (!peerIdentifier)
  {
    // Create a new peer identifier - UUID is as good as any.
    peerIdentifier = [[NSUUID UUID] UUIDString];
    [userDefaults setValue:peerIdentifier forKey:PEER_IDENTIFIER_KEY];
    [userDefaults synchronize];
  }
    
  // Allocate and initialize the peer Bluetooth context.
  //_peerBluetooth = [[THEPeerBluetooth alloc] initWithServiceType:serviceType
  //                                                peerIdentifier:peerIdentifier
  //                                                      peerName:[[UIDevice currentDevice] name]];
  //[_peerBluetooth setDelegate:(id<THEPeerBluetoothDelegate>)self];
    
  // Allocate and initialize peer networking.
  _multipeerSession = [[THEMultipeerSession alloc] 
                                         initWithServiceType:@"Thali"
                                              peerIdentifier:peerIdentifier
                                                    peerName:[[UIDevice currentDevice] name]];

  [_multipeerSession setDelegate:(id<THEMultipeerSessionDelegate>)self];
    
  // Initialize the the mutex and peers dictionary.
  pthread_mutex_init(&_mutex, NULL);

  // Get the default notification center.
  NSNotificationCenter * notificationCenter = [NSNotificationCenter defaultCenter];
    
  // Add our observers for application events.
  [notificationCenter addObserver:self
                         selector:@selector(applicationWillResignActiveNotification:)
                             name:UIApplicationWillResignActiveNotification
                           object:nil];

  [notificationCenter addObserver:self
                         selector:@selector(applicationDidBecomeActiveNotification:)
                             name:UIApplicationDidBecomeActiveNotification
                           object:nil];

    // Done.
  return self;
}

// Fires the network changed event.
- (void)fireNetworkChangedEvent
{
    // Construct the JSON for the networkChanged event.
    NSString * json;
    if ([[NPReachability sharedInstance] isCurrentlyReachable])
    {
        json = [NSString stringWithFormat:@"{ \"isReachable\": %@, \"isWiFi\": %@ }",
                @"true",
                ([[NPReachability sharedInstance] currentReachabilityFlags] & kSCNetworkReachabilityFlagsIsWWAN) == 0 ? @"true" : @"false"];
    }
    else
    {
        json = @"{ \"isReachable\": false }";
    }

    // Fire the networkChanged event.
    OnMainThread(^{
        [JXcore callEventCallback:@"networkChanged"
                         withJSON:json];
    });
}

// UIApplicationWillResignActiveNotification callback.
- (void)applicationWillResignActiveNotification:(NSNotification *)notification
{
    [JXcore callEventCallback:@"appEnteringBackground"
                   withParams:@[]];
}

// UIApplicationDidBecomeActiveNotification callback.
- (void)applicationDidBecomeActiveNotification:(NSNotification *)notification
{
    [JXcore callEventCallback:@"appEnteredForeground"
                   withParams:@[]];
}

@end
