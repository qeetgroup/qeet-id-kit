# Troubleshooting the Qeet ID Kit

**Run Doctor first** (`bash macos/tools/doctor.sh`, `bash linux/tools/doctor.sh` or
`.\windows\tools\doctor.cmd`). It checks Docker, memory, disk, port 80, your GitHub sign-in
(including that it can download every image) and the kit itself, and says what to fix.

The tables below list the messages the kit shows, what they mean and what to do. Messages and
commands are shown for TEST on macOS. For STAGING the message names STAGING and the command uses
`staging/` instead of `test/`; on Linux use `linux/` instead of `macos/`, and on Windows
`.\windows\…\….cmd` (for example `.\windows\staging\reset.cmd`).

## Docker and your computer

| You see | Do this |
|---|---|
| *Docker is not installed.* | Install Docker Desktop (macOS, Windows) or Docker Engine (Linux), start it, try again. |
| *Docker Desktop is installed but is not running.* | Start Docker Desktop, wait until it says it is running, try again. |
| *Docker is running Windows containers.* | Right-click the Docker icon in the taskbar, choose **Switch to Linux containers**, try again. |
| *Docker Compose is not available* / *Docker Compose X is too old* | Update Docker Desktop (Linux: install Docker Compose 2.24 or newer). |
| *Port 80 is already in use by another program.* | Another program uses port 80, which the kit needs. Windows: often IIS / *World Wide Web Publishing Service*; stop it in Services, or ask IT. macOS: `sudo lsof -nP -iTCP:80 -sTCP:LISTEN` shows the program. |
| Doctor: *Docker has only N MiB of memory* | Docker Desktop → Settings → Resources: give Docker at least 2 GiB. |

## GitHub sign-in and downloads

| You see | Do this |
|---|---|
| *Unable to download Qeet ID: this computer's GitHub sign-in cannot read the Qeet ID packages.* or *Signed in, but this sign-in cannot download everything Qeet ID needs* | Run **Login** again (`bash macos/tools/login.sh`) with a **classic** token that has `read:packages` (fine-grained tokens do not work). If it still fails, your GitHub account has not been given access to the `qeetgroup` packages: ask your team lead. |
| *Sign-in to ghcr.io failed.* | The username or token is wrong, or the token has expired. Create a new classic token and run **Login** again. |
| *Docker's sign-in helper is not working* | Restart Docker Desktop and try again. If it keeps happening, reinstall Docker Desktop. |
| *The image registry is limiting downloads right now (too many requests).* | A public registry is briefly limiting downloads, which is common on shared office networks. Wait a minute and run the same command again. Nothing was changed. |
| *Cannot reach the image registry* | Check your internet connection, VPN or proxy. If the environment is already installed, Start warns *Could not check for a newer release* and starts the installed version. |
| *No Qeet ID release candidate is published as 'test' yet.* | Nothing has been released for testing yet. Ask the release manager. |
| *… needs Qeet ID Kit X or newer* / *… needs a newer Qeet ID Kit* | Run **Update Kit** (`bash macos/tools/update-kit.sh`). It installs the new kit in a folder next to this one; your data and changed settings are kept. |

## Starting an environment

| You see | Do this |
|---|---|
| *… failed its health check* | Run **Logs** (`bash macos/test/logs.sh`) and send the output to the Qeet ID team. |
| *Qeet ID Server refused its configuration:* followed by reasons | Usually a value you set in `environments/optional.env`. Fix the line it names, or put back the default, and start again. If you changed nothing there, send the message to the Qeet ID team. |
| *Database migrations for this release failed* | Run **Logs** for the server (`bash macos/test/logs.sh server`) and send it to the Qeet ID team. If your data is older than this release allows, **Reset** starts fresh. |
| *The local edge (port 80) did not start.* | Run **Doctor**. If it finds nothing, restart Docker Desktop and try again. |
| *TEST started but is not reachable.* | Run **Doctor**, then send the **Logs** output for the edge (`bash macos/test/logs.sh edge`) to the Qeet ID team. |
| *settings/.env is no longer read.* | Your settings from an older kit: copy their values into `environments/optional.env`, then delete the `settings` folder. |
| Warning: *Email is not being delivered to the Mail inbox* | Run **Logs** for the server and send it to the Qeet ID team. Verification codes will not arrive until it is fixed. |

## Your data

These messages appear before anything is changed. Your data is still there.

| You see | Do this |
|---|---|
| *… cannot use your existing TEST data* / *… is older than your TEST data* | This candidate needs fresh data. Run **Reset** (`bash macos/test/reset.sh`). |
| *The last database migration in TEST did not finish* | The data is in an unknown state. Run **Reset**. |
| *Existing TEST data was found, but its keys are missing* | TEST's local keys were deleted, so its data cannot be opened. Run **Reset**. |
| *PostgreSQL did not start for the compatibility check.* | Restart Docker Desktop and try again. If it repeats, send the **Logs** output for the database (`bash macos/test/logs.sh db`). |
| *No earlier TEST candidate is available on this computer.* | Rollback needs a previous candidate, which exists only after you have updated at least once. |
| *No Qeet ID candidate has been promoted to STAGING yet.* | QA has not approved a candidate yet. STAGING receives one when the release manager promotes it; ask them. |
| Rollback: *… is older than your TEST data* | Roll back with fresh data: `bash macos/test/rollback.sh --reset` (deletes TEST's data). |

## In the browser

| You see | Do this |
|---|---|
| *Qeet ID TEST is not running on this computer.* | Start that environment. |
| *Not a Qeet ID address.* | Check the address. Addresses look like `http://console.test.id.qeet.localhost` (or `staging` instead of `test`). |
| The page does not open at all | Use Google Chrome or Microsoft Edge, and check that the environment is running (**Status**). |
| A verification email never arrives | Open the **Mail inbox** (<http://mail.test.id.qeet.localhost>). If it stays empty, run **Logs** for the server. |
| The passkey prompt offers old passkeys after a Reset | Delete the passkeys saved for `test.id.qeet.localhost` in your browser or password manager. |

## Sending details to the Qeet ID team

- **Status** (`bash macos/test/status.sh`) shows the candidate and every component's version.
- **Logs** (`bash macos/test/logs.sh`) shows recent output. Add a service name for just one:
  `server`, `login`, `console`, `website`, `docs`, `db`, `mail` or `edge`.
- Adding `--verbose` to any command prints every Docker command it runs and that command's output.

Never paste passwords, tokens or cookie values into Jira or chat.
