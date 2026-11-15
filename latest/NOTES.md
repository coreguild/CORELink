▎ Fixes the "CORELink tried to call the protected function" errors that filled BugSack: the addon now reads Guild Info at login and every five minutes, and never in combat. /cl replies now appear in the chat tab you typed them in. Officers' messages default to a slightly darker guild green; a color you set yourself is kept.

## [0.2.2](https://github.com/coreguild/CORELink/compare/v0.2.1...v0.2.2) (2026-11-15)


### Features

* **display:** the default officer colour is #40db27, the guild green a shade darker ([4f3f720](https://github.com/coreguild/CORELink/commit/4f3f7208ca00fdcc40a85aa8088a9a6a2d6ebeeb))


### Bug Fixes

* **core:** the addon's own messages go to the chat tab the player is looking at ([0c9d4a6](https://github.com/coreguild/CORELink/commit/0c9d4a6316e0bb33f311b0bc81039744f4718184))
* **core:** a /cl reply goes to the chat window the command was typed in; other messages stay in the default window ([0c58db1](https://github.com/coreguild/CORELink/commit/0c58db1e7eb04456ddc6d1c40348cff9107e8cd3))
* **guildinfo:** read Guild Info at login and every five minutes, never in combat or chat lockdown ([4262896](https://github.com/coreguild/CORELink/commit/42628960ac4f4e43c4b9c1e3dd8ceb21daa6b3ea))
* **guildinfo:** also hold the read while the player is fighting; record where the block was seen ([a60af34](https://github.com/coreguild/CORELink/commit/a60af345857f91804997aeb8c1adf3d49ea7c47c))
* **guildinfo:** a read that had to wait is done after the fight; a guild change and /cl reload are never throttled; a blocked read is logged and backs off ([4d2a525](https://github.com/coreguild/CORELink/commit/4d2a5259625ec12e6c674faea2d5942f16653185))

Direct download (stable): https://coreguild.github.io/CORELink/latest/CORELink.zip
