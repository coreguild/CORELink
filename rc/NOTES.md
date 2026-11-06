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

Direct download (RC channel): https://core-wow-community.github.io/CORELink/rc/CORELink.zip
