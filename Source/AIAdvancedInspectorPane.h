/* 
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 * 
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import "AIContactInfoContentController.h"

#import <Adium/AIAccountMenu.h>
#import <Adium/AIContactMenu.h>
#import <AIUtilities/AISegmentedControl.h>

@class AIAccountMenu, AIContactMenu, AIAccount, AIListContact;

@interface AIAdvancedInspectorPane : NSObject <AIContentInspectorPane, AIAccountMenuDelegate, AIContactMenuDelegate> {
	IBOutlet	NSView							*inspectorContentView;
	
	IBOutlet	NSTextField						*label_account;
	IBOutlet	NSPopUpButton					*popUp_accounts;
	
	IBOutlet	NSTextField						*label_contact;
	IBOutlet	NSPopUpButton					*popUp_contact;
	
	IBOutlet	NSTableView						*tableView_groups;
	IBOutlet	AISegmentedControl				*button_addOrRemoveGroup;
	
	IBOutlet	NSTextField						*label_encryption;
	IBOutlet	NSPopUpButton					*popUp_encryption;
	
	IBOutlet	NSButton						*checkBox_alwaysShow;
	IBOutlet	NSButton						*checkBox_autoJoin;
	
	BOOL										switchingContacts;
	
	AIAccountMenu								*accountMenu;
	AIContactMenu								*contactMenu;
	
	AIAccount									*currentSelectedAccount;
	AIListContact								*currentSelectedContact;
	
	AIListObject								*displayedObject;
}

-(NSString *)nibName;
-(NSView *)inspectorContentView;
-(void)updateForListObject:(AIListObject *)inObject;

- (IBAction)selectedEncryptionPreference:(id)sender;
- (IBAction)setVisible:(id)sender;
- (IBAction)setAutoJoin:(id)sender;

- (IBAction)addOrRemoveGroup:(id)sender;
@end
