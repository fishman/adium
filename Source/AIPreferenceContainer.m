//
//  AIPreferenceContainer.m
//  Adium
//
//  Created by Evan Schoenberg on 1/8/08.
//

#import "AIPreferenceContainer.h"
#import "AIPreferenceController.h"
#import <Adium/AIListObject.h>
#import <Adium/AILoginControllerProtocol.h>
#import <AIUtilities/AIApplicationAdditions.h>
#import <AIUtilities/AIDictionaryAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <Adium/AIAccount.h>

@interface AIPreferenceContainer ()
- (id)initForGroup:(NSString *)inGroup object:(AIListObject *)inObject;
- (void)emptyCache:(NSTimer *)inTimer;
- (void)save;
@property (readonly, nonatomic) NSMutableDictionary *prefs;
- (void) loadGlobalPrefs;

//Lazily sets up our pref dict if needed
- (void) setPrefValue:(id)val forKey:(id)key;
@end

#define EMPTY_CACHE_DELAY		120.0
#define	SAVE_OBJECT_PREFS_DELAY	10.0

/* XXX Remove me */
#ifdef DEBUG_BUILD
	#define PREFERENCE_CONTAINER_DEBUG
#endif

static NSMutableDictionary	*objectPrefs = nil;
static NSInteger					usersOfObjectPrefs = 0;
static NSTimer				*timer_savingOfObjectCache = nil;

static NSMutableDictionary	*accountPrefs = nil;
static NSInteger					usersOfAccountPrefs = 0;
static NSTimer				*timer_savingOfAccountCache = nil;
	
/*!
 * @brief Preference Container
 *
 * A single AIPreferenceContainer instance provides read/write access preferences to a specific preference group, either
 * for the global preferences or for a specific object.  After EMPTY_CACHE_DELAY seconds, it releases its preferences from memory;
 * it will reload them from disk as needed when accessed again.
 *
 * All contacts share a single plist on-disk, loaded into a single mutable dictionary in-memory, objectPrefs.
 * All accounts share a single plist on-disk, loaded into a single mutable dictionary in-memory, accountPrefs.
 * These global dictionaries provide per-object preference dictionaries, keyed by the object's internalObjectID.
 *
 * Individual instances of AIPreferenceContainer make use of this shared store.  Saving of changes is batched for all changes made during a
 * SAVE_OBJECT_PREFS_DELAY interval across all instances of AIPreferenceContainer for a given global dictionary. Because creating
 * the data representation of a large dictionary and writing it out can be time-consuming (certainly less than a second, but still long
 * enough to cause a perceptible delay for a user actively typing or interacting with Adium), saving is performed on a thread.
 *
 * When no instances are currently making use of a global dictionary, it is removed from memory; it will be reloaded from disk as needed.
 */
@implementation AIPreferenceContainer

+ (AIPreferenceContainer *)preferenceContainerForGroup:(NSString *)inGroup object:(AIListObject *)inObject
{
	return [[[self alloc] initForGroup:inGroup object:inObject] autorelease];
}

+ (void)preferenceControllerWillClose
{
	//If a save of the object prefs is pending, perform it immediately since we are quitting
	if (timer_savingOfObjectCache) {
			[objectPrefs writeToPath:[adium.loginController userDirectory]
							withName:@"ByObjectPrefs"];
		/* There's no guarantee that 'will close' is called in the same run loop as the actual program termination.
		 * We've done our final save, though; don't let the timer fire again.
		 */
		[timer_savingOfObjectCache invalidate];
		[timer_savingOfObjectCache release]; timer_savingOfObjectCache = nil;
	}

	//If a save of the account prefs is pending, perform it immediately since we are quitting
	if (timer_savingOfAccountCache) {
		[accountPrefs writeToPath:[adium.loginController userDirectory]
						 withName:@"AccountPrefs"];
		/* There's no guarantee that 'will close' is called in the same run loop as the actual program termination.
		 * We've done our final save, though; don't let the timer fire again.
		 */		
		[timer_savingOfAccountCache invalidate];
		[timer_savingOfAccountCache release]; timer_savingOfObjectCache = nil;
	}
}

