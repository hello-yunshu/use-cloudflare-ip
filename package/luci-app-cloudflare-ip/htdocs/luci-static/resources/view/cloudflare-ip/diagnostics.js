'use strict';
'require view';
'require ui';
'require rpc';
'require cloudflare-ip/utils as utils';

var callStatus = rpc.declare({ object: 'cf_ip', method: 'status', expect: { '': {} } });
var callReadLog = rpc.declare({ object: 'cf_ip', method: 'read-log', expect: { '': {} } });
var callClearLog = rpc.declare({ object: 'cf_ip', method: 'clear-log', expect: { '': {} } });
var callIpHistory = rpc.declare({ object: 'cf_ip', method: 'ip-history', expect: { '': {} } });
var callSelfUpdate = rpc.declare({ object: 'cf_ip', method: 'self-update', expect: { '': {} } });
var callRun = rpc.declare({ object: 'cf_ip', method: 'run', expect: { '': {} } });

var css = `
	.cfi-log-area {
		min-height: 16em; max-height: 26em; overflow: auto; padding: 1em;
		background: var(--background-color-low);
		color: inherit;
		font-size: 0.85em; line-height: 1.45; border-radius: 6px;
		border: 1px solid var(--border-color);
		font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
		white-space: pre;
		tab-size: 4;
	}
	.cfi-log-area.is-empty,
	.cfi-log-area.is-loading { color: var(--subtext-color); font-style: italic; }
	.cfi-log-area.is-error { color: var(--danger-color); }
	.cfi-danger-zone {
		margin-bottom: 1.5em;
		border-left: 5px solid var(--danger-color, #d94b4b);
	}
	.cfi-ip-table {
		width: 100%;
	}
	.cfi-ip-table td {
		font-family: monospace;
	}
`;

