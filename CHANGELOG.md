# Changelog

All notable changes to Classic Fishing Companion will be documented in this file.

## [1.0.5] - 2025-11-30

### Added
- Fishing pole and lure bonus display on HUD skill line
  - Shows fishing pole inherent bonus in green with pole icon (e.g., "+25")
  - Shows active lure bonus in yellow with lure icon (e.g., "+75")
  - Dynamic icon fetching displays actual equipped pole and selected lure icons
  - Supports all lure types: +25 (Shiny Bauble), +50 (Nightcrawlers, Aquadynamic Fish Lens), +75 (Bright Baubles, Flesh Eating Worm), +100 (Aquadynamic Fish Attractor)
  - Example display: "Skill: 150/300 +25 [pole icon] +75 [lure icon]"
- Casting protection for gear swapper
  - Prevents gear swaps while casting or channeling any spell
  - Shows warning message when attempting to swap during cast
  - Uses UnitCastingInfo and UnitChannelInfo for comprehensive protection
- Configurable announcement settings
  - New setting to enable/disable buff warning messages (enabled by default)
  - New setting to enable/disable fishing skill increase announcements (enabled by default)
  - Both settings available in Settings tab with clear descriptions
- Data import/export functionality
  - Export all fishing data for backup or transfer between characters
  - Import data from exported files to restore or merge statistics
- Automatic backup system
  - Internal backups created every 24 hours (stored in SavedVariables: `WTF\Account\[ACCOUNT_NAME]\[RandomNumberString]\SavedVariables\ClassicFishingCompanion.lua.bak`)
  - Export reminder shown every 7 days of play time
  - "Enable Automatic Backups" setting to toggle automatic backups (enabled by default)
  - "Restore from Backup" button to restore from most recent automatic backup
  - Backup timestamp displayed in Settings tab
  - Session data preserved when restoring from backup
  - Confirmation dialog when restoring backup
- Enhanced Lure tab with macro creation functionality
  - Step-by-step instructions for creating lure macro
  - "Update CFC_ApplyLure Macro" button to automatically create/update macro
  - Macro now uses the icon of the selected lure
  - Four-step guide including typing /macro to open macro interface
  - Scrollable lure list with 7 different lure options
  - Added Sharpened Fish Hook (+100) to lure options

### Changed
- Updated Ace3 libraries to latest versions
  - AceAddon-3.0: v12 → v13 (bug fixes and improvements)
  - AceEvent-3.0: v3 → v4 (enhanced event handling)
  - CallbackHandler-1.0: v6 → v8 (stability improvements)
  - LibStub and AceConsole-3.0 already up to date
- HUD Lure button simplified for better workflow
  - Button now displays as "Lure" instead of "Apply Lure"
  - Clicking the button opens the main UI to the Lure tab
  - Allows easy access to lure selection and macro creation
  - Removes the need for pre-selecting lures before accessing the tab
  - Standardized button width to 88px (matches Swap button)
  - Added lure icon for visual consistency with other HUD buttons
- Performance optimizations
  - Moved lure mapping tables to module-level constants to prevent recreation on every HUD update
  - Eliminated duplicate GetCurrentFishingBuff() call (was called twice per update)
  - Consolidated multiple time() calls in fishing state checks to single variable
  - Removed redundant conditional checks
  - Removed dead code: unused variables (addonName, addon, lastSpellCast, fishingStartTime)
  - Removed dead code: unused lureNames table from HUD.lua (duplicate of lureNamesWithBonus)
  - Removed unnecessary local reference `local CFC = CFC`

### Fixed
- Fixed buff usage statistics counting same lure multiple times
  - Previously counted existing lure as "new" when gear swapping or doing /reload
  - Swapping to combat gear (sword/axe) checked that weapon for enchants and reset tracking
  - Reloading UI reset runtime tracking variables (currentTrackedBuff)
  - Now verifies equipped weapon is actually a fishing pole before checking enchants
  - Checks database for recent lure applications (within 9 minutes) before counting as new
  - Prevents double-counting same lure after reloads or gear swaps
  - Only counts as new application if: different lure, or 9+ minutes since last count, or expiration jumped 500+ seconds
- Fixed chest/container loot being incorrectly tracked as fish catches
  - Added UNIT_SPELLCAST_SUCCEEDED event to detect when Fishing spell is cast
  - Added check to verify Fishing was recently cast (within 30 seconds) before counting loot
  - Clears fishing cast flag after successfully looting from fishing to prevent subsequent chest/container loot from being tracked
  - Prevents loot from chests, crates, and other containers from being tracked when fishing pole is equipped
  - Only loot from actual fishing casts is now tracked
  - Debug mode shows spell cast detection, time-since-cast validation, and flag clearing
- Fixed lure detection for TBC compatibility
  - Core.lua CheckLureChanges: Simplified tooltip scanning approach (removed unnecessary `:Show()` call)
  - Core.lua CheckLureChanges: Direct pattern matching for "Lure" or "Increased Fishing" text
  - Core.lua CheckLureChanges: Strips duration text to get consistent lure names for statistics tracking
  - Core.lua HasFishingBuff: Updated pattern to match TBC tooltip format "Fishing Lure (+25 Fishing Skill)"
  - Core.lua HasFishingBuff: Changed from `"Fishing Lure %+(%d+)"` to `"Lure.*%(%+(%d+)"`
  - Core.lua HasFishingBuff: Reuses tooltip for better performance (was creating new tooltip each call)
  - HUD.lua GetCurrentFishingBuff: Updated pattern to match TBC tooltip format
  - HUD.lua GetCurrentFishingBuff: Changed from `"Fishing Lure %+(%d+)"` to `"Lure.*%(%+(%d+)"` to extract bonus from parentheses
  - Added comprehensive debug logging to all lure detection functions to diagnose tooltip scanning issues
  - Fixed false "missing buff" raid warnings when lure is actually applied
