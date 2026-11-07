// SPDX-License-Identifier: GPL-3.0-only

'use strict';
'require baseclass';
'require rpc';

const callStatus = rpc.declare({
	object: 'honk',
	method: 'status',
	expect: { '': {} }
});

const callCheck = rpc.declare({
	object: 'honk',
	method: 'check',
	expect: { '': {} }
});

const callInitialize = rpc.declare({
	object: 'honk',
	method: 'initialize',
	params: [ 'username', 'password' ],
	expect: { '': {} }
});

const callStart = rpc.declare({ object: 'honk', method: 'start', expect: { '': {} } });
const callStop = rpc.declare({ object: 'honk', method: 'stop', expect: { '': {} } });
const callRestart = rpc.declare({ object: 'honk', method: 'restart', expect: { '': {} } });

const callSettings = rpc.declare({
	object: 'honk',
	method: 'settings',
	params: [ 'lan_network', 'listen_port', 'boot_enabled' ],
	expect: { '': {} }
});

const callRepair = rpc.declare({ object: 'honk', method: 'repair', expect: { '': {} } });
const callBackup = rpc.declare({ object: 'honk', method: 'backup', expect: { '': {} } });
const callRestore = rpc.declare({ object: 'honk', method: 'restore', expect: { '': {} } });
const callRestorePrepare = rpc.declare({ object: 'honk', method: 'restore_prepare', expect: { '': {} } });
const callReset = rpc.declare({ object: 'honk', method: 'reset', expect: { '': {} } });
const callJobStatus = rpc.declare({
	object: 'honk',
	method: 'job_status',
	params: [ 'job_id' ],
	expect: { '': {} }
});
const callLogs = rpc.declare({
	object: 'honk',
	method: 'logs',
	params: [ 'source', 'level', 'limit' ],
	expect: { '': {} }
});
const callUpdateCheck = rpc.declare({ object: 'honk', method: 'update_check', expect: { '': {} } });
const callUpdateApply = rpc.declare({ object: 'honk', method: 'update_apply', expect: { '': {} } });
const callSetGeo = rpc.declare({
	object: 'honk',
	method: 'set_geo',
	params: [ 'geoip_url', 'geosite_url', 'geo_auto', 'geo_auto_freq' ],
	expect: { '': {} }
});

let pageStylesInstalled = false;

function installStyles() {
	if (pageStylesInstalled || document.getElementById('honk-page-styles'))
		return;

	const stylesheet = document.createElement('link');
	stylesheet.id = 'honk-page-styles';
	stylesheet.rel = 'stylesheet';
	stylesheet.href = L.resource('view/honk/honk.css');
	document.head.appendChild(stylesheet);
	pageStylesInstalled = true;
}

function isIpLiteral(host) {
	const bare = String(host || '').replace(/^\[|\]$/g, '');
	if (!bare)
		return false;
	if (bare.indexOf(':') >= 0)
		return true;
	const octets = bare.split('.');
	return octets.length === 4 && octets.every(function(part) { return /^\d{1,3}$/.test(part) && Number(part) <= 255; });
}

function authorityHost(host) {
	const bare = String(host || '').replace(/^\[|\]$/g, '');
	return bare.indexOf(':') >= 0 ? '[' + bare + ']' : bare;
}

function hostFromApiUrl(apiUrl) {
	try {
		return new URL(String(apiUrl || '')).hostname || '';
	}
	catch (e) {
		return '';
	}
}

function isLoopback(host) {
	const bare = String(host || '').replace(/^\[|\]$/g, '').toLowerCase();
	if (bare === 'localhost' || bare === '::1' || bare === '0:0:0:0:0:0:0:1')
		return true;
	const octets = bare.split('.');
	return octets.length === 4 && octets.every(function(part) { return Number(part) === 0; });
}

