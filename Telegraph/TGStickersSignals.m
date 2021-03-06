#import "TGStickersSignals.h"

#import "TGTelegramNetworking.h"
#import "TL/TLMetaScheme.h"

#import <LegacyComponents/TGStickerAssociation.h>
#import "TGFavoriteStickersSignal.h"
#import "TGRecentStickersSignal.h"

#import "TGDocumentMediaAttachment+Telegraph.h"
#import "TGMediaOriginInfo+Telegraph.h"

#import "TGAppDelegate.h"

#import "TGPreparedLocalDocumentMessage.h"
#import "TGRemoteFileSignal.h"

#import "TGImageInfo+Telegraph.h"
#import "TGTelegraph.h"

#import "TLRPCmessages_searchStickerSets.h"

#import <libkern/OSAtomic.h>

static bool alreadyReloadedStickerPacksFromRemote = false;
static bool alreadyReloadedFeaturedPacksFromRemote = false;

static NSDictionary *cachedPacks = nil;
static OSSpinLock cachedPacksLock = 0;


@implementation TGStickersSignals

+ (int32_t)hashForStickerPacks:(NSArray *)stickerPacks {
    uint32_t acc = 0;
    
    for (TGStickerPack *pack in stickerPacks) {
        if (!pack.hidden) {
            acc = (acc * 20261) + pack.packHash;
        }
    }
    return acc % 0x7FFFFFFF;
}

+ (SSignal *)updateStickerPacks
{
    return [[SSignal single:nil] mapToSignal:^SSignal *(__unused id next)
    {
        SSignal *signal = [SSignal complete];
        
        int cacheInvalidationTimeout = 60 * 60;
#ifdef DEBUG
        //cacheInvalidationTimeout = 10;
#endif
        
        NSDictionary *cachedPacks = [self cachedStickerPacks];
        int currentTime = (int)[[NSDate date] timeIntervalSince1970];
        if (cachedPacks == nil || currentTime > [cachedPacks[@"cacheUpdateDate"] intValue] + cacheInvalidationTimeout || !alreadyReloadedStickerPacksFromRemote)
        {
            signal = [self remoteStickerPacksWithCacheHash:[self hashForStickerPacks:cachedPacks[@"packs"]]];
        }
        else
        {
            int delay = cacheInvalidationTimeout - (currentTime - [cachedPacks[@"cacheUpdateDate"] intValue]);
            signal = [[self remoteStickerPacksWithCacheHash:[self hashForStickerPacks:cachedPacks[@"packs"]]] delay:delay onQueue:[SQueue concurrentDefaultQueue]];
        }
        alreadyReloadedStickerPacksFromRemote = true;
        
        SSignal *periodicFetchSignal = [[[SSignal single:nil] mapToSignal:^SSignal *(__unused id next)
        {
            NSDictionary *cachedPacks = [self cachedStickerPacks];
            return [self remoteStickerPacksWithCacheHash:[self hashForStickerPacks:cachedPacks[@"packs"]]];
        }] catch:^SSignal *(__unused id error) {
            return [SSignal complete];
        }];
        
        signal = [signal then:[[periodicFetchSignal delay:cacheInvalidationTimeout onQueue:[SQueue concurrentDefaultQueue]] restart]];
        
        return signal;
    }];
}

+ (SSignal *)updateFeaturedStickerPacks
{
    return [[SSignal single:nil] mapToSignal:^SSignal *(__unused id next)
    {
        SSignal *signal = [SSignal complete];
        
        int cacheInvalidationTimeout = 60 * 60;
#ifdef DEBUG
        //cacheInvalidationTimeout = 10;
#endif
        
        NSDictionary *cachedPacks = [self cachedStickerPacks];
        int currentTime = (int)[[NSDate date] timeIntervalSince1970];
        if (cachedPacks == nil || currentTime > [cachedPacks[@"featuredCacheUpdateDate"] intValue] + cacheInvalidationTimeout || !alreadyReloadedFeaturedPacksFromRemote)
        {
            signal = [self remoteFeaturedPacksWithCacheHash:[self hashForStickerPacks:cachedPacks[@"featuredPacks"]]];
        }
        else
        {
            int delay = cacheInvalidationTimeout - (currentTime - [cachedPacks[@"featuredCacheUpdateDate"] intValue]);
            signal = [[self remoteFeaturedPacksWithCacheHash:[self hashForStickerPacks:cachedPacks[@"featuredPacks"]]] delay:delay onQueue:[SQueue concurrentDefaultQueue]];
        }
        alreadyReloadedFeaturedPacksFromRemote = true;
        
        SSignal *periodicFetchSignal = [[[SSignal single:nil] mapToSignal:^SSignal *(__unused id next)
        {
            NSDictionary *cachedPacks = [self cachedStickerPacks];
            return [self remoteFeaturedPacksWithCacheHash:[self hashForStickerPacks:cachedPacks[@"featuredPacks"]]];
        }] catch:^SSignal *(__unused id error) {
            return [SSignal complete];
        }];
        
        signal = [signal then:[[periodicFetchSignal delay:cacheInvalidationTimeout onQueue:[SQueue concurrentDefaultQueue]] restart]];
        
        return signal;
    }];
}

+ (void)updateShowStickerButtonModeForStickerPacks:(NSArray *)__unused stickerPacks
{
//    for (TGStickerPack *stickerPack in stickerPacks)
//    {
//        bool isExternalPack = true;
//        if ([stickerPack.packReference isKindOfClass:[TGStickerPackBuiltinReference class]])
//            isExternalPack = false;
//        
//        if ([stickerPack.packReference isKindOfClass:[TGStickerPackIdReference class]])
//        {
//            TGStickerPackIdReference *reference = (TGStickerPackIdReference *)stickerPack.packReference;
//            if (reference.shortName.length == 0)
//                isExternalPack = false;
//        }
//        
//        if (true || isExternalPack)
//        {
//            if (TGAppDelegateInstance.alwaysShowStickersMode == 0)
//            {
//                TGAppDelegateInstance.alwaysShowStickersMode = 2;
//                [TGAppDelegateInstance saveSettings];
//            }
//            
//            break;
//        }
//    }
    
    if (TGAppDelegateInstance.alwaysShowStickersMode == 0)
    {
        TGAppDelegateInstance.alwaysShowStickersMode = 2;
        [TGAppDelegateInstance saveSettings];
    }
}

+ (bool)isStickerPackInstalled:(id<TGStickerPackReference>)packReference
{
    NSString *packShortname = [self stickerPackShortName:packReference];
    
    for (TGStickerPack *pack in [self cachedStickerPacks][@"packs"])
    {
        if ([pack.packReference isEqual:packReference]) {
            return true;
        }
        
        if ([pack.packReference isKindOfClass:[TGStickerPackIdReference class]] && [packReference isKindOfClass:[TGStickerPackIdReference class]]) {
            if (((TGStickerPackIdReference *)pack.packReference).packId == ((TGStickerPackIdReference *)packReference).packId) {
                return true;
            }
        }
        
        if (packShortname.length != 0 && TGStringCompare(packShortname, [self stickerPackShortName:pack.packReference])) {
            return true;
        }
    }
    return false;
}

+ (NSString *)stickerPackShortName:(id<TGStickerPackReference>)packReference {
    if ([packReference isKindOfClass:[TGStickerPackShortnameReference class]]) {
        return ((TGStickerPackShortnameReference *)packReference).shortName;
    } else {
        for (TGStickerPack *pack in [self cachedStickerPacks][@"packs"])
        {
            if ([pack.packReference isEqual:packReference]) {
                if ([pack.packReference isKindOfClass:[TGStickerPackIdReference class]]) {
                    return ((TGStickerPackIdReference *)pack.packReference).shortName;
                }
            }
        }
    }
    
    return nil;
}

+ (NSMutableDictionary *)useCountFromOrderedReferences:(NSArray *)orderedReferences
{
    NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
    
    int distance = 1;
    int useCount = distance;
    
    for (id<TGStickerPackReference> reference in orderedReferences.reverseObjectEnumerator)
    {
        if ([reference isKindOfClass:[TGStickerPackIdReference class]])
        {
            result[@(((TGStickerPackIdReference *)reference).packId)] = @(useCount);
            useCount += distance;
        }
    }
    
    return result;
}

+ (void)forceUpdateStickers {
    [[[TGTelegramNetworking instance] genericTasksSignalManager] startStandaloneSignalIfNotRunningForKey:@"forceUpdateStickers" producer:^SSignal *{
        return [[self remoteStickerPacksWithCacheHash:0] onNext:^(NSDictionary *dict) {
            [[[TGTelegramNetworking instance] genericTasksSignalManager] putNext:dict toMulticastedPipeForKey:@"stickerPacks"];
        }];
    }];
}

+ (void)dispatchStickers {
    [[[TGTelegramNetworking instance] genericTasksSignalManager] putNext:[self cachedStickerPacks] toMulticastedPipeForKey:@"stickerPacks"];
}

+ (SSignal *)stickerPacks
{
    return [[SSignal single:nil] mapToSignal:^SSignal *(__unused id defer)
    {
        [[[TGTelegramNetworking instance] genericTasksSignalManager] startStandaloneSignalIfNotRunningForKey:@"updateStickers" producer:^SSignal *
        {
            return [[self updateStickerPacks] onNext:^(NSDictionary *dict)
            {
                [self updateShowStickerButtonModeForStickerPacks:dict[@"packs"]];
                
                [[[TGTelegramNetworking instance] genericTasksSignalManager] putNext:dict toMulticastedPipeForKey:@"stickerPacks"];
            }];
        }];
        
        SSignal *signal = [SSignal single:@{@"packs": @[]}];
     
        NSDictionary *cachedPacks = [self cachedStickerPacks];
        if (cachedPacks.count != 0)
            signal = [SSignal single:cachedPacks];

        signal = [signal then:[[[TGTelegramNetworking instance] genericTasksSignalManager] multicastedPipeForKey:@"stickerPacks"]];
        
        return signal;
    }];
}

