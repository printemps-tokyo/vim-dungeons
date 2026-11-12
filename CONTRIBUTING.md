# Contributing

Thanks for your interest in contributing to a printemps-tokyo project.

## Development

1. Fork / clone the repository
2. Try the game locally:
   ```bash
   nvim --cmd 'set rtp+=.' +VimDungeons
   ```
3. Create a branch: `git switch -c feat/your-change`
4. Make your change and verify locally:
   ```bash
   XDG_DATA_HOME=$(mktemp -d) nvim --headless --clean -l tests/smoke.lua
   ```
5. Commit and open a pull request

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/) are preferred
(`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`).

## Pull requests

- Keep one PR focused on a single purpose
- CI (headless smoke tests) must be green
- Update the README and tests when behavior changes
- Game text goes through `lua/vimdungeons/i18n.lua`; add both the Japanese
  source string and its English translation

## Bug reports and requests

Please open an [issue](../../issues).