function localWebUi(status) {
	if (!status || !status.initialized || !status.running || !status.api_ready)
		return null;

	const port = Number(status.listen_port);
	if (!Number.isInteger(port) || port < 1 || port > 65535)
		return null;

	// The core binds the native API to every interface, so the panel is reached
	// through the address the browser already uses for the router. A wildcard
	// bind accepts only an IP literal or localhost as the Host, so a name the
	// browser used falls back to the address the core reports.
	const browserHost = (window.location && window.location.hostname) || '';
	let host = browserHost;
	if (!isIpLiteral(host) && host !== 'localhost')
		host = hostFromApiUrl(status.api_url);
	if (!host)
		return null;
	// A loopback address only reaches a browser on the router itself; on any
	// other machine it would open the client instead of the panel.
	if (isLoopback(host) && !isLoopback(browserHost))
		return null;

	return 'http://' + authorityHost(host) + ':' + port + '/ui/';
}

function tokenMessage(token) {
	const messages = {
		disabled: _('Honk is disabled.'),
		not_initialized: _('Complete initial setup before starting Honk.'),
		service_not_running: _('Honk is enabled but currently stopped.'),
		api_unavailable: _('Honk is running, but its management interface is not ready.'),
		operation_in_progress: _('Another Honk operation is in progress.'),
		stale_operation_lock: _('A previous operation did not finish cleanly.'),
		started: _('Honk started.'),
		already_running: _('Honk is already running.'),
		stopped: _('Honk stopped.'),
		restarted: _('Honk restarted.'),
		settings_saved: _('Settings saved and applied.'),
		initialized: _('Honk initialized.'),
		administrator_initialized: _('Honk initialized.'),
		system_config_healthy: _('System check passed.'),
		system_config_repaired: _('Repair completed.'),
		backup_created: _('Backup created.'),
		restored: _('Backup restored.'),
		data_reset: _('Honk data reset. The service is stopped.'),
		worker_lost: _('The maintenance worker stopped unexpectedly; check system recovery status before retrying.'),
		operation_failed: _('The maintenance operation failed.'),
		job_timeout: _('The maintenance operation timed out.'),
		maintenance_recovery_required: _('Recovery is required. Run system recovery before starting another maintenance operation.'),
		update_recovery_required: _('The signed update did not finish. Keep Honk stopped and reinstall a complete verified package set before retrying.'),
		rollback_tuple_unavailable: _('A compatible update is available, but a complete verified rollback package set is not available yet.'),
		trusted_feed_unavailable: _('No trusted update source is configured.'),
		manifest_incompatible: _('The signed update manifest does not match this device.'),
		signed_manifest_unavailable: _('The signed update manifest could not be fetched or verified.'),
		update_available: _('A compatible update is available.'),
		no_update: _('No compatible update is available.'),
		already_current: _('Honk is already up to date.'),
		update_apply_failed: _('The update could not be installed.'),
		update_check_failed: _('The signed update could not be verified for this device.'),
		signed_manifest_missing: _('Check for updates again to refresh the signed manifest.'),
		signed_manifest_expired: _('The signed manifest expired. Check for updates again.'),
		reset_failed: _('Reset failed; the previous service state was restored.'),
		reset_failed_rollback_failed: _('Reset failed and automatic recovery did not finish. Run system recovery before retrying.'),
		restore_failed_rollback_failed: _('Restore failed and automatic recovery did not finish. Run system recovery before retrying.'),
		logs_unavailable: _('Honk logs are unavailable.'),
		invalid_request: _('The import request is incomplete or invalid.'),
		upload_unavailable: _('A private upload location could not be prepared.'),
		settings_write_failed: _('Could not save Honk settings.'),
		curl_missing: _('The curl command is missing. Install the curl package and try again.'),
		start_failed: _('Honk could not start.'),
		stop_failed: _('Honk could not stop.'),
		restart_failed: _('Honk could not restart.'),
		managed_service_unhealthy: _('The managed Honk service is not healthy.'),
		unmanaged_core_running: _('An unmanaged Honk core process is running.'),
		invalid_lan_network: _('The selected LAN network is invalid or unavailable.'),
		lan_network_unavailable: _('The selected LAN network is unavailable.'),
		listen_port_occupied: _('The listen port is already in use.'),
		invalid_listen_port: _('The listen port is invalid.'),
		initialize_before_enabling_service: _('Complete initial setup before enabling Honk.'),
		system_config_unavailable: _('Honk system configuration is unavailable.'),
		package_config_unavailable: _('Honk configuration is unavailable.'),
		service_apply_failed_rolled_back: _('Settings could not be applied. The previous settings were restored.'),
		invalid_credentials: _('The administrator name or password is not correct.'),
		core_missing: _('The Honk core binary is missing. Reinstall the package.'),
		ui_assets_missing: _('The Honk panel assets are missing. Reinstall the honk package.'),
		udp_trace_unavailable: _('The kernel lacks the optional UDP receive-trace support (ftrace/BTF), so kernel route evidence is incomplete. UDP and QUIC traffic is still proxied.'),
		administrator_exists_reuse_credentials_or_reset_state: _('An administrator already exists. Use the same credentials or reset the data.'),
		invalid_settings_json: _('The settings request is not valid.'),
		settings_too_large: _('The settings request is too large.'),
		invalid_geo_url: _('The geo data URL is not a valid https URL.'),
		invalid_geo_auto: _('The auto-update switch is not valid.'),
		invalid_geo_auto_freq: _('The auto-update schedule is not valid.'),
		geo_settings_saved: _('Geo data source saved.')
	};

	// An unknown token is shown as it is: a swallowed reason leaves the user
	// with a generic message and nothing to act on.
	return messages[token] || token || null;
}