+ (NSString *)filePath {
    return [[TGAppDelegate documentsPath] stringByAppendingPathComponent:@"stickerPacks.data"];
}

+ (NSData *)loadPacksData {
    NSData *data = [NSData dataWithContentsOfFile:[self filePath]];
    if (data == nil) {
        data = [[NSUserDefaults standardUserDefaults] objectForKey:@"TG_stickerPacks"];
        if (![data writeToFile:[self filePath] atomically:true]) {
            TGLog(@"***** TGStickersSignalsClass loadPacksData couldn't write to file");
        } else {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"TG_stickerPacks"];
        }
    }
    return data;
}

+ (void)storePacksData:(NSData *)data {
    if (![data writeToFile:[self filePath] atomically:true]) {
        TGLog(@"***** TGStickersSignalsClass storePacksData couldn't write to file");
    }
}

+ (void)clearCache
{
    OSSpinLockLock(&cachedPacksLock);
    cachedPacks = nil;
    OSSpinLockUnlock(&cachedPacksLock);
    [[NSFileManager defaultManager] removeItemAtPath:[self filePath] error:nil];
    alreadyReloadedStickerPacksFromRemote = false;
}

+ (NSDictionary *)cachedStickerPacks
{
    OSSpinLockLock(&cachedPacksLock);
    NSDictionary *loadedFromCachePacks = cachedPacks;
    OSSpinLockUnlock(&cachedPacksLock);
    if (loadedFromCachePacks != nil) {
        return loadedFromCachePacks;
    }
    
    NSData *cachedStickerPacksData = [self loadPacksData];
    if (cachedStickerPacksData == nil)
        return nil;
    
    NSDictionary *dict = nil;
    @try
    {
        dict = [NSKeyedUnarchiver unarchiveObjectWithData:cachedStickerPacksData];
    }
    @catch (__unused NSException *e)
    {
    }
    
    if (dict == nil)
        return nil;
    
    if ([dict[@"packs"] isKindOfClass:[NSArray class]])
    {
        NSArray *cachedPacks = dict[@"packs"];

        NSMutableIndexSet *legacyStickerPacksIndexes = [[NSMutableIndexSet alloc] init];
        [cachedPacks enumerateObjectsUsingBlock:^(TGStickerPack *stickerPack, NSUInteger index, __unused BOOL * stop)
        {
            if ([stickerPack.packReference isKindOfClass:[TGStickerPackBuiltinReference class]])
                [legacyStickerPacksIndexes addIndex:index];
        }];
        
        if (legacyStickerPacksIndexes.count > 0)
        {
            NSMutableArray *filteredPacks = [cachedPacks mutableCopy];
            [filteredPacks removeObjectsAtIndexes:legacyStickerPacksIndexes];
         
            NSMutableDictionary *updatedDict = [[NSMutableDictionary alloc] initWithDictionary:dict];
            updatedDict[@"packs"] = filteredPacks;
            dict = updatedDict;
            
            NSData *data = [NSKeyedArchiver archivedDataWithRootObject:dict];
            [self storePacksData:data];
        }
    }
    
    OSSpinLockLock(&cachedPacksLock);
    cachedPacks = dict;
    OSSpinLockUnlock(&cachedPacksLock);
    
    return dict;
}

+ (void)replaceCacheUpdateDate:(int32_t)cacheUpdateDate
{
    NSDictionary *currentDict = [self cachedStickerPacks];
    if (currentDict != nil)
    {
        NSMutableDictionary *newDict = [[NSMutableDictionary alloc] initWithDictionary:currentDict];
        newDict[@"cacheUpdateDate"] = @(cacheUpdateDate);
        
        OSSpinLockLock(&cachedPacksLock);
        cachedPacks = newDict;
        OSSpinLockUnlock(&cachedPacksLock);
        
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:newDict];
        [self storePacksData:data];
    }
}

+ (NSDictionary *)replaceCachedStickerPacks:(NSArray *)stickerPacks cacheUpdateDate:(int32_t)cacheUpdateDate
{
    NSDictionary *currentDict = [self cachedStickerPacks];
    NSDictionary *newDict = nil;
    if (currentDict.count == 0)
    {
        NSMutableArray *orderedReferences = [[NSMutableArray alloc] init];
        for (TGStickerPack *stickerPack in stickerPacks)
        {
            [orderedReferences addObject:stickerPack.packReference];
        }
        newDict = @{@"packs": stickerPacks, @"cacheUpdateDate": @(cacheUpdateDate), @"documentIdsUseCount": @{}};
    }
    else
    {
        NSMutableSet *documentIds = [[NSMutableSet alloc] init];
        
        for (TGStickerPack *stickerPack in stickerPacks)
        {
            for (TGDocumentMediaAttachment *document in stickerPack.documents)
            {
                [documentIds addObject:@(document.documentId)];
            }
        }
        
        NSMutableDictionary *documentIdsUseCount = [[NSMutableDictionary alloc] initWithDictionary:currentDict[@"documentIdsUseCount"]];
        NSMutableArray *removedDocumentIds = [[NSMutableArray alloc] init];
        for (NSNumber *nDocumentId in documentIdsUseCount.allKeys)
        {
            if (![documentIds containsObject:nDocumentId])
                [removedDocumentIds addObject:nDocumentId];
        }
        [documentIdsUseCount removeObjectsForKeys:removedDocumentIds];
        
        NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:currentDict];
        dict[@"packs"] = stickerPacks;
        dict[@"cacheUpdateDate"] = @(cacheUpdateDate);
        dict[@"documentIdsUseCount"] = documentIdsUseCount;
        newDict = dict;
    }
    
    OSSpinLockLock(&cachedPacksLock);
    cachedPacks = newDict;
    OSSpinLockUnlock(&cachedPacksLock);
    
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:newDict];
    [self storePacksData:data];
    
    return newDict;
}

+ (void)replaceFeaturedCacheUpdateDate:(int32_t)cacheUpdateDate
{
    NSDictionary *currentDict = [self cachedStickerPacks];
    if (currentDict != nil)
    {
        NSMutableDictionary *newDict = [[NSMutableDictionary alloc] initWithDictionary:currentDict];
        newDict[@"featuredCacheUpdateDate"] = @(cacheUpdateDate);
        
        OSSpinLockLock(&cachedPacksLock);
        cachedPacks = newDict;
        OSSpinLockUnlock(&cachedPacksLock);
        
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:newDict];
        [self storePacksData:data];
    }
}

+ (void)replaceFeaturedUnreadPackIds:(NSArray *)unreadPackIds
{
    NSDictionary *currentDict = [self cachedStickerPacks];
    if (currentDict != nil)
    {
        NSMutableDictionary *newDict = [[NSMutableDictionary alloc] initWithDictionary:currentDict];
        newDict[@"featuredPacksUnreadIds"] = unreadPackIds;
        
        OSSpinLockLock(&cachedPacksLock);
        cachedPacks = newDict;
        OSSpinLockUnlock(&cachedPacksLock);
        
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:newDict];
        [self storePacksData:data];
    }
}

+ (NSDictionary *)replaceArchivedStickerPacksSummary:(TGArchivedStickerPacksSummary *)summary
{
    NSDictionary *currentDict = [self cachedStickerPacks];
    if (currentDict != nil)
    {
        NSMutableDictionary *newDict = [[NSMutableDictionary alloc] initWithDictionary:currentDict];
        if (!TGObjectCompare(newDict[@"archivedPacksSummary"], summary)) {
            if (summary != nil) {
                newDict[@"archivedPacksSummary"] = summary;
            } else {
                [newDict removeObjectForKey:@"archivedPacksSummary"];
            }
            
            OSSpinLockLock(&cachedPacksLock);
            cachedPacks = newDict;
            OSSpinLockUnlock(&cachedPacksLock);
            
            NSData *data = [NSKeyedArchiver archivedDataWithRootObject:newDict];
            [self storePacksData:data];
            
            return newDict;
        }
    }
    return nil;
}

+ (NSDictionary *)replaceCachedFeaturedPacks:(NSArray *)stickerPacks unreadPackIds:(NSArray *)unreadPackIds cacheUpdateDate:(int32_t)cacheUpdateDate
{
    NSDictionary *currentDict = [self cachedStickerPacks];
    NSDictionary *newDict = nil;
    if (currentDict.count == 0)
    {
        NSMutableArray *orderedReferences = [[NSMutableArray alloc] init];
        for (TGStickerPack *stickerPack in stickerPacks)
        {
            [orderedReferences addObject:stickerPack.packReference];
        }
        newDict = @{@"featuredPacks": stickerPacks, @"featuredCacheUpdateDate": @(cacheUpdateDate), @"featuredPacksUnreadIds": unreadPackIds, @"documentIdsUseCount": @{}};
    }
    else
    {
        NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:currentDict];
        dict[@"featuredPacks"] = stickerPacks;
        dict[@"featuredCacheUpdateDate"] = @(cacheUpdateDate);
        dict[@"featuredPacksUnreadIds"] = unreadPackIds;
        newDict = dict;
    }
    
    OSSpinLockLock(&cachedPacksLock);
    cachedPacks = newDict;
    OSSpinLockUnlock(&cachedPacksLock);
    
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:newDict];
    [self storePacksData:data];
    
    return newDict;
}