- (id)initForGroup:(NSString *)inGroup object:(AIListObject *)inObject
{
	if ((self = [super init])) {
		group = [inGroup retain];
		object = [inObject retain];
		if (object) {
			if ([object isKindOfClass:[AIAccount class]]) {
				myGlobalPrefs = &accountPrefs;
				myUsersOfGlobalPrefs = &usersOfAccountPrefs;
				myTimerForSavingGlobalPrefs = &timer_savingOfAccountCache;
				globalPrefsName = @"AccountPrefs";
				
			} else {
				myGlobalPrefs = &objectPrefs;
				myUsersOfGlobalPrefs = &usersOfObjectPrefs;
				myTimerForSavingGlobalPrefs = &timer_savingOfObjectCache;
				globalPrefsName = @"ByObjectPrefs";
			}
		}
	}

	return self;
}

- (void)dealloc
{
	[defaults release]; defaults = nil;
	[group release];
	[object release];
	[timer_clearingOfCache release]; timer_clearingOfCache = nil;
	[globalPrefsName release]; globalPrefsName = nil;

	[self emptyCache:nil];
	
	[super dealloc];
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)theKey
{
	return NO;
}

#pragma mark Cache

/*!
 * @brief Empty our cache
 */
- (void)emptyCache:(NSTimer *)inTimer
{
	if (object) {
		(*myUsersOfGlobalPrefs)--;
		
		[prefs release]; prefs = nil;
		[prefsWithDefaults release]; prefsWithDefaults = nil;
		
		if ((*myUsersOfGlobalPrefs) == 0) {
			NSLog(@"Clearing *myGlobalPrefs");
			[*myGlobalPrefs release]; *myGlobalPrefs = nil;
		}

	} else {
		[prefs release]; prefs = nil;
		[prefsWithDefaults release]; prefsWithDefaults = nil;
	}
	
	[timer_clearingOfCache release]; timer_clearingOfCache = nil;
}

/*!
 * @brief Queue clearing of the cache
 *
 * If this method isn't called again within 30 seconds, the passed key will be removed from the passed cache dictionary.
 */
- (void)queueClearingOfCache
{
	if (!timer_clearingOfCache) {
		timer_clearingOfCache = [[NSTimer scheduledTimerWithTimeInterval:EMPTY_CACHE_DELAY
																  target:self
																selector:@selector(emptyCache:)
																userInfo:nil
																 repeats:NO] retain];
	} else {
		[timer_clearingOfCache setFireDate:[NSDate dateWithTimeIntervalSinceNow:EMPTY_CACHE_DELAY]];
	}
}

#pragma mark Defaults

@synthesize defaults;

/*!
 * @brief Register defaults
 *
 * These defaults will be added to any existing defaults; if there is overlap between keys, the new key-value pair will be used.
 */
- (void)registerDefaults:(NSDictionary *)inDefaults
{
	if (!defaults) defaults = [[NSMutableDictionary alloc] init];
	
	[defaults addEntriesFromDictionary:inDefaults];
	
	//Clear the cached defaults dictionary so it will be recreated as needed
	[prefsWithDefaults release]; prefsWithDefaults = nil;
}

#pragma mark Get and set

- (void) loadGlobalPrefs
{
	NSAssert(*myGlobalPrefs == nil, @"Attempting to load global prefs when they're already loaded");
	NSString	*objectPrefsPath = [[adium.loginController.userDirectory stringByAppendingPathComponent:globalPrefsName] stringByAppendingPathExtension:@"plist"];
	NSString	*errorString = nil;
	NSError		*error = nil;
	NSData		*data = [NSData dataWithContentsOfFile:objectPrefsPath
										   options:NSUncachedRead
											 error:&error];
	
	if (error) {
		NSLog(@"Error reading data for preferences file %@: %@ (%@ %ld: %@)", objectPrefsPath, error,
			  [error domain], [error code], [error userInfo]);
		AILogWithSignature(@"Error reading data for preferences file %@: %@ (%@ %i: %@)", objectPrefsPath, error,
						   [error domain], [error code], [error userInfo]);
		if ([[NSFileManager defaultManager] fileExistsAtPath:objectPrefsPath]) {
			while (!data) {
				AILogWithSignature(@"Preferences file %@'s attributes: %@. Reattempting to read the file...", globalPrefsName, [[NSFileManager defaultManager] fileAttributesAtPath:objectPrefsPath traverseLink:NO]);
				data = [NSData dataWithContentsOfFile:objectPrefsPath
											  options:NSUncachedRead
												error:&error];
				if (error) {
					AILogWithSignature(@"Error reading data for preferences file %@: %@ (%@ %i: %@)", objectPrefsPath, error,
									   [error domain], [error code], [error userInfo]);
				}	
			}
		}
	}
	
	//We want to load a mutable dictioanry of mutable dictionaries.
	if (data) {
		*myGlobalPrefs = [[NSPropertyListSerialization propertyListFromData:data 
														   mutabilityOption:NSPropertyListMutableContainers 
																	 format:NULL 
														   errorDescription:&errorString] retain];
	}
	
	/* Log any error */
	if (errorString) {
		NSLog(@"Error reading preferences file %@: %@", objectPrefsPath, errorString);
		AILogWithSignature(@"Error reading preferences file %@: %@", objectPrefsPath, errorString);
	}
	
#ifdef PREFERENCE_CONTAINER_DEBUG
	AILogWithSignature(@"I read in %@ with %i items", globalPrefsName, [*myGlobalPrefs count]);
#endif
	
	/* If we don't get a dictionary, create a new one */
	if (!*myGlobalPrefs) {
		/* This wouldn't be an error if this were a new Adium installation; the below is temporary debug logging. */
		NSLog(@"WARNING: Unable to parse preference file %@ (data was %@)", objectPrefsPath, data);
		AILogWithSignature(@"WARNING: Unable to parse preference file %@ (data was %@)", objectPrefsPath, data);
		
		*myGlobalPrefs = [[NSMutableDictionary alloc] init];
	}
}

