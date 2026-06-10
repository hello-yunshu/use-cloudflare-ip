'use strict';
'require view';
'require ui';
'require rpc';
'require uci';
'require form';
'require cloudflare-ip/utils as utils';

var callRefreshEnv = rpc.declare({
	object: 'cf_ip',
	method: 'refresh-env',
	expect: { '': {} }
});

var callRun = rpc.declare({
	object: 'cf_ip',
	method: 'run',
	expect: { '': {} }
});

var callSpeedtestStatus = rpc.declare({
	object: 'cf_ip',
	method: 'speedtest-status',
	expect: { '': {} }
});

var callServiceStart = rpc.declare({
	object: 'cf_ip',
	method: 'start',
	expect: { '': {} }
});

var callServiceStop = rpc.declare({
	object: 'cf_ip',
	method: 'stop',
	expect: { '': {} }
});

var callDownloadCfst = rpc.declare({
	object: 'cf_ip',
	method: 'download-cfst',
	expect: { '': {} }
});

var SPEEDTEST_POLL_INTERVAL = 3000;

var STATUS_LABELS = {
	scheduled: _('Scheduled'),
	running: _('Running'),
	success: _('Success'),
	error: _('Error'),
	stopped: _('Stopped'),
	unknown: _('unknown')
};

function translateStatus(status) {
	if (typeof status !== 'string')
		return STATUS_LABELS.unknown || status;
	if (STATUS_LABELS[status])
		return STATUS_LABELS[status];
	if (status.indexOf('success') === 0)
		return STATUS_LABELS.success;
	return status;
}

function showSpeedtestModal() {
	var statusNode = E('span', { 'class': 'cfi-badge orange' }, '\u23F3 ' + _('Running'));
	var logNode = E('textarea', {
		'class': 'cbi-input-textarea cfi-log-area is-loading',
		'rows': 20,
		'readonly': 'readonly'
	}, _('Loading...'));
	var modalOpen = true;

	function setLogText(text) {
		logNode.value = text;
	}

	function update(result) {
		result = result || {};
		var status = result.last_result || 'unknown';
		var isRunning = status === 'running';

		if (status === 'success' || (typeof status === 'string' && status.indexOf('success') === 0)) {
			statusNode.className = 'cfi-badge green';
			statusNode.textContent = '\u2714 ' + translateStatus(status);
		} else if (status === 'running') {
			statusNode.className = 'cfi-badge orange';
			statusNode.textContent = '\u23F3 ' + translateStatus(status);
		} else if (status === 'error') {
			statusNode.className = 'cfi-badge red';
			statusNode.textContent = '\u2718 ' + translateStatus(status);
		} else {
			statusNode.className = 'cfi-badge gray';
			statusNode.textContent = translateStatus(status);
		}

		var logData = result.log_data || {};
		var logs = logData.logs || '';
		if (logs && logs.trim()) {
			logNode.className = 'cbi-input-textarea cfi-log-area';
			setLogText(logs);
			logNode.scrollTop = logNode.scrollHeight;
		} else if (!isRunning) {
			logNode.className = 'cbi-input-textarea cfi-log-area is-empty';
			setLogText(_('No log output yet.'));
		}

		if (modalOpen && isRunning)
			setTimeout(refresh, SPEEDTEST_POLL_INTERVAL);
	}

	function refresh() {
		callSpeedtestStatus().then(update).catch(function(err) {
			logNode.className = 'cbi-input-textarea cfi-log-area is-error';
			setLogText(_('Failed to get status: ') + String(err));
		});
	}

	ui.showModal(_('Speedtest Log'), [
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Status')),
			E('div', { 'class': 'cbi-value-field' }, statusNode)
		]),
		E('div', { 'class': 'cbi-value cfi-value-full' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Log')),
			E('div', { 'class': 'cbi-value-field' }, logNode)
		]),
		E('div', { 'class': 'right' }, [
			E('button', { 'class': 'btn', 'click': refresh }, _('Refresh')),
			E('button', {
				'class': 'btn',
				'click': function() {
					modalOpen = false;
					ui.hideModal();
					location.reload();
				}
			}, _('Close'))
		])
	]);

	refresh();
}