+ (void)addUseCountForDocumentId:(int64_t)documentId
{
    NSDictionary *dict = [self cachedStickerPacks];
    if (dict == nil)
        return;
    
    bool found = false;
    int64_t packId = 0;
    for (TGStickerPack *stickerPack in dict[@"packs"])
    {
        for (TGDocumentMediaAttachment *document in stickerPack.documents)
        {
            if (document.documentId == documentId)
            {
                if ([stickerPack.packReference isKindOfClass:[TGStickerPackIdReference class]])
                    packId = ((TGStickerPackIdReference *)stickerPack.packReference).packId;
                
                found = true;
                break;
            }
        }
    }
    
    if (found)
    {
        NSMutableDictionary *updatedDict = [[NSMutableDictionary alloc] initWithDictionary: dict];
        NSNumber *nextUseCount = dict[@"maxDocumentIdsUseCount_v2"];
        if (nextUseCount == nil) {
            __block NSInteger maxUseCount = 0;
            [dict[@"documentIdsUseCount"] enumerateKeysAndObjectsUsingBlock:^(__unused id key, NSNumber *nUseCount, __unused BOOL *stop) {
                maxUseCount = MAX(maxUseCount, [nUseCount integerValue]);
            }];
            nextUseCount = @(maxUseCount);
        }
        NSMutableDictionary *updatedDocumentIdsUseCount = [[NSMutableDictionary alloc] initWithDictionary:dict[@"documentIdsUseCount"]];
        updatedDocumentIdsUseCount[@(documentId)] = @([nextUseCount intValue] + 1);
        updatedDict[@"maxDocumentIdsUseCount_v2"] = @([nextUseCount intValue] + 2);
        
        updatedDict[@"documentIdsUseCount"] = updatedDocumentIdsUseCount;
        
        OSSpinLockLock(&cachedPacksLock);
        cachedPacks = updatedDict;
        OSSpinLockUnlock(&cachedPacksLock);
        
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:updatedDict];
        [self storePacksData:data];
    }
}

+ (SSignal *)remoteStickerPacksWithCacheHash:(int32_t)cacheHash
{
    TLRPCmessages_getAllStickers$messages_getAllStickers *getAllStickers = [[TLRPCmessages_getAllStickers$messages_getAllStickers alloc] init];
    getAllStickers.n_hash = cacheHash;
    
    SSignal *allStickers = [[[TGTelegramNetworking instance] requestSignal:getAllStickers] mapToSignal:^SSignal *(TLmessages_AllStickers *result)
    {
        if ([result isKindOfClass:[TLmessages_AllStickers$messages_allStickers class]])
        {
            TLmessages_AllStickers$messages_allStickers *allStickers = (TLmessages_AllStickers$messages_allStickers *)result;
            
            NSMutableDictionary *currentStickerPacks = [self cachedStickerPacks][@"packs"];
            
            NSMutableArray *resultingPackReferences = [[NSMutableArray alloc] init];
            NSMutableArray *missingPackSignals = [[NSMutableArray alloc] init];
            
            for (TLStickerSet *resultPack in allStickers.sets)
            {
                TGStickerPackIdReference *resultPackReference = [[TGStickerPackIdReference alloc] initWithPackId:resultPack.n_id packAccessHash:resultPack.access_hash shortName:resultPack.short_name];
                
                TGStickerPack *currentPack = nil;
                for (TGStickerPack *pack in currentStickerPacks)
                {
                    if ([pack.packReference isEqual:resultPackReference])
                    {
                        currentPack = pack;
                        break;
                    }
                }
                
                if (currentPack == nil || currentPack.packHash != resultPack.n_hash || currentPack.installedDate == 0)
                    [missingPackSignals addObject:[self stickerPackInfo:resultPackReference packHash:resultPack.n_hash]];
                
                [resultingPackReferences addObject:resultPackReference];
            }
            
            return [[SSignal combineSignals:missingPackSignals] map:^id (NSArray *additionalPacks)
            {
                NSMutableArray *finalStickerPacks = [[NSMutableArray alloc] init];
                
                for (id<TGStickerPackReference> reference in resultingPackReferences)
                {
                    TGStickerPack *foundPack = nil;
                    
                    for (TGStickerPack *pack in additionalPacks)
                    {
                        if ([pack.packReference isEqual:reference])
                        {
                            foundPack = pack;
                            break;
                        }
                    }
                    
                    if (foundPack == nil)
                    {
                        for (TGStickerPack *pack in currentStickerPacks)
                        {
                            if ([pack.packReference isEqual:reference])
                            {
                                foundPack = pack;
                                break;
                            }
                        }
                    }
                    
                    if (foundPack != nil)
                        [finalStickerPacks addObject:foundPack];
                }
                
                
                
                NSDictionary *result = [self replaceCachedStickerPacks:finalStickerPacks cacheUpdateDate:(int32_t)[[NSDate date] timeIntervalSince1970]];
                return result;
            }];
        }
        
        [self replaceCacheUpdateDate:(int32_t)[[NSDate date] timeIntervalSince1970]];
        
        return [SSignal single:[NSNull null]];
    }];
    
    TLRPCmessages_getArchivedStickers$messages_getArchivedStickers *getArchivedStickers = [[TLRPCmessages_getArchivedStickers$messages_getArchivedStickers alloc] init];
    getArchivedStickers.offset_id = 0;
    getArchivedStickers.limit = 1;
    
    SSignal *archivedStickers = [[[TGTelegramNetworking instance] requestSignal:getArchivedStickers] mapToSignal:^SSignal *(TLmessages_ArchivedStickers *result) {
        TGArchivedStickerPacksSummary *summary = [[TGArchivedStickerPacksSummary alloc] initWithCount:result.count];
        NSDictionary *dict = [self replaceArchivedStickerPacksSummary:summary];
        
        if (dict != nil) {
            return [SSignal single:dict];
        }
        
        return [SSignal single:[NSNull null]];
    }];
    
    return [[SSignal combineSignals:@[allStickers, archivedStickers]] mapToSignal:^SSignal *(NSArray *values) {
        if (![values[1] isEqual:[NSNull null]]) {
            return [SSignal single:values[1]];
        } else if (![values[0] isEqual:[NSNull null]]) {
            return [SSignal single:values[0]];
        } else {
            return [SSignal complete];
        }
    }];
}

+ (SSignal *)remoteFeaturedPacksWithCacheHash:(int32_t)cacheHash
{
#ifdef DEBUG
    cacheHash = 0;
#endif
    TLRPCmessages_getFeaturedStickers$messages_getFeaturedStickers *getFeaturedStickers = [[TLRPCmessages_getFeaturedStickers$messages_getFeaturedStickers alloc] init];
    
    getFeaturedStickers.n_hash = cacheHash;
    
    return [[[TGTelegramNetworking instance] requestSignal:getFeaturedStickers] mapToSignal:^SSignal *(TLmessages_FeaturedStickers *result)
    {
        if ([result isKindOfClass:[TLmessages_FeaturedStickers$messages_featuredStickers class]])
        {
            TLmessages_FeaturedStickers$messages_featuredStickers *allStickers = (TLmessages_FeaturedStickers$messages_featuredStickers *)result;
            
            NSMutableDictionary *currentStickerPacks = [self cachedStickerPacks][@"featuredPacks"];
            
            NSMutableArray *resultingPackReferences = [[NSMutableArray alloc] init];
            NSMutableArray *missingPackSignals = [[NSMutableArray alloc] init];
            
            for (TLStickerSetCovered *resultPackCovered in allStickers.sets)
            {
                TLStickerSet *resultPack = resultPackCovered.set;
                TGStickerPackIdReference *resultPackReference = [[TGStickerPackIdReference alloc] initWithPackId:resultPack.n_id packAccessHash:resultPack.access_hash shortName:resultPack.short_name];
                
                TGStickerPack *currentPack = nil;
                for (TGStickerPack *pack in currentStickerPacks)
                {
                    if ([pack.packReference isEqual:resultPackReference])
                    {
                        currentPack = pack;
                        break;
                    }
                }
                
                if (currentPack == nil || currentPack.packHash != resultPack.n_hash)
                    [missingPackSignals addObject:[self stickerPackInfo:resultPackReference packHash:resultPack.n_hash featured:true]];
                
                [resultingPackReferences addObject:resultPackReference];
            }
            
            return [[SSignal combineSignals:missingPackSignals] map:^id (NSArray *additionalPacks)
            {
                NSMutableArray *finalStickerPacks = [[NSMutableArray alloc] init];
                
                for (id<TGStickerPackReference> reference in resultingPackReferences)
                {
                    TGStickerPack *foundPack = nil;
                    
                    for (TGStickerPack *pack in additionalPacks)
                    {
                        if ([pack.packReference isEqual:reference])
                        {
                            foundPack = pack;
                            break;
                        }
                    }
                    
                    if (foundPack == nil)
                    {
                        for (TGStickerPack *pack in currentStickerPacks)
                        {
                            if ([pack.packReference isEqual:reference])
                            {
                                foundPack = pack;
                                break;
                            }
                        }
                    }
                    
                    if (foundPack != nil)
                        [finalStickerPacks addObject:foundPack];
                }
                
                NSMutableArray *unreadPackIds = [[NSMutableArray alloc] init];
                for (NSNumber *nPackId in allStickers.unread) {
                    [unreadPackIds addObject:nPackId];
                }
                
                NSDictionary *result = [self replaceCachedFeaturedPacks:finalStickerPacks unreadPackIds:unreadPackIds cacheUpdateDate:(int32_t)[[NSDate date] timeIntervalSince1970]];
                return result;
            }];
        }
        
        [self replaceFeaturedCacheUpdateDate:(int32_t)[[NSDate date] timeIntervalSince1970]];
        
        return [SSignal complete];
    }];
}