- (void) setPrefValue:(id)value forKey:(id)key
{
	NSAssert([NSThread currentThread] == [NSThread mainThread], @"AIPreferenceContainer is not threadsafe! Don't set prefs from non-main threads");
	NSMutableDictionary *prefDict = self.prefs;
	if (object && !prefDict) {
		//For compatibility with having loaded individual object prefs from previous version of Adium, we key by the safe filename string
		NSString *globalPrefsKey = [object.internalObjectID safeFilenameString];
		prefs = [[NSMutableDictionary alloc] init];
		[*myGlobalPrefs setObject:prefs
						   forKey:globalPrefsKey];
		(*myUsersOfGlobalPrefs)++;
	}
	[self.prefs setValue:value forKey:key];
}

/*!
 * @brief Return a dictionary of our preferences, loading it from disk as needed
 */
- (NSMutableDictionary *)prefs
{
	if (!prefs) {
		NSString	*userDirectory = adium.loginController.userDirectory;
		
		if (object) {
			if (!(*myGlobalPrefs))
				[self loadGlobalPrefs];

			//For compatibility with having loaded individual object prefs from previous version of Adium, we key by the safe filename string
			NSString *globalPrefsKey = [object.internalObjectID safeFilenameString];
			prefs = [[*myGlobalPrefs objectForKey:globalPrefsKey] retain];
			if (prefs)
				(*myUsersOfGlobalPrefs)++;

		} else {
			prefs = [[NSMutableDictionary dictionaryAtPath:userDirectory
												  withName:group
													create:YES] retain];
		}
		
		[self queueClearingOfCache];
	}
	
	return prefs;
}

/*!
 * @brief Return a dictionary of preferences and defaults, appropriately merged together
 */
- (NSDictionary *)dictionary
{
	if (!prefsWithDefaults) {
		//Add our own preferences to the defaults dictionary to get a dict with the set keys overriding the default keys
		if (defaults) {
			prefsWithDefaults = [defaults mutableCopy];
			NSDictionary *prefDict = self.prefs;
			if (prefDict)
				[prefsWithDefaults addEntriesFromDictionary:prefDict];

		} else {
			prefsWithDefaults = [self.prefs retain];
		}
		
		[self queueClearingOfCache];
	}

	return prefsWithDefaults;
}

/*!
 * @brief Set value for key
 *
 * This sets and saves a preference for the given key
 */
- (void)setValue:(id)value forKey:(NSString *)key
{
	BOOL	valueChanged = YES;
	/* Comparing pointers, numbers, and strings is far cheapear than writing out to disk;
	 * check to see if we don't need to change anything at all. However, we still want to post notifications
	 * for observers that we were set.
	 */
	id oldValue = [self valueForKey:key];
	if ((!value && !oldValue) || (value && oldValue && [value isEqual:oldValue]))
		valueChanged = NO;

	[self willChangeValueForKey:key];

	if (valueChanged) {
		//Clear the cached defaults dictionary so it will be recreated as needed
		if (value)
			[prefsWithDefaults setValue:value forKey:key];
		else {
			[prefsWithDefaults autorelease]; prefsWithDefaults = nil;
		}
		
		[self setPrefValue:value forKey:key];		
	}

	[self didChangeValueForKey:key];

	//Now tell the preference controller
	if (!preferenceChangeDelays) {
		[adium.preferenceController informObserversOfChangedKey:key inGroup:group object:object];
		if (valueChanged)
			[self save];
	}
}

