# Changelog

All notable changes to CORELink are documented in this file. It is generated at release time from the commit history; commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `feat(scope)!:` ...).

## [0.2.1-rc1](https://github.com/coreguild/CORELink/compare/v0.2.0...v0.2.1-rc1) (2026-11-15)


### Features

* **release:** upload each rc and final to CurseForge ([df6871d](https://github.com/coreguild/CORELink/commit/df6871dbe8ec7b9b69f32a0faac0f6fefe4dd830))
* **release:** a curseforge-check button proves the key and game versions without releasing ([c9aa2cc](https://github.com/coreguild/CORELink/commit/c9aa2cc9afe7eaf3ee4c2c325fe55d146b42a951))
* **tests:** self-review loop: mutation check, review evals, and the self-review skill ([cc4597d](https://github.com/coreguild/CORELink/commit/cc4597d653ac245d9fcc4e861b9fc7935d695af7))
* **release:** the curseforge-check button can upload an existing GitHub release by tag ([84afff9](https://github.com/coreguild/CORELink/commit/84afff9dea59e5ef978efa243aae24d3b8912d0b))


### Bug Fixes

* **release:** the site channel refreshes a channel's notes from the GitHub release ([dc5f54b](https://github.com/coreguild/CORELink/commit/dc5f54bab124b063b0818b48f583060cabcb5d2c))
* **release:** the CurseForge key never reaches a command line or a log ([042c4e2](https://github.com/coreguild/CORELink/commit/042c4e2fdc8a2db88b2ec5e903b412e54fdc571c))
* **release:** the CurseForge upload script and the secrets check are executable ([05d9a07](https://github.com/coreguild/CORELink/commit/05d9a070396abc54285e7dd928799d3b7e93b191))
* **tests:** the mutation check and the eval runner are executable ([2573f66](https://github.com/coreguild/CORELink/commit/2573f66c7237e3c0f4d63e385f4baf640c19b1bd))
* **tests:** the mutation check compares against the merge-base and knows a no-op change; the eval runner reports errors apart from misses ([107bb5f](https://github.com/coreguild/CORELink/commit/107bb5f1281c97ed1be98222b8a98af4418af31c))
* **release:** the tag upload gets its own button, reads the zip's TOCs, and refuses a partial version list ([4d6afd6](https://github.com/coreguild/CORELink/commit/4d6afd6ef670a636386d403e1a9328aac4138b51))
* **release:** post to CurseForge's upload-file endpoint and trust only a file id in the answer ([f5c3c2d](https://github.com/coreguild/CORELink/commit/f5c3c2db6be3b50d8ec6369dc7db0c451df05aef))
* **release:** every CurseForge call checks status and JSON, and a printed answer never holds the key ([bec2a98](https://github.com/coreguild/CORELink/commit/bec2a98bd993d68190fdb9483fb5230c73b92d07))
* **release:** send the CurseForge metadata with --form-string, so a semicolon in the notes keeps the JSON whole ([e6bfe40](https://github.com/coreguild/CORELink/commit/e6bfe40ca97db4f0086a89db8ed4d9f1e5784856))
* **release:** CurseForge metadata goes through a file; empty notes get a changelog; unreachable is said plainly ([96a3a3d](https://github.com/coreguild/CORELink/commit/96a3a3d5a47cf2f9c78feda4340e38aa85db7e8c))
* **release:** the CurseForge helper reports curl's exit code, so a lost answer is told apart from no connection ([dc0df71](https://github.com/coreguild/CORELink/commit/dc0df7173844f1bedbefc1ce1238c35b03a00017))
* **whisper:** hide the game's "not playing" reply to a carried line and stop whispering to that peer ([59cd727](https://github.com/coreguild/CORELink/commit/59cd72791ec077913faf6dc0ca63afa8fb083d58))
* **whisper:** a peer the game calls not playing is marked gone, not unanswered, and is asked again for an hour ([3576897](https://github.com/coreguild/CORELink/commit/357689777d236f6788f30280b3d7ac015dd94cf9))
* **whisper:** a carried line that hit a peer who is not playing goes to the guild's next peer ([bc71ada](https://github.com/coreguild/CORELink/commit/bc71ada2046739241383540c223b94433df0c110))
* **whisper:** the who lookup runs only from /cl who, one guild per command ([cf4c5d7](https://github.com/coreguild/CORELink/commit/cf4c5d7d88d355fe7d6c6691390b4ad579528f6d))
* **whisper:** /cl who waits for its answer, notices a block, asks an unanswered guild again, and gives the Who results back to chat ([1886664](https://github.com/coreguild/CORELink/commit/188666490b1f4e163ac065119d7c3bd5f69c00ba))
* **whisper:** remove the who lookup of guilds= guilds; the game blocks it and shows "Interface action failed" ([9bbb191](https://github.com/coreguild/CORELink/commit/9bbb19135395645202cf63dab25fdf65a721c5e9))


### Documentation

* **readme:** install steps that match the download page; everyone must be on 0.2.0 ([8e837f6](https://github.com/coreguild/CORELink/commit/8e837f60d130ef5a60f7d27f7aa2697f1f69b450))
* release branches are protected like main; feature branches reach them through reviewed PRs ([2306b95](https://github.com/coreguild/CORELink/commit/2306b95f153ef6e8985af2f6b29f44bfb0b85141))
* **readme:** what a player does, what a guild master does, nothing else first ([e919f35](https://github.com/coreguild/CORELink/commit/e919f353d92ed317b3293728f1a2062b2cdcf4d4))
* commands grouped by task with who may run them; troubleshooting rows for old versions and members without the addon; example line in the README ([e37738b](https://github.com/coreguild/CORELink/commit/e37738b00246e3a1a4d0dccca8ff0b19902efbf1))
* **readme:** clean up a lot of wording for ease of understanding ([dd4f26d](https://github.com/coreguild/CORELink/commit/dd4f26dbac2c5e8e3244a6766a17b86a8b5d6df3))
* **commands:** clean up a lot of wording for ease of understanding ([0caa9fa](https://github.com/coreguild/CORELink/commit/0caa9fa5a692e40e821ee4450b15a84730fe0a6c))
* **troubleshooting:** clean up a lot of wording for ease of understanding ([b682fbf](https://github.com/coreguild/CORELink/commit/b682fbf41cf9f57a83940a015ca163abb4798af9))
* add nod to greenwall ([af200e4](https://github.com/coreguild/CORELink/commit/af200e40cff85672a13da4be9205c8e663a29daa))
* **skills:** say the skills folder is hidden; the rc refusal cites the development doc ([09c6d0e](https://github.com/coreguild/CORELink/commit/09c6d0ebf27f516c3ffb0aea1cbd2d4465c648a2))
* release branches need green checks, not an approval, since the ruleset dropped it ([0ba6735](https://github.com/coreguild/CORELink/commit/0ba67355a6c2f12c5776287dc9a85959a1552a1e))


### Maintenance

* ISC license ([d3ea73e](https://github.com/coreguild/CORELink/commit/d3ea73e47a13a8c41e69d6ec0db474fb0f564e8e))
* keep Python bytecode out of the repo ([10418a9](https://github.com/coreguild/CORELink/commit/10418a96c3f490f2b2a2a45b9da370abced2d957))
* **skills:** one home for the skills, .claude/skills/, instead of skills/ plus symlinks ([3ba1819](https://github.com/coreguild/CORELink/commit/3ba18198b3cdc56df3f8feb193c5fa220f8f09ea))
* **compat:** run the released 0.2.0 against the working copy on every pull request ([41bf69c](https://github.com/coreguild/CORELink/commit/41bf69c9758a2e17dd3a27763cdc3b742cdbe4a9))
* **compat:** close the gaps the self-review found in the cross-version test ([9e6919f](https://github.com/coreguild/CORELink/commit/9e6919f71f3bc80be73fbff1a4c761ab86e76386))


### Other Changes

* Update LICENSE ([f56f886](https://github.com/coreguild/CORELink/commit/f56f886cdea90b79cca233570d956098d092c799))

## [0.2.0](https://github.com/coreguild/CORELink/compare/v0.1.0...v0.2.0) (2026-11-09)


### ⚠ BREAKING CHANGES

* **relay:** relay as channel text from the keypress; the courier whispers lines from members without the addon ([090d7f5](https://github.com/coreguild/CORELink/commit/090d7f5a64dff616e359dc7398a0d71a1e6656b9))


### Features

* two-channel release flow (rc/final) with a public download page on gh-pages (#5) ([e6df59c](https://github.com/coreguild/CORELink/commit/e6df59cce6fbfc9367fe5f0cac3658c6061bd25c))
* Release workflow (manual button) wrapping scripts/release.sh; publish dates fixed ([c5d06f2](https://github.com/coreguild/CORELink/commit/c5d06f2c2f5ec47b6ee7ed36eeb67f65d837980e))
* automatic version numbers; release notes generated from PR titles ([c11ad72](https://github.com/coreguild/CORELink/commit/c11ad72848a599c81e61d017e00127f9a1f04a74))
* release notes built from commits since the last release, shown on the download page ([4894b1d](https://github.com/coreguild/CORELink/commit/4894b1d800d34dbbfb6a0fa96bb8653b1f53f152))
* **release:** conventional-changelog sections with commit links, published CHANGELOG.md ([8fb0b56](https://github.com/coreguild/CORELink/commit/8fb0b561984a903ace02a2cd66fc819ccbf45c26))
* **officer:** drop the dash in the officer tag, (Firelord Tanner) instead of (Firelord - Tanner) ([bf936ca](https://github.com/coreguild/CORELink/commit/bf936ca1c6059483ca19759737d7ac0992bd8caf))
* **guilds:** show which realms each linked guild reaches; warn when one has no relay on ours ([4da6ab3](https://github.com/coreguild/CORELink/commit/4da6ab3fe65dc332dd4827b1862a9f3675dffea5))
* **bridge:** carry other guilds' lines across realms through a cross-realm guild ([42c62c6](https://github.com/coreguild/CORELink/commit/42c62c65432071d5ab99c730957235775666f032))
* **mirror:** post typed guild lines into a Blizzard Community named by club= in Guild Info ([6f60a39](https://github.com/coreguild/CORELink/commit/6f60a3946862306ec5bb8a9dc84222816b642a0c))
* **mirror:** show community lines from other guilds in guild chat, de-duplicated against the relay ([1950d4e](https://github.com/coreguild/CORELink/commit/1950d4eaa96084dfaf295b0a081da8acb364bde2))
* **mirror:** class and officer colours on community lines ([c8c2d58](https://github.com/coreguild/CORELink/commit/c8c2d58155e1d1964f5f8d2276eb3c61b27eb743))
* **mirror:** hook guild sends, focus before posting, hide raw lines, name the club ([a8f882b](https://github.com/coreguild/CORELink/commit/a8f882b06637d83c056f8d9d22ed74cbe38079bb))
* **mirror:** WoW communities, sealed text, class colours from the member record ([a3f1fdf](https://github.com/coreguild/CORELink/commit/a3f1fdf31d2051fb3410b198f1e58d33007a3482))
* **mirror:** officer rank and nickname on community posts, officer colour from roles ([2f2d664](https://github.com/coreguild/CORELink/commit/2f2d66426aa584ef06e345ab0571140543b73d0f))
* **mirror:** carry guild lines from members without the addon into the community ([7dd553b](https://github.com/coreguild/CORELink/commit/7dd553b38b7c733f0c1489156dac8f13d06ddc5c))
* **mirror:** one community channel per guild carries the tag ([8a2faa6](https://github.com/coreguild/CORELink/commit/8a2faa6f17cf1cdcd1308b1499c45974233ba6be))
* **echo:** re-post other guilds' lines into real guild chat for members without the addon ([2e8d2f6](https://github.com/coreguild/CORELink/commit/2e8d2f6a65b0a4228b17881fdbcde0913d7a4c9b))
* **whisper:** courier whisper bridge for guilds that share no realm ([ae19776](https://github.com/coreguild/CORELink/commit/ae197768810596b78a3fe5e999d85d928a53149f))
* **whisper:** /cl hello greets one player by hand; realm omitted from directory entries that carry it ([f10850e](https://github.com/coreguild/CORELink/commit/f10850ee74f9bb2fee5ec81fe65f16bf3eb3670a))
* **relay:** relay as channel text from the keypress; the courier whispers lines from members without the addon ([090d7f5](https://github.com/coreguild/CORELink/commit/090d7f5a64dff616e359dc7398a0d71a1e6656b9))


### Bug Fixes

* debug echo is always off at login; /cl debug on lasts for the session only ([482678b](https://github.com/coreguild/CORELink/commit/482678bf533410bc2a4aa30e2531e1c79f0c880c))
* configure and join automatically at login; retry until connected, then print status once ([11750ed](https://github.com/coreguild/CORELink/commit/11750ed834eb4d588a59cf15611ad558dd4271c5))
* **setup:** /cl publish always writes the officer rank, including the default 1 ([3a5badc](https://github.com/coreguild/CORELink/commit/3a5badc5f24b60d82149fd5b3de70382aae2970a))
* **connect:** record why joining fails and tell the player; wrong password pauses retries ([121e7cb](https://github.com/coreguild/CORELink/commit/121e7cbcaa4f7e26cff9ac199f9f20da4856bc26))
* **nicknames:** identify the player by GUID so nicknames and self checks work with Forever surnames ([aa9a021](https://github.com/coreguild/CORELink/commit/aa9a021678795b60a0570959cdbec89e06129fd3))
* **connect:** one message for an unconfigured login, naming what Guild Info held ([9c6c8a5](https://github.com/coreguild/CORELink/commit/9c6c8a58f8cf1d9423576f1da46fa5b123e0c719))
* **commands:** members can run /cl reload, on, off, mute and unmute ([39cb9c6](https://github.com/coreguild/CORELink/commit/39cb9c6cd0dc243ff8bce55214a1093c29bcdc8b))
* **mirror:** subscribe to the community stream as soon as login connects, retry each minute ([d39e61c](https://github.com/coreguild/CORELink/commit/d39e61ce06d2e313151a2e6e242db559ef573e8e))
* **mirror:** carry guildmates' lines for five minutes, not two ([32c8b2b](https://github.com/coreguild/CORELink/commit/32c8b2bd6acda758f1b3dd038facf2fd972be562))
* **release:** render the download page by literal substitution; site repairs channels from the GitHub release ([83cb490](https://github.com/coreguild/CORELink/commit/83cb49014c0a7eed372b9aaa3b36e8cc7964d072))
* **release:** run the renderer through bash, repair a channel only when its zip differs from the release ([cbb1434](https://github.com/coreguild/CORELink/commit/cbb14346187f125f19db670dc80cad018f6107ae))
* **site:** readable link colour on the download page, brighter in dark mode ([a8a4234](https://github.com/coreguild/CORELink/commit/a8a4234df3cda08858c772ae1f4cef599c053b9d))
* **whisper:** learn realms from PEER answers, not /who; exact guild match; rotate greetings ([2acc328](https://github.com/coreguild/CORELink/commit/2acc3283197519725d1b3c258f8f26b5d03b44f3))
* **whisper:** a peer that never answered is never live ([3ddd53a](https://github.com/coreguild/CORELink/commit/3ddd53a6b721cbbe7a08f8313b5b51ad8de98bbc))
* **relay:** the courier carries any line that gets no channel copy; a successful join clears the hold ([a53e4b8](https://github.com/coreguild/CORELink/commit/a53e4b8cdcc35d3d6ec73c6d868357a66026aa73))
* **channel:** answer the client's password prompt for the link channel from the config ([b0aea00](https://github.com/coreguild/CORELink/commit/b0aea00e45a21615ca72a89fc03a36914b7f39f4))
* **channel:** a wrong-password notice that answers no join of ours means the client rejoined without the password ([6ff04fb](https://github.com/coreguild/CORELink/commit/6ff04fbdf53b3ce69f6e6086c1bf7b563d11a504))


### Documentation

* add ONBOARDING.md for new contributors starting without a GitHub account (#3) ([47b3a0a](https://github.com/coreguild/CORELink/commit/47b3a0a140061169981150dc6473e8612156d375))
* plain-language release flow in README (#6) ([716d46c](https://github.com/coreguild/CORELink/commit/716d46c8eee19822941400f1aeb3bfe13cf4f509))
* more technical release flow in README (CI checks, tags, gh-pages layout) (#7) ([fca718f](https://github.com/coreguild/CORELink/commit/fca718f7b1040906b5ce6ef143eaec46ac211bbd))
* agents never merge; merging is a human button press (#8) ([0e6dafe](https://github.com/coreguild/CORELink/commit/0e6dafe889db409532d987932a759afcfd674b87))
* merge commits instead of squash ([c09610d](https://github.com/coreguild/CORELink/commit/c09610d9a138f08085747c24926b9c34a70899b1))
* **mirror:** community text is a Kstring token; treat |K..|k as sealed ([673bafb](https://github.com/coreguild/CORELink/commit/673bafba03935bf859540c93e44dd85fb7efef49))
* one short README; commands, troubleshooting, development and architecture move to docs/ ([bb5df82](https://github.com/coreguild/CORELink/commit/bb5df827544ebf4e42908c159ca55c4b9e76658b))
* describe the text relay and courier transport; realms no longer matter ([0717930](https://github.com/coreguild/CORELink/commit/0717930511fdfd7da31bee4c7d38b7a918f6e704))
* **site:** install into the _forever_ client folder; /cl report shows the version ([6c57194](https://github.com/coreguild/CORELink/commit/6c5719462f544a6fb5aad47dcff61302d9c70b9a))


### Maintenance

* add start-feature skill so agents branch before editing ([7a9344b](https://github.com/coreguild/CORELink/commit/7a9344b0f29e5c322a918cd50ef5b6440935cf74))
* CI tests on every PR, PR template with feature notes, CHANGELOG, feature-request rules ([d65f36c](https://github.com/coreguild/CORELink/commit/d65f36c74c5a6b26cd1bc5fb74903802513ffc69))
* live game-version check in CI, gameplay-impact review checklist and review-pr skill ([92bfc95](https://github.com/coreguild/CORELink/commit/92bfc952f9dff6b84063392ea5df5c9a141090be))
* make the surname block set up its own joined client ([e4be41d](https://github.com/coreguild/CORELink/commit/e4be41df3aae401f308eb5feaf701b85d4746a88))
* close the merged harness block ([3dfd74d](https://github.com/coreguild/CORELink/commit/3dfd74de9fcc47baa5bac54790a38d5bd248983c))
* **mirror:** drop the piggyback; guild channels must be marked ([d0d02ef](https://github.com/coreguild/CORELink/commit/d0d02eff2ed7fed2b6f1412271e658802255c3a9))
* point install and version-check tooling at the live WoW: Forever client ([03b2c23](https://github.com/coreguild/CORELink/commit/03b2c235b74315c8460d6090e2f0f0737a322f94))
* **release:** cut release candidates from release/* branches, finals from main ([fdbbd7c](https://github.com/coreguild/CORELink/commit/fdbbd7cfaded8b2a2edbff66f2cbacc82ec5fb5b))
* split the addon into fourteen files by concern, one function per command and packet ([7c14736](https://github.com/coreguild/CORELink/commit/7c14736d666918ebcae78379273849c291a10416))
* register events set after Events.lua loads, load-order test, state ownership, command checks ([536c916](https://github.com/coreguild/CORELink/commit/536c916c86131ae272ffdfd904373dcdc525ee10))
* the GitHub organization is now coreguild ([4a82fa8](https://github.com/coreguild/CORELink/commit/4a82fa89cb73c2a3255deed89ec1eee4d12569f1))


### Other Changes

* /cl report and /cl debug diagnostics, luacheck in tests and CI (0.1.1) (#4) ([f3112b7](https://github.com/coreguild/CORELink/commit/f3112b785bbb1d68e34595743825f968340ce631))

## [0.2.0-rc3](https://github.com/core-wow-community/CORELink/compare/v0.2.0-rc2...v0.2.0-rc3) (2026-11-09)


### Bug Fixes

* **channel:** answer the client's password prompt for the link channel from the config ([b0aea00](https://github.com/core-wow-community/CORELink/commit/b0aea00e45a21615ca72a89fc03a36914b7f39f4))
* **channel:** a wrong-password notice that answers no join of ours means the client rejoined without the password ([6ff04fb](https://github.com/core-wow-community/CORELink/commit/6ff04fbdf53b3ce69f6e6086c1bf7b563d11a504))

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
