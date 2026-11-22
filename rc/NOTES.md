## [0.3.0-rc1](https://github.com/coreguild/CORELink/compare/v0.2.2...v0.3.0-rc1) (2026-11-22)


### Features

* **roster:** say once per session when a guildmate runs a newer release ([126ad2b](https://github.com/coreguild/CORELink/commit/126ad2b2225609c0a0a2d64b3f821d23478d9197))
* **relay:** say once per session when a linked guild sends a newer protocol than this version reads ([5140050](https://github.com/coreguild/CORELink/commit/514005005d19cf1346b4e19bcaeb055f8c845c6f))
* **members:** /cl members lists who is in the link channel, grouped by guild, also in the copy box ([fa34039](https://github.com/coreguild/CORELink/commit/fa340391f5907ca5796193fead6490c848f1a249))
* **members:** the report log records the request and how many names came back ([f3b612c](https://github.com/coreguild/CORELink/commit/f3b612c7659734eb191b23a6f57e0ed4b7bf0efa))
* **members:** one line per guild whether a peer is known by name or tag; gossip is not knowledge; fewer hellos ([b8501f2](https://github.com/coreguild/CORELink/commit/b8501f2bf9bea92fd702728f9e8e5696e45ff3f6))
* **report:** /cl report and the /cl status line say "version <number>" in words ([8a7cdea](https://github.com/coreguild/CORELink/commit/8a7cdeadbd4ebafcaae73a3d310a795c617cfbe3))


### Bug Fixes

* **roster:** the update notice names the guildmate instead of claiming a release, once per version ([28591f7](https://github.com/coreguild/CORELink/commit/28591f786752d1a6385c6e3fda831249ebb8302e))
* **ci:** the game-version check fails when the TOC does not list the live interface ([4c5b3aa](https://github.com/coreguild/CORELink/commit/4c5b3aa2497bbabcc04d4826687d36b04e39af46))
* **commands:** plain /cl no longer prints the stale "(0 = success)" hint ([683fee4](https://github.com/coreguild/CORELink/commit/683fee4616a32507fe21f9c20956cb97d0ef1689))
* **commands:** /cl who names the guild's courier instead of a realm ([3057957](https://github.com/coreguild/CORELink/commit/30579571ef73c67e47d940bdaf350afd3a063add))
* **release:** a release candidate carries its rc number in game and in its zip name ([1436dac](https://github.com/coreguild/CORELink/commit/1436dac22247230f1c41a2773e2a7e2066c03f73))
* clean names and tags sent by other clients and harden the chat handlers ([ea235d6](https://github.com/coreguild/CORELink/commit/ea235d6d6e1a44c0536d74ac624ac421d4412b4b))
* **ci:** only an unreachable version server passes with a warning, and only on pull requests ([0750dea](https://github.com/coreguild/CORELink/commit/0750dea9978016d31d24c9da79f341a434ed91eb))
* **relay:** the newer-protocol notice needs a packet's shape and skips our own and muted guilds ([c2efdd5](https://github.com/coreguild/CORELink/commit/c2efdd51a1f1925ef9e5545b9e825dd23e84d8f4))
* **site:** the candidate card stays hidden when stable has moved past the candidate ([5fdd8b0](https://github.com/coreguild/CORELink/commit/5fdd8b0907df2e92066c95790d306d8bc0e0c06c))
* strip line breaks from relayed text, clean peer cards, and wait ten minutes before forgetting a nickname ([f103ac1](https://github.com/coreguild/CORELink/commit/f103ac11c4723e11c76acf01af314b2490ccd6ba))
* **channel:** keep the link-channel name match as it was in 0.2.0 ([07b2604](https://github.com/coreguild/CORELink/commit/07b26047389b949a090540d0c1ccdf2a81ca48a2))
* **roster:** a client on a release candidate is told when its release is out ([7cd81e2](https://github.com/coreguild/CORELink/commit/7cd81e2bcde79a9d610ff9f80094c4bb9b73d45e))
* **relay:** a line with a quest link is no longer shown more than once in the linked guild ([c44b7b7](https://github.com/coreguild/CORELink/commit/c44b7b7261b9e17457ea1da3e7e372045626d18f))
* **relay:** two variants of one item linked back to back are both shown; the line key keeps a link's name ([e8e4863](https://github.com/coreguild/CORELink/commit/e8e486338baba84306b7ad0e637e90e4f747adfb))
* **relay:** only quest links are compared by quest id; other links keep their data, the community copy is matched too ([65f615f](https://github.com/coreguild/CORELink/commit/65f615f51578577df8f82e9ce3afbcb3c6b524f6))
* **relay:** a line on the link channel is shown under the player who posted it, not the name written in it ([251a6ab](https://github.com/coreguild/CORELink/commit/251a6ab5e061e5b4e3da0ebb54261b2a9373358d))
* **relay:** a packet naming another author also loses the rank and nickname it claims, and its poster is no peer ([973793d](https://github.com/coreguild/CORELink/commit/973793d70ff2b213179cda8e10456dc63c123400))
* **relay:** a line is dropped when its author is not a possible character name, or a guildmate sends it for another guild ([aacbda8](https://github.com/coreguild/CORELink/commit/aacbda8bf0eb5401eb33ee12feefcb44bc45a1c9))
* **relay:** the name rule covers the whole author and only where the game does not name the poster ([3735225](https://github.com/coreguild/CORELink/commit/37352253c6bc2d1e32d36ce45b1ac1c8b6447c7b))
* **relay:** a realm after the author's name may use any letters; only spaces, pipes and control bytes are refused ([b281790](https://github.com/coreguild/CORELink/commit/b281790bfe02bbb68e3ed91abbc6d53f6b20ffd7))


### Documentation

* **skills:** unslop skill, trimmed to this project's prose, run from the self-review when prose changes ([a0337bb](https://github.com/coreguild/CORELink/commit/a0337bb082dd37dbc58b350d8c36bceedfac5753))
* **skills:** unslop keeps the repository's own conventions; the self-review reads the file, since it is hidden ([5fc7d00](https://github.com/coreguild/CORELink/commit/5fc7d0022a8e98e3d7a0a7f44a35c440c6517fdb))
* **commands:** lastSend ok, not 0, in troubleshooting; describe the /cl who refusal without quoting it ([5a90132](https://github.com/coreguild/CORELink/commit/5a901326f01b4be1ae0e15e723a2a3fbdb578860))
* what a receiver can and cannot tell about a forged line ([9d13d17](https://github.com/coreguild/CORELink/commit/9d13d17dfb477c5de7c4c6ff1a8a8634f84f9608))


### Maintenance

* **harness:** the version checks fail, not crash, against an addon without the feature ([49fb02b](https://github.com/coreguild/CORELink/commit/49fb02be77738661ac7ae936b7e14f19819a10c7))
* **commands:** keep the /cl who check from shifting the who rounds after it ([d4a4d16](https://github.com/coreguild/CORELink/commit/d4a4d160d0fd8b4b4c74628bd9673b3afcaf1c03))
* the fan-out check uses a guildmate who is already an addon user, so the courier does not change ([ec6c90b](https://github.com/coreguild/CORELink/commit/ec6c90b858253263091dbd9eb3e0d400e3477070))
* **compat:** the oldest supported release is 0.2.2 ([9ec23fa](https://github.com/coreguild/CORELink/commit/9ec23fa67d6fd4fb7825f22eaf101ec33dfc718a))

Direct download (RC channel): https://coreguild.github.io/CORELink/rc/CORELink.zip