function waitReadyAndReload() {
	return utils.waitForServiceReady(utils.callStatus).then(function(status) {
		if (status && status.last_result === 'running')
			ui.addNotification(null, E('p', _('Service action completed, but speedtest is still in progress. Refreshing current status.')), 'warning');
		utils.reloadSoon(300);
		return status;
	});
}

function makeEnvBadge(installed, label) {
	if (installed) {
		return E('span', { 'class': 'cfi-badge green' }, '\u2714 ' + (label || _('Installed')));
	}
	return E('span', { 'class': 'cfi-badge orange' }, '\u2718 ' + (label || _('Missing')));
}

function makePluginBadge(installed, running) {
	if (running) {
		return E('span', { 'class': 'cfi-badge green' }, '\u2714 ' + _('Running'));
	} else if (installed) {
		return E('span', { 'class': 'cfi-badge orange' }, '\u26A0 ' + _('Installed (Stopped)'));
	}
	return E('span', { 'class': 'cfi-badge orange' }, '\u2718 ' + _('Not Installed'));
}

function buildDepSection(missingDeps, pkgManager) {
	var section = E('div', { 'class': 'cbi-section cfi-section' });
	section.appendChild(E('h3', {}, _('Missing Dependencies & Fix Commands')));
	if (missingDeps.length > 0) {
		var installCmd = pkgManager === 'apk' ?
			'apk add --allow-untrusted ' + missingDeps.join(' ') :
			'opkg install ' + missingDeps.join(' ');
		section.appendChild(E('p', { 'style': 'color:var(--warning-color, #d89b00);margin-bottom:0.5em' },
			'\u2718 ' + _('Missing dependencies: ') + missingDeps.join(', ')));
		section.appendChild(E('div', { 'class': 'cfi-cmd-box' }, installCmd));
	} else {
		section.appendChild(E('p', { 'style': 'color:var(--success-color, #3aa657)' },
			'\u2714 ' + _('All dependencies are installed.')));
	}
	return section;
}

var css = `
	.cfi-status-banner {
		display: flex; align-items: center; gap: 1.2em;
		padding: 1.5em; margin-bottom: 1.5em;
	}
	.cfi-status-banner.running { border-left: 5px solid var(--success-color, #3aa657); }
	.cfi-status-banner.stopped { border-left: 5px solid var(--warning-color, #d89b00); }
	.cfi-status-banner.running-test { border-left: 5px solid var(--main-color, #0069d9); }
	.cfi-status-icon { font-size: 2.5em; line-height: 1; flex-shrink: 0; }
	.cfi-status-icon.running { color: var(--success-color, #3aa657); }
	.cfi-status-icon.stopped { color: var(--warning-color, #d89b00); }
	.cfi-status-icon.running-test { color: var(--main-color, #0069d9); animation: cfi-pulse 1.5s ease-in-out infinite; }
	.cfi-status-text h3 { margin: 0 0 0.2em 0; font-size: 1.3em; }
	.cfi-status-text h3.running { color: var(--success-color, #3aa657); }
	.cfi-status-text h3.stopped { color: var(--warning-color, #d89b00); }
	.cfi-status-text h3.running-test { color: var(--main-color, #0069d9); }
	@keyframes cfi-pulse { 0%,100% { opacity:1; } 50% { opacity:0.4; } }
	.cfi-status-text p { margin: 0; color: var(--subtext-color, #666); font-size: 0.9em; }
	.cfi-stats-grid {
		display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
		gap: 1em; margin-bottom: 1.5em;
	}
	.cfi-stat-card {
		padding: 1em 1.2em; border-radius: 8px;
		text-align: center;
	}
	.cfi-stat-card .cfi-stat-value {
		font-size: 1.8em; font-weight: bold; line-height: 1.2;
		color: var(--main-color, #0069d9);
	}
	.cfi-stat-card .cfi-stat-value.green { color: var(--success-color, #3aa657); }
	.cfi-stat-card .cfi-stat-value.red { color: var(--danger-color, #d94b4b); }
	.cfi-stat-card .cfi-stat-value.orange { color: var(--warning-color, #d89b00); }
	.cfi-stat-card .cfi-stat-label {
		font-size: 0.85em; color: var(--subtext-color, #666);
		margin-top: 0.3em;
	}
	@media (max-width: 600px) {
		.cfi-status-banner {
			flex-wrap: wrap; gap: 0.6em; padding: 1em;
		}
		.cfi-status-icon { font-size: 1.8em; }
		.cfi-status-text h3 { font-size: 1.1em; }
		.cfi-status-text p { font-size: 0.85em; }
		.cfi-stats-grid {
			grid-template-columns: repeat(2, 1fr); gap: 0.6em;
		}
		.cfi-stat-card .cfi-stat-value { font-size: 1.4em; }
		.cfi-stat-card .cfi-stat-label { font-size: 0.78em; }
	}
	`;