+ (TLInputStickerSet *)_inputStickerSetFromPackReference:(id<TGStickerPackReference>)packReference
{
    if ([packReference isKindOfClass:[TGStickerPackIdReference class]])
    {
        TLInputStickerSet$inputStickerSetID *concreteId = [[TLInputStickerSet$inputStickerSetID alloc] init];;
        concreteId.n_id = ((TGStickerPackIdReference *)packReference).packId;
        concreteId.access_hash = ((TGStickerPackIdReference *)packReference).packAccessHash;
        return concreteId;
    }
    else if ([packReference isKindOfClass:[TGStickerPackShortnameReference class]])
    {
        TLInputStickerSet$inputStickerSetShortName *concreteId = [[TLInputStickerSet$inputStickerSetShortName alloc] init];
        concreteId.short_name = ((TGStickerPackShortnameReference *)packReference).shortName;
        return concreteId;
    }
    
    return [[TLInputStickerSet$inputStickerSetEmpty alloc] init];
}

+ (SSignal *)remoteStickersForEmoticon:(NSString *)emoticon
{
    if (emoticon.length == 0)
        return [SSignal single:@[]];
    
    SSignal *cachedSignal = [SSignal defer:^SSignal *{
        return [SSignal single:[TGDatabaseInstance() remoteStickersForEmoticon:emoticon]];
    }];
    
    SSignal *(^remoteSignal)(int32_t) = ^SSignal *(int32_t hash) {
        TLRPCmessages_getStickers$messages_getStickers *getStickers = [[TLRPCmessages_getStickers$messages_getStickers alloc] init];
        getStickers.emoticon = emoticon;
        getStickers.n_hash = hash;
        return [[[TGTelegramNetworking instance] requestSignal:getStickers] mapToSignal:^SSignal *(TLmessages_Stickers *result)
        {
            if ([result isKindOfClass:[TLmessages_Stickers$messages_stickers class]]) {
                TLmessages_Stickers$messages_stickers *concreteResult = (TLmessages_Stickers$messages_stickers *)result;
                
                NSMutableArray *documents = [[NSMutableArray alloc] init];
                for (TLDocument *resultDocument in concreteResult.stickers) {
                    TGDocumentMediaAttachment *document = [[TGDocumentMediaAttachment alloc] initWithTelegraphDocumentDesc:resultDocument];
                    if (document.documentId != 0)
                        [documents addObject:document];
                }
                
                [TGDatabaseInstance() storeRemoteStickers:documents forEmoticon:emoticon hash:concreteResult.n_hash];
                
                return [SSignal single:documents];
            }
            else {
                return [SSignal complete];
            }
        }];
    };
    
    return [cachedSignal mapToSignal:^SSignal *(TGCachedStickers *cachedStickers) {
        if (cachedStickers.documents.count > 0) {
            return [[SSignal single:cachedStickers.documents] then:remoteSignal(cachedStickers.stickersHash)];
        } else {
            return [[SSignal single:nil] then:remoteSignal(0)];
        }
    }];
}

+ (SSignal *)stickerPackInfo:(id<TGStickerPackReference>)packReference
{
    return [self stickerPackInfo:packReference packHash:0];
}

+ (SSignal *)stickerPackInfo:(id<TGStickerPackReference>)packReference packHash:(int32_t)packHash
{
    return [self stickerPackInfo:packReference packHash:packHash featured:false];
}

+ (SSignal *)stickerPackInfo:(id<TGStickerPackReference>)packReference packHash:(int32_t)packHash featured:(bool)featured
{
    TLRPCmessages_getStickerSet$messages_getStickerSet *getStickerSet = [[TLRPCmessages_getStickerSet$messages_getStickerSet alloc] init];
    getStickerSet.stickerset = [self _inputStickerSetFromPackReference:packReference];
    return [[[TGTelegramNetworking instance] requestSignal:getStickerSet] map:^id (TLmessages_StickerSet *result)
    {
        TGStickerPackIdReference *resultPackReference = [[TGStickerPackIdReference alloc] initWithPackId:result.set.n_id packAccessHash:result.set.access_hash shortName:result.set.short_name];
        
        NSMutableArray *stickerAssociations = [[NSMutableArray alloc] init];
        for (TLStickerPack *resultAssociation in result.packs)
        {
            TGStickerAssociation *association = [[TGStickerAssociation alloc] initWithKey:resultAssociation.emoticon documentIds:resultAssociation.documents];
            [stickerAssociations addObject:association];
        }

        NSMutableArray *documents = [[NSMutableArray alloc] init];
        for (TLDocument *resultDocument in result.documents)
        {
            TGDocumentMediaAttachment *document = [[TGDocumentMediaAttachment alloc] initWithTelegraphDocumentDesc:resultDocument];
            if ([packReference isKindOfClass:[TGStickerPackIdReference class]])
            {
                int64_t stickerPackId = ((TGStickerPackIdReference *)packReference).packId;
                int64_t stickerPackAccessHash = ((TGStickerPackIdReference *)packReference).packAccessHash;
                document.originInfo = [TGMediaOriginInfo mediaOriginInfoForDocument:resultDocument stickerPackId:stickerPackId stickerPackAccessHash:stickerPackAccessHash];
            }
            if (document.documentId != 0)
                [documents addObject:document];
        }
        
        return [[TGStickerPack alloc] initWithPackReference:resultPackReference title:result.set.title stickerAssociations:stickerAssociations documents:documents packHash:packHash hidden:(result.set.flags & (1 << 1)) isMask:(result.set.flags & (1 << 3)) isFeatured:featured installedDate:result.set.installed_date];
    }];
}

+ (SSignal *)installStickerPackAndGetArchived:(id<TGStickerPackReference>)packReference {
    return [self installStickerPackAndGetArchived:packReference hintUnarchive:false];
}

+ (SSignal *)installStickerPackAndGetArchived:(id<TGStickerPackReference>)packReference hintUnarchive:(bool)hintUnarchive
{
    TLRPCmessages_installStickerSet$messages_installStickerSet *installStickerSet = [[TLRPCmessages_installStickerSet$messages_installStickerSet alloc] init];
    installStickerSet.stickerset = [self _inputStickerSetFromPackReference:packReference];
    
    return [[[TGTelegramNetworking instance] requestSignal:installStickerSet] mapToSignal:^SSignal *(TLmessages_StickerSetInstallResult *result) {
        return [[self stickerPackInfo:packReference] mapToSignal:^SSignal *(TGStickerPack *pack) {
            NSMutableDictionary *updatedDict = [[NSMutableDictionary alloc] initWithDictionary:[self cachedStickerPacks]];
            
            NSMutableArray *packs = [[NSMutableArray alloc] initWithArray:updatedDict[@"packs"]];
            bool found = false;
            for (TGStickerPack *existingPack in packs) {
                if ([existingPack.packReference isEqual:pack.packReference]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                [packs insertObject:pack atIndex:0];
            }
            updatedDict[@"packs"] = packs;
            
            int addedArchivedCount = 0;
            if ([result isKindOfClass:[TLmessages_StickerSetInstallResult$messages_stickerSetInstallResultArchive class]]) {
                TLmessages_StickerSetInstallResult$messages_stickerSetInstallResultArchive *concreteResult = (TLmessages_StickerSetInstallResult$messages_stickerSetInstallResultArchive *)result;
                addedArchivedCount = (int)concreteResult.sets.count;
            }
            
            TGArchivedStickerPacksSummary *summary = [[TGArchivedStickerPacksSummary alloc] initWithCount:((TGArchivedStickerPacksSummary *)updatedDict[@"archivedPacksSummary"]).count + (hintUnarchive ? -1 : 0) + addedArchivedCount];
            updatedDict[@"archivedPacksSummary"] = summary;
            
            OSSpinLockLock(&cachedPacksLock);
            cachedPacks = updatedDict;
            OSSpinLockUnlock(&cachedPacksLock);
            
            [self updateShowStickerButtonModeForStickerPacks:updatedDict[@"packs"]];
            
            [[[TGTelegramNetworking instance] genericTasksSignalManager] putNext:updatedDict toMulticastedPipeForKey:@"stickerPacks"];
            
            NSData *data = [NSKeyedArchiver archivedDataWithRootObject:updatedDict];
            [self storePacksData:data];
            
            if ([result isKindOfClass:[TLmessages_StickerSetInstallResult$messages_stickerSetInstallResultArchive class]]) {
                TLmessages_StickerSetInstallResult$messages_stickerSetInstallResultArchive *concreteResult = (TLmessages_StickerSetInstallResult$messages_stickerSetInstallResultArchive *)result;
                
                NSMutableArray *resultingPackReferences = [[NSMutableArray alloc] init];
                NSMutableArray *missingPackSignals = [[NSMutableArray alloc] init];
                
                for (TLStickerSet *resultPack in concreteResult.sets)
                {
                    TGStickerPackIdReference *resultPackReference = [[TGStickerPackIdReference alloc] initWithPackId:resultPack.n_id packAccessHash:resultPack.access_hash shortName:resultPack.short_name];
                    [missingPackSignals addObject:[self stickerPackInfo:resultPackReference packHash:resultPack.n_hash]];
                    
                    [resultingPackReferences addObject:resultPackReference];
                }
                
                return [[SSignal combineSignals:missingPackSignals] map:^id (NSArray *additionalPacks) {
                    NSMutableArray *finalStickerPacks = [[NSMutableArray alloc] init];
                    
                    for (id<TGStickerPackReference> reference in resultingPackReferences) {
                        TGStickerPack *foundPack = nil;
                        
                        for (TGStickerPack *pack in additionalPacks)
                        {
                            if ([pack.packReference isEqual:reference])
                            {
                                foundPack = pack;
                                break;
                            }
                        }
                        
                        if (foundPack != nil)
                            [finalStickerPacks addObject:foundPack];
                    }
                    return finalStickerPacks;
                }];
            } else {
                return [SSignal single:@[]];
            }
        }];
    }];
}

+ (SSignal *)removeStickerPack:(id<TGStickerPackReference>)packReference hintArchived:(bool)hintArchived
{
    TLRPCmessages_uninstallStickerSet$messages_uninstallStickerSet *uninstallStickerSet = [[TLRPCmessages_uninstallStickerSet$messages_uninstallStickerSet alloc] init];
    uninstallStickerSet.stickerset = [self _inputStickerSetFromPackReference:packReference];
    
    return [[[TGTelegramNetworking instance] requestSignal:uninstallStickerSet] mapToSignal:^SSignal *(id __unused result) {
        NSMutableDictionary *updatedDict = [[NSMutableDictionary alloc] initWithDictionary:[self cachedStickerPacks]];
        
        NSMutableArray *packs = [[NSMutableArray alloc] initWithArray:updatedDict[@"packs"]];
        NSInteger index = -1;
        for (TGStickerPack *pack in packs) {
            index++;
            if ([pack.packReference isEqual:packReference]) {
                [packs removeObjectAtIndex:index];
                break;
            }
        }
        updatedDict[@"packs"] = packs;
        
        int addedArchivedCount = hintArchived ? -1 : 0;
        
        TGArchivedStickerPacksSummary *summary = [[TGArchivedStickerPacksSummary alloc] initWithCount:MAX(0, (int)((TGArchivedStickerPacksSummary *)updatedDict[@"archivedPacksSummary"]).count + addedArchivedCount)];
        updatedDict[@"archivedPacksSummary"] = summary;
        
        OSSpinLockLock(&cachedPacksLock);
        cachedPacks = updatedDict;
        OSSpinLockUnlock(&cachedPacksLock);
        
        [self updateShowStickerButtonModeForStickerPacks:updatedDict[@"packs"]];
        
        [[[TGTelegramNetworking instance] genericTasksSignalManager] putNext:updatedDict toMulticastedPipeForKey:@"stickerPacks"];
        
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:updatedDict];
        [self storePacksData:data];
        
        return [SSignal complete];
    }];
}

