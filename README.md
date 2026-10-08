# arcade-deploy

A GitHub Action that uploads a game's browser bundle to [arcade](https://github.com/Stephenson-Software/arcade),
the shared host for browser games at `<slug>.play.danielstephenson.dev` (Stephenson-Software RFC 0006).

It tars the game's `index.html`, `game.zip` and `version.txt` (or, with `site-dir`, a whole static
site) and `PUT`s them to arcade's API with the game's token. The version deployed is whatever
`version.txt` says, and arcade refuses a `version.txt` that disagrees with it. Any non-2xx response
fails the step with the server's reason, except a 409 when `skip-existing` is `true`.

## Use

```yaml
# .github/workflows/deploy.yml in a game's repository
name: Deploy
on:
  push:
    tags: ['v*']
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install -r requirements.txt && python3 web/build_zip.py
      - uses: Stephenson-Software/arcade-deploy@v1
        with:
          slug: tidewater
          token: ${{ secrets.ARCADE_TOKEN }}
```

Before the first deploy, the game needs an entry in the gateway's `games.yaml` with the
`token_sha256` of its token, and the token itself as the repository secret `ARCADE_TOKEN`. The
arcade README explains how to mint both.

## A static game (pygbag, Emscripten, plain HTML/JS)

For a game registered with `kind: static`, upload a whole build directory:

```yaml
      - run: pip install pygbag && python -m pygbag --build src
      - uses: Stephenson-Software/arcade-deploy@v1
        with:
          slug: rock-paper-scissors
          token: ${{ secrets.ARCADE_TOKEN }}
          site-dir: src/build/web
```

The action writes `version.txt` into the uploaded tree and dereferences links, which arcade refuses.

## Inputs

| Input | Default | |
|---|---|---|
| `slug` | (required) | the game's slug in `games.yaml` |
| `token` | (required) | the upload token; pass a secret |
| `index` | `web/index.html` | the page |
| `game-zip` | `web/game.zip` | the built bundle |
| `site-dir` | (empty) | for a `kind: static` game, a directory uploaded as the whole site (must hold `index.html`); `index` and `game-zip` are then ignored |
| `version-file` | `version.txt` | its contents are the version |
| `url` | `https://play.danielstephenson.dev` | arcade's API base |
| `activate` | `true` | `false` stores the version without making it live (promote later with arcade's `POST /api/games/<slug>/current`) |
| `skip-existing` | `false` | treat "already deployed" (409) as success, for re-run jobs |

Outputs: `version` and `url`.

Versions are immutable. Re-running a deploy of the same version fails unless `skip-existing` is
`true`, so a changed game needs a new `version.txt`.

The token is written to a temporary header file (mode 600), not passed on the command line, and the
file is deleted when the step ends.

## By hand

`deploy.sh` runs outside Actions with the same inputs as `ARCADE_*` variables:

```sh
ARCADE_SLUG=tidewater ARCADE_TOKEN="$(cat token.txt)" ./deploy.sh
```

## Tests

CI starts a real arcade from a pinned release on `play.localhost` and deploys through the action.
It covers a first deploy, the game being served, a re-run failing, `skip-existing`, a wrong token,
an empty token, an empty slug, `activate: false`, and a static site uploaded with `site-dir`.

## License

[Stephenson Software Non-Commercial License (Stephenson-NC)](LICENSE).