- Fixed Fish List icon loading for TBC
  - Updated to use C_Container API (TBC container system)
  - Searches player bags using C_Container.GetContainerItemInfo to get icon textures
  - Falls back to default fish icon for items not in bags
  - Provides better visual consistency for caught fish no longer in inventory
- Fixed Fish List showing wrong icons for fish no longer in bags
  - Icons are now cached when fish are first caught and stored in database
  - Cached icons are used first, eliminating dependency on item cache or bag contents
  - Icons automatically update when found via GetItemInfo or bag scanning
  - Ensures correct icons display even for fish caught long ago or sold/banked
- Fixed tooltip pollution causing item data caching issues
  - Moved tooltip creation to module-level for reuse in GetFishingPoleBonus() and GetCurrentFishingBuff()
  - Prevents excessive tooltip creation impacting item icon loading
- Improved code efficiency by removing unnecessary operations
- Optimized HUD update cycle for better performance

## [1.0.3] - 2024-11-23

### Added
- Gear Sets system for quick equipment swapping
  - Save fishing and combat gear sets with one click
  - Swap between gear sets instantly with HUD button or slash commands
  - New "Gear Sets" tab in main UI for managing saved equipment
  - Visual display of all saved items in each gear set
  - Quick swap button on Stats HUD showing current mode (🎣 Fishing / ⚔️ Combat)
  - Slash commands: `/cfc savefishing`, `/cfc savecombat`, `/cfc swap`
  - Combat lockdown protection prevents gear swaps during combat
  - Automatic detection of gear configuration status
- Lure Manager system for quick lure application
  - New "Lure" tab in main UI for selecting preferred fishing lures
  - "Apply Lure" button on HUD to instantly apply selected lure to fishing pole
  - Support for all common fishing lures (Shiny Bauble, Nightcrawlers, Bright Baubles, Flesh Eating Worm, Aquadynamic Fish Attractor, Aquadynamic Fish Lens)
  - Corrected lure icons to match actual Classic WoW items
  - Inventory check warns when attempting to apply lure not in bags
  - Warning message when attempting to apply lure while in combat gear

### Changed
- HUD now displays "Lure:" instead of "Buff:" for better clarity
- Simplified HUD gear swap button text to prevent overlap ("Swap to" + icon)
- Renamed "Lure Manager" tab to "Lure" for cleaner interface

### Fixed
- Fixed lure tracking false positives when buying lures from vendors
  - Increased detection threshold from 5 to 500 seconds to prevent false counts
  - Only genuine lure applications are now tracked
- Fixed lure statistics tracking incorrect data
  - Now reads actual lure from fishing pole tooltip instead of trusting UI selection
  - Prevents false statistics when clicking Apply Lure for items not in inventory
- Fixed lure statistics showing duplicate entries with different time formats
  - Improved regex pattern to strip both minute and second formats from lure names
  - Ensures consistent lure names in statistics regardless of time remaining
- Fixed raid warnings triggering when not in fishing gear mode
  - Warnings now only appear when in fishing gear mode, not combat gear
  - Added gear mode check to prevent false warnings after swapping to combat gear
- Fixed combat loot being tracked as fish catches
  - Addon now only tracks loot from actual fishing casts, not combat kills
  - Uses UnitIsDead check to distinguish fishing loot from mob loot
  - Prevents mob loot from being tracked when you have a fishing pole equipped
- Fixed missing buff warnings not triggering consistently when actively fishing
  - Removed overly restrictive time-since-last-cast check
  - Warning now triggers reliably every 30 seconds (reduced from 60) when fishing without a lure
  - Warning only requires fishing pole equipped and fishing gear mode active
- Fixed "Clear All Statistics" button not clearing fishing pole usage and sessions data
- Fixed lure selection not updating the Apply Lure button macro
- Improved macro handling for lure application

## [1.0.2] - 2024-11-22

### Added
- Clickable lock icon on HUD for instant lock/unlock toggle
- Hover tooltips on lock icon showing current state and instructions
- Native WoW padlock icons for professional appearance

## [1.0.1] - 2024-11-22

### Added
- Missing buff warning system
  - On-screen warnings every 60 seconds when fishing without a lure/buff
  - Displays prominently in center of screen for 10 seconds
  - HUD shows "None" in red when no buff is active
  - Warning enabled by default, can be toggled in Settings

### Changed
- Updated settings UI with clearer descriptions

### Fixed
- Bug where cooked/crafted fish were incorrectly tracked as caught fish
  - Addon now only tracks items from "You receive loot:" messages (fishing)
  - Ignores "You create:" messages from cooking and other professions

## [1.0.0] - 2024-11-21

### Added
- Initial release with comprehensive fishing tracking
- Stats HUD with real-time display
- Buff timer with color-coded countdown
- Fishing skill progression tracking
- Buff and pole usage statistics
- Customizable settings
- Minimap button with quick actions
- Full Classic WoW compatibility
