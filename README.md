# Classic Fishing Companion

A comprehensive fishing tracker addon for World of Warcraft Anniversary Classic. Track catches, monitor efficiency, view detailed statistics, and display real-time stats with an on-screen HUD.

**Update 11/22/25** - Waiting on PTR access for TBC so I can start testing. More to come. -- Relyk22

## Features

- **Comprehensive Tracking**: Records every fish caught with location, timestamp, and efficiency metrics
- **Stats HUD**: Draggable on-screen display showing session/total catches, fish/hour, skill level, and active lure with color-coded timer
- **Gear Sets**: Save and swap between fishing and combat equipment with one click
- **Lure Manager**: Select your preferred lure and apply it instantly with the HUD button
- **Detailed Statistics**: Fish list, catch history, top catches, zone productivity, skill progression, and buff/pole usage
- **Missing Buff Warnings**: On-screen alerts every 30 seconds when fishing without a lure
- **Minimap Button**: Quick access to UI (left-click), HUD toggle (right-click), and session stats (hover)
- **Customizable Settings**: Toggle features, lock HUD position, enable debug mode, and more

## Quick Start

1. Enable the addon and load into the game
2. Click the minimap button or type `/cfc` to open the UI
3. Start fishing - all catches are tracked automatically
4. Use the Stats HUD for real-time information

## Commands

- `/cfc` - Open/close main UI
- `/cfc stats` - Print statistics to chat
- `/cfc reset` - Reset all data (with confirmation)
- `/cfc debug` - Toggle debug mode
- `/cfc minimap` - Toggle minimap button
- `/cfc savefishing` - Save current gear as fishing set
- `/cfc savecombat` - Save current gear as combat set
- `/cfc swap` - Swap between fishing and combat gear

## Interface Tabs

### Overview
Current session and lifetime stats at a glance with recent catches list.

### Fish List
All unique fish caught, sorted by count.

### History
Log of your last 50 catches with date/time and location.

### Statistics
- Fishing skill level and recent increases
- Fishing poles used and cast counts
- Lures/buffs applied and usage frequency
- Top 10 most caught fish
- Most productive fishing zones

### Gear Sets
Save and manage fishing and combat equipment. Equip your desired gear, click "Save Current Gear", then use the swap button to quickly switch between sets. Cannot swap during combat.

### Settings
- Show/hide minimap button and Stats HUD
- Lock/unlock HUD position
- Enable/disable fish catch announcements
- Enable/disable missing buff warnings (30-second interval)
- Debug mode
- Clear all statistics

## Stats HUD

The HUD displays:
- **Session/Total**: Fish caught this session and lifetime
- **Fish/Hour**: Current fishing efficiency
- **Skill**: Fishing skill level (current/max)
- **Lure**: Active lure with color-coded timer (🟢 >2min, 🟡 1-2min, 🔴 <1min)
- **Swap Button**: Quick gear swap showing current mode (🎣 Fishing / ⚔️ Combat)

**To move the HUD**: Click the lock icon (top-right) to unlock, drag to position, then lock again.

## Data Tracked

**Per Fish**: Name, timestamp, zone, sub-zone, coordinates, formatted date/time
**Additional**: Fishing skill progression, lures/buffs applied, fishing poles used

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Fish not tracking | Enable addon in AddOns menu, use `/cfc debug` for details |
| Minimap button missing | Type `/cfc` or check Settings tab |
| Stats HUD not showing | Right-click minimap button or enable in Settings |
| Buff timer not showing | Apply a fishing lure to your pole |
| UI not showing | Check addon is enabled, try `/reload` |
| Data not saving | Exit WoW properly, check SavedVariables folder |

## Performance

Lightweight design with minimal impact:
- Only tracks events during fishing
- Efficient data storage
- HUD updates once per second
- No continuous scanning

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

**Latest (v1.0.4)**: Enhanced combat protection for gear swapping and code optimization improvements.

## Support

Issues or suggestions? Check Troubleshooting first, then report bugs at:
https://github.com/DigitalPenguin1/ClassicFishingCompanion/issues

## Credits

Created for World of Warcraft Classic
Uses embedded Ace3 libraries (Copyright © 2007, Ace3 Development Team)

## License

Free to use and modify for personal use.

**Happy Fishing!** 🎣
