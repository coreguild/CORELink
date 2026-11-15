▎ Two fixes for the live link. When a player in a linked guild logs off, CORELink no longer shows "No player named … is currently playing" for every carried line; it stops whispering that player and sends the line to another addon user in their guild. Guilds with a guilds= list on their Guild Info line no longer get "Interface action failed because of an AddOn": the lookup that caused it is removed, and guilds= is now ignored. Nothing changes on the wire, so 0.2.0 and 0.2.1 clients keep working together.

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

Direct download (RC channel): https://coreguild.github.io/CORELink/rc/CORELink.zip