function statusIssue(token) {
	return tokenMessage(token) || _('Honk reported a system issue.');
}

function resultMessage(result, fallback) {
	return result && tokenMessage(result.message) || fallback;
}

function errorMessage(error, fallback) {
	return error && tokenMessage(error.message) || fallback;
}

function jobPhaseMessage(phase) {
	const messages = {
		queued: _('Waiting for the operation to start…'),
		checking_feed: _('Checking the signed update source…'),
		downloading: _('Downloading the signed package set…'),
		preparing: _('Preparing configuration apply…'),
		validating_candidate: _('Validating the candidate in an isolated runtime…'),
		stopping: _('Stopping Honk safely…'),
		applying: _('Applying the reviewed configuration…'),
		validating: _('Checking the updated configuration…'),
		starting: _('Restoring the previous service state…'),
		rolling_back: _('Restoring the previous configuration…'),
		committing: _('Finishing the transaction…'),
		recovery: _('Recovery is required before another operation.')
	};
	return messages[phase] || _('Applying configuration…');
}

function ensureOk(result) {
	if (!result || result.ok !== true)
		throw new Error(result && result.message ? result.message : _('The backend did not confirm the operation.'));

	return result;
}

function waitJob(jobId, onProgress) {
	if (!/^[0-9a-f]{32}$/.test(jobId || ''))
		return Promise.reject(new Error('invalid_job_id'));

	let attempts = 0;
	return new Promise(function(resolve, reject) {
		function poll() {
			callJobStatus(jobId).then(function(result) {
				if (!result || typeof result.state !== 'string')
					throw new Error('invalid_job_status');
				if (onProgress)
					onProgress(result);
				if (result.state === 'succeeded') {
					resolve(result);
					return;
				}
				if (result.state === 'failed' || result.state === 'rollback_required') {
					const error = new Error(result.state === 'rollback_required' ? 'maintenance_recovery_required' : result.message || 'operation_failed');
					error.recoveryRequired = result.state === 'rollback_required';
					reject(error);
					return;
				}
				if (result.state !== 'queued' && result.state !== 'running') {
					reject(new Error('invalid_job_status'));
					return;
				}
				if (++attempts >= 1800) {
					reject(new Error('job_timeout'));
					return;
				}
				setTimeout(poll, 1000);
			}).catch(reject);
		}
		poll();
	});
}

return baseclass.extend({
	status: callStatus,
	check: callCheck,
	initialize: callInitialize,
	start: callStart,
	stop: callStop,
	restart: callRestart,
	settings: callSettings,
	repair: callRepair,
	backup: callBackup,
	restore: callRestore,
	restorePrepare: callRestorePrepare,
	reset: callReset,
	logs: callLogs,
	updateCheck: callUpdateCheck,
	updateApply: callUpdateApply,
	setGeo: callSetGeo,
	waitJob: waitJob,
	ensureOk: ensureOk,
	localWebUi: localWebUi,
	statusIssue: statusIssue,
	resultMessage: resultMessage,
	errorMessage: errorMessage,
	jobPhaseMessage: jobPhaseMessage,
	installStyles: installStyles
});