return view.extend({
	load: function() {
		return Promise.all([
			utils.callStatus(),
			uci.load('cf_ip')
		]).then(function(results) {
			return results[0];
		});
	},

	render: function(data) {
		utils.loadSharedCSS();
		data = data || {};

		var running = data.running || false;
		var lastRun = data.last_run || '-';
		var lastResult = data.last_result || '-';
		var mode = data.mode || uci.get('cf_ip', 'main', 'mode') || '-';
		var ipType = data.ip_type || uci.get('cf_ip', 'main', 'ip_type') || '-';
		var ipCount = data.ip_count || 0;
		var speedtestProtocol = data.speedtest_protocol || uci.get('cf_ip', 'main', 'speedtest_protocol') || '-';
		var bestIps = data.best_ips || [];
		var cfstVersion = data.cfst_version || '-';
		var scriptVersion = data.script_version || '-';
		if (scriptVersion.charAt(0) === '@') scriptVersion = '-';
		var error = data.error || '';

		/* Env info from status (merged by backend) */
		var envUpdatedAt = data.updated_at || '';

		var container = E('div', { 'class': 'cbi-map cfi-dashboard' });
		container.appendChild(E('style', {}, css));

		container.appendChild(E('h2', { 'class': 'cbi-map-title' }, _('Overview')));

		var isRunningTest = running && lastResult === 'running';
		var bannerState = isRunningTest ? 'running-test' : (running ? 'running' : 'stopped');
		var banner = E('div', { 'class': 'cbi-section cfi-status-banner ' + bannerState });
		banner.appendChild(E('div', { 'class': 'cfi-status-icon ' + bannerState },
			isRunningTest ? '\u23F3' : (running ? '\u25CF' : '\u25CB')));
		var bannerText = E('div', { 'class': 'cfi-status-text' });
		bannerText.appendChild(E('h3', { 'class': bannerState },
			isRunningTest ? _('Speedtest Running') : (running ? _('Service Running') : _('Service Stopped'))));
		bannerText.appendChild(E('p', {}, isRunningTest ?
			_('Cloudflare IP speedtest is in progress, please wait...') :
			(running ?
				_('Cloudflare IP optimization service is active and running.') :
				_('Cloudflare IP optimization service is not running. Click Start to begin.'))));
		banner.appendChild(bannerText);
		container.appendChild(banner);

		if (isRunningTest) {
			// Auto-show speedtest modal when page loads during active test
			setTimeout(showSpeedtestModal, 300);
			utils.waitForServiceReady(utils.callStatus, {
				isActive: function() { return container.isConnected; }
			}).then(function() {
				if (container.isConnected)
					utils.reloadSoon(300);
			}).catch(function() {});
		} else if (running) {
			// Edge case: page loaded right after callRun() but before backend wrote "running" status
			// Re-check after short delay to catch the transition
			setTimeout(function() {
				utils.callStatus().then(function(s) {
					if (s && s.last_result === 'running')
						utils.reloadSoon(300);
				});
			}, 2000);
		}

		var statsGrid = E('div', { 'class': 'cfi-stats-grid' });

		var ipCountClass = ipCount > 0 ? 'cfi-stat-value green' : 'cfi-stat-value red';
		statsGrid.appendChild(E('div', { 'class': 'cbi-section cfi-stat-card' }, [
			E('div', { 'class': ipCountClass }, String(ipCount)),
			E('div', { 'class': 'cfi-stat-label' }, _('Best IP Count'))
		]));

		statsGrid.appendChild(E('div', { 'class': 'cbi-section cfi-stat-card' }, [
			E('div', { 'class': 'cfi-stat-value' }, ipType.toUpperCase()),
			E('div', { 'class': 'cfi-stat-label' }, _('IP Type'))
		]));

		statsGrid.appendChild(E('div', { 'class': 'cbi-section cfi-stat-card' }, [
			E('div', { 'class': 'cfi-stat-value' }, speedtestProtocol.toUpperCase()),
			E('div', { 'class': 'cfi-stat-label' }, _('Speedtest Protocol'))
		]));

		statsGrid.appendChild(E('div', { 'class': 'cbi-section cfi-stat-card' }, [
			E('div', { 'class': 'cfi-stat-value' }, cfstVersion),
			E('div', { 'class': 'cfi-stat-label' }, _('CFST Version'))
		]));

		container.appendChild(statsGrid);

		var controlSection = E('div', { 'class': 'cbi-section cfi-section' });
		controlSection.appendChild(E('h3', {}, _('Service Control')));

		var btnGroup = E('div', { 'class': 'cfi-btn-group' });

		if (!running) {
			btnGroup.appendChild(E('button', {
				'class': 'cbi-button cbi-button-apply',
				'click': function() {
					var btn = this;
					utils.setBusy(btn, _('Loading...'));
					return callServiceStart().then(utils.requireSuccess).then(function() {
						ui.addNotification(null, E('p', _('Service started.')), 'info');
						return waitReadyAndReload();
					}).catch(function(e) {
						ui.addNotification(null, E('p', _('Failed to start service: ') + e.message), 'error');
						utils.resetBusy(btn);
					});
				}
			}, '\u25B6 ' + _('Start')));
		}

		if (running) {
			btnGroup.appendChild(E('button', {
				'class': 'cbi-button cbi-button-reset',
				'click': function() {
					var btn = this;
					utils.setBusy(btn, _('Loading...'));
					return callServiceStop().then(utils.requireSuccess).then(function() {
						ui.addNotification(null, E('p', _('Service stopped.')), 'info');
						utils.reloadSoon();
					}).catch(function(e) {
						ui.addNotification(null, E('p', _('Failed to stop service: ') + e.message), 'error');
						utils.resetBusy(btn);
					});
				}
			}, '\u25A0 ' + _('Stop')));
		}

		btnGroup.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				var btn = this;
				utils.setBusy(btn, _('Loading...'));
				return utils.callServiceRestart().then(utils.requireSuccess).then(function() {
					ui.addNotification(null, E('p', _('Service restarted.')), 'info');
					return waitReadyAndReload();
				}).catch(function(e) {
					ui.addNotification(null, E('p', _('Failed to restart service: ') + e.message), 'error');
					utils.resetBusy(btn);
				});
			}
		}, '\u21BB ' + _('Restart')));

		if (running) {
			/* Speedtest button: shows "Running..." when test is active, click to view log */
			var speedtestBtn = E('button', {
				'class': 'cbi-button cbi-button-apply',
				'click': function() {
					if (isRunningTest) {
						showSpeedtestModal();
						return;
					}
					var btn = this;
					utils.setBusy(btn, '\u23F3 ' + _('Running...'));
					isRunningTest = true;
					// Trigger speedtest in background (non-blocking RPC)
					callRun().then(function(result) {
						result = result || {};
						if (result.success !== true) {
							ui.addNotification(null, E('p', _('Failed to trigger speedtest: %s').format(result.error || _('unknown'))), 'error');
							isRunningTest = false;
							utils.resetBusy(btn);
							return;
						}
						// Reload page after short delay; backend writes "running" status almost instantly
						utils.reloadSoon(1000);
					}).catch(function(e) {
						ui.addNotification(null, E('p', _('Speedtest failed: %s').format(e.message)), 'error');
						isRunningTest = false;
						utils.resetBusy(btn);
					});
				}
			}, isRunningTest ? '\u23F3 ' + _('Running...') : '\u26A1 ' + _('Run Speedtest'));
			btnGroup.appendChild(speedtestBtn);
		}

		controlSection.appendChild(btnGroup);

		/* CFST button in button group */
		var cfstInstalled = data.cfst_installed || false;
		btnGroup.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				var btn = this;
				utils.setBusy(btn, cfstInstalled ? _('Updating...') : _('Downloading...'));
				ui.addNotification(null, E('p', cfstInstalled
					? _('Updating CFST, this may take a few minutes depending on network conditions. Please wait...')
					: _('Downloading CFST, this may take a few minutes depending on network conditions. Please wait...')), 'info');
				return callDownloadCfst().then(function(result) {
					result = result || {};
					if (result.success !== true) {
						ui.addNotification(null, E('p', _('CFST operation failed: ') + (result.error || _('unknown'))), 'error');
					} else {
						ui.addNotification(null, E('p', _('CFST updated successfully.') + (result.cfst_version ? ' (' + result.cfst_version + ')' : '')), 'info');
						utils.reloadSoon(1500);
					}
				}).catch(function(e) {
					ui.addNotification(null, E('p', _('CFST operation failed: ') + e.message), 'error');
				}).finally(function() {
					utils.resetBusy(btn);
				});
			}
		}, cfstInstalled ? '\u21BB ' + _('Update CFST') : '\u2B07 ' + _('Download CFST')));

		container.appendChild(controlSection);

		var infoSection = E('div', { 'class': 'cbi-section cfi-section' });
		infoSection.appendChild(E('h3', {}, _('Service Information')));

		var infoTable = E('table', { 'class': 'table' });

		infoTable.appendChild(E('tr', { 'class': 'tr' }, [
			E('th', { 'class': 'th' }, _('Mode')),
			E('td', { 'class': 'td' }, mode)
		]));

		infoTable.appendChild(E('tr', { 'class': 'tr' }, [
			E('th', { 'class': 'th' }, _('Last Run Time')),
			E('td', { 'class': 'td' }, lastRun)
		]));

		var lastResultBadge;
		if (lastResult === 'running') {
			lastResultBadge = E('span', { 'class': 'cfi-badge orange', 'style': 'cursor:pointer', 'click': showSpeedtestModal }, '\u23F3 ' + translateStatus(lastResult));
		} else if (lastResult === 'success' || (typeof lastResult === 'string' && lastResult.indexOf('success') === 0)) {
			lastResultBadge = E('span', { 'class': 'cfi-badge green' }, '\u2714 ' + translateStatus(lastResult));
		} else if (lastResult === '-' || lastResult === 'unknown') {
			lastResultBadge = E('span', { 'class': 'cfi-badge gray' }, '\u26A0 ' + '-');
		} else {
			lastResultBadge = E('span', { 'class': 'cfi-badge red' }, '\u2718 ' + translateStatus(lastResult));
		}
		infoTable.appendChild(E('tr', { 'class': 'tr' }, [
			E('th', { 'class': 'th' }, _('Last Result')),
			E('td', { 'class': 'td' }, lastResultBadge)
		]));

		var bestIpsText = bestIps.length > 0 ? bestIps.slice(0, 5).join(', ') + (bestIps.length > 5 ? ' ...' : '') : '-';
		infoTable.appendChild(E('tr', { 'class': 'tr' }, [
			E('th', { 'class': 'th' }, _('Best IPs')),
			E('td', { 'class': 'td' }, bestIpsText)
		]));

		infoTable.appendChild(E('tr', { 'class': 'tr' }, [
			E('th', { 'class': 'th' }, _('Script Version')),
			E('td', { 'class': 'td' }, scriptVersion)
		]));

		infoTable.appendChild(E('tr', { 'class': 'tr' }, [
			E('th', { 'class': 'th' }, _('CFST Version')),
			E('td', { 'class': 'td' }, cfstVersion)
		]));

		infoTable.appendChild(E('tr', { 'class': 'tr' }, [
			E('th', { 'class': 'th' }, _('GitHub')),
			E('td', { 'class': 'td' }, E('a', {
				'href': 'https://github.com/hello-yunshu/use-cloudflare-ip',
				'target': '_blank',
				'rel': 'noopener',
				'style': 'color:var(--main-color, #0069d9);text-decoration:none'
			}, 'hello-yunshu/use-cloudflare-ip'))
		]));

		infoSection.appendChild(E('div', { 'class': 'cfi-table-wrap' }, infoTable));
		container.appendChild(infoSection);

		/* Environment Detection */
		var envSection = E('div', { 'class': 'cbi-section cfi-section' });
		envSection.appendChild(E('h3', {}, _('Environment Detection')));

		var envTable = E('table', { 'class': 'table' });

		var envItems = [
			{ label: _('bash'), key: 'bash' },
			{ label: _('curl'), key: 'curl' },
			{ label: _('tar'), key: 'tar' },
			{ label: _('jq'), key: 'jq' },
			{ label: _('awk'), key: 'awk' },
			{ label: _('sed'), key: 'sed' },
			{ label: _('uci'), key: 'uci' },
			{ label: _('PassWall'), key: 'passwall_installed', plugin: true, runningKey: 'passwall_running' },
			{ label: _('OpenClash'), key: 'openclash_installed', plugin: true, runningKey: 'openclash_running' },
			{ label: _('CFST'), key: 'cfst_installed', cfst: true }
		];

		var envTds = [];
		for (var i = 0; i < envItems.length; i++) {
			var item = envItems[i];
			var val = data[item.key];
			var badge;

			if (item.plugin) {
				var isRunning = data[item.runningKey] || false;
				badge = makePluginBadge(val, isRunning);
			} else if (item.cfst) {
				if (val) {
					var cfstVer = data.cfst_version || '';
					badge = E('span', { 'class': 'cfi-badge green' }, '\u2714 ' + (cfstVer ? cfstVer : _('Installed')));
				} else {
					badge = E('span', { 'class': 'cfi-badge red' }, '\u2718 ' + _('Not Installed'));
				}
			} else {
				badge = makeEnvBadge(val);
			}

			var tdContent = [badge];

			var td = E('td', { 'class': 'td' }, tdContent);
			envTds.push({ td: td, item: item });
			envTable.appendChild(E('tr', { 'class': 'tr' }, [
				E('th', { 'class': 'th' }, item.label),
				td
			]));
		}

		envSection.appendChild(E('div', { 'class': 'cfi-table-wrap' }, envTable));

		var envBtnBar = E('div', { 'class': 'cfi-btn-group', 'style': 'margin-top:1em' });
		envBtnBar.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				var btn = this;
				utils.setBusy(btn, _('Checking...'));
				return callRefreshEnv().then(function(result) {
					result = result || {};
					for (var j = 0; j < envTds.length; j++) {
						var entry = envTds[j];
						var it = entry.item;
						var newVal = result[it.key];
						var newBadge;

						if (it.plugin) {
							var newRunning = result[it.runningKey] || false;
							newBadge = makePluginBadge(newVal, newRunning);
						} else if (it.cfst) {
							if (newVal) {
								var ver = result.cfst_version || '';
								newBadge = E('span', { 'class': 'cfi-badge green' }, '\u2714 ' + (ver ? ver : _('Installed')));
							} else {
								newBadge = E('span', { 'class': 'cfi-badge red' }, '\u2718 ' + _('Not Installed'));
							}
						} else {
							newBadge = makeEnvBadge(newVal);
						}

						while (entry.td.firstChild) entry.td.removeChild(entry.td.firstChild);
						entry.td.appendChild(newBadge);
					}

					var newMissing = result.missing_deps || [];
					var depSectionParent = depSection.parentNode;
					if (depSectionParent) {
						var newDepSection = buildDepSection(newMissing, result.package_manager || 'opkg');
						depSectionParent.replaceChild(newDepSection, depSection);
						depSection = newDepSection;
					}

					utils.resetBusy(btn);
					ui.addNotification(null, E('p', _('Environment detection refreshed.')), 'info');
				}).catch(function(e) {
					ui.addNotification(null, E('p', _('Failed to refresh environment: ') + e.message), 'error');
					utils.resetBusy(btn);
				});
			}
		}, '\u21BB ' + _('Refresh Env')));
		envSection.appendChild(envBtnBar);
		container.appendChild(envSection);

		var missingDeps = data.missing_deps || [];
		var depSection = buildDepSection(missingDeps, data.package_manager || 'opkg');
		container.appendChild(depSection);


		return utils.appendFooter(container, Object.assign({}, utils.FOOTER_OPTIONS, { version: scriptVersion }));
	}
});