+ (SSignal *)toggleStickerPackHidden:(id<TGStickerPackReference>)packReference hidden:(bool)hidden
{
    if (!hidden) {
        return [self installStickerPackAndGetArchived:packReference hintUnarchive:true];
    }
    
    TLRPCmessages_installStickerSet$messages_installStickerSet *installStickerSet = [[TLRPCmessages_installStickerSet$messages_installStickerSet alloc] init];
    installStickerSet.stickerset = [self _inputStickerSetFromPackReference:packReference];
    installStickerSet.archived = hidden;
    
    return [[[[TGTelegramNetworking instance] requestSignal:installStickerSet] mapToSignal:^SSignal *(__unused id result) {
        return [SSignal complete];
    }] afterCompletion:^{
        NSMutableDictionary *updatedDict = [[NSMutableDictionary alloc] initWithDictionary:[self cachedStickerPacks]];
        
        NSMutableArray *updatedPacks = [[NSMutableArray alloc] initWithArray:updatedDict[@"packs"]];
        
        if (hidden) {
            NSInteger index = -1;
            for (TGStickerPack *pack in updatedPacks) {
                index++;
                
                if (TGObjectCompare(pack.packReference, packReference)) {
                    [updatedPacks removeObjectAtIndex:index];
                    break;
                }
            }
        }
        updatedDict[@"packs"] = updatedPacks;
        
        TGArchivedStickerPacksSummary *summary = [[TGArchivedStickerPacksSummary alloc] initWithCount:MAX(0, (int)((TGArchivedStickerPacksSummary *)updatedDict[@"archivedPacksSummary"]).count + (hidden ? 1 : -1))];
        updatedDict[@"archivedPacksSummary"] = summary;
        
        OSSpinLockLock(&cachedPacksLock);
        cachedPacks = updatedDict;
        OSSpinLockUnlock(&cachedPacksLock);
        
        [self updateShowStickerButtonModeForStickerPacks:updatedDict[@"packs"]];
        
        [[[TGTelegramNetworking instance] genericTasksSignalManager] putNext:updatedDict toMulticastedPipeForKey:@"stickerPacks"];
        
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:updatedDict];
        [self storePacksData:data];
    }];
}

+ (SSignal *)reorderStickerPacks:(NSArray *)packReferences {
    TLRPCmessages_reorderStickerSets$messages_reorderStickerSets *reorderStickerSets = [[TLRPCmessages_reorderStickerSets$messages_reorderStickerSets alloc] init];
    NSMutableArray *order = [[NSMutableArray alloc] init];
    
    for (id<TGStickerPackReference> reference in packReferences) {
        if ([reference isKindOfClass:[TGStickerPackIdReference class]]) {
            [order addObject:@(((TGStickerPackIdReference *)reference).packId)];
        }
    }
    
    reorderStickerSets.order = order;
    
    return [[[TGTelegramNetworking instance] requestSignal:reorderStickerSets] afterCompletion:^{
        NSMutableDictionary *updatedDict = [[NSMutableDictionary alloc] initWithDictionary:[self cachedStickerPacks]];
        
        NSMutableArray *packs = [[NSMutableArray alloc] init];
        NSMutableString *packOrderString = [[NSMutableString alloc] init];
        for (id<TGStickerPackReference> packReference in packReferences) {
            for (TGStickerPack *pack in updatedDict[@"packs"]) {
                if (TGObjectCompare(pack.packReference, packReference)) {
                    [packs addObject:pack];
                    if ([pack.packReference isKindOfClass:[TGStickerPackIdReference class]]) {
                        if (packOrderString.length != 0) {
                            [packOrderString appendString:@", "];
                        }
                        [packOrderString appendFormat:@"%lld", ((TGStickerPackIdReference *)pack.packReference).packId];
                    }
                    break;
                }
            }
        }
        updatedDict[@"packs"] = packs;
        
        OSSpinLockLock(&cachedPacksLock);
        cachedPacks = updatedDict;
        OSSpinLockUnlock(&cachedPacksLock);
        
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:updatedDict];
        [self storePacksData:data];
        
        [[[TGTelegramNetworking instance] genericTasksSignalManager] putNext:updatedDict toMulticastedPipeForKey:@"stickerPacks"];
    }];
}

+ (void)remoteAddedStickerPack:(TGStickerPack *)stickerPack {
    NSMutableDictionary *updatedDict = [[NSMutableDictionary alloc] initWithDictionary:[self cachedStickerPacks]];
    
    bool found = false;
    for (TGStickerPack *pack in updatedDict[@"packs"]) {
        if (TGObjectCompare(pack.packReference, stickerPack)) {
            found = true;
            break;
        }
    }
    
    if (!found) {
        NSMutableArray *updatedPacks = [[NSMutableArray alloc] initWithArray:updatedDict[@"packs"]];
        [updatedPacks insertObject:stickerPack atIndex:0];
        updatedDict[@"packs"] = updatedPacks;
        
        OSSpinLockLock(&cachedPacksLock);
        cachedPacks = updatedDict;
        OSSpinLockUnlock(&cachedPacksLock);
        
        [[[TGTelegramNetworking instance] genericTasksSignalManager] putNext:updatedDict toMulticastedPipeForKey:@"stickerPacks"];
    }
}

+ (void)remoteReorderedStickerPacks:(NSArray *)updatedOrder {
    NSMutableDictionary *updatedDict = [[NSMutableDictionary alloc] initWithDictionary:[self cachedStickerPacks]];
    
    NSMutableArray *allPacks = [[NSMutableArray alloc] initWithArray:updatedDict[@"packs"]];
    NSMutableArray *updatedPacks = [[NSMutableArray alloc] init];
    
    for (NSNumber *nPackId in updatedOrder) {
        NSInteger index = -1;
        for (TGStickerPack *pack in allPacks) {
            index++;
            
            if ([pack.packReference isKindOfClass:[TGStickerPackIdReference class]] && ((TGStickerPackIdReference *)pack.packReference).packId == [nPackId longLongValue]) {
                [updatedPacks addObject:pack];
                [allPacks removeObjectAtIndex:index];
                break;
            }
        }
    }
    
    [updatedPacks addObjectsFromArray:allPacks];
    
    updatedDict[@"packs"] = updatedPacks;
    
    OSSpinLockLock(&cachedPacksLock);
    cachedPacks = updatedDict;
    OSSpinLockUnlock(&cachedPacksLock);
    
    [[[TGTelegramNetworking instance] genericTasksSignalManager] putNext:updatedDict toMulticastedPipeForKey:@"stickerPacks"];
}

+ (SSignal *)preloadedStickerPreviews:(NSDictionary *)dictionary count:(NSUInteger)count
{
    NSArray *documents = dictionary[@"documents"];

    return [[SSignal single:nil] mapToSignal:^SSignal *(__unused id next)
    {
        SSignal *signal = [SSignal complete];
        
        for (NSUInteger i = 0; i < count && i < documents.count; i++)
        {
            TGDocumentMediaAttachment *document = documents[i];
            
            NSString *directory = [TGPreparedLocalDocumentMessage localDocumentDirectoryForDocumentId:document.documentId version:document.version];
            [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:true attributes:nil error:NULL];
            
            NSString *path = [directory stringByAppendingPathComponent:@"thumbnail-high"];
            
            NSString *thumbnailUrl = [document.thumbnailInfo imageUrlForLargestSize:NULL];
            int32_t datacenterId = 0;
            int64_t volumeId = 0;
            int32_t localId = 0;
            int64_t secret = 0;
            if (extractFileUrlComponents(thumbnailUrl, &datacenterId, &volumeId, &localId, &secret))
            {
                if (![[NSFileManager defaultManager] fileExistsAtPath:path])
                {
                    TLInputFileLocation$inputFileLocation *location = [[TLInputFileLocation$inputFileLocation alloc] init];
                    location.volume_id = volumeId;
                    location.local_id = localId;
                    location.secret = secret;
                    location.file_reference = [document.originInfo fileReferenceForVolumeId:volumeId localId:localId];
                    
                    SSignal *downloadSignal = [[TGRemoteFileSignal dataForLocation:location datacenterId:datacenterId originInfo:document.originInfo identifier:document.documentId size:0 reportProgress:false mediaTypeTag:TGNetworkMediaTypeTagDocument] onNext:^(id next)
                    {
                        if ([next isKindOfClass:[NSData class]])
                        {
                            TGLog(@"preloaded sticker preview to %@", path);
                            [(NSData *)next writeToFile:path atomically:true];
                        }
                    }];
                    
                    signal = [signal then:downloadSignal];
                }
            }
        }
        
        return [[signal reduceLeft:nil with:^id(__unused id current, __unused id next)
        {
            return current;
        }] then:[SSignal single:dictionary]];
    }];
}

