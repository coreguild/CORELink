# Changelog

All notable changes to CORELink are documented in this file. It is generated at release time from the commit history; commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `feat(scope)!:` ...).

## [0.2.0-rc2](https://github.com/core-wow-community/CORELink/compare/v0.2.0-rc1...v0.2.0-rc2) (2026-11-09)


### Bug Fixes

* **relay:** the courier carries any line that gets no channel copy; a successful join clears the hold ([a53e4b8](https://github.com/core-wow-community/CORELink/commit/a53e4b8cdcc35d3d6ec73c6d868357a66026aa73))

## [0.2.0-rc1](https://github.com/core-wow-community/CORELink/compare/v0.1.0...v0.2.0-rc1) (2026-11-09)


### ⚠ BREAKING CHANGES

* **relay:** relay as channel text from the keypress; the courier whispers lines from members without the addon ([090d7f5](https://github.com/core-wow-community/CORELink/commit/090d7f5a64dff616e359dc7398a0d71a1e6656b9))


### Features

* two-channel release flow (rc/final) with a public download page on gh-pages (#5) ([e6df59c](https://github.com/core-wow-community/CORELink/commit/e6df59cce6fbfc9367fe5f0cac3658c6061bd25c))
* Release workflow (manual button) wrapping scripts/release.sh; publish dates fixed ([c5d06f2](https://github.com/core-wow-community/CORELink/commit/c5d06f2c2f5ec47b6ee7ed36eeb67f65d837980e))
* automatic version numbers; release notes generated from PR titles ([c11ad72](https://github.com/core-wow-community/CORELink/commit/c11ad72848a599c81e61d017e00127f9a1f04a74))
* release notes built from commits since the last release, shown on the download page ([4894b1d](https://github.com/core-wow-community/CORELink/commit/4894b1d800d34dbbfb6a0fa96bb8653b1f53f152))
* **release:** conventional-changelog sections with commit links, published CHANGELOG.md ([8fb0b56](https://github.com/core-wow-community/CORELink/commit/8fb0b561984a903ace02a2cd66fc819ccbf45c26))
* **officer:** drop the dash in the officer tag, (Firelord Tanner) instead of (Firelord - Tanner) ([bf936ca](https://github.com/core-wow-community/CORELink/commit/bf936ca1c6059483ca19759737d7ac0992bd8caf))
* **guilds:** show which realms each linked guild reaches; warn when one has no relay on ours ([4da6ab3](https://github.com/core-wow-community/CORELink/commit/4da6ab3fe65dc332dd4827b1862a9f3675dffea5))
* **bridge:** carry other guilds' lines across realms through a cross-realm guild ([42c62c6](https://github.com/core-wow-community/CORELink/commit/42c62c65432071d5ab99c730957235775666f032))
* **mirror:** post typed guild lines into a Blizzard Community named by club= in Guild Info ([6f60a39](https://github.com/core-wow-community/CORELink/commit/6f60a3946862306ec5bb8a9dc84222816b642a0c))
* **mirror:** show community lines from other guilds in guild chat, de-duplicated against the relay ([1950d4e](https://github.com/core-wow-community/CORELink/commit/1950d4eaa96084dfaf295b0a081da8acb364bde2))
* **mirror:** class and officer colours on community lines ([c8c2d58](https://github.com/core-wow-community/CORELink/commit/c8c2d58155e1d1964f5f8d2276eb3c61b27eb743))
* **mirror:** hook guild sends, focus before posting, hide raw lines, name the club ([a8f882b](https://github.com/core-wow-community/CORELink/commit/a8f882b06637d83c056f8d9d22ed74cbe38079bb))
* **mirror:** WoW communities, sealed text, class colours from the member record ([a3f1fdf](https://github.com/core-wow-community/CORELink/commit/a3f1fdf31d2051fb3410b198f1e58d33007a3482))
* **mirror:** officer rank and nickname on community posts, officer colour from roles ([2f2d664](https://github.com/core-wow-community/CORELink/commit/2f2d66426aa584ef06e345ab0571140543b73d0f))
* **mirror:** carry guild lines from members without the addon into the community ([7dd553b](https://github.com/core-wow-community/CORELink/commit/7dd553b38b7c733f0c1489156dac8f13d06ddc5c))
* **mirror:** one community channel per guild carries the tag ([8a2faa6](https://github.com/core-wow-community/CORELink/commit/8a2faa6f17cf1cdcd1308b1499c45974233ba6be))
* **echo:** re-post other guilds' lines into real guild chat for members without the addon ([2e8d2f6](https://github.com/core-wow-community/CORELink/commit/2e8d2f6a65b0a4228b17881fdbcde0913d7a4c9b))
* **whisper:** courier whisper bridge for guilds that share no realm ([ae19776](https://github.com/core-wow-community/CORELink/commit/ae197768810596b78a3fe5e999d85d928a53149f))
* **whisper:** /cl hello greets one player by hand; realm omitted from directory entries that carry it ([f10850e](https://github.com/core-wow-community/CORELink/commit/f10850ee74f9bb2fee5ec81fe65f16bf3eb3670a))
* **relay:** relay as channel text from the keypress; the courier whispers lines from members without the addon ([090d7f5](https://github.com/core-wow-community/CORELink/commit/090d7f5a64dff616e359dc7398a0d71a1e6656b9))


### Bug Fixes

* debug echo is always off at login; /cl debug on lasts for the session only ([482678b](https://github.com/core-wow-community/CORELink/commit/482678bf533410bc2a4aa30e2531e1c79f0c880c))
* configure and join automatically at login; retry until connected, then print status once ([11750ed](https://github.com/core-wow-community/CORELink/commit/11750ed834eb4d588a59cf15611ad558dd4271c5))
* **setup:** /cl publish always writes the officer rank, including the default 1 ([3a5badc](https://github.com/core-wow-community/CORELink/commit/3a5badc5f24b60d82149fd5b3de70382aae2970a))
* **connect:** record why joining fails and tell the player; wrong password pauses retries ([121e7cb](https://github.com/core-wow-community/CORELink/commit/121e7cbcaa4f7e26cff9ac199f9f20da4856bc26))
* **nicknames:** identify the player by GUID so nicknames and self checks work with Forever surnames ([aa9a021](https://github.com/core-wow-community/CORELink/commit/aa9a021678795b60a0570959cdbec89e06129fd3))
* **connect:** one message for an unconfigured login, naming what Guild Info held ([9c6c8a5](https://github.com/core-wow-community/CORELink/commit/9c6c8a58f8cf1d9423576f1da46fa5b123e0c719))
* **commands:** members can run /cl reload, on, off, mute and unmute ([39cb9c6](https://github.com/core-wow-community/CORELink/commit/39cb9c6cd0dc243ff8bce55214a1093c29bcdc8b))
* **mirror:** subscribe to the community stream as soon as login connects, retry each minute ([d39e61c](https://github.com/core-wow-community/CORELink/commit/d39e61ce06d2e313151a2e6e242db559ef573e8e))
* **mirror:** carry guildmates' lines for five minutes, not two ([32c8b2b](https://github.com/core-wow-community/CORELink/commit/32c8b2bd6acda758f1b3dd038facf2fd972be562))
* **release:** render the download page by literal substitution; site repairs channels from the GitHub release ([83cb490](https://github.com/core-wow-community/CORELink/commit/83cb49014c0a7eed372b9aaa3b36e8cc7964d072))
* **release:** run the renderer through bash, repair a channel only when its zip differs from the release ([cbb1434](https://github.com/core-wow-community/CORELink/commit/cbb14346187f125f19db670dc80cad018f6107ae))
* **site:** readable link colour on the download page, brighter in dark mode ([a8a4234](https://github.com/core-wow-community/CORELink/commit/a8a4234df3cda08858c772ae1f4cef599c053b9d))
* **whisper:** learn realms from PEER answers, not /who; exact guild match; rotate greetings ([2acc328](https://github.com/core-wow-community/CORELink/commit/2acc3283197519725d1b3c258f8f26b5d03b44f3))
* **whisper:** a peer that never answered is never live ([3ddd53a](https://github.com/core-wow-community/CORELink/commit/3ddd53a6b721cbbe7a08f8313b5b51ad8de98bbc))


### Documentation

* add ONBOARDING.md for new contributors starting without a GitHub account (#3) ([47b3a0a](https://github.com/core-wow-community/CORELink/commit/47b3a0a140061169981150dc6473e8612156d375))
* plain-language release flow in README (#6) ([716d46c](https://github.com/core-wow-community/CORELink/commit/716d46c8eee19822941400f1aeb3bfe13cf4f509))
* more technical release flow in README (CI checks, tags, gh-pages layout) (#7) ([fca718f](https://github.com/core-wow-community/CORELink/commit/fca718f7b1040906b5ce6ef143eaec46ac211bbd))
* agents never merge; merging is a human button press (#8) ([0e6dafe](https://github.com/core-wow-community/CORELink/commit/0e6dafe889db409532d987932a759afcfd674b87))
* merge commits instead of squash ([c09610d](https://github.com/core-wow-community/CORELink/commit/c09610d9a138f08085747c24926b9c34a70899b1))
* **mirror:** community text is a Kstring token; treat |K..|k as sealed ([673bafb](https://github.com/core-wow-community/CORELink/commit/673bafba03935bf859540c93e44dd85fb7efef49))
* one short README; commands, troubleshooting, development and architecture move to docs/ ([bb5df82](https://github.com/core-wow-community/CORELink/commit/bb5df827544ebf4e42908c159ca55c4b9e76658b))
* describe the text relay and courier transport; realms no longer matter ([0717930](https://github.com/core-wow-community/CORELink/commit/0717930511fdfd7da31bee4c7d38b7a918f6e704))


### Maintenance

* add start-feature skill so agents branch before editing ([7a9344b](https://github.com/core-wow-community/CORELink/commit/7a9344b0f29e5c322a918cd50ef5b6440935cf74))
* CI tests on every PR, PR template with feature notes, CHANGELOG, feature-request rules ([d65f36c](https://github.com/core-wow-community/CORELink/commit/d65f36c74c5a6b26cd1bc5fb74903802513ffc69))
* live game-version check in CI, gameplay-impact review checklist and review-pr skill ([92bfc95](https://github.com/core-wow-community/CORELink/commit/92bfc952f9dff6b84063392ea5df5c9a141090be))
* make the surname block set up its own joined client ([e4be41d](https://github.com/core-wow-community/CORELink/commit/e4be41df3aae401f308eb5feaf701b85d4746a88))
* close the merged harness block ([3dfd74d](https://github.com/core-wow-community/CORELink/commit/3dfd74de9fcc47baa5bac54790a38d5bd248983c))
* **mirror:** drop the piggyback; guild channels must be marked ([d0d02ef](https://github.com/core-wow-community/CORELink/commit/d0d02eff2ed7fed2b6f1412271e658802255c3a9))
* point install and version-check tooling at the live WoW: Forever client ([03b2c23](https://github.com/core-wow-community/CORELink/commit/03b2c235b74315c8460d6090e2f0f0737a322f94))
* **release:** cut release candidates from release/* branches, finals from main ([fdbbd7c](https://github.com/core-wow-community/CORELink/commit/fdbbd7cfaded8b2a2edbff66f2cbacc82ec5fb5b))
* split the addon into fourteen files by concern, one function per command and packet ([7c14736](https://github.com/core-wow-community/CORELink/commit/7c14736d666918ebcae78379273849c291a10416))
* register events set after Events.lua loads, load-order test, state ownership, command checks ([536c916](https://github.com/core-wow-community/CORELink/commit/536c916c86131ae272ffdfd904373dcdc525ee10))


### Other Changes

* /cl report and /cl debug diagnostics, luacheck in tests and CI (0.1.1) (#4) ([f3112b7](https://github.com/core-wow-community/CORELink/commit/f3112b785bbb1d68e34595743825f968340ce631))

## [0.1.1-rc9](https://github.com/core-wow-community/CORELink/compare/v0.1.1-rc8...v0.1.1-rc9) (2026-11-07)


### Bug Fixes

* **release:** render the download page by literal substitution; site repairs channels from the GitHub release ([83cb490](https://github.com/core-wow-community/CORELink/commit/83cb49014c0a7eed372b9aaa3b36e8cc7964d072))
* **release:** run the renderer through bash, repair a channel only when its zip differs from the release ([cbb1434](https://github.com/core-wow-community/CORELink/commit/cbb14346187f125f19db670dc80cad018f6107ae))
* **site:** readable link colour on the download page, brighter in dark mode ([a8a4234](https://github.com/core-wow-community/CORELink/commit/a8a4234df3cda08858c772ae1f4cef599c053b9d))
* **whisper:** learn realms from PEER answers, not /who; exact guild match; rotate greetings ([2acc328](https://github.com/core-wow-community/CORELink/commit/2acc3283197519725d1b3c258f8f26b5d03b44f3))

## [0.1.1-rc8](https://github.com/core-wow-community/CORELink/compare/v0.1.1-rc7...v0.1.1-rc8) (2026-11-06)


### Features

* **mirror:** post typed guild lines into a Blizzard Community named by club= in Guild Info ([6f60a39](https://github.com/core-wow-community/CORELink/commit/6f60a3946862306ec5bb8a9dc84222816b642a0c))
* **mirror:** show community lines from other guilds in guild chat, de-duplicated against the relay ([1950d4e](https://github.com/core-wow-community/CORELink/commit/1950d4eaa96084dfaf295b0a081da8acb364bde2))
* **mirror:** class and officer colours on community lines ([c8c2d58](https://github.com/core-wow-community/CORELink/commit/c8c2d58155e1d1964f5f8d2276eb3c61b27eb743))
* **mirror:** hook guild sends, focus before posting, hide raw lines, name the club ([a8f882b](https://github.com/core-wow-community/CORELink/commit/a8f882b06637d83c056f8d9d22ed74cbe38079bb))
* **mirror:** WoW communities, sealed text, class colours from the member record ([a3f1fdf](https://github.com/core-wow-community/CORELink/commit/a3f1fdf31d2051fb3410b198f1e58d33007a3482))
* **mirror:** officer rank and nickname on community posts, officer colour from roles ([2f2d664](https://github.com/core-wow-community/CORELink/commit/2f2d66426aa584ef06e345ab0571140543b73d0f))
* **mirror:** carry guild lines from members without the addon into the community ([7dd553b](https://github.com/core-wow-community/CORELink/commit/7dd553b38b7c733f0c1489156dac8f13d06ddc5c))
* **mirror:** one community channel per guild carries the tag ([8a2faa6](https://github.com/core-wow-community/CORELink/commit/8a2faa6f17cf1cdcd1308b1499c45974233ba6be))
* **echo:** re-post other guilds' lines into real guild chat for members without the addon ([2e8d2f6](https://github.com/core-wow-community/CORELink/commit/2e8d2f6a65b0a4228b17881fdbcde0913d7a4c9b))
* **whisper:** courier whisper bridge for guilds that share no realm ([ae19776](https://github.com/core-wow-community/CORELink/commit/ae197768810596b78a3fe5e999d85d928a53149f))
* **whisper:** /cl hello greets one player by hand; realm omitted from directory entries that carry it ([f10850e](https://github.com/core-wow-community/CORELink/commit/f10850ee74f9bb2fee5ec81fe65f16bf3eb3670a))


### Bug Fixes

* **mirror:** subscribe to the community stream as soon as login connects, retry each minute ([d39e61c](https://github.com/core-wow-community/CORELink/commit/d39e61ce06d2e313151a2e6e242db559ef573e8e))
* **mirror:** carry guildmates' lines for five minutes, not two ([32c8b2b](https://github.com/core-wow-community/CORELink/commit/32c8b2bd6acda758f1b3dd038facf2fd972be562))


### Documentation

* **mirror:** community text is a Kstring token; treat |K..|k as sealed ([673bafb](https://github.com/core-wow-community/CORELink/commit/673bafba03935bf859540c93e44dd85fb7efef49))


### Maintenance

* **mirror:** drop the piggyback; guild channels must be marked ([d0d02ef](https://github.com/core-wow-community/CORELink/commit/d0d02eff2ed7fed2b6f1412271e658802255c3a9))
* point install and version-check tooling at the live WoW: Forever client ([03b2c23](https://github.com/core-wow-community/CORELink/commit/03b2c235b74315c8460d6090e2f0f0737a322f94))
* **release:** cut release candidates from release/* branches, finals from main ([fdbbd7c](https://github.com/core-wow-community/CORELink/commit/fdbbd7cfaded8b2a2edbff66f2cbacc82ec5fb5b))

## [0.1.1-rc6](https://github.com/core-wow-community/CORELink/compare/v0.1.1-rc5...v0.1.1-rc6) (2026-10-06)


### Bug Fixes

* **commands:** members can run /cl reload, on, off, mute and unmute ([39cb9c6](https://github.com/core-wow-community/CORELink/commit/39cb9c6cd0dc243ff8bce55214a1093c29bcdc8b))

## [0.1.1-rc5](https://github.com/core-wow-community/CORELink/compare/v0.1.1-rc4...v0.1.1-rc5) (2026-10-06)


### Features

* **officer:** drop the dash in the officer tag, (Firelord Tanner) instead of (Firelord - Tanner) ([bf936ca](https://github.com/core-wow-community/CORELink/commit/bf936ca1c6059483ca19759737d7ac0992bd8caf))


### Bug Fixes

* **setup:** /cl publish always writes the officer rank, including the default 1 ([3a5badc](https://github.com/core-wow-community/CORELink/commit/3a5badc5f24b60d82149fd5b3de70382aae2970a))
* **connect:** record why joining fails and tell the player; wrong password pauses retries ([121e7cb](https://github.com/core-wow-community/CORELink/commit/121e7cbcaa4f7e26cff9ac199f9f20da4856bc26))
* **nicknames:** identify the player by GUID so nicknames and self checks work with Forever surnames ([aa9a021](https://github.com/core-wow-community/CORELink/commit/aa9a021678795b60a0570959cdbec89e06129fd3))
* **connect:** one message for an unconfigured login, naming what Guild Info held ([9c6c8a5](https://github.com/core-wow-community/CORELink/commit/9c6c8a58f8cf1d9423576f1da46fa5b123e0c719))


### Maintenance

* make the surname block set up its own joined client ([e4be41d](https://github.com/core-wow-community/CORELink/commit/e4be41df3aae401f308eb5feaf701b85d4746a88))
* close the merged harness block ([3dfd74d](https://github.com/core-wow-community/CORELink/commit/3dfd74de9fcc47baa5bac54790a38d5bd248983c))

## [0.1.1-rc4](https://github.com/core-wow-community/CORELink/compare/v0.1.1-rc3...v0.1.1-rc4) (2026-10-05)


### Features

* **release:** conventional-changelog sections with commit links, published CHANGELOG.md ([8fb0b56](https://github.com/core-wow-community/CORELink/commit/8fb0b561984a903ace02a2cd66fc819ccbf45c26))
