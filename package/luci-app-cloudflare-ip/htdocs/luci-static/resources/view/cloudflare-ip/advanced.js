'use strict';
'require view';
'require ui';
'require rpc';
'require dom';
'require form';
'require uci';
'require cloudflare-ip/utils as utils';

var callStatus = rpc.declare({ object: 'cf_ip', method: 'status', expect: { '': {} } });
var callServiceRestart = rpc.declare({ object: 'cf_ip', method: 'restart', expect: { '': {} } });
var callSelfUpdate = rpc.declare({ object: 'cf_ip', method: 'self-update', expect: { '': {} } });

return view.extend({
	title: _('Cloudflare IP - Advanced'),

	load: function() {
		return uci.load('cf_ip');
	},

	render: function() {
		var m, s, o;

		m = new form.Map('cf_ip', _('Cloudflare IP - Advanced'));

		/* Self Update */
		s = m.section(form.TypedSection, 'service', _('Self Update'));
		s.anonymous = true;

		o = s.option(form.Flag, 'auto_update', _('Auto Update Script'),
			_('Check for script updates on startup and auto-upgrade if newer. Only replaces the script, not the configuration.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'self_update_url', _('Self Update URL'),
			_('URL to download the latest script version.'));
		o.placeholder = 'https://raw.githubusercontent.com/...';
		o.rmempty = false;
		o.datatype = 'string';
		o.depends('auto_update', '1');

		o = s.option(form.Button, '_self_update', _('Update Script Now'),
			_('Manually check for and install the latest script version.'));
		o.inputtitle = _('Update Script');
		o.inputstyle = 'apply';
		o.onclick = function() {
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
			});
		};

		/* Download */
		s = m.section(form.TypedSection, 'service', _('Download'));
		s.anonymous = true;

		o = s.option(form.Value, 'github_mirror', _('GitHub Mirror'),
			_('Prepend this URL to GitHub download links. Useful in mainland China. Leave empty for direct downloads. Must end with /.'));
		o.placeholder = 'https://ghp.ci/';
		o.rmempty = true;
		o.datatype = 'string';

		o = s.option(form.Value, 'download_retries', _('Download Retries'),
			_('Number of retry attempts for GitHub downloads.'));
		o.datatype = 'range(1,10)';
		o.placeholder = '3';
		o.rmempty = false;

		o = s.option(form.Value, 'download_retry_delay', _('Retry Delay (seconds)'),
			_('Seconds to wait between download retries.'));
		o.datatype = 'range(1,60)';
		o.placeholder = '5';
		o.rmempty = false;

		/* Startup */
		s = m.section(form.TypedSection, 'service', _('Startup'));
		s.anonymous = true;

		o = s.option(form.Value, 'startup_delay', _('Startup Delay'),
			_("Random delay upper bound in seconds. Useful for staggering startup on multiple routers. Empty or 'random' = 0~300s, '0' = no delay."));
		o.placeholder = 'random';
		o.rmempty = true;
		o.datatype = 'string';

		o = s.option(form.Flag, 'verbose', _('Verbose Logging'),
			_('Output detailed progress logs.'));
		o.default = '0';

		o = s.option(form.Value, 'work_dir', _('Work Directory'),
			_('Leave empty to use the script directory. The cfst binary, IP lists, and results are stored in a cfst/ subdirectory.'));
		o.placeholder = '/root/cf-ip';
		o.rmempty = true;
		o.datatype = 'string';

		m.handleSave = function(ev) {
			var tasks = [];
			document.getElementById('maincontent')
				.querySelectorAll('.cbi-map').forEach(function(map) {
					tasks.push(dom.callClassMethod(map, 'save'));
				});
			return Promise.all(tasks);
		};

		m.handleSaveApply = function(ev, mode) {
			return this.handleSave(ev).then(function() {
				return utils.safeApply();
			}).then(function() {
				return uci.load('cf_ip');
			}).then(function() {
				if (uci.get('cf_ip', 'main', 'enabled') !== '1') {
					ui.addNotification(null, E('p', _('Configuration saved and applied.')), 'info');
					utils.reloadSoon(600);
					return;
				}

				ui.addNotification(null, E('p', _('Configuration saved. Restarting service...')), 'info');
				return callServiceRestart().then(utils.requireSuccess).then(function() {
					return utils.waitForServiceReady(callStatus);
				}).then(function(status) {
					ui.addNotification(null, E('p', _('Configuration applied and service is ready.')), 'info');
					utils.reloadSoon(300);
				});
			}).catch(function(e) {
				ui.addNotification(null, E('p', _('Failed to apply configuration: ') + e.message), 'error');
			});
		};

		return utils.renderWithFooter(m.render(), {
			project: 'Cloudflare IP Optimization',
			repoUrl: 'https://github.com/hello-yunshu/use-cloudflare-ip'
		});
	}
});