+ (SSignal *)updatedFeaturedStickerPacks {
    return [[[TGTelegramNetworking instance] genericTasksSignalManager] multicastedSignalForKey:@"updateFeaturedStickers" producer:^SSignal *{
        return [[self updateFeaturedStickerPacks] onNext:^(NSDictionary *dict) {
            [[[TGTelegramNetworking instance] genericTasksSignalManager] putNext:dict toMulticastedPipeForKey:@"stickerPacks"];
        }];
    }];
}

+ (SSignal *)readRemoteFeaturedStickerPacks {
    TLRPCmessages_readFeaturedStickers$messages_readFeaturedStickers *readFeaturedStickers = [[TLRPCmessages_readFeaturedStickers$messages_readFeaturedStickers alloc] init];
    return [[TGTelegramNetworking instance] requestSignal:readFeaturedStickers];
}

+ (SSignal *)readRemoteFeaturedStickerPacks:(NSArray *)packIds {
    if (packIds.count != 0) {
        TLRPCmessages_readFeaturedStickers$messages_readFeaturedStickers *readFeaturedStickers = [[TLRPCmessages_readFeaturedStickers$messages_readFeaturedStickers alloc] init];
        readFeaturedStickers.n_id = packIds;
        return [[TGTelegramNetworking instance] requestSignal:readFeaturedStickers];
    } else {
        return [SSignal complete];
    }
}

+ (void)markFeaturedStickersAsRead {
    [[[TGTelegramNetworking instance] genericTasksSignalManager] startStandaloneSignalIfNotRunningForKey:@"markFeaturedStickersAsRead" producer:^SSignal *
    {
        return [[SSignal defer:^SSignal *{
            NSArray *featuredPacksUnreadIds = [self cachedStickerPacks][@"featuredPacksUnreadIds"];
            if (featuredPacksUnreadIds.count != 0) {
                [self replaceFeaturedUnreadPackIds:@[]];
                [self dispatchStickers];
                return [self readRemoteFeaturedStickerPacks];
            } else {
                return [SSignal fail:@true];
            }
        }] restart];
    }];
}

+ (void)markFeaturedStickerPackAsRead:(NSArray *)packIds {
    [[SQueue concurrentDefaultQueue] dispatch:^{
        if (packIds.count != 0) {
            NSArray *featuredPacksUnreadIds = [self cachedStickerPacks][@"featuredPacksUnreadIds"];
            if (featuredPacksUnreadIds.count != 0) {
                NSMutableArray *updatedFeaturedPacksUnreadIds = [[NSMutableArray alloc] initWithArray:featuredPacksUnreadIds];
                [updatedFeaturedPacksUnreadIds removeObjectsInArray:packIds];
                if (updatedFeaturedPacksUnreadIds.count != featuredPacksUnreadIds.count) {
                    [self replaceFeaturedUnreadPackIds:updatedFeaturedPacksUnreadIds];
                    [self dispatchStickers];
                    [TGTelegraphInstance.disposeOnLogout add:[[self readRemoteFeaturedStickerPacks:packIds] startWithNext:nil]];
                }
            }
        }
    }];
}

+ (SSignal *)archivedStickerPacksWithOffsetId:(int64_t)offsetId limit:(NSUInteger)limit {
    TLRPCmessages_getArchivedStickers$messages_getArchivedStickers *getArchivedStickers = [[TLRPCmessages_getArchivedStickers$messages_getArchivedStickers alloc] init];
    getArchivedStickers.offset_id = offsetId;
    getArchivedStickers.limit = (int32_t)limit;
    
    return [[[TGTelegramNetworking instance] requestSignal:getArchivedStickers] mapToSignal:^SSignal *(TLmessages_ArchivedStickers *result) {
        NSDictionary *dict = [self replaceArchivedStickerPacksSummary:[[TGArchivedStickerPacksSummary alloc] initWithCount:result.count]];
        
        if (dict != nil) {
            [[[TGTelegramNetworking instance] genericTasksSignalManager] putNext:dict toMulticastedPipeForKey:@"stickerPacks"];
        }
        
        NSMutableArray *resultingPackReferences = [[NSMutableArray alloc] init];
        NSMutableArray *missingPackSignals = [[NSMutableArray alloc] init];
        
        for (TLStickerSetCovered *resultPackCovered in result.sets)
        {
            TGStickerPackIdReference *resultPackReference = [[TGStickerPackIdReference alloc] initWithPackId:resultPackCovered.set.n_id packAccessHash:resultPackCovered.set.access_hash shortName:resultPackCovered.set.short_name];
            [missingPackSignals addObject:[self stickerPackInfo:resultPackReference packHash:resultPackCovered.set.n_hash]];
            
            [resultingPackReferences addObject:resultPackReference];
        }
        
        return [[SSignal combineSignals:missingPackSignals] map:^id (NSArray *additionalPacks) {
            NSMutableArray *finalStickerPacks = [[NSMutableArray alloc] init];
            
            for (id<TGStickerPackReference> reference in resultingPackReferences) {
                TGStickerPack *foundPack = nil;
                
                for (TGStickerPack *pack in additionalPacks)
                {
                    if ([pack.packReference isEqual:reference])
                    {
                        foundPack = pack;
                        break;
                    }
                }
                
                if (foundPack != nil)
                    [finalStickerPacks addObject:foundPack];
            }
            return finalStickerPacks;
        }];
    }];
    
    return nil;
}

+ (SSignal *)cachedStickerPack:(id<TGStickerPackReference>)packReference {
    if (packReference == nil)
        return [SSignal single:nil];
    
    SSignal *cachedSignal = [SSignal defer:^SSignal *{
        if ([packReference isKindOfClass:[TGStickerPackIdReference class]]) {
            TGStickerPackIdReference *packIdReference = (TGStickerPackIdReference *)packReference;
            TGCachedStickerPack *cachedStickerPack = [TGDatabaseInstance() stickerPackForReference:packIdReference];
            
            int32_t expirationTimestamp = cachedStickerPack.date + 60 * 60;
            if (CFAbsoluteTimeGetCurrent() < expirationTimestamp)
                return [SSignal single:cachedStickerPack.stickerPack];
        }
        
        return [SSignal fail:nil];
    }];
    
    return [cachedSignal catch:^SSignal *(__unused id error) {
        return [[self stickerPackInfo:packReference] onNext:^(TGStickerPack *next) {
            [TGDatabaseInstance() storeStickerPack:next forReference:next.packReference];
        }];
    }];
}

+ (void)updateStickerPack:(TGStickerPack *)stickerPack
{
    NSDictionary *currentDict = [self cachedStickerPacks];
    if (currentDict.count == 0)
        return;
    
    NSArray *stickerPacks = currentDict[@"packs"];
    __block NSUInteger index = NSNotFound;
    [stickerPacks enumerateObjectsUsingBlock:^(TGStickerPack *pack, NSUInteger idx, BOOL * _Nonnull stop)
    {
        if ([stickerPack.packReference isEqual:pack.packReference])
        {
            index = idx;
            *stop = true;
        }
    }];
    
    if (index == NSNotFound)
        return;

    NSMutableArray *newStickerPacks = [stickerPacks mutableCopy];
    [newStickerPacks replaceObjectAtIndex:index withObject:stickerPack];
    
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:currentDict];
    dict[@"packs"] = newStickerPacks;
    
    OSSpinLockLock(&cachedPacksLock);
    cachedPacks = dict;
    OSSpinLockUnlock(&cachedPacksLock);
    
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:dict];
    [self storePacksData:data];
}

+ (NSMutableDictionary<NSString *, NSArray *> *)stickerPackNameParts {
    static NSMutableDictionary<NSString *, NSArray *> *dictionary;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^ {
        dictionary = [[NSMutableDictionary alloc] init];
    });
    return dictionary;
}

