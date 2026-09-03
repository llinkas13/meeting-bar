'use strict';

/**
 * paths.js — every file this project reads or writes, resolved in one place.
 *
 * Three roots, kept apart on purpose:
 *
 *   HOME    the checkout itself. Holds code, config.json, and .secrets/ (both gitignored).
 *           Override with $MEETING_BAR_HOME. The menu bar app needs this: a GUI process cannot find the
 *           checkout by walking up from inside its .app bundle, so build.sh stamps the path in.
 *   DATA    ~/Library/Application Support/meeting-bar/ — events.json and sync state.
 *           Data, not logs, so `rm -rf` on the log directory cannot cost you your sync cursor.
 *           EVENTS_FILE alone can be redirected with $MEETING_BAR_EVENTS_FILE — lets another system drive
 *           the menu bar's display, or a test point it at fixture data, without forking the app.
 *   LOGS    ~/Library/Logs/meeting-bar/ — plain text, safe to delete at any time.
 *
 * Secrets live in the checkout rather than under ~/.config because that keeps one directory to
 * back up and one to delete, and because build.sh already has to know where the checkout is.
 */

const os = require('os');
const path = require('path');

const HOME = process.env.MEETING_BAR_HOME
  ? path.resolve(process.env.MEETING_BAR_HOME)
  : path.resolve(__dirname, '..');

const DATA = path.join(os.homedir(), 'Library', 'Application Support', 'meeting-bar');
const LOGS = path.join(os.homedir(), 'Library', 'Logs', 'meeting-bar');

module.exports = {
  HOME,
  DATA,
  LOGS,
  CONFIG_FILE: process.env.MEETING_BAR_CONFIG
    ? path.resolve(process.env.MEETING_BAR_CONFIG)
    : path.join(HOME, 'config.json'),
  SECRETS: path.join(HOME, '.secrets'),
  CLIENT_FILE: path.join(HOME, '.secrets', 'oauth-client.json'),
  TOKEN_FILE: path.join(HOME, '.secrets', 'token.json'),
  EVENTS_FILE: process.env.MEETING_BAR_EVENTS_FILE
    ? path.resolve(process.env.MEETING_BAR_EVENTS_FILE)
    : path.join(DATA, 'events.json'),
  SYNC_STATE_FILE: path.join(DATA, 'drive-sync-state.json'),
};
