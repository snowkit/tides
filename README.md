Haxe `T`ools for `IDE` `S`upport 

### What is tides?

A collection of shared tools, utilities and structures, 
that have become common across multiple Haxe IDE plugins (like atom and sublime). 

### Why?

Since Haxe can compile to JS and Python (and more), by combining the underlying layer of both plugins to a singular repo written in Haxe – we share features and implementation details.

This is beneficial as bugs are fixed once and common, and IDE's can support a consistent level of feature parity and reliability.

### What it won't do

This repo is _not_ an IDE plugin/package of any kind.
This is specifically a shared, standalone dependency that can be used by IDE plugin/package writers to skip directly to the IDE specifics, and keep the Haxe specifics available to other IDE's.

### What it does do

- Parsing Haxe code signatures for consuming
- Parsing Haxe `--display` completion results into consumable forms
- Querying and running Haxe background processes for completion or compilation (for services like linting)
- (future) Haxe documentation parsing services (see [scribe](https://github.com/underscorediscovery/scribe))

### Status

- Immediate term atom and sublime are the focus
- Creating empty Haxe plugin architectures and externs, for atom and sublime
  - atom [externs](https://github.com/jeremyfa/hxatom), ~~empty package~~
  - sublime ~~externs~~, ~~empty package~~
- Migrating existing code from atom and sublime to tides
- See the issue list for fuller milestones and details

### History

- 0.0.1 - initial commit