- (id)valueForKey:(NSString *)key
{
	return [[self dictionary] valueForKey:key];
}

/*!
 * @brief Get a preference, possibly ignoring the defaults
 *
 * @param key The key
 * @param ignoreDefaults If YES, the preferences are accessed diretly, without including the default values
 */
- (id)valueForKey:(NSString *)key ignoringDefaults:(BOOL)ignoreDefaults
{
	if (ignoreDefaults)
		return [self.prefs valueForKey:key];
	else
		return [self valueForKey:key];
}

- (id)defaultValueForKey:(NSString *)key
{
	return [[self defaults] valueForKey:key];
}

/*!
 * @brief Set all preferences for this group
 *
 * All existing preferences are removed for this group; the passed dictionary becomes the new preferences
 */
- (void)setPreferences:(NSDictionary *)inPreferences
{	
	[self setPreferenceChangedNotificationsEnabled:NO];
	
	[self setValuesForKeysWithDictionary:inPreferences];
	
	[self setPreferenceChangedNotificationsEnabled:YES];
}

- (void)setPreferenceChangedNotificationsEnabled:(BOOL)inEnabled
{
	if (inEnabled) 
		preferenceChangeDelays--;
	else
		preferenceChangeDelays++;
	
	if (preferenceChangeDelays == 0) {
		[adium.preferenceController informObserversOfChangedKey:nil inGroup:group object:object];
		[self save];
	}
}

#pragma mark Saving

- (void)performObjectPrefsSave:(NSTimer *)inTimer
{
	NSDictionary *immutablePrefsToWrite = [[[NSDictionary alloc] initWithDictionary:inTimer.userInfo copyItems:YES] autorelease];
	[immutablePrefsToWrite asyncWriteToPath:adium.loginController.userDirectory withName:globalPrefsName];
	if (inTimer == timer_savingOfObjectCache) {
			[timer_savingOfObjectCache release]; timer_savingOfObjectCache = nil;
	} else if (inTimer == timer_savingOfAccountCache) {
			[timer_savingOfAccountCache release]; timer_savingOfAccountCache = nil;
	}
	(*myUsersOfGlobalPrefs)--;
}

/*!
 * @brief Save to disk
 */
- (void)save
{
	if (object) {
		//For an object's pref changes, batch all changes in a SAVE_OBJECT_PREFS_DELAY second period. We'll force an immediate save if Adium quits.
		if (*myTimerForSavingGlobalPrefs) {
				[*myTimerForSavingGlobalPrefs setFireDate:[NSDate dateWithTimeIntervalSinceNow:SAVE_OBJECT_PREFS_DELAY]];
		} else {
				(*myUsersOfGlobalPrefs)++;
				
#ifdef PREFERENCE_CONTAINER_DEBUG
			// This shouldn't happen now that *myUsersOfGlobalPrefs is synchronized.
			// Let's just log it for now.
			if (!*myGlobalPrefs) {
				NSLog(@"Attempted to detach to save for %@ [%@], but info was nil.", self, globalPrefsName);
				AILogWithSignature(@"Attempted to detach to save for %@ [%@], but info was nil.", self, globalPrefsName);
			}
#endif

			*myTimerForSavingGlobalPrefs = [[NSTimer scheduledTimerWithTimeInterval:SAVE_OBJECT_PREFS_DELAY
																			 target:self
																		   selector:@selector(performObjectPrefsSave:)
																		   userInfo:*myGlobalPrefs
																			repeats:NO] retain];
		}


	} else {
		//Save the preference change immediately
		[self.prefs writeToPath:adium.loginController.userDirectory withName:group];
	}
}

- (void)setGroup:(NSString *)inGroup
{
	if (group != inGroup) {
		[group release];
		group = [inGroup retain];
	}
}

#pragma mark Debug
- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p: Group %@, object %@>", NSStringFromClass([self class]), self, group, object];
}
@end
