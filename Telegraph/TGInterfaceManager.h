/*
 * This is the source code of Telegram for iOS v. 1.1
 * It is licensed under GNU GPL v. 2 or later.
 * You should have received a copy of the license in this archive (see LICENSE).
 *
 * Copyright Peter Iakovlev, 2013.
 */

#import <Foundation/Foundation.h>
#import <SSignalKit/SSignalKit.h>
#import <LegacyComponents/ActionStage.h>

@class TGMessage;
@class TGConversation;
@class TGModernConversationController;
@class TGNavigationController;
@class TGCallManager;

@interface TGInterfaceManager : NSObject <ASWatcher>

@property (nonatomic, strong) ASHandle *actionHandle;

+ (TGInterfaceManager *)instance;

- (void)preload;

- (void)navigateToConversationWithId:(int64_t)conversationId conversation:(TGConversation *)conversation;
- (void)navigateToConversationWithId:(int64_t)conversationId conversation:(TGConversation *)conversation animated:(bool)animated;
- (void)navigateToConversationWithId:(int64_t)conversationId conversation:(TGConversation *)conversation performActions:(NSDictionary *)performActions;
- (void)navigateToConversationWithId:(int64_t)conversationId conversation:(TGConversation *)conversation performActions:(NSDictionary *)performActions animated:(bool)animated;
- (void)navigateToConversationWithId:(int64_t)conversationId conversation:(TGConversation *)conversation performActions:(NSDictionary *)performActions atMessage:(NSDictionary *)atMessage clearStack:(bool)clearStack openKeyboard:(bool)openKeyboard canOpenKeyboardWhileInTransition:(bool)canOpenKeyboardWhileInTransition animated:(bool)animated;
- (void)navigateToConversationWithId:(int64_t)conversationId conversation:(TGConversation *)conversation performActions:(NSDictionary *)performActions atMessage:(NSDictionary *)atMessage clearStack:(bool)clearStack openKeyboard:(bool)openKeyboard canOpenKeyboardWhileInTransition:(bool)canOpenKeyboardWhileInTransition navigationController:(TGNavigationController *)navigationController animated:(bool)animated;
- (void)navigateToConversationWithId:(int64_t)conversationId conversation:(TGConversation *)__unused conversation performActions:(NSDictionary *)performActions atMessage:(NSDictionary *)atMessage clearStack:(bool)clearStack openKeyboard:(bool)openKeyboard canOpenKeyboardWhileInTransition:(bool)canOpenKeyboardWhileInTransition navigationController:(TGNavigationController *)navigationController selectChat:(bool)selectChat animated:(bool)animated;
- (void)navigateToChannelLogWithConversation:(TGConversation *)conversation animated:(bool)animated;
- (void)navigateToChannelsFeed:(int32_t)feedId animated:(bool)animated;
- (TGModernConversationController *)configuredPreviewConversationControlerWithId:(int64_t)conversationId;
- (TGModernConversationController *)configuredPreviewFeedControllerWithId:(int32_t)feedId;
- (TGModernConversationController *)configuredConversationControlerWithId:(int64_t)conversationId performActions:(NSDictionary *)performActions preview:(bool)preview;

- (TGModernConversationController *)currentControllerWithPeerId:(int64_t)peerId;
- (void)dismissConversation;
- (void)navigateToProfileOfUser:(int)uid preferNativeContactId:(int)preferNativeContactId;
- (void)navigateToProfileOfUser:(int)uid;
- (void)navigateToProfileOfUser:(int)uid shareVCard:(void (^)())shareVCard;
- (void)navigateToProfileOfUser:(int)uid encryptedConversationId:(int64_t)encryptedConversationId;
- (void)navigateToProfileOfUser:(int)uid callMessages:(NSArray *)callMessages;
- (void)navigateToSharedMediaOfConversationWithId:(int64_t)conversationId mode:(int)mode atMessage:(NSDictionary *)atMessage;

- (void)displayHashtagOverview:(NSString *)hashtag conversationId:(int64_t)conversationId;

- (void)displayBannerIfNeeded:(TGMessage *)message conversationId:(int64_t)conversationId;
- (void)dismissBannerForConversationId:(int64_t)conversationId;
- (void)dismissAllBanners;

- (void)localizationUpdated;

- (void)setupCallManager:(TGCallManager *)callManager;
- (void)callPeerWithId:(int64_t)peerId;
- (void)callPeerWithId:(int64_t)peerId completion:(void (^)(void))completion;
- (void)dismissAllCalls;
- (void)maybeDisplayCallsTabAlert;
- (bool)hasCallControllerInForeground;

- (SSignal *)callControllerInForeground;
- (SSignal *)messageVisibilitySignalWithConversationId:(int64_t)conversationId messageId:(int32_t)messageId peerId:(int64_t)peerId;

@end
