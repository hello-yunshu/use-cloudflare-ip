'use strict';
'require view';
'require ui';
'require rpc';
'require cloudflare-ip/utils as utils';

var callReadLog = rpc.declare({ object: 'cf_ip', method: 'read-log', expect: { '': {} } });
var callClearLog = rpc.declare({ object: 'cf_ip', method: 'clear-log', expect: { '': {} } });
var callIpHistory = rpc.declare({ object: 'cf_ip', method: 'ip-history', expect: { '': {} } });

var css = `
	.cfi-ip-table {
		width: 100%;
	}
	.cfi-table-wrap > .cfi-ip-table {
		min-width: 0;
	}
	.cfi-ip-table th:first-child,
	.cfi-ip-table td:first-child {
		width: 3em;
		text-align: center;
	}
	.cfi-ip-table td {
		font-family: monospace;
		word-break: break-all;
	}
	@media (max-width: 600px) {
		.cfi-ip-table td {
			font-size: 0.85em;
		}
	}
`;

return view.extend({
	load: function() {
		return Promise.all([
			utils.callStatus().catch(function() { return {}; }),
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

		container.appendChild(E('h2', { 'class': 'cbi-map-title' }, _('Logs & Records')));

		/* Recent Logs */
		var logSection = E('div', { 'class': 'cbi-section cfi-section' });
		logSection.appendChild(E('h3', {}, _('Recent Logs')));

		var logArea = E('textarea', {
			'class': 'cbi-input-textarea cfi-log-area',
			'id': 'log-area',
			'rows': 20,
			'readonly': 'readonly'
		}, '');

		function setLogText(text) {
			logArea.value = text;
		}

		var logBtnBar = E('div', { 'class': 'cfi-btn-group', 'style': 'margin-bottom:1em' });

		logBtnBar.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				var btn = this;
				utils.setBusy(btn, _('Loading...'));
				logArea.className = 'cbi-input-textarea cfi-log-area is-loading';
				setLogText(_('Loading...'));
				return callReadLog().then(function(res) {
					res = res || {};
					if (res.success !== true) {
						logArea.className = 'cbi-input-textarea cfi-log-area is-error';
						setLogText(res.error || _('Failed to read logs'));
					} else if (res.logs) {
						logArea.className = 'cbi-input-textarea cfi-log-area';
						setLogText(res.logs);
						if (!res.logs.trim())
							logArea.className = 'cbi-input-textarea cfi-log-area is-empty';
						else
							logArea.scrollTop = logArea.scrollHeight;
					} else {
						logArea.className = 'cbi-input-textarea cfi-log-area is-empty';
						setLogText(_('No logs found.'));
					}
				}).catch(function(e) {
					logArea.className = 'cbi-input-textarea cfi-log-area is-error';
					setLogText(_('Failed to read logs: ') + (e.message || e));
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
					if (res.success === true) {
						logArea.className = 'cbi-input-textarea cfi-log-area is-empty';
						setLogText(_('Log file cleared.'));
					} else {
						ui.addNotification(null, E('p', _('Failed to clear logs: ') + (res.error || _('unknown'))), 'error');
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
		if (logData.success !== true) {
			logArea.className = 'cbi-input-textarea cfi-log-area is-error';
			setLogText(logData.error || _('Failed to read logs'));
		} else if (logData.logs) {
			logArea.className = 'cbi-input-textarea cfi-log-area';
			setLogText(logData.logs);
			if (!logData.logs.trim())
				logArea.className = 'cbi-input-textarea cfi-log-area is-empty';
		} else {
			logArea.className = 'cbi-input-textarea cfi-log-area is-empty';
			setLogText(_('No logs found.'));
		}

		logSection.appendChild(logArea);

		/* Auto-scroll to bottom after initial load */
		if (logData.success === true && logData.logs && logData.logs.trim())
			requestAnimationFrame(function() { logArea.scrollTop = logArea.scrollHeight; });

		if (status.error && status.error !== 'Status file not found') {
			logSection.appendChild(E('div', { 'class': 'alert-message danger', 'style': 'margin-top:1em' },
				E('p', {}, '\u2718 ' + _('Last Error: ') + status.error)));
		}
		container.appendChild(logSection);

		/* IP History */
		var ipSection = E('div', { 'class': 'cbi-section cfi-section' });
		ipSection.appendChild(E('h3', {}, _('IP History') + ' ' + _('(latest 10)')));

		var ipTableBody = E('tbody');

		function renderIpHistory(res) {
			while (ipTableBody.firstChild)
				ipTableBody.removeChild(ipTableBody.firstChild);

			res = res || {};
			if (res.success !== true) {
				ipTableBody.appendChild(E('tr', { 'class': 'tr' }, E('td', { 'class': 'td', 'colspan': '2', 'style': 'color:var(--danger-color)' }, res.error || _('Failed to load IP history'))));
				return;
			}

			var ips = res.ips || [];
			if (!ips.length) {
				ipTableBody.appendChild(E('tr', { 'class': 'tr cfi-no-hover' }, E('td', { 'class': 'td', 'colspan': '2', 'style': 'color:var(--subtext-color);font-style:italic' }, _('No IP history available'))));
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

		ipSection.appendChild(E('div', { 'class': 'cfi-table-wrap' }, E('table', { 'class': 'table cfi-ip-table' }, [
			E('thead', {}, E('tr', { 'class': 'tr' }, [
				E('th', { 'class': 'th' }, '#'),
				E('th', { 'class': 'th' }, _('IP Address'))
			])),
			ipTableBody
		])));
		container.appendChild(ipSection);

		return utils.appendFooter(container, utils.FOOTER_OPTIONS);
	}
});