static NSArray *breakStringIntoParts(NSString *string)
{
    NSMutableArray *parts = [[NSMutableArray alloc] initWithCapacity:2];
    string = [string stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    [string enumerateSubstringsInRange:NSMakeRange(0, string.length) options:NSStringEnumerationByWords usingBlock:^(NSString *substring, __unused NSRange substringRange, __unused NSRange enclosingRange, __unused BOOL *stop)
    {
        if (substring != nil)
            [parts addObject:[substring lowercaseString]];
    }];
    return parts;
}

+ (bool)stickerPack:(TGStickerPack *)stickerPack matchesQuery:(NSString *)query withParts:(NSArray *)parts
{
    if ([stickerPack.title isEqualToString:query])
        return true;
    
    NSArray *packNameParts = [self stickerPackNameParts][stickerPack.title];
    if (packNameParts == nil)
    {
        packNameParts = breakStringIntoParts(stickerPack.title);
        if ([stickerPack.packReference isKindOfClass:[TGStickerPackIdReference class]])
            packNameParts = [packNameParts arrayByAddingObjectsFromArray:breakStringIntoParts(((TGStickerPackIdReference *)stickerPack.packReference).shortName)];
        [self stickerPackNameParts][stickerPack.title] = packNameParts;
    }
    
    bool failed = true;
    
    bool everyPartMatches = true;
    for (NSString *queryPart in parts)
    {
        bool hasMatches = false;
        for (NSString *testPart in packNameParts)
        {
            if ([testPart hasPrefix:queryPart])
            {
                hasMatches = true;
                break;
            }
        }
        
        if (!hasMatches)
        {
            everyPartMatches = false;
            break;
        }
    }
    if (everyPartMatches)
        failed = false;
    
    return !failed;
}

+ (SSignal *)searchStickersWithQuery:(NSString *)query {
    NSString *lowercaseQuery = [[query lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    SSignal *localSearch = [[[self stickerPacks] take:1] map:^id(NSDictionary *result)
    {
        NSArray *parts = breakStringIntoParts(lowercaseQuery);
        if (parts.count == 0)
            return @{ @"local": @[] };
        
        NSArray *stickerPacks = result[@"packs"];
        NSMutableArray *matchingPacks = [[NSMutableArray alloc] init];
        for (TGStickerPack *pack in stickerPacks) {
            if ([self stickerPack:pack matchesQuery:lowercaseQuery withParts:parts])
                [matchingPacks addObject:pack];
        }
        
        return @{ @"local": matchingPacks };
    }];
    
    TLRPCmessages_searchStickerSets *searchStickerSets = [[TLRPCmessages_searchStickerSets alloc] init];
    searchStickerSets.q = query;
    
    SSignal *(^remoteSignal)(NSArray *) = ^(NSArray *localResults)
    {
        return [[[TGTelegramNetworking instance] requestSignal:searchStickerSets] mapToSignal:^SSignal *(TLmessages_FoundStickerSets *result)
        {
            NSMutableArray *resultingPackReferences = [[NSMutableArray alloc] init];
            NSMutableArray *missingPackSignals = [[NSMutableArray alloc] init];
            
            NSMutableDictionary *currentStickerPacks = [self cachedStickerPacks][@"featuredPacks"];
            
            if ([result isKindOfClass:[TLmessages_FoundStickerSets$messages_foundStickerSets class]])
            {
                TLmessages_FoundStickerSets$messages_foundStickerSets *stickerSets = (TLmessages_FoundStickerSets$messages_foundStickerSets *)result;
   
                for (TLStickerSetCovered *resultPackCovered in stickerSets.sets)
                {
                    TLStickerSet *resultPack = resultPackCovered.set;
                    TGStickerPackIdReference *resultPackReference = [[TGStickerPackIdReference alloc] initWithPackId:resultPack.n_id packAccessHash:resultPack.access_hash shortName:resultPack.short_name];
                    
                    TGStickerPack *currentPack = nil;
                    for (TGStickerPack *pack in currentStickerPacks)
                    {
                        if ([pack.packReference isEqual:resultPackReference])
                        {
                            currentPack = pack;
                            break;
                        }
                    }
                    
                    if (currentPack == nil)
                        currentPack = [TGDatabaseInstance() stickerPackForReference:resultPackReference].stickerPack;
                    
                    if (currentPack == nil || currentPack.packHash != resultPack.n_hash)
                        [missingPackSignals addObject:[self stickerPackInfo:resultPackReference packHash:resultPack.n_hash featured:true]];
                    
                    [resultingPackReferences addObject:resultPackReference];
                }
                
                return [[SSignal combineSignals:missingPackSignals] map:^id (NSArray *additionalPacks)
                {
                    NSMutableArray *finalStickerPacks = [[NSMutableArray alloc] init];
                    
                    for (TGStickerPack *pack in additionalPacks)
                    {
                        [TGDatabaseInstance() storeStickerPack:pack forReference:pack.packReference];
                    }
                    
                    for (id<TGStickerPackReference> reference in resultingPackReferences)
                    {
                        TGStickerPack *foundPack = nil;
                        
                        for (TGStickerPack *pack in additionalPacks)
                        {
                            if ([pack.packReference isEqual:reference])
                            {
                                foundPack = pack;
                                break;
                            }
                        }
                        
                        if (foundPack == nil)
                        {
                            for (TGStickerPack *pack in currentStickerPacks)
                            {
                                if ([pack.packReference isEqual:reference])
                                {
                                    foundPack = pack;
                                    break;
                                }
                            }
                        }
                        
                        if (foundPack != nil)
                            [finalStickerPacks addObject:foundPack];
                    }
                    
                    return @{@"local": localResults, @"remote": finalStickerPacks};
                }];
            }
            else
            {
                return [SSignal complete];
            }
        }];
    };
    
    return [localSearch mapToSignal:^SSignal *(NSDictionary *result) {
        return [[SSignal single:result] then:[[[SSignal complete] delay:0.5 onQueue:[SQueue concurrentDefaultQueue]] then:remoteSignal(result[@"local"])]];
    }];
}

+ (SSignal *)stickersForEmojis:(NSArray *)emojis includeRemote:(bool)includeRemote updateRemoteCached:(bool)updateRemoteCached
{
    NSMutableArray *signals = [[NSMutableArray alloc] init];
    [signals addObject:[[TGStickersSignals stickerPacks] take:1]];
    [signals addObject:[[TGFavoriteStickersSignal favoriteStickers] take:1]];
    [signals addObject:[[TGRecentStickersSignal recentStickers] take:1]];
    
    return [[SSignal combineSignals:signals] mapToSignal:^SSignal *(NSArray *results)
    {
        NSDictionary *dict = results[0];
        NSArray *favoriteStickers = results[1];
        NSDictionary *recentDict = results[2];
    
        NSMutableDictionary<NSString *, NSMutableSet *> *addedDocumentIds = [[NSMutableDictionary alloc] init];
        for (NSString *emoji in emojis) {
            addedDocumentIds[emoji] = [[NSMutableSet alloc] init];
        }
        NSMutableDictionary<NSString *, NSMutableSet *> *matchedRecentDocumentIds = [[NSMutableDictionary alloc] init];
        for (NSString *emoji in emojis) {
            matchedRecentDocumentIds[emoji] = [[NSMutableSet alloc] init];
        }
        NSMutableDictionary<NSString *, NSMutableArray *> *matchedRecentDocumentIdsSorted = [[NSMutableDictionary alloc] init];
        for (NSString *emoji in emojis) {
            matchedRecentDocumentIdsSorted[emoji] = [[NSMutableArray alloc] init];
        }
        
        NSMutableDictionary *maybeMatchedRecentDocuments = [[NSMutableDictionary alloc] init];
        
        NSMutableDictionary<NSString *, NSMutableArray *> *matchedRecentDocuments = [[NSMutableDictionary alloc] init];
        for (NSString *emoji in emojis) {
            matchedRecentDocuments[emoji] = [[NSMutableArray alloc] init];
        }
        
        NSMutableDictionary<NSString *, NSMutableArray *> *matchedFavoriteDocuments = [[NSMutableDictionary alloc] init];
        for (NSString *emoji in emojis) {
            matchedFavoriteDocuments[emoji] = [[NSMutableArray alloc] init];
        }
        
        NSMutableDictionary<NSString *, NSMutableArray *> *matchedAddedDocuments = [[NSMutableDictionary alloc] init];
        for (NSString *emoji in emojis) {
            matchedAddedDocuments[emoji] = [[NSMutableArray alloc] init];
        }
        
        NSMutableDictionary<NSString *, NSMutableArray *> *matchedOursDocuments = [[NSMutableDictionary alloc] init];
        for (NSString *emoji in emojis) {
            matchedOursDocuments[emoji] = [[NSMutableArray alloc] init];
        }
        
        NSMutableDictionary *associations = [[NSMutableDictionary alloc] init];
        NSMutableDictionary *stickerPacks = [[NSMutableDictionary alloc] init];
        NSMutableDictionary *stickerSortDates = [[NSMutableDictionary alloc] init];
        NSMutableDictionary *stickerPackSortDates = [[NSMutableDictionary alloc] init];
        
        [stickerSortDates addEntriesFromDictionary:recentDict[@"dates"]];
        
        for (TGDocumentMediaAttachment *document in recentDict[@"documents"]) {
            TGDocumentAttributeSticker *sticker = nil;
            for (id attribute in document.attributes) {
                if ([attribute isKindOfClass:[TGDocumentAttributeSticker class]]) {
                    sticker = (TGDocumentAttributeSticker *)attribute;
                    
                    for (NSString *emoji in emojis)
                    {
                        if ([sticker.alt isEqualToString:emoji]) {
                            maybeMatchedRecentDocuments[@(document.documentId)] = document;
                            [matchedRecentDocumentIds[emoji] addObject:@(document.documentId)];
                        }
                    }
                    break;
                }
            }
        }
        
        for (NSString *emoji in emojis)
        {
            NSMutableArray *sorted = [[NSMutableArray alloc] initWithArray:[matchedRecentDocumentIds[emoji] allObjects]];
            [sorted sortUsingComparator:^NSComparisonResult(NSNumber *obj1, NSNumber *obj2)
            {
                int32_t date1 = [stickerSortDates[obj1] int32Value];
                int32_t date2 = [stickerSortDates[obj2] int32Value];
                
                if (date1 > date2)
                    return NSOrderedAscending;
                else if (date1 < date2)
                    return NSOrderedDescending;
                else
                    return obj1.int64Value > obj2.int64Value ? NSOrderedAscending : NSOrderedDescending;
            }];
            
            sorted = [[sorted subarrayWithRange:NSMakeRange(0, MIN(5, (int)sorted.count))] mutableCopy];
            matchedRecentDocumentIds[emoji] = [NSMutableSet setWithArray:sorted];
            [addedDocumentIds[emoji] addObjectsFromArray:sorted];
            matchedRecentDocumentIdsSorted[emoji] = sorted;
        }
        
        NSMutableArray *stickerPacksToSearch = [[NSMutableArray alloc] init];
        NSMutableDictionary *stickerPacksMap = [[NSMutableDictionary alloc] init];
        
        for (TGStickerPack *stickerPack in dict[@"packs"]) {
            if ([stickerPack.packReference isKindOfClass:[TGStickerPackIdReference class]]) {
                [stickerPacksToSearch addObject:stickerPack];
                
                NSNumber *packId = @(((TGStickerPackIdReference *)stickerPack.packReference).packId);
                stickerPacksMap[packId] = stickerPack;
                
                if (stickerPackSortDates[packId] == nil)
                    stickerPackSortDates[packId] = @(stickerPack.installedDate > 0 ? stickerPack.installedDate : 10000 + arc4random_uniform(10000));
            }
        }
        
        NSMutableArray *unknownStickerPacks = [[NSMutableArray alloc] init];
        NSMutableSet *unknownStickerPackIds = [[NSMutableSet alloc] init];
        NSMutableSet *favoriteStickerIds = [[NSMutableSet alloc] init];
        int32_t favoriteIndex = 0;
        if (favoriteStickers.count > 0)
        {
            NSMutableSet *favoriteStickerPackIds = [[NSMutableSet alloc] init];
            for (TGDocumentMediaAttachment *document in favoriteStickers)
            {
                [favoriteStickerIds addObject:@(document.documentId)];
                
                if (stickerSortDates[@(document.documentId)] == nil)
                    stickerSortDates[@(document.documentId)] = @(INT32_MAX - favoriteIndex - 1);
                
                id<TGStickerPackReference> reference = document.stickerPackReference;
                if ([reference isKindOfClass:[TGStickerPackIdReference class]]) {
                    NSNumber *packId = @(((TGStickerPackIdReference *)reference).packId);
                    if ([favoriteStickerPackIds containsObject:packId])
                        continue;
                    
                    TGStickerPack *stickerPack = stickerPacksMap[packId];
                    if (stickerPack == nil && ![favoriteStickerPackIds containsObject:packId]) {
                        [unknownStickerPacks addObject:reference];
                        [unknownStickerPackIds addObject:packId];
                        [favoriteStickerPackIds addObject:packId];
                    }
                }
                
                favoriteIndex++;
            }
        }
        
        SSignal *packsSignal = [SSignal single:@[]];
        if (unknownStickerPacks.count > 0)
        {
            NSMutableArray *signals = [[NSMutableArray alloc] init];
            for (TGStickerPackIdReference *reference in unknownStickerPacks)
            {
                [signals addObject:[[TGStickersSignals cachedStickerPack:reference] catch:^SSignal *(__unused id error)
                {
                    return [SSignal single:[NSNull null]];
                }]];
            }
            packsSignal = [SSignal combineSignals:signals];
        }
        
        return [packsSignal mapToSignal:^SSignal *(NSArray *unknownStickerPacks) {
            for (TGStickerPack *stickerPack in unknownStickerPacks) {
                if (![stickerPack isKindOfClass:[TGStickerPack class]])
                    continue;
                
                if ([stickerPack.packReference isKindOfClass:[TGStickerPackIdReference class]]) {
                    [stickerPacksToSearch addObject:stickerPack];
                    
                    NSNumber *packId = @(((TGStickerPackIdReference *)stickerPack.packReference).packId);
                    stickerPacksMap[packId] = stickerPack;
                }
            }
            
            for (TGStickerPack *stickerPack in stickerPacksToSearch)
            {
                if (stickerPack.hidden)
                    continue;
                
                bool isUnknownStickerPack = [stickerPack.packReference isKindOfClass:[TGStickerPackIdReference class]] && [unknownStickerPackIds containsObject:@(((TGStickerPackIdReference *)stickerPack.packReference).packId)];
                
                NSMutableDictionary<NSString *, NSMutableArray *> *documentIds = [[NSMutableDictionary alloc] init];
                for (NSString *emoji in emojis) {
                    documentIds[emoji] = [[NSMutableArray alloc] init];
                }
                
                for (TGStickerAssociation *association in stickerPack.stickerAssociations)
                {
                    for (NSString *emoji in emojis)
                    {
                        if ([association.key isEqual:emoji])
                        {
                            for (NSNumber *documentId in association.documentIds)
                            {
                                if (!isUnknownStickerPack || [favoriteStickerIds containsObject:documentId])
                                {
                                    [documentIds[emoji] addObject:documentId];
                                    associations[documentId] = stickerPack.stickerAssociations;
                                    stickerPacks[documentId] = stickerPack;
                                }
                            }
                        }
                    }
                }
                
                for (NSString *emoji in emojis)
                {
                    for (NSNumber *nDocumentId in documentIds[emoji])
                    {
                        bool maybeRecent = [matchedRecentDocumentIds[emoji] containsObject:nDocumentId];
                        if ([addedDocumentIds[emoji] containsObject:nDocumentId] && !maybeRecent)
                            continue;
                        
                        for (TGDocumentMediaAttachment *document in stickerPack.documents)
                        {
                            if (document.documentId == [nDocumentId longLongValue])
                            {
                                if (maybeRecent) {
                                    maybeMatchedRecentDocuments[@(document.documentId)] = document;
                                    break;
                                } else {
                                    [addedDocumentIds[emoji] addObject:nDocumentId];
                                    if ([favoriteStickerIds containsObject:nDocumentId])
                                        [matchedFavoriteDocuments[emoji] addObject:document];
                                    else
                                        [matchedAddedDocuments[emoji] addObject:document];
                                    break;
                                }
                            }
                        }
                    }
                }
            }

            NSComparisonResult (^dateComparator)(TGDocumentMediaAttachment *, TGDocumentMediaAttachment *) = ^NSComparisonResult(TGDocumentMediaAttachment *obj1, TGDocumentMediaAttachment *obj2)
            {
                int32_t date1 = [stickerSortDates[@(obj1.documentId)] int32Value];
                if (date1 == 0) {
                    if ([obj1.stickerPackReference isKindOfClass:[TGStickerPackIdReference class]]) {
                        NSNumber *packId = @(((TGStickerPackIdReference *)obj1.stickerPackReference).packId);
                        date1 = [stickerPackSortDates[packId] int32Value];
                    }
                }
                int32_t date2 = [stickerSortDates[@(obj2.documentId)] int32Value];
                if (date2 == 0) {
                    if ([obj2.stickerPackReference isKindOfClass:[TGStickerPackIdReference class]]) {
                        NSNumber *packId = @(((TGStickerPackIdReference *)obj2.stickerPackReference).packId);
                        date2 = [stickerPackSortDates[packId] int32Value];
                    }
                }
                
                if (date1 > date2)
                    return NSOrderedAscending;
                else if (date1 < date2)
                    return NSOrderedDescending;
                else
                    return obj1.documentId > obj2.documentId ? NSOrderedAscending : NSOrderedDescending;
            };
            
            NSMutableArray *finalEmoji = [[NSMutableArray alloc] init];
            for (NSString *emoji in emojis)
            {
                NSMutableArray *finalDocuments = [[NSMutableArray alloc] init];

                [matchedAddedDocuments[emoji] sortUsingComparator:dateComparator];
                
                for (NSNumber *recentDocumentId in matchedRecentDocumentIdsSorted[emoji]) {
                    TGDocumentMediaAttachment *document = maybeMatchedRecentDocuments[recentDocumentId];
                    if (document != nil)
                        [matchedRecentDocuments[emoji] addObject:document];
                }
                
                [finalDocuments addObjectsFromArray:matchedRecentDocuments[emoji]];
                [finalDocuments addObjectsFromArray:matchedFavoriteDocuments[emoji]];
                [finalDocuments addObjectsFromArray:matchedAddedDocuments[emoji]];
                
                [finalEmoji addObject:@{ @"emoji": emoji, @"documents": finalDocuments }];
            }
            
            NSDictionary *result = @{ @"emojis": finalEmoji, @"associations": associations, @"stickerPacks": stickerPacks };
        
            if (includeRemote)
            {
                NSMutableArray *signals = [[NSMutableArray alloc] init];
                for (NSString *emoji in emojis)
                {
                    SSignal *signal = [TGStickersSignals remoteStickersForEmoticon:emoji];
                    if (!updateRemoteCached)
                    {
                        signal = [[signal filter:^bool(NSArray *stickers)
                        {
                            return stickers != nil;
                        }] take:1];
                    }
                    [signals addObject:signal];
                }
                
                SSignal *remoteSignal = [[SSignal combineSignals:signals] map:^id(NSArray *results)
                {
                    NSMutableArray *updatedEmoji = [[NSMutableArray alloc] init];
                    NSInteger i = 0;
                    for (NSDictionary *set in finalEmoji)
                    {
                        NSString *emoji = set[@"emoji"];
                        NSArray *additionalStickers = results[i];
                        i++;
                        
                        for (TGDocumentMediaAttachment *document in additionalStickers) {
                            if (stickerSortDates[@(document.documentId)] == nil)
                                stickerSortDates[@(document.documentId)] = @(arc4random_uniform(10000));
                            
                            if ([addedDocumentIds[emoji] containsObject:@(document.documentId)])
                                continue;
                            
                            [addedDocumentIds[emoji] addObject:@(document.documentId)];
                            [matchedOursDocuments[emoji] addObject:document];
                        }
                        
                         [matchedOursDocuments[emoji] sortUsingComparator:dateComparator];
                        
                        NSArray *updatedDocuments = [set[@"documents"] arrayByAddingObjectsFromArray:matchedOursDocuments[emoji]];
                        [updatedEmoji addObject:@{ @"emoji": emoji, @"documents": updatedDocuments }];
                    }
                    
                    return @{ @"emojis": updatedEmoji, @"associations": associations, @"stickerPacks": stickerPacks, @"final": @true };
                }];
                
                return [[SSignal single:result] then:remoteSignal];
            }
            else
            {
                return [SSignal single:result];
            }
        }];
        
        return nil;
    }];
}

@end