return view.extend({
	load: function() {
		return Promise.all([
			callStatus().catch(function() { return {}; }),
			callReadLog().catch(function() { return { success: false, error: 'read-log failed' }; }),
			callIpHistory().catch(function() { return { success: false, ips: [] }; })
		]).then(function(results) {
			return {
				status: results[0],
				logData: results[1],
				historyData: results[2]
			};
		});
	},

	render: function(data) {
		utils.loadSharedCSS();
		var status = data.status || {};
		var logData = data.logData || {};
		var historyData = data.historyData || {};

		var container = E('div', { 'class': 'cbi-map cfi-dashboard' });
		container.appendChild(E('style', {}, css));

		container.appendChild(E('h2', { 'class': 'cbi-map-title' }, _('Cloudflare IP - Logs & Maintenance')));

		/* Recent Logs */
		var logSection = E('div', { 'class': 'cbi-section cfi-section' });
		logSection.appendChild(E('h3', {}, _('Recent Logs')));

		var logArea = E('pre', { 'class': 'cfi-log-area', 'id': 'log-area' }, '');

		var logBtnBar = E('div', { 'class': 'cfi-btn-group', 'style': 'margin-bottom:1em' });

		logBtnBar.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				var btn = this;
				utils.setBusy(btn, _('Loading...'));
				logArea.className = 'cfi-log-area is-loading';
				logArea.textContent = _('Loading...');
				return callReadLog().then(function(res) {
					res = res || {};
					if (res.success === false) {
						logArea.className = 'cfi-log-area is-error';
						logArea.textContent = res.error || _('Failed to read logs');
					} else if (res.logs) {
						logArea.className = 'cfi-log-area';
						logArea.textContent = res.logs;
						if (!res.logs.trim())
							logArea.className = 'cfi-log-area is-empty';
						else
							logArea.scrollTop = logArea.scrollHeight;
					} else {
						logArea.className = 'cfi-log-area is-empty';
						logArea.textContent = _('No logs found.');
					}
				}).catch(function(e) {
					logArea.className = 'cfi-log-area is-error';
					logArea.textContent = _('Failed to read logs: ') + (e.message || e);
				}).finally(function() {
					utils.resetBusy(btn);
				});
			}
		}, '\u21BB ' + _('Refresh')));

		logBtnBar.appendChild(E('button', {
			'class': 'cbi-button cbi-button-reset',
			'click': function() {
				if (!confirm(_('Clear log file?')))
					return;
				var btn = this;
				utils.setBusy(btn, _('Loading...'));
				return callClearLog().then(function(res) {
					res = res || {};
					if (res.success) {
						logArea.className = 'cfi-log-area is-empty';
						logArea.textContent = _('Log file cleared.');
					} else {
						ui.addNotification(null, E('p', _('Failed to clear logs: ') + (res.error || 'unknown')), 'error');
					}
				}).catch(function(e) {
					ui.addNotification(null, E('p', _('Failed to clear logs: ') + e.message), 'error');
				}).finally(function() {
					utils.resetBusy(btn);
				});
			}
		}, '\u2716 ' + _('Clear Logs')));

		logSection.appendChild(logBtnBar);

		/* Populate initial log content */
		if (logData.success === false) {
			logArea.className = 'cfi-log-area is-error';
			logArea.textContent = logData.error || _('Failed to read logs');
		} else if (logData.logs) {
			logArea.className = 'cfi-log-area';
			logArea.textContent = logData.logs;
			if (!logData.logs.trim())
				logArea.className = 'cfi-log-area is-empty';
		} else {
			logArea.className = 'cfi-log-area is-empty';
			logArea.textContent = _('No logs found.');
		}

		logSection.appendChild(logArea);

		if (status.error) {
			logSection.appendChild(E('div', { 'class': 'alert-message danger', 'style': 'margin-top:1em' },
				E('p', {}, '\u2718 ' + _('Last Error: ') + status.error)));
		}
		container.appendChild(logSection);

		/* IP History */
		var ipSection = E('div', { 'class': 'cbi-section cfi-section' });
		ipSection.appendChild(E('h3', {}, _('IP History')));

		var ipTableBody = E('tbody');

		function renderIpHistory(res) {
			while (ipTableBody.firstChild)
				ipTableBody.removeChild(ipTableBody.firstChild);

			res = res || {};
			if (res.success === false) {
				ipTableBody.appendChild(E('tr', {}, E('td', { 'colspan': '2', 'style': 'color:var(--danger-color)' }, res.error || _('Failed to load IP history'))));
				return;
			}

			var ips = res.ips || [];
			if (!ips.length) {
				ipTableBody.appendChild(E('tr', {}, E('td', { 'colspan': '2', 'style': 'color:var(--subtext-color);font-style:italic' }, _('No IP history available'))));
				return;
			}

			ips.forEach(function(item, i) {
				var ip = (typeof item === 'string') ? item : (item.ip || '');
				ipTableBody.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, String(i + 1)),
					E('td', { 'class': 'td' }, ip)
				]));
			});
		}

		var ipBtnBar = E('div', { 'class': 'cfi-btn-group', 'style': 'margin-bottom:1em' });
		ipBtnBar.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				var btn = this;
				utils.setBusy(btn, _('Loading...'));
				return callIpHistory().then(function(res) {
					renderIpHistory(res);
				}).catch(function(e) {
					renderIpHistory({ success: false, error: e.message || String(e) });
				}).finally(function() {
					utils.resetBusy(btn);
				});
			}
		}, '\u21BB ' + _('Refresh')));
		ipSection.appendChild(ipBtnBar);

		renderIpHistory(historyData);

		ipSection.appendChild(E('table', { 'class': 'table cfi-ip-table' }, [
			E('thead', {}, E('tr', { 'class': 'tr' }, [
				E('th', { 'class': 'th' }, '#'),
				E('th', { 'class': 'th' }, _('IP Address'))
			])),
			ipTableBody
		]));
		container.appendChild(ipSection);

		/* Maintenance */
		var maintSection = E('div', { 'class': 'cbi-section cfi-section' });
		maintSection.appendChild(E('h3', {}, _('Maintenance')));

		var maintBtnBar = E('div', { 'class': 'cfi-btn-group' });

		maintBtnBar.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				var btn = this;
				utils.setBusy(btn, _('Checking...'));
				return callSelfUpdate().then(function(res) {
					res = res || {};
					if (res.success === false) {
						ui.addNotification(null, E('p', _('Self-update failed: ') + (res.error || 'unknown')), 'error');
						} else if (res.updated) {
							ui.addNotification(null, E('p', _('Script updated to version %s.').format(res.new_version || res.version || '')), 'info');
							utils.reloadSoon(2000);
					} else {
						ui.addNotification(null, E('p', _('Script is already up to date.')), 'info');
					}
				}).catch(function(e) {
					ui.addNotification(null, E('p', _('Self-update failed: ') + e.message), 'error');
				}).finally(function() {
					utils.resetBusy(btn);
				});
			}
		}, '\u21BB ' + _('Check Update')));

		maintBtnBar.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				var btn = this;
				utils.setBusy(btn, _('Running...'));
				return callRun().then(function(res) {
					res = res || {};
					if (res.success === false) {
						ui.addNotification(null, E('p', _('Speed test failed: ') + (res.error || 'unknown')), 'error');
					} else {
						var ips = res.best_ips || [];
						if (ips.length > 0) {
							ui.addNotification(null, E('p', _('Speed test completed: found %d best IPs.').format(ips.length)), 'info');
						} else {
							ui.addNotification(null, E('p', _('Speed test completed but no best IPs found.')), 'warning');
						}
						utils.reloadSoon(2500);
					}
				}).catch(function(e) {
					ui.addNotification(null, E('p', _('Speed test failed: ') + e.message), 'error');
				}).finally(function() {
					utils.resetBusy(btn);
				});
			}
		}, '\u26A1 ' + _('Run Now')));

		maintSection.appendChild(maintBtnBar);
		container.appendChild(maintSection);

		/* Danger Zone */
		var dangerSection = E('div', { 'class': 'cbi-section cfi-danger-zone' });
		dangerSection.appendChild(E('h3', {}, _('Danger Zone')));
		dangerSection.appendChild(E('div', { 'class': 'alert-message warning', 'style': 'margin-bottom:0.5em' },
			E('p', {}, _('Warning: The operations above modify the running service or its files. Use with caution.'))));
		container.appendChild(dangerSection);

		return container;
	}
});
